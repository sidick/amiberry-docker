# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Docker images for Amiga emulators (amiberry, Copperline) served in the browser via KasmVNC (display + audio). One multi-stage `Dockerfile` produces two published images (`ghcr.io/sidick/amiberry`, `ghcr.io/sidick/copperline-vnc`) from a shared `base` stage. There is no application code here — the repo is the Dockerfile, shell scripts, seed configs, and CI workflows.

## Commands

```sh
make build APP=amiberry          # docker build --target amiberry (also: copperline-vnc)
make build-all                   # build both images
make up APP=amiberry             # run detached on 8443 (copperline-vnc: 8444)
make logs APP=amiberry           # follow logs
make shell APP=amiberry          # bash into the running container
make down APP=amiberry           # remove container, keep config volume
make clean APP=amiberry          # remove container AND config volume (fresh first-run state)
```

Per-app targets require `APP=` explicitly. A bare `docker build .` (no `--target`) deliberately builds the amiberry image — the amiberry stage is last in the Dockerfile for that reason. Overridable vars: `PORT`, `IMAGE`, `NAME`, `VOLUME`, `VNC_PASSWORD`.

There are no tests or linters. Verification = build the image, run it, and check real pixels (see below).

## Verifying a container actually works

"Process alive + HTTP 200" proves nothing — the emulator can be running while the display is black. To get a screenshot without a browser:

```sh
docker exec <name> sh -c 'apt-get update -qq && apt-get install -y -qq x11-apps imagemagick'
docker exec <name> runuser -u app -- sh -c 'DISPLAY=:1 XAUTHORITY=/config/.Xauthority xwd -root -silent | convert xwd:- png:/tmp/shot.png'
docker cp <name>:/tmp/shot.png .
```

A fresh copperline-vnc volume boots the bundled AROS ROM, so its boot screen is a known-good render target. Avoid driving the KasmVNC web UI with browser automation — the basic-auth modal wedges it, and the `/api/get_screenshot` endpoint 401s for the seeded (non-owner) user.

## Architecture

### Container startup chain

`tini` → `entrypoint.sh` (root) → `vncserver :1` (as user `app`, UID 1000) → `/config/.vnc/xstartup` → `/usr/local/bin/start-app` → the emulator. `/config` is a volume and the app user's `$HOME`; ALL persistent state (KasmVNC config/passwd, emulator configs, ROMs, logs) lives there.

`entrypoint.sh` is generic and shared by both images. Everything app-specific lives in exactly two files per app under `apps/<app>/`:

- **`app-init.sh`** — sourced by the entrypoint *as root* after `/config` is prepared. Seeds config into the volume (from `/opt/app-seed/`) and appends `NAME=value` pairs to the `EXTRA_ENV` array to inject env into the emulator's session. Env must travel via `EXTRA_ENV`, not xstartup — old volumes can hold a stale xstartup, which still works precisely because xstartup carries no env.
- **`start-app`** — exec'd by the X session to launch the emulator.

Adding a new emulator = a new final Dockerfile stage `FROM base` + these two files (+ seed config), plus entries in the Makefile `APPS` list, docker-compose.yml, and the workflows.

### Seeding rules

First-run-only vs always-refreshed matters: amiberry's `default.uae` is seeded only if absent (never clobber user edits) while `vnc-default.uae` is re-copied every start as a pristine fallback. Copperline's `copperline.toml` is first-run-only. The entrypoint similarly only generates `kasmvnc.yaml`, `xstartup`, and `.kasmpasswd` when missing.

### CI / publishing

- `_build-image.yml` — the single reusable build: native amd64 + arm64 runners (no QEMU — the Copperline cargo build would crawl), each pushes by digest, a merge job stitches one manifest list per tag.
- `upstream-release.yml` — polls both upstream repos daily; on a new release, builds with the version passed as a build arg, tags `X.Y.Z` / `X.Y` / `latest`, and creates a marker release in this repo (`amiberry-vX.Y.Z`). Published images can therefore be **newer than the version pins in the Dockerfile** — the `ARG *_VERSION` values are fallback defaults, not the source of truth.
- `build-and-push.yml` — manual dispatch wrapper around the same reusable build.

## Hard-won gotchas (do not regress)

- **`AMIBERRY_NO_WM=1` (set in `apps/amiberry/app-init.sh`) is what stops the emulation screen from being black.** KasmVNC's Xvnc has no window manager; with `NO_WM=0` amiberry waits for a WM to map its emulation window and you get a black root window (while the amiberry GUI still renders, deceptively). Verified with both GL and non-GL builds — the renderer is irrelevant.
- `LIBGL_ALWAYS_SOFTWARE=1` and `SDL_RENDER_DRIVER=software` in the same file are belt-and-suspenders no-ops: the release .deb renders through its own OpenGL path (llvmpipe), not SDL's renderer.
- `shm-size 512m` is required — X servers crash without enough shm.
- Copperline resolves `./copperline.toml` and relative ROM/disk paths from its CWD; `start-app` must `cd /config/Copperline` first. Its AROS boot ROM is not embedded in the binary — the Dockerfile copies it to `/usr/share/copperline/aros/` where `romsearch.rs` expects it; without it Copperline exits at startup.
- The entrypoint tees all output to `$APP_LOG` in the volume (truncated each start). `AMIBERRY_LOG` is honoured as a legacy alias.
- Files copied into the volume from the host must be readable by UID 1000 (`docker cp` preserves host UIDs, e.g. 501 on macOS).
- amiberry buffers its own log (`/config/Amiberry/Amiberry.log`) and flushes only on clean exit; run with `--log` to stream it when debugging.
