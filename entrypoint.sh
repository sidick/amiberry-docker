#!/bin/bash -x

Xvfb :0 -screen 0 1280x800x24 &
sleep 2
x11vnc -display :0 \
       -forever \
       -shared \
       -nopw \
       -rfbport 5900 \
       -listen 0.0.0.0 &
sleep 2
exec amiberry "$@"
