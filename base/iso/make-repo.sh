#!/bin/bash
# make-repo.sh OUTDIR : copies only what the image needs into a clean folder, ready to become a git repository (no disk images, no installers).
set -e
BASE=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:?usage: make-repo.sh OUTDIR}
mkdir -p "$OUT/base"
rsync -a --exclude '__pycache__' "$BASE/shell" "$BASE/iso" "$BASE/sr" "$BASE/assets" "$OUT/base/"
mkdir -p "$OUT/base/vm"
rsync -a --exclude '*.qcow2' --exclude '*.fd' --exclude 'id_mjos*' --exclude 'credentials.txt' --exclude '*.log' --exclude '*.out' --exclude 'ip.txt' --exclude 'tty.txt' --exclude '__pycache__' \
  --include 'smof-*' --include 'sudo-wrapper' --include 'fonts-smof.conf' --include 'wayfire.ini' --include 'rounded-corners/' --include 'rounded-corners/*' --exclude '*' "$BASE/vm/" "$OUT/base/vm/"
cp "$BASE/donut.txt" "$BASE/fastfetch.jsonc" "$OUT/base/" 2>/dev/null || true
mkdir -p "$OUT/.github/workflows"
cp "$BASE/iso/.github/workflows/build-iso.yml" "$OUT/.github/workflows/"
rm -rf "$OUT/base/iso/out" "$OUT/base/iso/.github"
du -sh "$OUT"
