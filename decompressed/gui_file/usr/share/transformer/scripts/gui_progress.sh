#!/bin/sh
# Helper avanzamento upgrade GUI - POSIX ash. Scrive solo su RAM (/tmp, /var/run).

GUI_PROGRESS_FILE="${GUI_PROGRESS_FILE:-/tmp/gui_progress.json}"
GUI_MAINT_FLAG="${GUI_MAINT_FLAG:-/var/run/gui_maintenance}"

# set_gui_progress <pct 0-100> <download|extract|config|done|error> "<msg>"
set_gui_progress() {
    gp_pct="$1"; gp_step="$2"
    case "$gp_pct" in ''|*[!0-9]*) gp_pct=0 ;; esac
    [ "$gp_pct" -lt 0 ] && gp_pct=0
    [ "$gp_pct" -gt 100 ] && gp_pct=100
    case "$gp_step" in download|extract|config|done|error) ;; *) gp_step=config ;; esac

    # Rimuove control chars ed esegue escape JSON senza spezzare sequenze multibyte UTF-8
    gp_msg=$(printf '%s' "$3" | tr -d '\000-\037' | sed 's/\\/\\\\/g; s/"/\\"/g')

    printf '{"pct":%d,"step":"%s","msg":"%s"}\n' "$gp_pct" "$gp_step" "$gp_msg" \
        >"$GUI_PROGRESS_FILE.tmp.$$" 2>/dev/null &&
        mv -f "$GUI_PROGRESS_FILE.tmp.$$" "$GUI_PROGRESS_FILE" 2>/dev/null
    return 0
}

# Aggiorna il timestamp del flag (valido per 600s in Nginx)
gui_maint_touch() {
    date +%s >"$GUI_MAINT_FLAG.tmp.$$" 2>/dev/null &&
        mv -f "$GUI_MAINT_FLAG.tmp.$$" "$GUI_MAINT_FLAG" 2>/dev/null
    return 0
}

# In caso di errore fatale, imposta il timestamp a (now - 510s), lasciando la pagina
# di errore visibile per 90 secondi prima di sbloccare Nginx
gui_maint_error() {
    set_gui_progress "${1:-0}" error "${2:-Aggiornamento interrotto}"
    if [ -f "$GUI_MAINT_FLAG" ]; then
        gp_now=$(date +%s 2>/dev/null)
        case "$gp_now" in ''|*[!0-9]*) rm -f "$GUI_MAINT_FLAG" ;; *)
            echo $((gp_now - 510)) >"$GUI_MAINT_FLAG.tmp.$$" 2>/dev/null &&
                mv -f "$GUI_MAINT_FLAG.tmp.$$" "$GUI_MAINT_FLAG" 2>/dev/null
        ;; esac
    fi
}

gui_maint_begin() {
    set_gui_progress "${1:-0}" "${2:-download}" "${3:-Preparazione aggiornamento...}"
    gui_maint_touch
}

gui_maint_end() {
    rm -f "$GUI_MAINT_FLAG" "$GUI_MAINT_FLAG".tmp.* 2>/dev/null
    return 0
}

# Chiamato da /etc/modgui_scripts/NN_*.sh (no-op durante il boot normale fuori da upgradegui)
gui_progress() {
    [ -f "$GUI_MAINT_FLAG" ] || return 0
    gp_c="$1"
    case "$gp_c" in ''|*[!0-9]*) gp_c=75 ;; esac
    [ "$gp_c" -lt 75 ] && gp_c=75
    [ "$gp_c" -gt 98 ] && gp_c=98
    set_gui_progress "$gp_c" config "$2"
    gui_maint_touch
}

# Mappa l'estrazione file su 50..75%
gui_extract_progress() {
    gp_n="$1"; gp_t="$2"
    case "$gp_n" in ''|*[!0-9]*) return 0 ;; esac
    case "$gp_t" in ''|*[!0-9]*|0) return 0 ;; esac
    [ "$gp_n" -gt "$gp_t" ] && gp_n="$gp_t"
    set_gui_progress $((50 + gp_n * 25 / gp_t)) extract "Estrazione file ($gp_n/$gp_t)..."
}
