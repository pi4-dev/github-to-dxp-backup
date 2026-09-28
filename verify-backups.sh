#!/bin/sh

set -eu

BACKUP_ROOT="${BACKUP_ROOT:?Set BACKUP_ROOT to the backup data directory}"

found=0
failures=0

for repo in "$BACKUP_ROOT"/repositories/*/repository; do
    if [ ! -d "$repo" ]; then
        continue
    fi

    found=1

    echo
    echo "=== $repo ==="

    if git -c safe.directory="$repo" \
        --git-dir="$repo" \
        fsck --full
    then
        echo "PASS"
    else
        echo "FAIL" >&2
        failures=$((failures + 1))
    fi
done

echo

if [ "$found" -eq 0 ]; then
    echo "No repository mirrors found under: $BACKUP_ROOT/repositories" >&2
    exit 1
fi

if [ "$failures" -ne 0 ]; then
    echo "$failures repository mirror(s) failed verification." >&2
    exit 1
fi

echo "All repository mirrors passed git fsck --full."
