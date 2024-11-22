#!/bin/bash

# Set environment variable for the backup passphrase
export BORG_PASSPHRASE="your-secure-password"

# Define log file
LOGFILE="/var/log/borg_backup.log"

# Lock file for flock
LOCKFILE="/var/run/borg_backup.lock"

# Minimum free space in gigabytes (adjust as needed)
MIN_FREE_SPACE_GB=10

# Excluded paths (relative to each backup source path)
EXCLUDE_PATHS=(
    "/path/to/exclude/dir1"
    "/path/to/exclude/file1"
    "/path/to/exclude/dir2"
)

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

# Function: Check free space on the backup repository
check_free_space() {
    local repo_host=$1
    local repo_path=$2

    # Use SSH to query free space on the backup system
    local free_space=$(ssh "$repo_host" "df -BG \"$repo_path\" | awk 'NR==2 {print \$4}' | tr -d 'G'")
    if [ -z "$free_space" ]; then
        error_exit "Failed to check free space on $repo_host:$repo_path"
    fi

    log_info "Free space on $repo_host:$repo_path: ${free_space}GB"
    if (( free_space < MIN_FREE_SPACE_GB )); then
        error_exit "Not enough free space on $repo_host:$repo_path (required: ${MIN_FREE_SPACE_GB}GB, available: ${free_space}GB)"
    fi
}

# Backup repositories and directories with multiple source paths
BACKUPS=(
    # Format: "REPOSITORY PATH1 PATH2 PATH3 ..."
    "backup@Server:/mnt/backup/docker /var/lib/docker /etc/docker"
    "backup@Server:/mnt/backup/system /etc /var/log"
)

# Lock the script to prevent parallel execution
exec 200>$LOCKFILE
flock -n 200 || error_exit "Backup is already running. Exiting."

# Backup loop
for backup in "${BACKUPS[@]}"; do
    # Extract repository and source paths
    REPO=$(echo "$backup" | awk '{print $1}')
    PATHS=$(echo "$backup" | cut -d' ' -f2-)

    # Parse repository for host and path
    REPO_HOST=$(echo "$REPO" | cut -d':' -f1)
    REPO_PATH=$(echo "$REPO" | cut -d':' -f2)

    # Check free space before starting backup
    check_free_space "$REPO_HOST" "$REPO_PATH"

    # Generate snapshot name (date for all paths in the same repository)
    SNAPSHOT_NAME=$(basename "$REPO")-$(date +%Y-%m-%d)

    # Debug: Start backup
    log_info "Starting backup for repository: $REPO with paths: $PATHS"

    # Build the exclude arguments
    EXCLUDE_ARGS=""
    for exclude in "${EXCLUDE_PATHS[@]}"; do
        EXCLUDE_ARGS="$EXCLUDE_ARGS --exclude $exclude"
    done

    # Create backup with exclusions
    borg create --progress --stats --compression lz4 \
        $EXCLUDE_ARGS "$REPO::${SNAPSHOT_NAME}" $PATHS 2>>"$LOGFILE" || error_exit "Backup failed for $REPO"

    # Debug: Start prune
    log_info "Starting prune for repository: $REPO"

    # Clean up old backups (Prune)
    borg prune --list --keep-daily=7 --keep-weekly=4 --keep-monthly=3 "$REPO" 2>>"$LOGFILE" || error_exit "Prune failed for $REPO"
done

# Debug: Finished
log_info "Backup and prune completed."

# Disable debug mode
set +x
