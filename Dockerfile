# syntax=docker/dockerfile:1.7
FROM debian:trixie-slim

ARG TARGETARCH
ARG AMIBERRY_VERSION=8.2.2
ARG KASMVNC_VERSION=1.4.0

LABEL org.opencontainers.image.title="amiberry" \
      org.opencontainers.image.description="Amiberry Amiga emulator with KasmVNC web access" \
      org.opencontainers.image.version="${AMIBERRY_VERSION}" \
      org.opencontainers.image.source="https://github.com/sidick/amiberry-docker" \
      org.opencontainers.image.url="https://github.com/sidick/amiberry-docker" \
      org.opencontainers.image.licenses="GPL-3.0-only" \
      org.opencontainers.image.base.name="docker.io/library/debian:trixie-slim"

ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/config \
    USER=amiberry \
    DISPLAY=:1 \
    VNC_PORT=8443 \
    VNC_GEOMETRY=1280x960 \
    VNC_DEPTH=24 \
    SDL_AUDIODRIVER=pulseaudio \
    PULSE_SERVER=unix:/tmp/pulse-socket

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl unzip \
        tini \
        pulseaudio pulseaudio-utils \
        xauth xfonts-base xfonts-100dpi xfonts-75dpi \
        libxfont2 libpixman-1-0 libxkbcommon0 libxshmfence1 \
        libgl1 libegl1 libgles2 libglx-mesa0 \
        libgomp1 \
        dbus-x11 \
        ssl-cert \
    && make-ssl-cert generate-default-snakeoil --force-overwrite \
    && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    case "${TARGETARCH}" in \
        amd64) arch=amd64 ;; \
        arm64) arch=arm64 ;; \
        *) echo "Unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /tmp/kasmvnc.deb \
        "https://github.com/kasmtech/KasmVNC/releases/download/v${KASMVNC_VERSION}/kasmvncserver_trixie_${KASMVNC_VERSION}_${arch}.deb"; \
    apt-get update; \
    apt-get install -y --no-install-recommends /tmp/kasmvnc.deb; \
    rm -f /tmp/kasmvnc.deb; \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    case "${TARGETARCH}" in \
        amd64) arch=amd64 ;; \
        arm64) arch=arm64 ;; \
    esac; \
    curl -fsSL -o /tmp/amiberry.zip \
        "https://github.com/BlitterStudio/amiberry/releases/download/v${AMIBERRY_VERSION}/amiberry-v${AMIBERRY_VERSION}-debian-trixie-${arch}.zip"; \
    cd /tmp && unzip amiberry.zip; \
    apt-get update; \
    apt-get install -y --no-install-recommends /tmp/amiberry_*.deb; \
    rm -f /tmp/amiberry.zip /tmp/amiberry_*.deb; \
    rm -rf /var/lib/apt/lists/*

RUN useradd -u 1000 -s /bin/bash -d /config -M -G ssl-cert,audio,video amiberry \
    && mkdir -p /config \
    && chown -R amiberry:amiberry /config

# Seed configs copied into the image; the entrypoint installs them into the
# /config volume on startup (default.uae only if absent; vnc-default.uae is
# always refreshed as a pristine fallback).
COPY amiberry-config/ /opt/amiberry-seed/

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

VOLUME ["/config"]
EXPOSE 8443

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
