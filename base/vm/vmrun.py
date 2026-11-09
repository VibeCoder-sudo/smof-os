#!/usr/bin/env python3
"""Run a command as root inside the VM over the UTM serial pty and print its output.
usage: vmrun.py [--timeout SECONDS] 'command'
The pty path is read from vm/tty.txt (for example /dev/ttys000). Root password comes from vm/credentials.txt."""
import os, sys, re, time, select, tty, random

HERE = os.path.dirname(os.path.abspath(__file__))
args = sys.argv[1:]
timeout = 120.0
if args and args[0] == "--timeout":
    timeout = float(args[1]); args = args[2:]
cmd = args[0]

path = open(os.path.join(HERE, "tty.txt")).read().strip()
pw = open(os.path.join(HERE, "credentials.txt")).read().split()[2]
fd = os.open(path, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
tty.setraw(fd)
log = open(os.path.join(HERE, "console.log"), "ab")

ANSI = re.compile(rb"\x1b\][^\x07\x1b]*(\x07|\x1b\\)|\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b[()][A-Z0-9]|\x11")


def read(t):
    out = b""
    end = time.time() + t
    while time.time() < end:
        if select.select([fd], [], [], 0.2)[0]:
            try:
                d = os.read(fd, 65536)
            except BlockingIOError:
                continue
            out += d
            log.write(d); log.flush()
    return out


def send(s):
    os.write(fd, s.encode() + b"\r")


# get to a root shell
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
        break
    if tail.endswith("$"):  # logged in as a normal user, leave
        send("exit"); read(1.5); continue
else:
    print("could not reach a root shell, last screen:", tail); sys.exit(2)

marker = "__M%d" % random.randint(1000, 99999)
send("stty -echo 2>/dev/null; %s; echo %s_$((6*7))" % (cmd, marker))
out = b""
end = time.time() + timeout
while time.time() < end:
    out += read(1.0)
    if re.search(rb"(^|\n)" + marker.encode() + rb"_42", ANSI.sub(b"", out)):
        break
send("stty echo 2>/dev/null")
text = ANSI.sub(b"", out).decode(errors="replace").replace("\r", "")
text = text.split(marker + "_42")[0]
print("\n".join(text.split("\n")[1:]).strip())
