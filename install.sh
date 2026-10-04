#!/bin/ash
# =============================================================================
#  tch-nginx-gui - installer unificato (BusyBox ash, nessun bashismo)
#
#  Uso:
#    curl -kfL https://raw.githubusercontent.com/ZioCook/tch-nginx-gui/master/install.sh | sh
#    curl -kfL .../install.sh | sh -s -- --dev --force
#    FORCE=1 curl -kfL .../install.sh | sh
#    sh install.sh [--stable|--dev] [--file <path>] [--force] [--keep-logs]
#
#  Opzioni CLI:
#    --stable       installa ultima release STABLE
#    --dev          installa build piu' recente del canale DEV
#    --file <path>  installazione offline da archivio .tar.bz2 locale
#    --force        ignora il controllo "stessa versione gia' installata"
#    --keep-logs    conserva /tmp/gui_install.log anche a installazione riuscita
#                   (in caso di errore il log viene sempre conservato)
#
#  Variabili d'ambiente opzionali (comode via pipe: es. FORCE=1 curl ... | sh):
#    FORCE=1                        forza reinstallazione stessa versione
#    DEV=1 / STABLE=1               seleziona canale dev/stabile direttamente
#    CHANNEL=dev|stable             seleziona canale
#    GUI_STABLE_URL / GUI_DEV_URL   URL alternativi dell'archivio
#    GUI_SHA256                     SHA256 atteso (solo --file / override)
#    HEALTH_TIMEOUT                 secondi di attesa health-check (default 10)
#
#  Fasi: 1 Pre-flight | 2 Download+integrita' | 3 Backup | 4 Estrazione+rootdevice
#        5 Health-check con auto-rescue
# =============================================================================

INSTALLER_VERSION="1.1.1"
REPO="ZioCook/tch-nginx-gui"
STABLE_URL="${GUI_STABLE_URL:-https://github.com/$REPO/releases/latest/download/GUI.tar.bz2}"

LOG="/tmp/gui_install.log"
TMP_DL="/tmp/GUI_download.tmp"
LIST_FULL="/tmp/gui_list_full.tmp"
LIST_NAMES="/tmp/gui_list_names.tmp"
BACKUP_DIR="/tmp/gui_backup_safety"
LOCK_DIR="/tmp/gui_install.lock"
MIN_RAM_KB=25600     # 25 MB liberi in /tmp
MIN_FLASH_KB=20480   # 20 MB liberi in /overlay
HEALTH_TIMEOUT="${HEALTH_TIMEOUT:-10}"
RESCUE_PORT=8088
RESCUE_SCRIPT="/www/lua/rescue_server.lua"

CHANNEL=""
LOCAL_FILE=""
FORCE="${FORCE:-${GUI_FORCE:-0}}"
KEEP_LOGS="${KEEP_LOGS:-${GUI_KEEP_LOGS:-0}}"
STEP_N=0
STEPS_TOT=5
HAVE_LOCK=0
ARCHIVE=""          # archivio validato pronto per l'estrazione
HANDOFF_NAME=""     # nome che rootdevice si aspetta in /tmp

# ----------------------------------------------------------------- logging ---
log()  { printf '%s %s\n' "$(date '+%H:%M:%S' 2>/dev/null)" "$*" >>"$LOG" 2>/dev/null; }
say()  { printf '%s\n' "$*"; log "$*"; }
step() { STEP_N=$((STEP_N + 1)); say ""; say "[$STEP_N/$STEPS_TOT] $*"; }
ok()   { say "   [ OK ] $*"; }
info() { say "   [INFO] $*"; }
warn() { say "   [WARN] $*"; }

cleanup_exit() {
  rc=$?
  rm -f "$TMP_DL" "$LIST_FULL" "$LIST_NAMES" /tmp/gui_sum.tmp
  [ -n "$HANDOFF_NAME" ] && rm -f "/tmp/$HANDOFF_NAME"
  [ "$HAVE_LOCK" = "1" ] && rm -rf "$LOCK_DIR"
  if [ "$rc" -eq 0 ] && [ "$KEEP_LOGS" != "1" ]; then
    rm -f "$LOG"
  elif [ -f "$LOG" ]; then
    printf '\n   Log conservato in %s\n' "$LOG"
  fi
}
trap cleanup_exit EXIT
trap 'exit 130' INT TERM

die() {
  say "   [FAIL] $*"
  say "   Nessuna modifica distruttiva e' stata applicata oltre questo punto."
  exit 1
}

