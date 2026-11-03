#!/usr/bin/env bash
# Imports TinyXML 2.6.2 into the evaluation workspace as a git repository.
# Set CPP_EVAL_SOURCES to a directory holding tinyxml_2_6_2.zip to avoid downloading.
set -euo pipefail
cd "$(dirname "$0")"
archive_name="tinyxml_2_6_2.zip"
url="https://sourceforge.net/projects/tinyxml/files/tinyxml/2.6.2/tinyxml_2_6_2.zip/download"
sha256="ac6bb9501c6f50cc922d22f26b02fab168db47521be5e845b83d3451a3e1d512"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
if [ -n "${CPP_EVAL_SOURCES:-}" ] && [ -f "$CPP_EVAL_SOURCES/$archive_name" ]; then
  cp "$CPP_EVAL_SOURCES/$archive_name" "$scratch/$archive_name"
else
  curl -fsSL -o "$scratch/$archive_name" "$url"
fi
python3 -c 'import hashlib, sys; sys.exit(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest() != sys.argv[2])' \
  "$scratch/$archive_name" "$sha256" || { echo "checksum mismatch for $archive_name" >&2; exit 1; }
unzip -q "$scratch/$archive_name" -d "$scratch/unpack"
cp -R "$scratch/unpack/tinyxml/." .
rm -f setup.sh
git init -q
git add -A
git -c user.name=import -c user.email=import@example.invalid commit -q -m "Import TinyXML 2.6.2"
# Keep build and test outputs out of the reviewed diff.
printf '%s\n' /xmltest /demotest.xml /test5.xml /test6.xml /test7.xml /textfile.txt /utf8testout.xml >> .git/info/exclude
