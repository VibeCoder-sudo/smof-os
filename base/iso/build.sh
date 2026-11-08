#!/bin/bash
# build.sh: builds the Smof live image for x86_64 PCs (a bootable .iso). Run as root, on Arch Linux x86_64 (or in an Arch container),
# from anywhere. It needs the whole base/ folder next to this one (shell, vm, assets, sr). Result: base/iso/out/smof-*.iso
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
BASE=$(cd "$HERE/.." && pwd)
WORK=${WORK:-/tmp/smof-build}
OUT=${OUT:-$HERE/out}
[ "$(uname -m)" = x86_64 ] || { echo "this has to run on an x86_64 machine, not $(uname -m)"; exit 1; }
[ "$(id -u)" = 0 ] || { echo "run as root"; exit 1; }
say() { printf '\n== %s\n' "$*"; }

say "tools and build dependencies"
pacman -Syu --noconfirm --needed archiso base-devel git meson ninja cmake pkgconf glm vulkan-headers wayland-protocols \
  wayfire quickshell ncnn rsync python
rm -rf "$WORK"; mkdir -p "$WORK" "$OUT"
STAGE="$WORK/stage"; mkdir -p "$STAGE"/{usr/local/bin,usr/local/sbin,usr/lib/wayfire,usr/share/wayfire/metadata,usr/share/smof,etc/fonts/conf.d,usr/share/fonts/smof}

say "the parts that must be compiled for this processor"
# rounded corners and shadows: our port of the plugin, built against the wayfire and wlroots in the image
g++ -std=c++17 -O2 -shared -fPIC -DWLR_USE_UNSTABLE -DWAYFIRE_PLUGIN -o "$STAGE/usr/lib/wayfire/librounded-corners.so" \
  "$BASE/vm/rounded-corners/rounded-corners.cpp" $(pkg-config --cflags --libs wayfire wlroots-0.20 pixman-1)
install -m 644 "$BASE/vm/rounded-corners/rounded-corners.xml" "$STAGE/usr/share/wayfire/metadata/"
# window frames: pixdecor from upstream
git clone --depth 1 https://github.com/soreau/pixdecor "$WORK/pixdecor"
meson setup "$WORK/pixdecor/build" "$WORK/pixdecor" --prefix=/usr --buildtype=release
ninja -C "$WORK/pixdecor/build"
DESTDIR="$STAGE" ninja -C "$WORK/pixdecor/build" install
# the picture upscaler runner
g++ -O3 -fopenmp -o "$STAGE/usr/local/bin/smof-sr" "$BASE/sr/smof-sr.cpp" -lncnn