usage() {
  cat <<EOF
tch-nginx-gui installer v$INSTALLER_VERSION
Uso: sh install.sh [--stable|--dev] [--file <path>] [--force] [--keep-logs]
EOF
}

# ------------------------------------------------------------ argomenti ------
CLI_CHANNEL=""
[ -n "$DEV" ] && [ "$DEV" = "1" ] && CLI_CHANNEL="dev"
[ -n "$STABLE" ] && [ "$STABLE" = "1" ] && CLI_CHANNEL="stable"
[ -n "$CHANNEL" ] && CLI_CHANNEL="$CHANNEL"
[ -n "$GUI_CHANNEL" ] && CLI_CHANNEL="$GUI_CHANNEL"

while [ $# -gt 0 ]; do
  case "$1" in
    --stable) CLI_CHANNEL="stable" ;;
    --dev) CLI_CHANNEL="dev" ;;
    --file)
      [ -n "$2" ] || { echo "--file richiede un percorso"; exit 2; }
      LOCAL_FILE="$2"; shift ;;
    --file=*) LOCAL_FILE="${1#--file=}" ;;
    --force) FORCE=1 ;;
    --keep-logs) KEEP_LOGS=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Argomento sconosciuto: $1"; usage; exit 2 ;;
  esac
  shift
done

# -------------------------------------------------------------- helpers ------
free_kb() { df -Pk "$1" 2>/dev/null | awk 'NR==2 {print $4}'; }
is_num()  { case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }
have()    { command -v "$1" >/dev/null 2>&1; }

proc_running() { # <pattern>
  if have pgrep; then
    pgrep -f "$1" >/dev/null 2>&1
  else
    ps w 2>/dev/null | grep -v grep | grep -q "$1"
  fi
}

http_ok() {
  if have curl; then
    code=$(curl -ks -o /dev/null -w '%{http_code}' --max-time 3 http://127.0.0.1/ 2>/dev/null)
    case "$code" in 2??|3??|401|403) return 0 ;; esac
    code=$(curl -ks -o /dev/null -w '%{http_code}' --max-time 3 https://127.0.0.1/ 2>/dev/null)
    case "$code" in 2??|3??|401|403) return 0 ;; esac
    return 1
  fi
  wget -q --spider --no-check-certificate -T 3 http://127.0.0.1/ 2>/dev/null ||
    wget -q --spider --no-check-certificate -T 3 https://127.0.0.1/ 2>/dev/null
}

fetch() { # <url> <dest>
  if have curl; then
    curl -kfL --retry 2 --connect-timeout 15 --max-time 900 -o "$2" "$1" 2>>"$LOG"
  else
    wget --no-check-certificate -q -T 30 -O "$2" "$1" 2>>"$LOG"
  fi
}

sha_of() { sha256sum "$1" 2>/dev/null | awk '{print $1}'; }
md5_of() { md5sum "$1" 2>/dev/null | awk '{print $1}'; }

