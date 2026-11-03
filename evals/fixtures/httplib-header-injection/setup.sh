#!/usr/bin/env bash
# Imports cpp-httplib 0.12.3 into the evaluation workspace as a git repository.
# Set CPP_EVAL_SOURCES to a directory holding the archive to avoid downloading.
set -euo pipefail
cd "$(dirname "$0")"
archive_name="cpp-httplib-0.12.3.tar.gz"
url="https://github.com/yhirose/cpp-httplib/archive/refs/tags/v0.12.3.tar.gz"
sha256="175ced3c9cdaf221e9edf210297568d8f7d402a41d6db01254ac9e0b25487c54"
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
cp -R "$scratch/unpack/cpp-httplib-0.12.3/." .
rm -f setup.sh
git init -q
git add -A
git -c user.name=import -c user.email=import@example.invalid commit -q -m "Import cpp-httplib 0.12.3"
# Keep build and test outputs out of the reviewed diff.
printf '%s\n' /test/test /test/*.o >> .git/info/exclude
