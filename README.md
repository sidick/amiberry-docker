# docker-amiberry

Containerised [amiberry](https://github.com/BlitterStudio/amiberry) Amiga
emulator, accessed in the browser over [KasmVNC](https://github.com/kasmtech/KasmVNC)
(display + audio in one). All user state — configs, kickstart ROMs, floppies,
hard files, savestates — lives in a single named volume mounted at `/config`.

Builds for `linux/amd64` and `linux/arm64`.

## Components

| | Version | Source |
|---|---|---|
| amiberry | 8.1.6 | `.deb` from upstream release |
| KasmVNC | 1.4.0 | `.deb` from upstream release |
| Base | `debian:trixie-slim` | |

## Run

### With docker compose

The included `docker-compose.yml` pulls `ghcr.io/sidick/amiberry:latest`:

```sh
docker compose up -d
```

### With plain docker

```sh
docker run --rm -it \
    -p 8443:8443 \
    -v amiberry-config:/config \
    --shm-size=512m \
    ghcr.io/sidick/amiberry:latest
```

Multi-arch — Docker auto-picks the right variant. Then open
<http://localhost:8443/> in a browser. Default credentials:
`amiberry` / `amiberry` (override via `VNC_USER` / `VNC_PASSWORD`).

## Build from source

```sh
docker build -t amiberry:local .
```

For multi-arch:

```sh
docker buildx build --platform linux/amd64,linux/arm64 -t amiberry:local .
```

To run the local build via compose, uncomment the `build:` block in
`docker-compose.yml` and either remove the `image:` line or point it at
your local tag, then `docker compose up --build`.

## The config volume

`/config` is the `amiberry` user's `$HOME`. On first run amiberry creates
`/config/Amiberry/` with these subdirectories:

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

KasmVNC stores its config under `/config/.vnc/` and the user/password
database at `/config/.kasmpasswd`.

To add ROMs / floppies from the host into a named volume, copy them in
and fix ownership (amiberry runs as UID 1000 inside the container, but
`docker cp` writes files using the **host** user's UID — typically 501
on macOS — which amiberry can't read):

```sh
docker cp ~/roms/kick13.rom amiberry:/config/Amiberry/ROMs/
docker exec -u 0 amiberry chown -R amiberry:amiberry /config/Amiberry/ROMs/
```

Or pipe the file in through an exec'd shell as the amiberry user — one
command, correct ownership from the start:

```sh
docker exec -i -u amiberry amiberry \
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

With `docker-compose.yml`, replace the `volumes:` block:

```yaml
services:
  amiberry:
    # ...
    volumes:
      - ./amiberry-data:/config   # bind mount
    # remove the top-level `volumes: amiberry-config:` block too
```

The entrypoint runs `chown amiberry:amiberry /config` at startup, so on
Linux your host directory's files will become owned by UID 1000. On macOS
and Windows, Docker Desktop maps ownership transparently and you don't
need to do anything.

Files you can stage into the host directory **before** the first run:

- `Amiberry/ROMs/*.rom` — kickstart ROMs
- `Amiberry/Floppies/*.adf` — floppy images
- `Amiberry/HardDrives/*.hdf` — hard files
- `Amiberry/Configurations/*.uae` — pre-made amiberry config files

amiberry will create the rest of the `Amiberry/` subdirectories on first
launch.

## Environment variables

| Var | Default | Purpose |
|---|---|---|
| `VNC_GEOMETRY` | `1280x960` | KasmVNC desktop resolution |
| `VNC_DEPTH` | `24` | Colour depth |
| `VNC_PORT` | `8443` | Browser websocket port |
| `VNC_USER` | `amiberry` | KasmVNC username |
| `VNC_PASSWORD` | `amiberry` | KasmVNC password (change this) |

## Audio

PulseAudio runs inside the container; KasmVNC streams its output to the
browser. The first time it works depends on your browser allowing audio
autoplay — click the speaker icon in the KasmVNC control bar if silent.

## Notes & caveats

- amiberry **does not bundle Amiga kickstart ROMs**. You must supply your
  own (AROS replacement ROMs are included, but won't run all software).
- `shm_size: 512m` matters — X servers crash without enough shm.
- The KasmVNC default config in `/config/.vnc/kasmvnc.yaml` is generated
  on first run; edit it (or delete it to regenerate) to customise.