clean_old_logs() { # pulizia SICURA: solo log modgui obsoleti
  for d in /overlay/modgui_log.remove_due_to_upgrade /overlay/modgui_log; do
    [ -d "$d" ] && { info "Pulizia $d"; rm -rf "$d"; }
  done
  rm -f /overlay/*/rootdevice_log_* 2>/dev/null
  sync
}

installed_version() {
  sed -n 's/^version_gui=//p' /etc/init.d/rootdevice 2>/dev/null | head -n 1
}

archive_version() {
  for p in etc/init.d/rootdevice ./etc/init.d/rootdevice; do
    v=$(bzcat "$1" 2>/dev/null | tar -xOf - "$p" 2>/dev/null | sed -n 's/^version_gui=//p' | head -n 1)
    [ -n "$v" ] && { echo "$v"; return 0; }
  done
  return 1
}

mem_avail_kb() {
  ma=0
  mf=0
  mc=0
  mb=0
  while read -r k v rest; do
    case "$k" in
      MemAvailable:) ma="$v" ;;
      MemFree:)      mf="$v" ;;
      Cached:)       mc="$v" ;;
      Buffers:)      mb="$v" ;;
    esac
  done < /proc/meminfo 2>/dev/null
  if is_num "$ma" && [ "$ma" -gt 0 ]; then
    echo "$ma"
  else
    echo $((mf + mc + mb))
  fi
}

get_lan_ip() {
  lip=$(uci -q get network.lan.ipaddr 2>/dev/null)
  if [ -z "$lip" ] && have ip; then
    lip=$(ip -4 addr show br-lan 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -n 1)
  fi
  if [ -z "$lip" ] && have ifconfig; then
    lip=$(ifconfig br-lan 2>/dev/null | awk '/inet addr:/{print $2}' | cut -d: -f2)
  fi
  [ -z "$lip" ] && lip="192.168.1.1"
  echo "$lip"
}

resolve_dev_url() {
  if [ -n "$GUI_DEV_URL" ]; then
    echo "$GUI_DEV_URL"
    return 0
  fi
  dev_tag=""
  if have curl; then
    dev_tag=$(curl -kfLs --connect-timeout 8 --max-time 15 "https://github.com/$REPO/releases/download/channel-dev/latest.version" 2>/dev/null | tr -d '\r\n[:space:]')
  elif have wget; then
    dev_tag=$(wget -q --no-check-certificate -T 10 -O - "https://github.com/$REPO/releases/download/channel-dev/latest.version" 2>/dev/null | tr -d '\r\n[:space:]')
  fi

  if [ -n "$dev_tag" ]; then
    echo "https://github.com/$REPO/releases/download/$dev_tag/GUI_dev.tar.bz2"
  else
    echo "https://raw.githubusercontent.com/$REPO/master/compressed/GUI_dev.tar.bz2"
  fi
}

# =============================================================================
#  SELEZIONE CANALE (Interattiva se non specificata via flag)
# =============================================================================
if [ -n "$LOCAL_FILE" ]; then
  CHANNEL="local"
elif [ -n "$CLI_CHANNEL" ]; then
  CHANNEL="$CLI_CHANNEL"
else
  echo ""
  echo "============================================================"
  echo "           tch-nginx-gui - Installazione Guidata            "
  echo "============================================================"
  echo "  Seleziona il canale di rilascio da installare:"
  echo ""
  echo "    [1] Stabile  - Versione testata e raccomandata (default)"
  echo "    [2] Dev      - Ultime novita' e funzionalita' in test"
  echo ""
  printf "  Scelta [1/2] (default 1): "

  choice=""
  if [ -t 0 ]; then
    read -r choice
  elif [ -r /dev/tty ]; then
    read -r choice </dev/tty 2>/dev/null
  fi

  case "$choice" in
    2|[dD]|[dD][eE][vV])
      CHANNEL="dev"
      echo "  -> Selezionato canale: DEV (Sviluppo)"
      ;;
    *)
      CHANNEL="stable"
      echo "  -> Selezionato canale: STABILE"
      ;;
  esac
  echo "============================================================"
  echo ""
fi

# =============================================================================
#  FASE 1 - PRE-FLIGHT
# =============================================================================
say "=== tch-nginx-gui installer v$INSTALLER_VERSION ==="
: >"$LOG" 2>/dev/null

# lock anti-esecuzione concorrente (mkdir e' atomico)
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  oldpid=$(cat "$LOCK_DIR/pid" 2>/dev/null)
  if [ -n "$oldpid" ] && kill -0 "$oldpid" 2>/dev/null; then
    echo "Un'altra installazione e' in corso (pid $oldpid)."; exit 1
  fi
  rm -rf "$LOCK_DIR"
  mkdir "$LOCK_DIR" || { echo "Impossibile creare il lock"; exit 1; }
fi
HAVE_LOCK=1
echo $$ >"$LOCK_DIR/pid"

step "Pre-flight checks"

[ "$(id -u 2>/dev/null)" = "0" ] || die "Servono i permessi di root."
ok "Permessi root"

for c in bzcat tar uci df awk sed grep; do
  have "$c" || die "Comando richiesto mancante: $c"
done
if [ -z "$LOCAL_FILE" ]; then
  have curl || have wget || die "Serve curl oppure wget per scaricare l'archivio."
fi
ok "Strumenti di base presenti"

hw_model=""
[ -r /proc/device-tree/model ] && hw_model=$(tr -d '\000' </proc/device-tree/model 2>/dev/null)
hw_env=$(uci -q get env.var.prod_friendly_name 2>/dev/null)
hw_cpu=$(sed -n 's/^\(system type\|Hardware\|model name\)[[:space:]]*:[[:space:]]*//p' /proc/cpuinfo 2>/dev/null | head -n 1)
hw_arch=$(uname -m 2>/dev/null)
info "Hardware: ${hw_env:-n/d} | ${hw_model:-n/d} | ${hw_cpu:-n/d} | $hw_arch"

# RAM (/tmp)
ram_free=$(free_kb /tmp)
is_num "$ram_free" || ram_free=0
memfree=$(mem_avail_kb)
is_num "$memfree" || memfree=0

# Su kernel con tmpfs unbounded (es. 3.4 su TG789vac v2) df riporta 0 per /tmp
if [ "$ram_free" -eq 0 ] && [ "$memfree" -gt 0 ]; then
  ram_avail="$memfree"
else
  ram_avail="$ram_free"
  [ "$memfree" -lt "$ram_avail" ] && [ "$memfree" -gt 0 ] && ram_avail="$memfree"
fi

if [ "$ram_avail" -lt "$MIN_RAM_KB" ]; then
  die "/tmp o RAM insufficiente ($((ram_avail / 1024)) MB disponibili, minimo $((MIN_RAM_KB / 1024)) MB). Libera memoria e riprova."
fi
ok "RAM /tmp: $((ram_avail / 1024)) MB disponibili (RAM libera di sistema: $((memfree / 1024)) MB)"

# Flash (/overlay)
if [ -d /overlay ]; then
  flash_free=$(free_kb /overlay)
else
  flash_free=$(free_kb /)
fi
is_num "$flash_free" || die "Impossibile leggere lo spazio libero della flash."
if [ "$flash_free" -lt "$MIN_FLASH_KB" ]; then
  warn "Flash libera bassa: $((flash_free / 1024)) MB (consigliati $((MIN_FLASH_KB / 1024)) MB). Provo pulizia log obsoleti..."
  clean_old_logs
  flash_free=$(free_kb /overlay)
  is_num "$flash_free" || flash_free=0
  [ "$flash_free" -lt "$MIN_FLASH_KB" ] &&
    warn "Dopo la pulizia: $((flash_free / 1024)) MB. Verifichero' lo spazio effettivo dopo aver letto l'archivio."
fi
ok "Flash: $((flash_free / 1024)) MB liberi"

# connettivita'
if [ -z "$LOCAL_FILE" ]; then
  net_fail=0
  if have curl; then
    curl -ksI --max-time 10 -o /dev/null https://github.com 2>>"$LOG" || net_fail=1
  else
    wget -q --spider --no-check-certificate -T 10 https://github.com 2>>"$LOG" || net_fail=1
  fi
  [ "$net_fail" = "1" ] && die "github.com non raggiungibile. Controlla la connessione (o usa --file)."
  ok "Connettivita' verso github.com"
fi

# =============================================================================
#  FASE 2 - DOWNLOAD ATOMICO + VALIDAZIONE
# =============================================================================
step "Download e validazione archivio"
rm -f "$TMP_DL"

if [ -n "$LOCAL_FILE" ]; then
  [ -f "$LOCAL_FILE" ] || die "File non trovato: $LOCAL_FILE"
  cp "$LOCAL_FILE" "$TMP_DL" || die "Copia in $TMP_DL fallita (RAM piena?)."
  SRC_DESC="file locale $LOCAL_FILE"
  SUM_BASE=""
else
  if [ "$CHANNEL" = "dev" ]; then
    URL=$(resolve_dev_url)
  else
    URL="$STABLE_URL"
  fi
  SRC_DESC="$URL"
  info "Canale $CHANNEL: $URL"
  fetch "$URL" "$TMP_DL" || die "Download fallito (interrotto o URL errato)."
  SUM_BASE="$URL"
fi

sz=$(wc -c <"$TMP_DL" 2>/dev/null)
is_num "$sz" && [ "$sz" -gt 1048576 ] || die "Archivio troppo piccolo o assente (${sz:-0} byte): download incompleto."
ok "Ottenuto archivio: $((sz / 1024)) KB"

# 2a. integrita' bzip2 (stadio separato: ash non ha pipefail)
bzcat "$TMP_DL" >/dev/null 2>>"$LOG" || die "Archivio bzip2 corrotto o troncato."
# 2b. integrita' tar + liste
bzcat "$TMP_DL" 2>/dev/null | tar -tvf - >"$LIST_FULL" 2>>"$LOG" || die "Archivio tar corrotto."
bzcat "$TMP_DL" 2>/dev/null | tar -tf - >"$LIST_NAMES" 2>>"$LOG" || die "Archivio tar corrotto (elenco nomi)."
[ -s "$LIST_NAMES" ] || die "Archivio vuoto."
ok "Integrita' bzip2/tar verificata"

# 2c. sicurezza dei percorsi + marker atteso
grep -q '^/' "$LIST_NAMES" && die "L'archivio contiene percorsi assoluti: rifiutato."
grep -qE '(^|/)\.\.(/|$)' "$LIST_NAMES" && die "L'archivio contiene percorsi con '..': rifiutato."
grep -qE '^(\./)?etc/init\.d/rootdevice$' "$LIST_NAMES" || die "L'archivio non sembra una GUI valida (manca etc/init.d/rootdevice)."
ok "Struttura archivio valida"

# 2d. spazio reale necessario in flash
unc_kb=$(awk '{s += $3} END {print int(s / 1024)}' "$LIST_FULL")
if is_num "$unc_kb"; then
  need=$((unc_kb + 2048))
  flash_free=$(free_kb /overlay); is_num "$flash_free" || flash_free=$(free_kb /)
  info "Spazio necessario stimato: $((need / 1024)) MB, disponibile: $((flash_free / 1024)) MB"
  [ "$flash_free" -lt "$need" ] && die "Spazio flash insufficiente per l'estrazione: rischio di overlay pieno/read-only."
fi

# 2e. checksum
chk_done=0
if [ -n "$GUI_SHA256" ] && have sha256sum; then
  [ "$(sha_of "$TMP_DL")" = "$GUI_SHA256" ] || die "SHA256 non corrispondente a GUI_SHA256."
  ok "SHA256 verificato (GUI_SHA256)"; chk_done=1
elif [ -n "$SUM_BASE" ]; then
  if have sha256sum && fetch "$SUM_BASE.sha256" /tmp/gui_sum.tmp 2>/dev/null && [ -s /tmp/gui_sum.tmp ]; then
    exp=$(awk '{print $1; exit}' /tmp/gui_sum.tmp)
    [ "$(sha_of "$TMP_DL")" = "$exp" ] || die "SHA256 non corrisponde a quello pubblicato."
    ok "SHA256 verificato"; chk_done=1
  elif have md5sum && fetch "$SUM_BASE.md5" /tmp/gui_sum.tmp 2>/dev/null && [ -s /tmp/gui_sum.tmp ]; then
    exp=$(awk '{print $1; exit}' /tmp/gui_sum.tmp)
    [ "$(md5_of "$TMP_DL")" = "$exp" ] || die "MD5 non corrisponde a quello pubblicato."
    ok "MD5 verificato"; chk_done=1
  fi
fi
[ "$chk_done" = "0" ] && warn "Nessun checksum remoto verificato: validata integrita' strutturale bzip2 e tar."

# 2f. controllo versione
new_ver=$(archive_version "$TMP_DL")
cur_ver=$(installed_version)
info "Versione installata: ${cur_ver:-n/d} | versione archivio: ${new_ver:-n/d}"
if [ "$FORCE" != "1" ] && [ -n "$new_ver" ] && [ "$new_ver" = "$cur_ver" ] && [ ! -f /root/.install_gui ]; then
  say "   La versione $cur_ver e' gia' installata."
  reinstall=""
  if [ -t 0 ]; then
    printf "   Vuoi forzare la reinstallazione comunque? [s/N]: "
    read -r reinstall
  elif [ -r /dev/tty ]; then
    printf "   Vuoi forzare la reinstallazione comunque? [s/N]: "
    read -r reinstall </dev/tty 2>/dev/null
  fi
  case "$reinstall" in
    [sSyY]|[sS][iI]|[yY][eE][sS])
      FORCE=1
      say "   -> Reinstallazione forzata confermata."
      ;;
    *)
      say "   Installazione terminata senza modifiche. (Per forzare via CLI: --force oppure FORCE=1)"
      exit 0
      ;;
  esac
