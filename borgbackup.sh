#!/bin/bash

# Set environment variable for the backup passphrase
export BORG_PASSPHRASE="your-secure-password"

# Define log file
LOGFILE="/var/log/borg_backup.log"

# Lock file for flock
LOCKFILE="/var/run/borg_backup.lock"

# Enable debug mode (show all commands before execution)
set -x

# Error handling function
error_exit() {
    echo "[$(date)] Backup failed: $1" | tee -a "$LOGFILE"
    exit 1
}

# Log information function
log_info() {
    echo "[$(date)] $1" | tee -a "$LOGFILE"
}

# Backup repositories and directories with multiple source paths
BACKUPS=(
    # Format: "REPOSITORY PATH1 PATH2 PATH3 ..."
    "homelab@maxServer002:/mnt/backup/docker /var/lib/docker /etc/docker"
    "homelab@maxServer002:/mnt/backup/system /etc /var/log"
)

# Lock the script to prevent parallel execution
exec 200>$LOCKFILE
flock -n 200 || error_exit "Backup is already running. Exiting."

# Backup loop
for backup in "${BACKUPS[@]}"; do
    # Extract repository and source paths
    REPO=$(echo "$backup" | awk '{print $1}')
    PATHS=$(echo "$backup" | cut -d' ' -f2-)

    # Generate snapshot name (date for all paths in the same repository)
    SNAPSHOT_NAME=$(basename "$REPO")-$(date +%Y-%m-%d)

    # Debug: Start backup
    log_info "Starting backup for repository: $REPO with paths: $PATHS"

    # Create backup
    borg create --progress --stats --compression lz4 \
        "$REPO::${SNAPSHOT_NAME}" $PATHS 2>>"$LOGFILE" || error_exit "Backup failed for $REPO"

    # Debug: Start prune
    log_info "Starting prune for repository: $REPO"

    # Clean up old backups (Prune)
    borg prune --list --keep-daily=7 --keep-weekly=4 --keep-monthly=3 "$REPO" 2>>"$LOGFILE" || error_exit "Prune failed for $REPO"
done

# Debug: Finished
log_info "Backup and prune completed."

# Disable debug mode
set +x
