#!/usr/bin/env bash
# Imports cxxopts 3.3.1 into the evaluation workspace as a git repository.
# Set CPP_EVAL_SOURCES to a directory holding the archive to avoid downloading.
set -euo pipefail
cd "$(dirname "$0")"
archive_name="cxxopts-3.3.1.tar.gz"
url="https://github.com/jarro2783/cxxopts/archive/refs/tags/v3.3.1.tar.gz"
sha256="3bfc70542c521d4b55a46429d808178916a579b28d048bd8c727ee76c39e2072"
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
cp -R "$scratch/unpack/cxxopts-3.3.1/." .
rm -f setup.sh
git init -q
git add -A
git -c user.name=import -c user.email=import@example.invalid commit -q -m "Import cxxopts 3.3.1"
# Keep build and test outputs out of the reviewed diff.
printf '%s\n' /build/ /build17/ >> .git/info/exclude
