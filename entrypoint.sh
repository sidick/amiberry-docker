#!/bin/bash
set -euo pipefail

: "${VNC_GEOMETRY:=1280x960}"
: "${VNC_DEPTH:=24}"
: "${VNC_PORT:=8443}"
: "${VNC_USER:=amiberry}"
: "${VNC_PASSWORD:=amiberry}"

# /config is the amiberry user's HOME (set in Dockerfile useradd).
# Make sure the volume root is owned by amiberry; everything below it
# is then created as amiberry to avoid root-owned secrets confusing kasmvnc.
chown amiberry:amiberry /config
runuser -u amiberry -- mkdir -p /config/.vnc

if ! runuser -u amiberry -- test -f /config/.vnc/kasmvnc.yaml; then
    runuser -u amiberry -- tee /config/.vnc/kasmvnc.yaml > /dev/null <<EOF
network:
  protocol: http
  websocket_port: ${VNC_PORT}
  use_ipv4: true
  use_ipv6: false
  ssl:
    require_ssl: false
runtime_configuration:
  allow_client_to_override_kasm_server_settings: true
EOF
fi

if ! runuser -u amiberry -- test -f /config/.vnc/xstartup; then
    runuser -u amiberry -- tee /config/.vnc/xstartup > /dev/null <<'EOF'
#!/bin/bash
exec /usr/bin/amiberry
EOF
    runuser -u amiberry -- chmod +x /config/.vnc/xstartup
fi

# Tell KasmVNC we've already chosen a desktop session (our xstartup runs amiberry directly).
runuser -u amiberry -- touch /config/.vnc/.de-was-selected

if ! runuser -u amiberry -- test -f /config/.kasmpasswd; then
    printf '%s\n%s\n' "${VNC_PASSWORD}" "${VNC_PASSWORD}" \
        | runuser -u amiberry -- vncpasswd -u "${VNC_USER}" -w -r /config/.kasmpasswd
fi

# Pulseaudio needs XDG_RUNTIME_DIR per-user.
mkdir -p /tmp/pulse-runtime
chown amiberry:amiberry /tmp/pulse-runtime
chmod 700 /tmp/pulse-runtime

runuser -u amiberry -- env XDG_RUNTIME_DIR=/tmp/pulse-runtime \
    pulseaudio \
        --exit-idle-time=-1 \
        --disallow-exit \
        --disable-shm \
        --load='module-native-protocol-unix socket=/tmp/pulse-socket auth-anonymous=1' \
        --load='module-null-sink sink_name=amiberry-out' \
        --daemonize=yes \
        --log-target=stderr \
    || echo 'pulseaudio failed to start; continuing without audio' >&2

# KasmVNC's Xvnc has no real GPU; without these the amiberry GUI renders
# (plain X drawing) but Amiga emulation comes up black because SDL3 picks an
# OpenGL renderer that can't present frames over GLX. Set in the entrypoint
# (not xstartup) so the fix applies even when an old volume has a stale
# xstartup from before this was added.
#   LIBGL_ALWAYS_SOFTWARE=1    -> Mesa libGL uses the swrast driver
#   SDL_RENDER_DRIVER=software -> SDL3 skips GL entirely
exec runuser -u amiberry -- env \
        XDG_RUNTIME_DIR=/tmp/pulse-runtime \
        PULSE_SERVER=unix:/tmp/pulse-socket \
        LIBGL_ALWAYS_SOFTWARE=1 \
        SDL_RENDER_DRIVER=software \
        AMIBERRY_NO_WM=0 \
    vncserver :1 \
        -depth "${VNC_DEPTH}" \
        -geometry "${VNC_GEOMETRY}" \
        -fg