say "the Smof desktop files"
# every app gets its own copy of the shared QML, the same as shell/deploy.sh does
for d in greeter apps/wallpaper apps/bar apps/dock apps/notifd apps/launcher apps/settings apps/files apps/auth apps/store apps/upscaler; do
  cp "$BASE"/shell/shared/*.qml "$BASE/shell/$d/"
done
cp -r "$BASE/shell/greeter" "$STAGE/usr/share/smof/greeter"
cp -r "$BASE/shell/apps" "$STAGE/usr/share/smof/apps"
cp -r "$BASE/assets/icons" "$STAGE/usr/share/smof/icons"
mkdir -p "$STAGE/usr/share/smof/sounds" "$STAGE/usr/share/smof/models/sr" "$STAGE/usr/share/smof/skel"
cp "$BASE"/assets/sounds/*.wav "$STAGE/usr/share/smof/sounds/"
cp "$BASE"/sr/models/* "$STAGE/usr/share/smof/models/sr/"
cp "$BASE"/assets/*.webp "$BASE"/assets/*.jpg "$BASE/assets/GoogleSansFlex.woff2" "$STAGE/usr/share/smof/" 2>/dev/null || true
cp "$BASE/donut.txt" "$STAGE/usr/share/smof/" 2>/dev/null || true
install -m 644 "$BASE/assets/GoogleSansFlex.ttf" "$STAGE/usr/share/fonts/smof/GoogleSansFlex.ttf"
install -m 644 "$BASE/vm/fonts-smof.conf" "$STAGE/etc/fonts/conf.d/60-smof.conf"

say "scripts"
for s in smof-activity smof-askpass smof-bgapps smof-brew smof-cleanup smof-desktop smof-devwatch smof-display smof-downloads smof-fileops smof-files \
         smof-front smof-health smof-input smof-ipc smof-menubridge smof-pkg smof-session smof-settings smof-shell smof-shot smof-sound smof-store \
         smof-tiler smof-timer smof-upscale smof-upscaler smof-volume smof-wm-theme; do
  [ -f "$BASE/vm/$s" ] || { echo "missing script $s"; exit 1; }
  install -m 755 "$BASE/vm/$s" "$STAGE/usr/local/bin/$s"
done
install -m 755 "$BASE/vm/sudo-wrapper" "$STAGE/usr/local/bin/sudo"
for s in smof-oobe smof-splash smof-install; do install -m 755 "$BASE/vm/$s" "$STAGE/usr/local/sbin/$s"; done
cp -r "$HERE/overlay/." "$STAGE/"
chmod 755 "$STAGE/usr/local/bin/"* "$STAGE/usr/local/sbin/"*
chmod 440 "$STAGE/etc/sudoers.d/smof"
# the default config of a new user: the VM one without any screen section, smof-output-init adds the right one for the real screen
python3 - "$BASE/vm/wayfire.ini" "$STAGE/usr/share/smof/skel/wayfire.ini" <<'PY'
import re, sys
t = open(sys.argv[1]).read()
t = re.sub(r"\[output:[^\]]*\][^\[]*", "", t)
t = t.replace("[autostart]\n", "[autostart]\noutputs = /usr/local/bin/smof-output-init\n", 1)
open(sys.argv[2], "w").write(t)
PY
cp "$BASE/vm/../fastfetch.jsonc" "$STAGE/usr/share/smof/skel/fastfetch.jsonc" 2>/dev/null || true
for d in Desktop Documents Downloads Music Pictures Videos; do mkdir -p "$STAGE/usr/share/smof/skel/$d"; done

say "the image profile"
cp -r /usr/share/archiso/configs/releng "$WORK/profile"
P="$WORK/profile"
cat "$HERE/packages.txt" | grep -v '^#' | grep -v '^$' >> "$P/packages.x86_64"
sed -i 's/^iso_name=.*/iso_name="smof"/; s/^iso_label=.*/iso_label="SMOF_$(date +%Y%m)"/; s/^iso_publisher=.*/iso_publisher="Smof"/; s/^iso_application=.*/iso_application="Smof live image"/' "$P/profiledef.sh"
sed -i 's/^install_dir=.*/install_dir="smof"/' "$P/profiledef.sh"
A="$P/airootfs"
rsync -a "$STAGE/" "$A/"
# the live user, greetd starts the desktop as this user at once
echo 'smof:x:1000:1000:Smof live:/home/smof:/bin/bash' >> "$A/etc/passwd"
echo 'smof:x:1000:' >> "$A/etc/group"
echo 'smof::14871::::::' >> "$A/etc/shadow"
echo 'smof:!*::' >> "$A/etc/gshadow"
mkdir -p "$A/etc/sysusers.d"
: > "$A/etc/sysusers.d/smof-live.conf"
for g in wheel audio video input seat render; do
  if grep -q "^$g:" "$A/etc/group"; then
    sed -i "s/^$g:\(.*\)$/$g:\1,smof/; s/:,smof/:smof/" "$A/etc/group"
  else
    # groups the base files do not have are made and filled at boot by systemd-sysusers
    printf 'g %s -\nm smof %s\n' "$g" "$g" >> "$A/etc/sysusers.d/smof-live.conf"
  fi
