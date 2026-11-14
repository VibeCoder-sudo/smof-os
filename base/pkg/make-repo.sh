#!/bin/bash
# make-repo.sh OUTDIR : builds the architecture independent smof-shell package and the repo database next to it.
# Run on an Arch machine as a normal user (makepkg refuses root). The result is a folder you can serve over http or upload as release files.
set -e
HERE=$(cd "$(dirname "$0")" && pwd); export SMOF_BASE=${SMOF_BASE:-$(cd "$HERE/.." && pwd)}
OUT=${1:?output folder}; mkdir -p "$OUT"
export SMOF_PKGVER=${SMOF_PKGVER:-$(date -u +%Y%m%d.%H%M%S)}
cd "$HERE/smof-shell"
PKGDEST="$OUT" makepkg -f --nodeps --noconfirm
# the Wayfire plugins are compiled, so they need Wayfire and its headers on this machine. Without Wayfire (for example a quick test on another system) they are skipped.
if pacman -Q wayfire >/dev/null 2>&1; then
  cd "$HERE/smof-wayfire-plugins"
  PKGDEST="$OUT" makepkg -f --nodeps --noconfirm
else
  echo "wayfire is not installed here, skipping smof-wayfire-plugins"
fi
cd "$OUT"
for n in smof-shell smof-wayfire-plugins; do
  ls $n-[0-9]*.pkg.tar.* 2>/dev/null | grep -v '.sig$' | sort | head -n -3 | xargs rm -f      # keep the last three versions of each
done
rm -f smof.db* smof.files*
repo-add smof.db.tar.gz $(ls smof-*.pkg.tar.* | grep -v '.sig$') >/dev/null
rm -f smof.db smof.files smof.files.tar.gz; cp smof.db.tar.gz smof.db
echo "repo ready in $OUT, version $SMOF_PKGVER"
