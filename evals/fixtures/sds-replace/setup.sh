#!/usr/bin/env bash
# Imports sds 5347739 into the evaluation workspace as a git repository.
# Set CPP_EVAL_SOURCES to a directory holding the archive to avoid downloading.
set -euo pipefail
cd "$(dirname "$0")"
archive_name="sds-5347739b1581fcba74fd5cab1fc21d2aef317d71.tar.gz"
url="https://github.com/antirez/sds/archive/5347739b1581fcba74fd5cab1fc21d2aef317d71.tar.gz"
sha256="37a4afd7d2b766609dfb0c2e3da84eaec74d00302165c0d04a0f42b204dfb295"
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
cp -R "$scratch/unpack/sds-5347739b1581fcba74fd5cab1fc21d2aef317d71/." .
rm -f setup.sh
git init -q
git add -A
git -c user.name=import -c user.email=import@example.invalid commit -q -m "Import sds 5347739"
# Keep build and test outputs out of the reviewed diff.
printf '%s\n' /sds-test >> .git/info/exclude