fi

# Posizionamento archivio validato per rootdevice
if [ "$CHANNEL" = "dev" ] && [ -z "$LOCAL_FILE" ]; then
  HANDOFF_NAME="GUI_dev.tar.bz2"
else
  HANDOFF_NAME="GUI.tar.bz2"
fi
rm -f "/tmp/$HANDOFF_NAME"
mv "$TMP_DL" "/tmp/$HANDOFF_NAME" || die "Impossibile posizionare l'archivio validato in /tmp."
ARCHIVE="/tmp/$HANDOFF_NAME"
ok "Archivio validato: $ARCHIVE"

# =============================================================================
#  FASE 3 - BACKUP DI SICUREZZA MINIMO
# =============================================================================
step "Backup di sicurezza (in $BACKUP_DIR, RAM)"
rm -rf "$BACKUP_DIR"
mkdir -p "$BACKUP_DIR" && chmod 700 "$BACKUP_DIR" || die "Impossibile creare $BACKUP_DIR"

bk_list=""
for f in etc/config/network etc/config/dropbear etc/config/firewall etc/config/env \
         etc/config/modgui etc/shadow etc/passwd etc/inittab etc/init.d/rootdevice \
         root/.ssh/authorized_keys etc/dropbear/authorized_keys; do
  [ -e "/$f" ] && bk_list="$bk_list $f"
