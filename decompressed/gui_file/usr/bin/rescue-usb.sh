#!/bin/sh
#
# Zero-Touch USB Recovery Engine for tch-nginx-gui
# Scans attached USB drives for recovery archives, validates integrity,
# and restores the system without requiring active web or network services.
#
# Target: BusyBox ash on OpenWrt (no bashisms, no arrays, no [[ ]]).
#
# Hardening overview:
#   * single instance (atomic mkdir lock with stale-lock detection)
#   * USB enumeration is polled instead of a fixed sleep; whole disks that carry
#     partitions are skipped; mounts are read-only,noexec,nosuid,nodev
#   * EVERY exit path (error, signal, success) unmounts the stick and removes temp files
#   * a bad archive no longer aborts the scan: the next candidate / device is tried
#   * archive validation = bzip2 stream + tar structure + path-traversal check, with the
#     exit status of BOTH sides of the pipe checked (a plain `a | b` only reports b)
#   * the same exact-match logic is used for MD5SUMS (no substring / regex surprises)
#   * extraction only starts from an archive that passed ALL checks
#
# Exit codes: 0 ok | 1 no USB block device | 2 no archive found | 3 archive corrupt/invalid
#             4 MD5 mismatch | 5 extraction error | 6 already running | 7 unsafe archive paths
#             8 cannot prepare work dirs | 9 required tool missing | 10 restored, service warnings
#

export PATH="/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
LOG_FILE="/tmp/rescue.log"
MOUNT_DIR="/tmp/rescue_usb"
LOCK_DIR="/tmp/rescue_usb.lock"
WORK_DIR="/tmp/rescue_usb.work.$$"
EXTRACT_ROOT="/"
ENUM_WAIT=15                                   # s to wait for /dev/sd* to appear
MOUNT_OPTS="ro,noexec,nosuid,nodev"
MOUNT_FSTYPES="vfat ext4 exfat ntfs ufsd"      # tried explicitly if autodetect fails
TARGET_NAMES="ziocook-gui-recovery.tar.bz2 GUI.tar.bz2 GUI_upload.tar.bz2 tch-gui-recovery.tar.bz2"

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [RESCUE-USB] $1"
    printf '%s\n' "$msg"
    printf '%s\n' "$msg" >> "$LOG_FILE" 2>/dev/null
    logger -t rescue_usb "$1" 2>/dev/null
}

mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null
touch "$LOG_FILE" 2>/dev/null

# ---------------------------------------------------------------------------
# Mount helpers
# ---------------------------------------------------------------------------
is_mounted() {
    grep -q " $MOUNT_DIR " /proc/mounts 2>/dev/null
}

# Unmount cleanly (also stacked mounts); fall back to a lazy unmount as last resort
safe_umount() {
    local n=0
    while is_mounted && [ "$n" -lt 5 ]; do
        sync
        umount "$MOUNT_DIR" 2>/dev/null && { n=$((n + 1)); continue; }
        sleep 1
        umount "$MOUNT_DIR" 2>/dev/null || umount -l "$MOUNT_DIR" 2>/dev/null
        n=$((n + 1))
    done
    return 0
}

try_mount() {
    local dev="$1" fs
    safe_umount
    if mount -o "$MOUNT_OPTS" "$dev" "$MOUNT_DIR" 2>/dev/null; then
        return 0
    fi
    for fs in $MOUNT_FSTYPES; do
        if mount -t "$fs" -o "$MOUNT_OPTS" "$dev" "$MOUNT_DIR" 2>/dev/null; then
            return 0
        fi
    done
    return 1
}

# ---------------------------------------------------------------------------
# Device helpers
# ---------------------------------------------------------------------------
list_usb_devices() {
    local d out=""
    for d in /dev/sd[a-z]*; do
        [ -b "$d" ] && out="$out $d"
    done
    echo $out
}

# Poll for USB block devices instead of a blind sleep
wait_for_devices() {
    local i=0
    sleep 2                                    # let the kernel start enumerating
    while [ -z "$(list_usb_devices)" ] && [ "$i" -lt "$ENUM_WAIT" ]; do
        sleep 1
        i=$((i + 1))
    done
    [ -n "$(list_usb_devices)" ] && sleep 1    # let partition nodes settle
    return 0
}

