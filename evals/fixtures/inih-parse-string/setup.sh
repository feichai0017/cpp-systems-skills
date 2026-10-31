#!/usr/bin/env bash
# Imports inih r30 into the evaluation workspace as a git repository.
# Set CPP_EVAL_SOURCES to a directory holding the archive to avoid downloading.
set -euo pipefail
cd "$(dirname "$0")"
archive_name="inih-r30.tar.gz"
url="https://github.com/benhoyt/inih/archive/refs/tags/r30.tar.gz"
sha256="929cff6f3306781eca7dcc66fb54eb46f4fa48138c391489d4e1a2ced8382137"
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
cp -R "$scratch/unpack/inih-r30/." .
rm -f setup.sh
git init -q
git add -A
git -c user.name=import -c user.email=import@example.invalid commit -q -m "Import inih r30"
# Keep build and test outputs out of the reviewed diff.
printf '%s\n' /tests/unittest /tests/out.txt /cpp/INIReaderTest >> .git/info/exclude
