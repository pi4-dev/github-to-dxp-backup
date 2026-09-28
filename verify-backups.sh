#!/bin/sh

set -eu

BACKUP_ROOT="${BACKUP_ROOT:?Set BACKUP_ROOT to the backup data directory}"

found=0
failures=0

echo "Starting repository integrity verification."

for repo in "$BACKUP_ROOT"/repositories/*/repository; do
    if [ ! -d "$repo" ]; then
        continue
    fi

    found=1

    echo
    echo "=== Git fsck: $repo ==="

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
    echo "$failures repository mirror(s) failed git fsck." >&2
    exit 1
fi

echo "All Git mirrors passed git fsck --full."
echo
echo "Validating JSON metadata and Git LFS object hashes."

python - "$BACKUP_ROOT" <<'PY'
import hashlib
import json
import os
import string
import sys

backup_root = sys.argv[1]
json_checked = 0
lfs_checked = 0
errors = []
hexchars = set(string.hexdigits.lower())

for directory, _, filenames in os.walk(backup_root):
    normalized = directory.replace(os.sep, "/")

    for filename in filenames:
        path = os.path.join(directory, filename)

        if filename.endswith(".json"):
            json_checked += 1
            try:
                with open(path, "r", encoding="utf-8") as handle:
                    json.load(handle)
            except Exception as exc:
                errors.append(f"Invalid JSON: {path}: {exc}")

        if "/lfs/objects/" in normalized:
            oid = filename.lower()

            if len(oid) == 64 and all(char in hexchars for char in oid):
                lfs_checked += 1
                digest = hashlib.sha256()

                try:
                    with open(path, "rb") as handle:
                        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                            digest.update(chunk)
                except Exception as exc:
                    errors.append(f"Cannot read LFS object: {path}: {exc}")
                    continue

                if digest.hexdigest() != oid:
                    errors.append(
                        f"LFS SHA-256 mismatch: {path}: "
                        f"expected {oid}, got {digest.hexdigest()}"
                    )

print(f"JSON files checked: {json_checked}")
print(f"LFS objects checked: {lfs_checked}")

if errors:
    for error in errors:
        print(error, file=sys.stderr)
    raise SystemExit(1)
PY

echo
echo "Backup verification completed successfully."
