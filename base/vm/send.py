#!/usr/bin/env python3
"""Send one line to the VM serial console and print what comes back.
usage: send.py [--wait SECONDS] [--quiet SECONDS] 'command'   (use '' to only read)"""
import socket, sys, time, os

sock_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ser.sock")
args = sys.argv[1:]
wait, quiet = 120.0, 2.0
while args and args[0].startswith("--"):
    k = args.pop(0)
    v = float(args.pop(0))
    if k == "--wait":
        wait = v
    elif k == "--quiet":
        quiet = v
cmd = args[0] if args else ""

c = socket.socket(socket.AF_UNIX)
c.connect(sock_path)
c.settimeout(0.3)
if cmd:
    c.sendall(cmd.encode() + b"\r")
buf = b""
start = last = time.time()
while time.time() - start < wait:
    try:
        d = c.recv(65536)
        if not d:
            break
        buf += d
        last = time.time()
    except socket.timeout:
        if buf and time.time() - last > quiet:
            break
        if not cmd and time.time() - start > quiet:
            break
print(buf.decode(errors="replace"))
