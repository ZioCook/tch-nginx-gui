#!/bin/sh
#
# Zero-Touch USB Recovery Engine for tch-nginx-gui
# Scans attached USB drives for recovery archives, validates integrity,
# and restores the system without requiring active web or network services.
#

LOG_FILE="/tmp/rescue.log"

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [RESCUE-USB] $1"
    echo "$msg"
    echo "$msg" >> "$LOG_FILE"
    logger -t rescue_usb "$1" 2>/dev/null
}

mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"

log "=================================================="
log "Starting Zero-Touch USB Recovery scan..."
log "=================================================="

# 1. Force loading of USB storage and filesystem kernel modules
log "Probing USB storage and filesystem kernel modules..."
modprobe bcm_usb 2>/dev/null
modprobe usb-storage 2>/dev/null
modprobe sd_mod 2>/dev/null
modprobe vfat 2>/dev/null
modprobe ext4 2>/dev/null
modprobe ufsd 2>/dev/null

# Give kernel time to enumerate USB devices
sleep 2

# 2. Check for USB mass storage block devices
DEVICES=$(ls /dev/sd[a-z]* 2>/dev/null)

if [ -z "$DEVICES" ]; then
    log "ERROR: No USB block devices (/dev/sd*) detected."
    log "Please plug a USB flash drive into the router USB port and retry."
    exit 1
fi

log "Detected potential USB block devices: $DEVICES"

MOUNT_DIR="/tmp/rescue_usb"
mkdir -p "$MOUNT_DIR"

TARGET_NAMES="ziocook-gui-recovery.tar.bz2 GUI.tar.bz2 GUI_upload.tar.bz2 tch-gui-recovery.tar.bz2"
RECOVERY_ARCHIVE=""
MOUNTED_DEV=""

# 3. Scan each device and partition
for dev in $DEVICES; do
    log "Checking partition/disk $dev..."
    
    # Try mounting read-only
    umount -l "$MOUNT_DIR" 2>/dev/null
    if ! mount -o ro "$dev" "$MOUNT_DIR" 2>/dev/null; then
        # Try explicitly with common filesystems
        if ! mount -t vfat -o ro "$dev" "$MOUNT_DIR" 2>/dev/null && \
           ! mount -t ext4 -o ro "$dev" "$MOUNT_DIR" 2>/dev/null && \
           ! mount -t ufsd -o ro "$dev" "$MOUNT_DIR" 2>/dev/null; then
            continue
        fi
    fi

    log "Successfully mounted $dev on $MOUNT_DIR"

    # Search for known recovery packages in root of USB or rescue/ folder
    for target in $TARGET_NAMES; do
        if [ -f "$MOUNT_DIR/$target" ]; then
            RECOVERY_ARCHIVE="$MOUNT_DIR/$target"
            MOUNTED_DEV="$dev"
            break 2
        elif [ -f "$MOUNT_DIR/rescue/$target" ]; then
            RECOVERY_ARCHIVE="$MOUNT_DIR/rescue/$target"
            MOUNTED_DEV="$dev"
            break 2
        fi
    done

    umount -l "$MOUNT_DIR" 2>/dev/null
done

if [ -z "$RECOVERY_ARCHIVE" ] || [ ! -f "$RECOVERY_ARCHIVE" ]; then
    log "ERROR: No recovery archive found on attached USB storage."
    log "Expected one of: $TARGET_NAMES in USB root directory or /rescue/ folder."
    umount -l "$MOUNT_DIR" 2>/dev/null
    exit 2
fi

log "Found recovery target: $RECOVERY_ARCHIVE on $MOUNTED_DEV"

# 4. Integrity Verification
log "Verifying archive integrity with bzcat..."
if ! bzcat "$RECOVERY_ARCHIVE" >/dev/null 2>&1; then
    log "FATAL: Archive $RECOVERY_ARCHIVE is corrupted or incomplete!"
    umount -l "$MOUNT_DIR" 2>/dev/null
    exit 3
