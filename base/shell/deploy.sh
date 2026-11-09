#!/bin/bash
# copies the shared QML into the lock screen and every app (quickshell does not allow imports from outside its config folder),
# then sends everything to the VM: shells, icons, wallpaper layers, and makes /var/lib/smof/theme
cd "$(dirname "$0")/.."
V=vm; H=$(cat $V/ip.txt); O="-i $V/id_mjos -o BatchMode=yes -o LogLevel=ERROR -o StrictHostKeyChecking=accept-new"
for d in greeter apps/wallpaper apps/bar apps/dock apps/notifd apps/launcher apps/settings apps/files apps/auth apps/store apps/upscaler; do cp shell/shared/*.qml shell/$d/; done
ssh $O root@$H "mkdir -p /usr/share/smof/apps"
scp -q $O -r shell/greeter root@$H:/usr/share/smof/
scp -q $O -r shell/apps root@$H:/usr/share/smof/
for f in smof-ipc smof-settings smof-shell smof-files smof-fileops smof-askpass smof-brew smof-pkg smof-bgapps smof-input smof-shot smof-front smof-sound smof-devwatch smof-activity smof-volume smof-timer smof-store smof-display smof-desktop smof-upscaler smof-upscale smof-downloads smof-devwatch smof-health smof-cleanup smof-wifi smof-bt smof-night smof-spotlight smof-snap smof-record smof-glitch smof-glitch-mem; do scp -q $O vm/$f root@$H:/usr/local/bin/$f; done
ssh $O root@$H "chmod 755 /usr/local/bin/smof-ipc /usr/local/bin/smof-settings /usr/local/bin/smof-shell /usr/local/bin/smof-files /usr/local/bin/smof-fileops /usr/local/bin/smof-askpass /usr/local/bin/smof-brew /usr/local/bin/smof-pkg /usr/local/bin/smof-bgapps /usr/local/bin/smof-input /usr/local/bin/smof-shot /usr/local/bin/smof-front /usr/local/bin/smof-sound /usr/local/bin/smof-devwatch /usr/local/bin/smof-activity /usr/local/bin/smof-volume /usr/local/bin/smof-timer /usr/local/bin/smof-store /usr/local/bin/smof-display /usr/local/bin/smof-desktop /usr/local/bin/smof-upscaler /usr/local/bin/smof-upscale /usr/local/bin/smof-downloads /usr/local/bin/smof-devwatch /usr/local/bin/smof-health /usr/local/bin/smof-cleanup /usr/local/bin/smof-wifi /usr/local/bin/smof-bt /usr/local/bin/smof-night /usr/local/bin/smof-spotlight /usr/local/bin/smof-snap /usr/local/bin/smof-record /usr/local/bin/smof-glitch /usr/local/bin/smof-glitch-mem"
ssh $O root@$H "mkdir -p /usr/share/smof/sounds"; scp -q $O assets/sounds/*.wav root@$H:/usr/share/smof/sounds/
scp -q $O vm/fonts-smof.conf root@$H:/etc/fonts/conf.d/60-smof.conf; ssh $O root@$H "fc-cache -f >/dev/null 2>&1 &"
scp -q $O vm/sudo-wrapper root@$H:/usr/local/bin/sudo; ssh $O root@$H "chmod 755 /usr/local/bin/sudo"
scp -q $O -r assets/icons root@$H:/usr/share/smof/
ssh $O root@$H "mkdir -p /var/lib/smof; [ -f /var/lib/smof/theme ] || echo light > /var/lib/smof/theme; chmod 777 /var/lib/smof; mkdir -p /var/lib/smof/wp; chmod 777 /var/lib/smof/wp; [ -f /var/lib/smof/look.json ] || echo '{}' > /var/lib/smof/look.json; chmod 666 /var/lib/smof/look.json; chmod 666 /var/lib/smof/theme; sync"
# a reload that started while files were still arriving can miss new ones, so reload every app once more now that all are there
sleep 1; ssh $O root@$H "touch /usr/share/smof/apps/*/shell.qml"
