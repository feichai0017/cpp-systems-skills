#!/usr/bin/env bash
# Imports TinyXML-2 2.2.0 into the evaluation workspace as a git repository.
# Set CPP_EVAL_SOURCES to a directory holding the archive to avoid downloading.
set -euo pipefail
cd "$(dirname "$0")"
archive_name="tinyxml2-2.2.0.tar.gz"
url="https://github.com/leethomason/tinyxml2/archive/refs/tags/2.2.0.tar.gz"
sha256="f891224f32e7a06bf279290619cec80cc8ddc335c13696872195ffb87f5bce67"
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
cp -R "$scratch/unpack/tinyxml2-2.2.0/." .
rm -f setup.sh
git init -q
git add -A
git -c user.name=import -c user.email=import@example.invalid commit -q -m "Import TinyXML-2 2.2.0"
# Keep build and test outputs out of the reviewed diff.
printf '%s\n' /xmltest /resources/out/ /resources/bomtest.xml >> .git/info/exclude
