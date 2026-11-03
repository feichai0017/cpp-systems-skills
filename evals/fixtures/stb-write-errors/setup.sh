#!/usr/bin/env bash
# Imports stb at commit 003501f into the evaluation workspace as a git repository.
# Set CPP_EVAL_SOURCES to a directory holding the archive to avoid downloading.
set -euo pipefail
cd "$(dirname "$0")"
archive_name="stb-003501f6d7a8668ce8b6d875e34dd97ad0d5d5b5.tar.gz"
url="https://github.com/nothings/stb/archive/003501f6d7a8668ce8b6d875e34dd97ad0d5d5b5.tar.gz"
sha256="a6c31950b3bdf05eb92258768ba2a11bd44449490574b1aac67028452288c40d"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
if [ -n "${CPP_EVAL_SOURCES:-}" ] && [ -f "$CPP_EVAL_SOURCES/$archive_name" ]; then
  cp "$CPP_EVAL_SOURCES/$archive_name" "$scratch/$archive_name"
else
  curl -fsSL -o "$scratch/$archive_name" "$url"
fi
python3 -c 'import hashlib, sys; sys.exit(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest() != sys.argv[2])' \
  "$scratch/$archive_name" "$sha256" || { echo "checksum mismatch for $archive_name" >&2; exit 1; }
mkdir "$scratch/unpack"
tar -xzf "$scratch/$archive_name" -C "$scratch/unpack"
cp -R "$scratch/unpack/stb-003501f6d7a8668ce8b6d875e34dd97ad0d5d5b5/." .
rm -f setup.sh
git init -q
git add -A
git -c user.name=import -c user.email=import@example.invalid commit -q -m "Import stb 003501f"
# Keep build and test outputs out of the reviewed diff.
printf '%s\n' /tests/output/ /tests/image_write_test >> .git/info/exclude
