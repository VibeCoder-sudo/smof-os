#!/bin/bash
# boots the Alpine installer with the empty disk (vdb is not needed yet) and the Arch archive as a raw second disk
cd "$(dirname "$0")/.."
qemu-system-aarch64 \
  -machine virt,highmem=on -accel hvf -cpu host -smp 2 -m 2048 \
  -drive if=pflash,format=raw,readonly=on,file=/opt/homebrew/share/qemu/edk2-aarch64-code.fd \
  -drive if=pflash,format=raw,file=vm/vars.fd \
  -drive if=none,id=hd,file=vm/arch.qcow2,format=qcow2 -device virtio-blk-pci,drive=hd \
  -drive if=none,id=tar,file=ArchLinuxARM-aarch64-latest.tar.gz,format=raw,readonly=on -device virtio-blk-pci,drive=tar \
  -drive if=none,id=cd,file=alpine-virt-3.24.4-aarch64.iso,format=raw,readonly=on -device virtio-blk-pci,drive=cd,bootindex=0 \
  -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
  -display none -monitor none \
  -chardev socket,id=s0,path=vm/ser.sock,server=on,wait=off,logfile=vm/console.log,logappend=off -serial chardev:s0