done
mkdir -p "$A/home/smof/.config"
cp -r "$STAGE/usr/share/smof/skel/." "$A/home/smof/"
mv "$A/home/smof/wayfire.ini" "$A/home/smof/.config/wayfire.ini"
mv "$A/home/smof/fastfetch.jsonc" "$A/home/smof/.config/" 2>/dev/null || true
echo smof > "$A/etc/hostname"
echo 'LANG=C.UTF-8' > "$A/etc/locale.conf"
# state folders the desktop writes to
mkdir -p "$A/etc/tmpfiles.d"
cat > "$A/etc/tmpfiles.d/smof.conf" <<'TMP'
d /var/lib/smof 0777 root root -
d /var/lib/smof/wp 0777 root root -
f /var/lib/smof/theme 0666 root root - dark
f /var/lib/smof/look.json 0666 root root - {}
f /var/lib/smof/oobe-state 0644 root root - pending
f /var/lib/smof/live 0644 root root - live
TMP
# the live home folder belongs to the live user, the profile can not set that for every file
mkdir -p "$A/etc/systemd/system/multi-user.target.wants" "$A/etc/systemd/system/sysinit.target.wants"
cat > "$A/etc/systemd/system/smof-live-home.service" <<'UNIT'
[Unit]
Description=Give the live user its home folder
Before=greetd.service
[Service]
Type=oneshot
ExecStart=/usr/bin/chown -R 1000:1000 /home/smof
[Install]
WantedBy=multi-user.target
UNIT
ln -sf /etc/systemd/system/smof-live-home.service "$A/etc/systemd/system/multi-user.target.wants/smof-live-home.service"
# services: the desktop and the network. The default root autologin on the console is removed, greetd owns the first screen.
rm -rf "$A/etc/systemd/system/getty@tty1.service.d"
ln -sf /usr/lib/systemd/system/greetd.service "$A/etc/systemd/system/display-manager.service"
ln -sf /etc/systemd/system/smof-rawlog.service "$A/etc/systemd/system/multi-user.target.wants/smof-rawlog.service"
ln -sf /usr/lib/systemd/system/seatd.service "$A/etc/systemd/system/multi-user.target.wants/seatd.service"
ln -sf /usr/lib/systemd/system/NetworkManager.service "$A/etc/systemd/system/multi-user.target.wants/NetworkManager.service"
rm -f "$A/etc/systemd/system/multi-user.target.wants/systemd-networkd.service" "$A/etc/systemd/system/sockets.target.wants/systemd-networkd.socket" 2>/dev/null || true
# permissions that matter, on top of the ones the base profile sets
python3 - "$P/profiledef.sh" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
extra = '''  ["/etc/sudoers.d/smof"]="0:0:440"
  ["/usr/local/bin/smof-output-init"]="0:0:755"
'''
s = s.replace("file_permissions=(\n", "file_permissions=(\n" + extra, 1)
open(p, "w").write(s)
PY

# the boot menu entries say Smof, not Arch
for f in "$P"/efiboot/loader/entries/*.conf; do
  [ -f "$f" ] && sed -i -E 's/^title .*/title    Smof (x86_64, UEFI)/; s/Arch Linux install medium/Smof live image/' "$f"
done
for f in "$P"/syslinux/*.cfg "$P"/grub/grub.cfg; do
  [ -f "$f" ] && sed -i 's/Arch Linux install medium/Smof live image/g' "$f"
done

say "building the image, this takes a while"
# check the image tree before packing it: broken links, missing scripts, ordering cycles
echo "=== image check ==="
bad=0
for l in "$A"/etc/systemd/system/*.wants/*; do
  [ -L "$l" ] || continue
  t=$(readlink "$l")
  if [ ! -e "$A$t" ] && [ ! -e "$t" ]; then echo "BROKEN LINK $l -> $t"; bad=1; fi
done
for f in /usr/local/bin/smof-rawlog /usr/local/sbin/smof-oobe /usr/local/sbin/smof-install; do
  [ -x "$A$f" ] || { echo "NOT EXECUTABLE $f"; bad=1; }
done
systemd-analyze verify --root="$A" smof-rawlog.service smof-live-home.service 2>&1 | head -40 || true
ls -l "$A/etc/systemd/system" "$A/etc/systemd/system/multi-user.target.wants" "$A/etc/sudoers.d" || true
stat -c '%a %U %n' "$A/etc/sudoers.d/"* || true
[ "$bad" = 0 ] || { echo "image check failed"; exit 1; }
mkarchiso -v -w "$WORK/work" -o "$OUT" "$P"
ls -la "$OUT"
( cd "$OUT" && sha256sum smof-*.iso > SHA256SUMS && cat SHA256SUMS )
say "done: $(ls "$OUT"/smof-*.iso)"
