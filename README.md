# docker-amiberry

Containerised Amiga emulators, accessed in the browser over
[KasmVNC](https://github.com/kasmtech/KasmVNC) (display + audio in one).
One Dockerfile, two published images built from a shared base:

| Image | Emulator | Default port |
|---|---|---|
| `ghcr.io/sidick/amiberry` | [amiberry](https://github.com/BlitterStudio/amiberry) | 8443 |
| `ghcr.io/sidick/copperline` | [Copperline](https://github.com/LinuxJedi/Copperline) | 8444 |

All user state — configs, kickstart ROMs, floppies, hard files, savestates —
lives in a single named volume per emulator, mounted at `/config`.

Builds for `linux/amd64` and `linux/arm64`.

## Components

| | Version | Source |
|---|---|---|
| amiberry | 8.2.2 | `.deb` from upstream release |
| Copperline | 0.12.0 | built from source (cargo) at the release tag |
| KasmVNC | 1.4.0 | `.deb` from upstream release |
| Base | `debian:trixie-slim` | |

## Run

### With the Makefile

The included `Makefile` wraps the common `docker` commands. Every target
is parameterised by `APP` (`amiberry`, the default, or `copperline`):

```sh
make up                    # amiberry on port 8443
make up APP=copperline     # copperline on port 8444 (they can run together)
make logs                  # follow the logs
make stop                  # stop without removing
make down                  # stop and remove the container (keeps the config volume)
```

Run `make` (or `make help`) to list every target:

| Target | Does |
|---|---|
| `up` | Create and start the container in the background |
| `down` | Stop and remove the container (keeps the config volume) |
| `start` / `stop` | Start / stop an existing container without removing it |
| `restart` | Restart the container |
| `pull` | Pull the latest image from the registry |
| `build` | Build the `$(APP)` image locally from this checkout |
| `build-all` | Build every app image locally |
| `logs` | Follow the container logs |
| `ps` | Show container status |
| `shell` | Open a shell in the running container |
| `clean` | Remove the container **and** delete the config volume |
| `prune` | `clean` + remove the image and prune the build cache |

Settings can be overridden on the command line, e.g. `make up PORT=9000`
or `make build APP=copperline IMAGE=copperline:local`.

### With docker compose

The included `docker-compose.yml` defines both emulators:

```sh
docker compose up -d               # both
docker compose up -d amiberry      # just one
```

### With plain docker

```sh
docker run --rm -it \
    -p 8443:8443 \
    -v amiberry-config:/config \
    --shm-size=512m \
    ghcr.io/sidick/amiberry:latest
```

```sh
docker run --rm -it \
    -p 8444:8443 \
    -v copperline-config:/config \
    --shm-size=512m \
    ghcr.io/sidick/copperline:latest
```

Multi-arch — Docker auto-picks the right variant. Then open
<http://localhost:8443/> (or 8444) in a browser. Default credentials are
the app name twice: `amiberry` / `amiberry`, `copperline` / `copperline`
(override via `VNC_USER` / `VNC_PASSWORD`).

## Build from source

```sh
docker build --target amiberry   -t amiberry:local .
docker build --target copperline -t copperline:local .
```

(A bare `docker build .` with no `--target` builds the amiberry image.)

For multi-arch:

```sh
docker buildx build --platform linux/amd64,linux/arm64 --target amiberry -t amiberry:local .
```

To run a local build via compose, uncomment the `build:` block under the
service in `docker-compose.yml` and either remove the `image:` line or
point it at your local tag, then `docker compose up --build`.

## The config volume

`/config` is the container user's `$HOME` (UID 1000). KasmVNC stores its
config under `/config/.vnc/` and the user/password database at
`/config/.kasmpasswd` in both images.

### amiberry

On first run amiberry creates `/config/Amiberry/` with these
subdirectories:

| Directory | Holds |
|---|---|
| `Configurations/` | `.uae` config files |
| `ROMs/` | kickstart ROMs (supply your own) |
| `Floppies/` | `.adf` / `.adz` floppy images |
| `HardDrives/` | HDF / directory hard drives |
| `CDROMs/` | CD image files |
| `LHA/` | LHA archives |
| `SaveStates/` | savestates |
| `Screenshots/` | captured screenshots |
| `Visuals/` | UI themes / assets |

A VNC-optimised `default.uae` (A500/KS1.3, sized to fill the desktop) is
seeded on first run; a pristine copy is refreshed every start as
`vnc-default.uae`.

### Copperline

Copperline runs from `/config/Copperline/` and reads
`copperline.toml` there (a fully-commented example is seeded on first
run). With no configuration it boots the bundled AROS ROM, so it works
out of the box; drop your own kickstart ROMs and disk images into
`/config/Copperline/` and reference them from the toml with relative
paths. See the
[Copperline configuration reference](https://github.com/LinuxJedi/Copperline)
for all settings.

### Copying files in

To add ROMs / floppies from the host into a named volume, copy them in
and fix ownership (the emulator runs as UID 1000 inside the container,
but `docker cp` writes files using the **host** user's UID — typically
501 on macOS — which it can't read):

```sh
docker cp ~/roms/kick13.rom amiberry:/config/Amiberry/ROMs/
docker exec -u 0 amiberry chown -R app:app /config/Amiberry/ROMs/
```

Or pipe the file in through an exec'd shell as the container user — one
command, correct ownership from the start:

```sh
docker exec -i -u app amiberry \
    tee /config/Amiberry/ROMs/kick13.rom < ~/roms/kick13.rom > /dev/null
```

### Bind-mount a host directory instead

If you'd rather have `/config` live in a directory you can browse and edit
directly on the host, swap the named volume for a bind mount.

With `docker run`:

```sh
mkdir -p ~/amiberry
docker run --rm -it \
    -p 8443:8443 \
    -v ~/amiberry:/config \
    --shm-size=512m \
    ghcr.io/sidick/amiberry:latest
```

With `docker-compose.yml`, replace the service's `volumes:` entry:

```yaml
services:
  amiberry:
    # ...
    volumes:
      - ./amiberry-data:/config   # bind mount
    # remove the matching named volume from the top-level `volumes:` block too
```

The entrypoint runs `chown app:app /config` at startup, so on Linux your
host directory's files will become owned by UID 1000. On macOS and
Windows, Docker Desktop maps ownership transparently and you don't need
to do anything.

Files you can stage into the host directory **before** the first run
(amiberry example):

- `Amiberry/ROMs/*.rom` — kickstart ROMs
- `Amiberry/Floppies/*.adf` — floppy images
- `Amiberry/HardDrives/*.hdf` — hard files
- `Amiberry/Configurations/*.uae` — pre-made amiberry config files

amiberry will create the rest of the `Amiberry/` subdirectories on first
launch. For Copperline, stage ROMs/disk images into `Copperline/` along
with a `copperline.toml`.

## Environment variables

| Var | Default | Purpose |
|---|---|---|
| `VNC_GEOMETRY` | `1280x960` | KasmVNC desktop resolution |
| `VNC_DEPTH` | `24` | Colour depth |
| `VNC_PORT` | `8443` | Browser websocket port |
| `VNC_USER` | app name | KasmVNC username |
| `VNC_PASSWORD` | same as `VNC_USER` | KasmVNC password (change this) |
| `APP_LOG` | `/config/<app>.log` | Logfile the container output is also tee'd to (persists in the volume; truncated each start). `AMIBERRY_LOG` still works as a legacy alias in the amiberry image. |

## Audio

PulseAudio runs inside the container; KasmVNC streams its output to the
browser. amiberry talks to it via SDL, Copperline via ALSA's pulse
plugin (`/etc/asound.conf`). The first time it works depends on your
browser allowing audio autoplay — click the speaker icon in the KasmVNC
control bar if silent.

## Repo layout

| Path | What |
|---|---|
| `Dockerfile` | Multi-stage: shared `base` + one final stage per emulator |
| `entrypoint.sh` | Generic KasmVNC/X/pulseaudio startup, shared by all images |
| `apps/<app>/start-app` | Launches the emulator inside the X session |
| `apps/<app>/app-init.sh` | Per-app volume seeding + session env, sourced by the entrypoint |
| `apps/<app>/…` | Seed configs and other app-specific files |

## Notes & caveats

- Neither emulator bundles **Amiga kickstart ROMs**. You must supply your
  own (both include AROS replacement ROMs, but those won't run all
  software).
- `shm_size: 512m` matters — X servers crash without enough shm.
- The KasmVNC default config in `/config/.vnc/kasmvnc.yaml` is generated
  on first run; edit it (or delete it to regenerate) to customise.
- Both images render in software (no GPU passthrough): amiberry via
  llvmpipe (OpenGL), Copperline via lavapipe (Vulkan).
