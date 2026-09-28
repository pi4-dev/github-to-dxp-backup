#!/bin/sh

set -eu

GH_ACCOUNT="${GH_ACCOUNT:?GH_ACCOUNT must be set}"
GH_ORGANIZATION="${GH_ORGANIZATION:-false}"
BACKUP_INTERVAL="${BACKUP_INTERVAL:-21600}"
FULL_INTERVAL="${FULL_INTERVAL:-604800}"
KEEPALIVE_URL="${KEEPALIVE_URL:-}"
KEEPALIVE_TIMEOUT="${KEEPALIVE_TIMEOUT:-10}"

BACKUP_DIR="/data"
STATUS_DIR="${BACKUP_DIR}/status"
TOKEN_FILE="/run/secrets/github_token"

mkdir -p "${STATUS_DIR}"

LAST_FULL="${STATUS_DIR}/last-full"
LAST_SUCCESS="${STATUS_DIR}/last-success"
LAST_FAILURE="${STATUS_DIR}/last-failure"

send_keepalive() {
    if [ -z "$KEEPALIVE_URL" ]; then
        return 0
    fi

    echo "[$(date -Iseconds)] sending keepalive notification"

    if python -c '
import sys
import urllib.request

url = sys.argv[1]
timeout = float(sys.argv[2])

with urllib.request.urlopen(url, timeout=timeout) as response:
    status = getattr(response, "status", 200)

raise SystemExit(0 if 200 <= status < 400 else 1)
' "$KEEPALIVE_URL" "$KEEPALIVE_TIMEOUT"
    then
        echo "[$(date -Iseconds)] keepalive notification succeeded"
    else
        echo "[$(date -Iseconds)] WARNING: keepalive notification failed" >&2
    fi
}

run_backup() {
    mode="$1"
    incremental=""
    organization=""

    if [ "$mode" = "incremental" ]; then
        incremental="--incremental"
    fi

    if [ "$GH_ORGANIZATION" = "true" ]; then
        organization="--organization"
    fi

    echo "[$(date -Iseconds)] starting $mode backup for $GH_ACCOUNT"

    if github-backup \
        "$GH_ACCOUNT" \
        --token-fine "file://$TOKEN_FILE" \
        --output-directory "$BACKUP_DIR" \
        $organization \
        $incremental \
        --private \
        --fork \
        --repositories \
        --bare \
        --lfs \
        --wikis \
        --issues \
        --issue-comments \
        --issue-events \
        --issue-timeline \
        --pulls \
        --pull-comments \
        --pull-reviews \
        --pull-commits \
        --pull-details \
        --labels \
        --milestones \
        --discussions \
        --releases \
        --assets \
        --attachments \
        --retries 5
    then
        touch "$LAST_SUCCESS"
        rm -f "$LAST_FAILURE"

        if [ "$mode" = "full" ]; then
            touch "$LAST_FULL"
        fi

        echo "[$(date -Iseconds)] backup completed successfully"

        # Notify external monitoring only after the backup and local
        # status updates have completed successfully.
        send_keepalive

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
