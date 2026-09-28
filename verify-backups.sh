#!/usr/bin/env bash

set -euo pipefail

BACKUP_ROOT="${BACKUP_ROOT:?Set BACKUP_ROOT to the backup data directory}"

mapfile -d '' repositories < <(
  find "$BACKUP_ROOT/repositories"     -mindepth 2     -maxdepth 2     -type d     -name repository     -print0
)

if [ "${#repositories[@]}" -eq 0 ]; then
  echo "No repository mirrors found under: $BACKUP_ROOT/repositories" >&2
  exit 1
fi

failures=0

for repo in "${repositories[@]}"; do
  echo
  echo "=== $repo ==="

  if git -c safe.directory="$repo"       --git-dir="$repo"       fsck --full
  then
    echo "PASS"
  else
    echo "FAIL" >&2
    failures=$((failures + 1))
  fi
done

echo

if [ "$failures" -ne 0 ]; then
  echo "$failures repository mirror(s) failed verification." >&2
  exit 1
fi

echo "All repository mirrors passed git fsck --full."
