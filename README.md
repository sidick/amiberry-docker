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

## Build & run (compose)

```sh
docker compose up --build
```

Then open <http://localhost:8443/> in a browser. Default credentials:
`amiberry` / `amiberry` (override via `VNC_USER` / `VNC_PASSWORD`).

## Build & run (plain docker)

```sh
docker build -t amiberry:local .
docker run --rm -it \
    -p 8443:8443 \
    -v amiberry-config:/config \
    --shm-size=512m \
    amiberry:local
```

For multi-arch:

```sh
docker buildx build --platform linux/amd64,linux/arm64 -t amiberry:local .
```

## The config volume

`/config` is the `amiberry` user's `$HOME`. amiberry creates `/config/Amiberry/`
on first run with the usual subdirectories (`conf/`, `kickstarts/`, `floppies/`,
`harddrives/`, `savestates/`, `screenshots/`, etc.). KasmVNC stores its config
under `/config/.vnc/` and the user/password database at `/config/.kasmpasswd`.

To add ROMs / floppies from the host, copy into the volume:

```sh
docker cp ~/roms/kick13.rom amiberry:/config/Amiberry/kickstarts/
```

…or mount a host directory in `docker-compose.yml` instead of the named
volume.

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
