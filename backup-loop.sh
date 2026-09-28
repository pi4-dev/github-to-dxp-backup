#!/bin/sh

set -eu

GH_ACCOUNT="${GH_ACCOUNT:?GH_ACCOUNT must be set}"
GH_ORGANIZATION="${GH_ORGANIZATION:-false}"
BACKUP_INTERVAL="${BACKUP_INTERVAL:-21600}"
FULL_INTERVAL="${FULL_INTERVAL:-604800}"
KEEPALIVE_URL="${KEEPALIVE_URL:-}"
KEEPALIVE_TIMEOUT="${KEEPALIVE_TIMEOUT:-10}"
VERIFY_INTERVAL="${VERIFY_INTERVAL:-604800}"
VERIFY_KEEPALIVE_URL="${VERIFY_KEEPALIVE_URL:-}"
VERIFY_KEEPALIVE_TIMEOUT="${VERIFY_KEEPALIVE_TIMEOUT:-10}"

BACKUP_DIR="/data"
STATUS_DIR="${BACKUP_DIR}/status"
TOKEN_FILE="/run/secrets/github_token"
VERIFIER_SCRIPT="/verify-backups.sh"

mkdir -p "${STATUS_DIR}"

LAST_FULL="${STATUS_DIR}/last-full"
LAST_SUCCESS="${STATUS_DIR}/last-success"
LAST_FAILURE="${STATUS_DIR}/last-failure"
LAST_VERIFY_SUCCESS="${STATUS_DIR}/last-verify-success"
LAST_VERIFY_FAILURE="${STATUS_DIR}/last-verify-failure"

send_keepalive() {
    url="$1"
    timeout="$2"
    label="$3"

    if [ -z "$url" ]; then
        return 0
    fi

    echo "[$(date -Iseconds)] sending $label keepalive notification"

    if python -c '
import sys
import urllib.request

url = sys.argv[1]
timeout = float(sys.argv[2])

with urllib.request.urlopen(url, timeout=timeout) as response:
    status = getattr(response, "status", 200)

raise SystemExit(0 if 200 <= status < 400 else 1)
' "$url" "$timeout"
    then
        echo "[$(date -Iseconds)] $label keepalive notification succeeded"
    else
        echo "[$(date -Iseconds)] WARNING: $label keepalive notification failed" >&2
    fi
}

verification_due() {
    if [ ! -f "$LAST_VERIFY_SUCCESS" ]; then
        return 0
    fi

    now="$(date +%s)"
    last_verify="$(stat -c %Y "$LAST_VERIFY_SUCCESS" 2>/dev/null || echo 0)"
    age=$((now - last_verify))

    [ "$age" -ge "$VERIFY_INTERVAL" ]
}

run_verification_if_due() {
    if ! verification_due; then
        return 0
    fi

    echo "[$(date -Iseconds)] starting backup verification"

    if BACKUP_ROOT="$BACKUP_DIR" sh "$VERIFIER_SCRIPT"; then
        touch "$LAST_VERIFY_SUCCESS"
        rm -f "$LAST_VERIFY_FAILURE"

        echo "[$(date -Iseconds)] backup verification completed successfully"

        send_keepalive \
            "$VERIFY_KEEPALIVE_URL" \
            "$VERIFY_KEEPALIVE_TIMEOUT" \
            "verification"
    else
        touch "$LAST_VERIFY_FAILURE"
        echo "[$(date -Iseconds)] ERROR: backup verification failed" >&2
        echo "[$(date -Iseconds)] verification keepalive will not be sent" >&2
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

        send_keepalive \
            "$KEEPALIVE_URL" \
            "$KEEPALIVE_TIMEOUT" \
            "backup"

        run_verification_if_due

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
