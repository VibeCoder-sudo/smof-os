#!/bin/bash
# vmrun.sh 'command' : runs a command in the guest as root, waits until it finishes (env T = max seconds), prints the output.
cd "$(dirname "$0")"
M="__M${RANDOM}"
python3 send.py --wait 3 --quiet 1 "" >/dev/null
if tail -c 200 console.log | grep -q "login:"; then
  python3 send.py --wait 4 "root" >/dev/null
  python3 send.py --wait 15 --quiet 3 "$(awk '{print $3}' credentials.txt)" >/dev/null
fi
START=$(wc -c < console.log)
python3 send.py --wait 2 --quiet 1 "$1; echo ${M}_END" >/dev/null
for i in $(seq 1 $(( ${T:-120} / 2 ))); do
  tail -c +$((START+1)) console.log | grep -q "^${M}_END" && break
  sleep 2
done
tail -c +$((START+1)) console.log | tr -d '\033' | sed -E 's/\]3008;[^\\]*\\//g; s/\[\?2004[hl]//g'
