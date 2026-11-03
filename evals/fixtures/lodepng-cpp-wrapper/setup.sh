#!/usr/bin/env bash
# Imports lodepng at a pinned commit into the evaluation workspace as a git repository.
# Set CPP_EVAL_SOURCES to a directory holding the archive to avoid downloading.
set -euo pipefail
cd "$(dirname "$0")"
commit="e584a8490db1b76b81bf298c11c09d3b55d9c270"
archive_name="lodepng-$commit.tar.gz"
url="https://github.com/lvandeve/lodepng/archive/$commit.tar.gz"
sha256="c9cc1dcd143bd1365f0ce50cfc14bacab43d7bee5a2be212d6f4b73eefa8626f"
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
cp -R "$scratch/unpack/lodepng-$commit/." .
rm -f setup.sh
git init -q
git add -A
git -c user.name=import -c user.email=import@example.invalid commit -q -m "Import lodepng $commit"
# Keep build and test outputs out of the reviewed diff.
printf '%s\n' /unittest /benchmark /pngdetail /showpng >> .git/info/exclude
