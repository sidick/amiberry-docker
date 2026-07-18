# Sourced by entrypoint.sh as root; $APP_USER and the EXTRA_ENV array are in
# scope. Not executable on its own.

# Seed the amiberry configs from the image (see Dockerfile COPY apps/amiberry/config/).
# default.uae is the VNC-optimised config (A500/KS1.3, sized to fill the 1280x960
# desktop). It is only installed if the user has no default yet, so their own
# edits are never clobbered. vnc-default.uae is refreshed every start as a
# pristine known-good fallback in case the main default gets overwritten.
SEED_DIR=/opt/app-seed
if [ -f "$SEED_DIR/default.uae" ]; then
    runuser -u "$APP_USER" -- mkdir -p /config/Amiberry/Configurations
    if ! runuser -u "$APP_USER" -- test -f /config/Amiberry/Configurations/default.uae; then
        runuser -u "$APP_USER" -- cp "$SEED_DIR/default.uae" /config/Amiberry/Configurations/default.uae
    fi
    runuser -u "$APP_USER" -- cp "$SEED_DIR/default.uae" /config/Amiberry/Configurations/vnc-default.uae
fi

# AMIBERRY_NO_WM=1 is what stops the emulation from coming up black.
# KasmVNC's Xvnc has no window manager. With NO_WM=0 amiberry assumes a WM
# will map/raise its emulation window, so on Start nothing shows the window
# and you get the black root window (the amiberry GUI still renders because
# it draws into the already-mapped window). NO_WM=1 forces shared-window mode
# so amiberry maps the emulation display itself. Verified: with NO_WM=1 the
# Amiga display (e.g. Workbench 1.3) renders; with NO_WM=0 it is black,
# independent of the GL vs software renderer. Injected via EXTRA_ENV (not
# xstartup) so it applies even to old volumes with a stale xstartup.
#
# LIBGL_ALWAYS_SOFTWARE=1 / SDL_RENDER_DRIVER=software are kept as harmless
# belt-and-suspenders (force llvmpipe), but note SDL_RENDER_DRIVER is a no-op:
# the release .deb renders via its own OpenGL path, not SDL's renderer.
EXTRA_ENV+=(
    AMIBERRY_NO_WM=1
    LIBGL_ALWAYS_SOFTWARE=1
    SDL_RENDER_DRIVER=software
)
