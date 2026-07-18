#!/bin/bash
set -euo pipefail

# Generic entrypoint shared by every app image built from this repo (amiberry,
# copperline). It owns the KasmVNC/X/pulseaudio plumbing; everything
# app-specific lives in two files each image bakes in:
#
#   /usr/local/lib/app-init.sh — sourced (as root) after /config is prepared.
#                                Seeds app config into the volume and may
#                                append NAME=value pairs to the EXTRA_ENV
#                                array to inject env into the app's session.
#   /usr/local/bin/start-app   — exec'd by the X session (via xstartup) to
#                                launch the app itself.

APP_USER=app

: "${VNC_GEOMETRY:=1280x960}"
: "${VNC_DEPTH:=24}"
: "${VNC_PORT:=8443}"
: "${VNC_USER:=${APP_USER}}"
: "${VNC_PASSWORD:=${VNC_USER}}"
# AMIBERRY_LOG is honoured as a legacy alias from the amiberry-only image.
: "${APP_LOG:=${AMIBERRY_LOG:-/config/app.log}}"

# Mirror everything this entrypoint (and the vncserver/app it exec's at
# the end) writes to stdout/stderr into a logfile as well, so logs survive
# after the container stops. `exec` with only redirections rewires this
# shell's fds without replacing the process, so the final `exec vncserver`
# still works and inherits the tee. tee's own stdout is the original
# container stdout, so output goes to both places. The file is truncated
# each start; switch `tee` to `tee -a` to append across restarts instead.
mkdir -p "$(dirname "$APP_LOG")"
exec > >(tee "$APP_LOG") 2>&1

# Clean up stale lock/PID/socket files from previous runs. The pid file lives
# in the persisted /config volume; if the container was killed without
# vncserver's cleanup running, vncserver refuses to start with "A VNC server
# is already running as :1". X server lock files, X11 sockets, and pulseaudio
# runtime state are also cleared in case the container's /tmp survived
# (e.g. docker restart of the same container rather than a fresh one).
rm -f /config/.vnc/*.pid
rm -f /tmp/.X*-lock
rm -rf /tmp/.X11-unix /tmp/pulse-runtime /tmp/pulse-socket
mkdir -p /tmp/.X11-unix
chmod 1777 /tmp/.X11-unix

# /config is the app user's HOME (set in Dockerfile useradd).
# Make sure the volume root is owned by the app user; everything below it
# is then created as that user to avoid root-owned secrets confusing kasmvnc.
chown "$APP_USER:$APP_USER" /config
runuser -u "$APP_USER" -- mkdir -p /config/.vnc

if ! runuser -u "$APP_USER" -- test -f /config/.vnc/kasmvnc.yaml; then
    runuser -u "$APP_USER" -- tee /config/.vnc/kasmvnc.yaml > /dev/null <<EOF
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

# The seeded xstartup defers to the image's start-app so the launch command
# tracks the image, not the volume. Volumes created by the old amiberry-only
# image may hold a stale xstartup exec'ing /usr/bin/amiberry directly; that
# still works because app-specific env travels via EXTRA_ENV below, not via
# xstartup.
if ! runuser -u "$APP_USER" -- test -f /config/.vnc/xstartup; then
    runuser -u "$APP_USER" -- tee /config/.vnc/xstartup > /dev/null <<'EOF'
#!/bin/bash
exec /usr/local/bin/start-app
EOF
    runuser -u "$APP_USER" -- chmod +x /config/.vnc/xstartup
fi

# Tell KasmVNC we've already chosen a desktop session (our xstartup runs the app directly).
runuser -u "$APP_USER" -- touch /config/.vnc/.de-was-selected

# App-specific volume seeding and session env.
EXTRA_ENV=()
if [ -f /usr/local/lib/app-init.sh ]; then
    . /usr/local/lib/app-init.sh
fi

if ! runuser -u "$APP_USER" -- test -f /config/.kasmpasswd; then
    printf '%s\n%s\n' "${VNC_PASSWORD}" "${VNC_PASSWORD}" \
        | runuser -u "$APP_USER" -- vncpasswd -u "${VNC_USER}" -w -r /config/.kasmpasswd
fi

# Pulseaudio needs XDG_RUNTIME_DIR per-user.
mkdir -p /tmp/pulse-runtime
chown "$APP_USER:$APP_USER" /tmp/pulse-runtime
chmod 700 /tmp/pulse-runtime

runuser -u "$APP_USER" -- env XDG_RUNTIME_DIR=/tmp/pulse-runtime \
    pulseaudio \
        --exit-idle-time=-1 \
        --disallow-exit \
        --disable-shm \
        --load='module-native-protocol-unix socket=/tmp/pulse-socket auth-anonymous=1' \
        --load='module-null-sink sink_name=app-out' \
        --daemonize=yes \
        --log-target=stderr \
    || echo 'pulseaudio failed to start; continuing without audio' >&2

exec runuser -u "$APP_USER" -- env \
        XDG_RUNTIME_DIR=/tmp/pulse-runtime \
        PULSE_SERVER=unix:/tmp/pulse-socket \
        "${EXTRA_ENV[@]}" \
    vncserver :1 \
        -depth "${VNC_DEPTH}" \
        -geometry "${VNC_GEOMETRY}" \
        -fg
