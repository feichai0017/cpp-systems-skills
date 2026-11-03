#!/usr/bin/env bash
# Imports minIni at commit 1bb6557 into the evaluation workspace as a git repository.
# Set CPP_EVAL_SOURCES to a directory holding the archive to avoid downloading.
set -euo pipefail
cd "$(dirname "$0")"
archive_name="minIni-1bb6557030964c921da374e6541e6acb965588e2.tar.gz"
url="https://github.com/compuphase/minIni/archive/1bb6557030964c921da374e6541e6acb965588e2.tar.gz"
sha256="9af9d8ef61325d4decff6b19fbb21dfc2f4c5377792a179abbd0ee8dc95841ef"
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
cp -R "$scratch/unpack/minIni-1bb6557030964c921da374e6541e6acb965588e2/." .
rm -f setup.sh
git init -q
git add -A
git -c user.name=import -c user.email=import@example.invalid commit -q -m "Import minIni 1bb6557"
# Keep build and test outputs out of the reviewed diff.
printf '%s\n' /dev/test /dev/test2 /dev/*.o >> .git/info/exclude
