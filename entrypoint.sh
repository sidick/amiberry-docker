#!/bin/bash
set -euo pipefail

: "${VNC_GEOMETRY:=1280x960}"
: "${VNC_DEPTH:=24}"
: "${VNC_PORT:=8443}"
: "${VNC_USER:=amiberry}"
: "${VNC_PASSWORD:=amiberry}"
: "${AMIBERRY_LOG:=/config/amiberry.log}"

# Mirror everything this entrypoint (and the vncserver/amiberry it exec's at
# the end) writes to stdout/stderr into a logfile as well, so logs survive
# after the container stops. `exec` with only redirections rewires this
# shell's fds without replacing the process, so the final `exec vncserver`
# still works and inherits the tee. tee's own stdout is the original
# container stdout, so output goes to both places. The file is truncated
# each start; switch `tee` to `tee -a` to append across restarts instead.
mkdir -p "$(dirname "$AMIBERRY_LOG")"
exec > >(tee "$AMIBERRY_LOG") 2>&1

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

# Seed the amiberry configs from the image (see Dockerfile COPY amiberry-config/).
# default.uae is the VNC-optimised config (A500/KS1.3, sized to fill the 1280x960
# desktop). It is only installed if the user has no default yet, so their own
# edits are never clobbered. vnc-default.uae is refreshed every start as a
# pristine known-good fallback in case the main default gets overwritten.
SEED_DIR=/opt/amiberry-seed
if [ -f "$SEED_DIR/default.uae" ]; then
    runuser -u amiberry -- mkdir -p /config/Amiberry/Configurations
    if ! runuser -u amiberry -- test -f /config/Amiberry/Configurations/default.uae; then
        runuser -u amiberry -- cp "$SEED_DIR/default.uae" /config/Amiberry/Configurations/default.uae
    fi
    runuser -u amiberry -- cp "$SEED_DIR/default.uae" /config/Amiberry/Configurations/vnc-default.uae
fi

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

# AMIBERRY_NO_WM=1 is what stops the emulation from coming up black.
# KasmVNC's Xvnc has no window manager. With NO_WM=0 amiberry assumes a WM
# will map/raise its emulation window, so on Start nothing shows the window
# and you get the black root window (the amiberry GUI still renders because
# it draws into the already-mapped window). NO_WM=1 forces shared-window mode
# so amiberry maps the emulation display itself. Verified: with NO_WM=1 the
# Amiga display (e.g. Workbench 1.3) renders; with NO_WM=0 it is black,
# independent of the GL vs software renderer. Set in the entrypoint (not
# xstartup) so it applies even to old volumes with a stale xstartup.
#
# LIBGL_ALWAYS_SOFTWARE=1 / SDL_RENDER_DRIVER=software are kept as harmless
# belt-and-suspenders (force llvmpipe), but note SDL_RENDER_DRIVER is a no-op:
# the release .deb renders via its own OpenGL path, not SDL's renderer.
exec runuser -u amiberry -- env \
        XDG_RUNTIME_DIR=/tmp/pulse-runtime \
        PULSE_SERVER=unix:/tmp/pulse-socket \
        LIBGL_ALWAYS_SOFTWARE=1 \
        SDL_RENDER_DRIVER=software \
        AMIBERRY_NO_WM=1 \
    vncserver :1 \
        -depth "${VNC_DEPTH}" \
        -geometry "${VNC_GEOMETRY}" \
        -fg