fi
log "Archive integrity check: PASSED"

# Optional MD5 verification if checksum file exists alongside archive
ARCHIVE_DIR=$(dirname "$RECOVERY_ARCHIVE")
ARCHIVE_BASE=$(basename "$RECOVERY_ARCHIVE")
MD5_FILE="$RECOVERY_ARCHIVE.md5"

if [ -f "$MD5_FILE" ]; then
    log "Verifying MD5 checksum from $MD5_FILE..."
    EXPECTED_MD5=$(awk '{print $1}' "$MD5_FILE")
    CALCULATED_MD5=$(md5sum "$RECOVERY_ARCHIVE" | awk '{print $1}')
    if [ "$EXPECTED_MD5" != "$CALCULATED_MD5" ]; then
        log "FATAL: MD5 mismatch! Expected: $EXPECTED_MD5, Got: $CALCULATED_MD5"
        umount -l "$MOUNT_DIR" 2>/dev/null
        exit 4
    fi
    log "MD5 checksum verification: PASSED ($CALCULATED_MD5)"
elif [ -f "$ARCHIVE_DIR/MD5SUMS" ]; then
    if grep -q "$ARCHIVE_BASE" "$ARCHIVE_DIR/MD5SUMS"; then
        EXPECTED_MD5=$(grep "$ARCHIVE_BASE" "$ARCHIVE_DIR/MD5SUMS" | awk '{print $1}')
        CALCULATED_MD5=$(md5sum "$RECOVERY_ARCHIVE" | awk '{print $1}')
        if [ "$EXPECTED_MD5" != "$CALCULATED_MD5" ]; then
            log "FATAL: MD5SUMS mismatch! Expected: $EXPECTED_MD5, Got: $CALCULATED_MD5"
            umount -l "$MOUNT_DIR" 2>/dev/null
            exit 4
        fi
        log "MD5SUMS verification: PASSED ($CALCULATED_MD5)"
    fi
fi

# 5. Extraction
log "Extracting recovery archive to system root (/)..."
log "This will safely overwrite damaged GUI files and restore base functionality."

if ! bzcat "$RECOVERY_ARCHIVE" | tar -C / -xf - 2>>"$LOG_FILE"; then
    log "FATAL: Extraction error encountered during tar unpack!"
    umount -l "$MOUNT_DIR" 2>/dev/null
    exit 5
fi

log "Extraction complete! Syncing filesystem buffers..."
sync

# Cleanly unmount USB
umount -l "$MOUNT_DIR" 2>/dev/null
log "Unmounted USB partition $MOUNTED_DEV"

# 6. Re-execute initialization and restart services
log "Executing post-recovery service reconfiguration..."

# Ensure executable permissions on essential scripts
chmod +x /etc/init.d/rootdevice /etc/init.d/transformer /etc/init.d/nginx 2>/dev/null
chmod +x /usr/share/transformer/scripts/* 2>/dev/null
chmod +x /usr/bin/safe-poweroff.sh /usr/bin/wps-poweroff-monitor.sh 2>/dev/null

if [ -x /etc/init.d/rootdevice ]; then
    log "Running /etc/init.d/rootdevice force..."
    /etc/init.d/rootdevice force >>"$LOG_FILE" 2>&1
else
    log "Restarting transformer and nginx directly..."
    /etc/init.d/transformer restart >>"$LOG_FILE" 2>&1
    /etc/init.d/nginx restart >>"$LOG_FILE" 2>&1
fi

# Ensure Eco/Stealth LED state is re-applied
if [ -x /usr/share/transformer/scripts/check_ecoled.sh ]; then
    /usr/share/transformer/scripts/check_ecoled.sh >>"$LOG_FILE" 2>&1
fi

log "=================================================="
log "Zero-Touch Recovery SUCCESSFUL!"
log "Web interface and core services have been restored."
log "=================================================="

exit 0
