#!/bin/bash
# boots the installed Arch from its disk. serial console goes to vm/ser.sock and vm/console.log, screen opens in a window
cd "$(dirname "$0")/.."
qemu-system-aarch64 \
  -machine virt,highmem=on -accel hvf -cpu host -smp 2 -m 2048 \
  -drive if=pflash,format=raw,readonly=on,file=/opt/homebrew/share/qemu/edk2-aarch64-code.fd \
  -drive if=pflash,format=raw,file=vm/vars.fd \
  -drive if=none,id=hd,file=vm/arch.qcow2,format=qcow2 -device virtio-blk-pci,drive=hd \
  -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
  -device virtio-gpu-pci -device qemu-xhci -device usb-kbd -device usb-tablet \
  -display cocoa -monitor none \
  -chardev socket,id=s0,path=vm/ser.sock,server=on,wait=off,logfile=vm/console.log,logappend=off -serial chardev:s0