done
# shellcheck disable=SC2086
tar -C / -cf "$BACKUP_DIR/safety.tar" $bk_list 2>>"$LOG" || die "Backup fallito: installazione annullata."
tar -tf "$BACKUP_DIR/safety.tar" >/dev/null 2>&1 || die "Backup non leggibile: installazione annullata."
ok "Salvati $(echo $bk_list | wc -w) file (ripristino rapido: tar -C / -xf $BACKUP_DIR/safety.tar)"

# =============================================================================
#  FASE 4 - ESTRAZIONE + ROOTDEVICE
# =============================================================================
step "Estrazione ed esecuzione rootdevice"
info "ATTENZIONE: su router dual-bank rootdevice puo' pianificare l'OBP e riavviare il router."
info "L'installazione prosegue automaticamente dopo l'eventuale riavvio."

if ! bzcat "$ARCHIVE" | tar -C / -xf - 2>>"$LOG"; then
  warn "Estrazione fallita: ripristino del backup..."
  tar -C / -xf "$BACKUP_DIR/safety.tar" 2>>"$LOG"
  sync
  die "Estrazione fallita, configurazioni vitali ripristinate."
fi
sync
ok "File estratti con successo"

[ -f /etc/init.d/rootdevice ] || die "rootdevice assente dopo l'estrazione."
chmod 755 /etc/init.d/rootdevice

