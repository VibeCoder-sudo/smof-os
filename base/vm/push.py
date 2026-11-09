#!/usr/bin/env python3
"""Copy files into the VM over the serial pty (no network).
usage: push.py LOCAL_FILE GUEST_PATH [LOCAL_FILE GUEST_PATH ...]
Logs in as root like vmrun.py, sends base64 chunks, decodes in the guest and checks md5."""
import os, sys, re, time, select, tty, base64, hashlib, random

HERE = os.path.dirname(os.path.abspath(__file__))
path = open(os.path.join(HERE, "tty.txt")).read().strip()
pw = open(os.path.join(HERE, "credentials.txt")).read().split()[2]
fd = os.open(path, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
tty.setraw(fd)
ANSI = re.compile(rb"\x1b\][^\x07\x1b]*(\x07|\x1b\\)|\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b[()][A-Z0-9]|\x11")


def read(t):
    out = b""
    end = time.time() + t
    while time.time() < end:
        if select.select([fd], [], [], 0.05)[0]:
            try:
                out += os.read(fd, 65536)
            except BlockingIOError:
                pass
    return out


def send(s, pause=0.0):
    os.write(fd, s.encode() + b"\r")
    if pause:
        time.sleep(pause)


def login():
    read(0.5)
    for _ in range(6):
        send("")
        buf = ANSI.sub(b"", read(1.5)).decode(errors="replace")
        tail = buf.strip().splitlines()[-1] if buf.strip() else ""
        if tail.endswith("login:"):
            send("root"); read(1.0); send(pw); read(2.5); continue
        if tail.endswith("Password:"):
            send(pw); read(2.5); continue
        if tail.startswith("[root@") and tail.endswith("#"):
            return
        if tail.endswith("$"):
            send("exit"); read(1.5); continue
    sys.exit("no root shell")


login()
args = sys.argv[1:]
for i in range(0, len(args), 2):
    src, dst = args[i], args[i + 1]
    data = open(src, "rb").read()
    b64 = base64.b64encode(data).decode()
    md5 = hashlib.md5(data).hexdigest()
    tmp = "/tmp/push_%d.b64" % random.randint(1000, 99999)
    send("stty -echo; mkdir -p $(dirname '%s'); rm -f %s" % (dst, tmp), 0.3)
    for j in range(0, len(b64), 1000):
        send("echo %s >> %s" % (b64[j:j + 1000], tmp))
        read(0.12)
    send("base64 -d %s > '%s'; rm -f %s; echo MD5_$(md5sum '%s' | cut -d' ' -f1)" % (tmp, dst, tmp, dst))
    out = b""
    end = time.time() + 120
    while time.time() < end:
        out += read(0.5)
        m = re.search(rb"MD5_([0-9a-f]{32})", ANSI.sub(b"", out))
        if m:
            break
    ok = bool(m) and m.group(1).decode() == md5
    print(("ok  " if ok else "BAD ") + dst, len(data))
send("stty echo")
