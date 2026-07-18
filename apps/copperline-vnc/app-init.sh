# Sourced by entrypoint.sh as root; $APP_USER and the EXTRA_ENV array are in
# scope. Not executable on its own.

# Copperline resolves ./copperline.toml (and any relative rom/floppy paths in
# it) from its working directory; start-app cd's to /config/Copperline. Seed a
# fully-commented example config there once so users have something to edit —
# never overwritten after that.
runuser -u "$APP_USER" -- mkdir -p /config/Copperline
if ! runuser -u "$APP_USER" -- test -f /config/Copperline/copperline.toml; then
    runuser -u "$APP_USER" -- cp /opt/app-seed/copperline.toml /config/Copperline/copperline.toml
fi