info "Eseguo /etc/init.d/rootdevice force ..."
/etc/init.d/rootdevice force >>"$LOG" 2>&1
rd_rc=$?
[ "$rd_rc" -ne 0 ] && warn "rootdevice ha restituito codice $rd_rc (verifico lo stato dei servizi)."
ok "rootdevice completato"

# =============================================================================
#  FASE 5 - HEALTH CHECK + AUTO-RESCUE
# =============================================================================
step "Health check servizi web (timeout ${HEALTH_TIMEOUT}s)"
healthy=0
i=0
while [ "$i" -lt "$HEALTH_TIMEOUT" ]; do
  if proc_running nginx && proc_running transformer && http_ok; then
    healthy=1; break
  fi
  i=$((i + 1)); sleep 1
done

lan_ip=$(get_lan_ip)
final_ver=$(installed_version)

if [ "$healthy" = "1" ]; then
  ok "nginx, transformer e risposta HTTP locale: OK"
  say ""
  say "============================================================"
  say "               INSTALLAZIONE COMPLETATA                     "
  say "   Versione GUI : ${final_ver:-n/d}"
  say "   Indirizzo    : http://$lan_ip  (https://$lan_ip)"
  say "   SSH          : ssh root@$lan_ip"
  say "   Credenziali  : utente root, password invariata se gia'"
  say "                  impostata (default: root)"
  say "============================================================"
  exit 0
fi

warn "nginx/transformer non rispondono entro ${HEALTH_TIMEOUT}s."
proc_running nginx       || warn "  - nginx NON attivo"
proc_running transformer || warn "  - transformer NON attivo"
http_ok                  || warn "  - nessuna risposta HTTP locale"

if [ -f "$RESCUE_SCRIPT" ] && have lua; then
  if netstat -ln 2>/dev/null | grep -q ":$RESCUE_PORT "; then
    info "Rescue Server gia' in ascolto sulla porta $RESCUE_PORT"
  else
    ( lua "$RESCUE_SCRIPT" "$RESCUE_PORT" >>"$LOG" 2>&1 & )
    sleep 2
  fi
  say ""
  say "============================================================"
  say " ATTENZIONE: installazione terminata ma GUI NON operativa   "
  say "   Rescue Server avviato: http://$lan_ip:$RESCUE_PORT"
  say "   Log: $LOG (e /tmp/rootdevice_install.log)"
  say "============================================================"
else
  say "   [FAIL] Rescue Server non disponibile ($RESCUE_SCRIPT o lua mancanti)."
  say "   Backup per ripristino manuale: $BACKUP_DIR/safety.tar"
fi
exit 3
