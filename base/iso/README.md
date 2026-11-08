# Smof live image for x86_64 PCs

What it is: a bootable image with the real Smof desktop (the same files as in the VM) on top of Arch Linux, with hardware support for normal PCs
(Intel and AMD graphics, linux-firmware for Wi-Fi and sound, NetworkManager). It starts straight into the desktop as the user `smof`.

Status: first draft, written without being able to run an x86_64 build. Expect to fix things after the first build.

## Build it in the cloud (GitHub Actions)
1. `bash base/iso/make-repo.sh ~/smof-repo` makes a clean copy of just what is needed (about 45 MB).
2. Put that folder in a new GitHub repository (private is fine) and push.
3. In the repo on GitHub: Actions, build-smof-iso, Run workflow. After about 20 to 30 minutes the image is under Artifacts as `smof-iso`.

## Build it on any Arch Linux x86_64 machine
`sudo bash base/iso/build.sh`, the image ends up in `base/iso/out/`.

## Known gaps in this draft
- Wi-Fi: the drivers and firmware are there, but Settings has no Wi-Fi page yet. Use a cable first, or `nmcli device wifi connect NAME password PASS`.
- No boot splash (the current one only exists for 1280x800), no installer yet, the live image is for trying and testing.
- The window frames plugin is built from the latest upstream pixdecor, if it does not match the wayfire in the image the build stops there.