# A whole disk (sda) that has partitions (sda1...) cannot be mounted: skip it
is_disk_with_partitions() {
    local b="${1##*/}" p
    [ -d "/sys/block/$b" ] || return 1
    for p in /sys/block/$b/${b}[0-9]*; do
        [ -e "$p" ] && return 0
    done
    return 1
}

# ---------------------------------------------------------------------------
# Archive validation
# ---------------------------------------------------------------------------

# Structure check without extracting: bzip2 stream + tar listing + path traversal.
# Both exit statuses are recorded (the shell only reports the last command of a pipe).
# The tar side drains stdin on success so bzcat never dies of SIGPIPE on trailing padding.
# Returns 0 ok | 3 corrupt/invalid | 7 unsafe paths
check_structure() {
    local arc="$1" st_bz="$WORK_DIR/c_bz" st_tar="$WORK_DIR/c_tar" res entries bad
    rm -f "$st_bz" "$st_tar"
    res=$( ( bzcat "$arc" 2>>"$LOG_FILE"; echo $? > "$st_bz" ) \
         | ( tar -tf - 2>>"$LOG_FILE"; rc=$?; echo "$rc" > "$st_tar"; [ "$rc" -eq 0 ] && cat >/dev/null ) \
         | awk 'BEGIN { n = 0; bad = 0 } { n++; if ($0 ~ /(^|\/)\.\.(\/|$)/) bad++ } END { print n, bad }' )

    if [ "$(cat "$st_bz" 2>/dev/null)" != "0" ] || [ "$(cat "$st_tar" 2>/dev/null)" != "0" ]; then
        return 3
    fi
    entries=${res%% *}
    bad=${res##* }
    if [ -z "$entries" ] || [ "$entries" -eq 0 ] 2>/dev/null; then
        log "ERROR: archive is empty or is not a tar archive."
        return 3
    fi
    if [ "$bad" != "0" ]; then
        log "ERROR: archive contains $bad path(s) with '..' components: refusing to extract."
        return 7
    fi
    ARCHIVE_ENTRIES="$entries"
    return 0
}

# Optional MD5 verification (<archive>.md5 or MD5SUMS in the same directory).
# Returns 0 ok / not applicable | 4 mismatch
verify_md5() {
    local arc="$1" dir base expected calc srcf
    dir=$(dirname "$arc")
    base=$(basename "$arc")

    if [ -f "$arc.md5" ]; then
        srcf="$arc.md5"
        log "Verifying MD5 checksum from $srcf..."
        expected=$(tr -d '\r' < "$srcf" | awk 'NR == 1 { print tolower($1) }')
    elif [ -f "$dir/MD5SUMS" ]; then
        srcf="$dir/MD5SUMS"
        # Exact file-name match (binary-mode '*' and './' prefixes tolerated, CRLF stripped)
        expected=$(awk -v f="$base" '{ gsub(/\r/, ""); n = $2; sub(/^\*/, "", n); sub(/^\.\//, "", n);
                                       if (n == f) { print tolower($1); exit } }' "$srcf")
        if [ -z "$expected" ]; then
            log "MD5SUMS found but $base is not listed: checksum verification skipped."
            return 0
        fi
        log "Verifying MD5 checksum from $srcf..."
    else
        return 0
    fi

    calc=$(md5sum "$arc" 2>/dev/null | awk '{ print tolower($1) }')
    if [ -z "$expected" ] || [ "$expected" != "$calc" ]; then
        log "FATAL: MD5 mismatch! Expected: ${expected:-<empty>}, Got: ${calc:-<unreadable>}"
        return 4
    fi
    log "MD5 checksum verification: PASSED ($calc)"
    return 0
}

# Full verification of one candidate. Returns 0 | 3 | 4 | 7
verify_candidate() {
    local arc="$1" rc
    log "Verifying archive integrity with bzcat..."
    check_structure "$arc"
    rc=$?
    if [ "$rc" -ne 0 ]; then
        [ "$rc" -eq 3 ] && log "ERROR: Archive $arc is corrupted or incomplete!"
        return "$rc"
    fi
    log "Archive integrity check: PASSED ($ARCHIVE_ENTRIES entries)"
    verify_md5 "$arc"
    return $?
}

# Extract to $EXTRACT_ROOT; success only if bzcat AND tar both exited with 0
extract_archive() {
    local arc="$1" st_bz="$WORK_DIR/x_bz" st_tar="$WORK_DIR/x_tar"
    rm -f "$st_bz" "$st_tar"
    ( bzcat "$arc" 2>>"$LOG_FILE"; echo $? > "$st_bz" ) \
        | ( tar -C "$EXTRACT_ROOT" -xf - 2>>"$LOG_FILE"; rc=$?; echo "$rc" > "$st_tar"; [ "$rc" -eq 0 ] && cat >/dev/null )
    [ "$(cat "$st_bz" 2>/dev/null)" = "0" ] && [ "$(cat "$st_tar" 2>/dev/null)" = "0" ]
}

# ---------------------------------------------------------------------------
# Single instance + cleanup (installed only AFTER the lock is ours, so a second
# instance can never remove the first one's lock or unmount its stick)
# ---------------------------------------------------------------------------
acquire_lock() {
    local old
    if mkdir "$LOCK_DIR" 2>/dev/null; then
        echo "$$" > "$LOCK_DIR/pid"
        return 0
    fi
    old=$(cat "$LOCK_DIR/pid" 2>/dev/null)
    if [ -n "$old" ] && kill -0 "$old" 2>/dev/null \
       && tr '\0' ' ' < "/proc/$old/cmdline" 2>/dev/null | grep -q "${0##*/}"; then
        LOCK_HOLDER="$old"
        return 1
    fi
    log "Removing stale lock (pid ${old:-?} is gone)."
    rm -rf "$LOCK_DIR"
    if mkdir "$LOCK_DIR" 2>/dev/null; then
        echo "$$" > "$LOCK_DIR/pid"
        return 0
    fi
    return 1
}

cleanup() {
    safe_umount
    rmdir "$MOUNT_DIR" 2>/dev/null
    rm -rf "$WORK_DIR"
    rm -rf "$LOCK_DIR"
}

# ===========================================================================
# main
# ===========================================================================
log "=================================================="
log "Starting Zero-Touch USB Recovery scan..."
log "=================================================="

for tool in bzcat tar awk grep tr; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        log "FATAL: required tool '$tool' not found."
        exit 9
    fi
done

if ! acquire_lock; then
    log "ERROR: another USB recovery is already running (pid ${LOCK_HOLDER:-?}). Aborting."
    exit 6
fi
trap cleanup EXIT
trap 'log "Interrupted by signal."; exit 130' INT TERM HUP

if ! mkdir -p "$MOUNT_DIR" "$WORK_DIR" 2>/dev/null; then
    log "FATAL: cannot create work directories under /tmp."
    exit 8
fi
safe_umount                                    # stale mount left by a previous crashed run

# 1. Force loading of USB storage and filesystem kernel modules
log "Probing USB storage and filesystem kernel modules..."
modprobe bcm_usb 2>/dev/null
modprobe usb-storage 2>/dev/null
modprobe sd_mod 2>/dev/null
modprobe vfat 2>/dev/null
modprobe ext4 2>/dev/null
modprobe ufsd 2>/dev/null

# 2. Check for USB mass storage block devices (polled, not a blind sleep)
wait_for_devices
DEVICES=$(list_usb_devices)

if [ -z "$DEVICES" ]; then
    log "ERROR: No USB block devices (/dev/sd*) detected."
    log "Please plug a USB flash drive into the router USB port and retry."
    exit 1
fi

log "Detected potential USB block devices: $DEVICES"

RECOVERY_ARCHIVE=""
MOUNTED_DEV=""
FOUND_ANY=0
LAST_FAIL=3
ARCHIVE_ENTRIES=0

# 3. Scan each device and partition; a bad candidate does NOT stop the scan
for dev in $DEVICES; do
    if is_disk_with_partitions "$dev"; then
        log "Skipping $dev (whole disk, its partitions are checked individually)."
        continue
    fi
    log "Checking partition/disk $dev..."

    if ! try_mount "$dev"; then
        sleep 1                                # freshly created node: one more attempt
        try_mount "$dev" || continue
    fi
    log "Successfully mounted $dev on $MOUNT_DIR"

    # Search for known recovery packages in root of USB or rescue/ folder
    for target in $TARGET_NAMES; do
        for cand in "$MOUNT_DIR/$target" "$MOUNT_DIR/rescue/$target"; do
            [ -f "$cand" ] || continue
            FOUND_ANY=1
            log "Found recovery target: $cand on $dev"
            verify_candidate "$cand"
            rc=$?
            if [ "$rc" -eq 0 ]; then
                RECOVERY_ARCHIVE="$cand"
                MOUNTED_DEV="$dev"
                break 3
            fi
            LAST_FAIL="$rc"
            log "Candidate rejected (code $rc), continuing the scan..."
        done
    done

    safe_umount
done

if [ -z "$RECOVERY_ARCHIVE" ] || [ ! -f "$RECOVERY_ARCHIVE" ]; then
    if [ "$FOUND_ANY" -eq 1 ]; then
        log "FATAL: recovery archive(s) found, but none passed verification!"
        exit "$LAST_FAIL"
    fi
    log "ERROR: No recovery archive found on attached USB storage."
    log "Expected one of: $TARGET_NAMES in USB root directory or /rescue/ folder."
    exit 2
fi

log "Using verified recovery archive: $RECOVERY_ARCHIVE on $MOUNTED_DEV"

# 5. Extraction (only from an archive that passed every check)
log "Extracting recovery archive to system root ($EXTRACT_ROOT)..."
log "This will safely overwrite damaged GUI files and restore base functionality."

if ! extract_archive "$RECOVERY_ARCHIVE"; then
    log "FATAL: Extraction error encountered during tar unpack!"
    exit 5
fi

log "Extraction complete! Syncing filesystem buffers..."
sync

# Cleanly unmount USB
safe_umount
log "Unmounted USB partition $MOUNTED_DEV"

# 6. Re-execute initialization and restart services
log "Executing post-recovery service reconfiguration..."
WARNINGS=0

# Ensure executable permissions on essential scripts
chmod +x /etc/init.d/rootdevice /etc/init.d/transformer /etc/init.d/nginx 2>/dev/null
chmod +x /usr/share/transformer/scripts/* 2>/dev/null
chmod +x /usr/bin/safe-poweroff.sh /usr/bin/wps-poweroff-monitor.sh 2>/dev/null

if [ -x /etc/init.d/rootdevice ]; then
    log "Running /etc/init.d/rootdevice force..."
    /etc/init.d/rootdevice force >>"$LOG_FILE" 2>&1 </dev/null
    if [ $? -ne 0 ]; then
        log "WARNING: /etc/init.d/rootdevice force returned an error."
        WARNINGS=1
    fi
else
    log "Restarting transformer and nginx directly..."
    /etc/init.d/transformer restart >>"$LOG_FILE" 2>&1 </dev/null || WARNINGS=1
    /etc/init.d/nginx restart >>"$LOG_FILE" 2>&1 </dev/null || WARNINGS=1
    [ "$WARNINGS" -eq 1 ] && log "WARNING: a service restart returned an error."
fi

# Ensure Eco/Stealth LED state is re-applied
if [ -x /usr/share/transformer/scripts/check_ecoled.sh ]; then
    /usr/share/transformer/scripts/check_ecoled.sh >>"$LOG_FILE" 2>&1 </dev/null
fi

log "=================================================="
if [ "$WARNINGS" -eq 0 ]; then
    log "Zero-Touch Recovery SUCCESSFUL!"
    log "Web interface and core services have been restored."
else
    log "Zero-Touch Recovery COMPLETED WITH WARNINGS: files restored, check the service errors above."
fi
log "=================================================="

[ "$WARNINGS" -eq 0 ] && exit 0
exit 10
