#!/usr/bin/env bash
# Imports jsmn 25647e6 into the evaluation workspace as a git repository.
# Set CPP_EVAL_SOURCES to a directory holding the archive to avoid downloading.
set -euo pipefail
cd "$(dirname "$0")"
archive_name="jsmn-25647e692c7906b96ffd2b05ca54c097948e879c.tar.gz"
url="https://github.com/zserge/jsmn/archive/25647e692c7906b96ffd2b05ca54c097948e879c.tar.gz"
sha256="02ac62537ea34ee33b55efa41a832b78086548715298a454b6f304e29a7c9d43"
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
cp -R "$scratch/unpack/jsmn-25647e692c7906b96ffd2b05ca54c097948e879c/." .
rm -f setup.sh
git init -q
git add -A
git -c user.name=import -c user.email=import@example.invalid commit -q -m "Import jsmn 25647e6"
# Keep build and test outputs out of the reviewed diff.
printf '%s\n' '/test/test_*' >> .git/info/exclude
