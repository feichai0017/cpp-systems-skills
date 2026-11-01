#!/usr/bin/env bash
# Imports utf8proc 2.12.0 into the evaluation workspace as a git repository.
# Set CPP_EVAL_SOURCES to a directory holding the archive to avoid downloading.
set -euo pipefail
cd "$(dirname "$0")"
archive_name="utf8proc-2.12.0.tar.gz"
url="https://github.com/JuliaStrings/utf8proc/archive/refs/tags/v2.12.0.tar.gz"
sha256="f564011d38b2888d583d510b08e69ffa15aa117155db1b9b49ef1dfe1fa25111"
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
cp -R "$scratch/unpack/utf8proc-2.12.0/." .
rm -f setup.sh
git init -q
git add -A
git -c user.name=import -c user.email=import@example.invalid commit -q -m "Import utf8proc 2.12.0"
# Keep build and test outputs out of the reviewed diff.
printf '%s\n' '*.o' '*.a' '*.dylib' '*.so*' /test/charwidth /test/misc /test/valid /test/iterate /test/custom /test/strwidth >> .git/info/exclude
