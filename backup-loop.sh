#!/bin/sh

set -eu

GH_ACCOUNT="${GH_ACCOUNT:?GH_ACCOUNT must be set}"
BACKUP_INTERVAL="${BACKUP_INTERVAL:-21600}"
FULL_INTERVAL="${FULL_INTERVAL:-604800}"

BACKUP_DIR="/data"
STATUS_DIR="${BACKUP_DIR}/status"
TOKEN_FILE="/run/secrets/github_token"

mkdir -p "${STATUS_DIR}"

LAST_FULL="${STATUS_DIR}/last-full"
LAST_SUCCESS="${STATUS_DIR}/last-success"
LAST_FAILURE="${STATUS_DIR}/last-failure"

run_backup() {
    mode="$1"

    incremental=""

    if [ "$mode" = "incremental" ]; then
        incremental="--incremental"
    fi

    echo "[$(date -Iseconds)] starting $mode backup for $GH_ACCOUNT"

    if github-backup         "$GH_ACCOUNT"         --token-fine "file://$TOKEN_FILE"         --output-directory "$BACKUP_DIR"         $incremental         --private         --fork         --repositories         --bare         --lfs         --wikis         --issues         --issue-comments         --issue-events         --issue-timeline         --pulls         --pull-comments         --pull-reviews         --pull-commits         --pull-details         --labels         --milestones         --discussions         --releases         --assets         --attachments         --retries 5
    then
        touch "$LAST_SUCCESS"
        rm -f "$LAST_FAILURE"

        if [ "$mode" = "full" ]; then
            touch "$LAST_FULL"
        fi

        echo "[$(date -Iseconds)] backup completed successfully"
        return 0
    fi

    touch "$LAST_FAILURE"
    echo "[$(date -Iseconds)] backup failed" >&2
    return 1
}

while true; do
    now="$(date +%s)"

    if [ ! -f "$LAST_FULL" ]; then
        mode="full"
    else
        last_full="$(stat -c %Y "$LAST_FULL" 2>/dev/null || echo 0)"
        age=$((now - last_full))

        if [ "$age" -ge "$FULL_INTERVAL" ]; then
            mode="full"
        else
            mode="incremental"
        fi
    fi

    run_backup "$mode" || true

    echo "[$(date -Iseconds)] next run in $BACKUP_INTERVAL seconds"
    sleep "$BACKUP_INTERVAL"
done
