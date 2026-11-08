#!/bin/bash
# installs the picture upscaler into the VM: ncnn, Pillow, numpy, the models, the small C++ runner and the wrapper.
# models come from the Real-ESRGAN release v0.2.5.0 (ncnn zip, models folder), kept in sr/models
cd "$(dirname "$0")/.."
V=vm; H=$(cat $V/ip.txt); O="-i $V/id_mjos -o BatchMode=yes -o LogLevel=ERROR"
ssh $O root@$H "pacman -S --noconfirm --needed ncnn python-pillow python-numpy gcc; mkdir -p /usr/share/smof/models/sr"
scp -q $O sr/models/* root@$H:/usr/share/smof/models/sr/
scp -q $O sr/smof-sr.cpp root@$H:/tmp/smof-sr.cpp
ssh $O root@$H "cd /tmp && g++ -O3 -fopenmp -o smof-sr smof-sr.cpp -lncnn && install -m 755 smof-sr /usr/local/bin/smof-sr"
scp -q $O vm/smof-upscale root@$H:/usr/local/bin/smof-upscale
ssh $O root@$H "chmod 755 /usr/local/bin/smof-upscale"
