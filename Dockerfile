# syntax=docker/dockerfile:1
ARG debian_release=13
FROM --platform=$BUILDPLATFORM debian:${debian_release} AS build

ARG TARGETPLATFORM
ARG BUILDPLATFORM
ARG AMIBERRY_TYPE=amiberry-lite
# ARG AMIBERRY_TYPE=amiberry
ARG AMIBERRY_TAG=v5.9.1

LABEL maintainer="Simon Dick"

ENV DEBIAN_FRONTEND=noninteractive

WORKDIR /build

RUN apt-get update && \
    apt-get dist-upgrade -fuy && \
    apt-get install -y --no-install-recommends \
        autoconf git build-essential cmake ninja-build \
        libsdl2-dev libsdl2-ttf-dev libsdl2-image-dev \
        libpng-dev libflac-dev libmpg123-dev libmpeg2-4-dev \
        libenet-dev \
        pkgconf libpcap-dev libzstd-dev ca-certificates && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 https://github.com/BlitterStudio/${AMIBERRY_TYPE}.git . && \
	git checkout ${AMIBERRY_TAG}

RUN cmake -DUSE_LIBSERIALPORT=OFF -DUSE_PORTMIDI=OFF -B build && \
	cmake --build build

FROM debian:${debian_release}-slim

ARG AMIBERRY_TYPE=amiberry-lite

ENV DISPLAY=:0
ENV DEBIAN_FRONTEND=noninteractive
ENV AMIBERRY_HOME_DIR=/amiberry
ENV AMIBERRY_DATA_DIR=/usr/share/amiberry-lite/data

RUN apt-get update && \
    apt-get dist-upgrade -fuy && \
    apt-get install -y --no-install-recommends \
        libmpeg2-4 libenet7 libflac14 libpng16-16t64 libmpg123-0t64 libsdl2-2.0-0 libsdl2-ttf-2.0-0 libsdl2-image-2.0-0 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN apt-get update && apt-get install -y --no-install-recommends \
    xvfb \
    x11vnc \
    xauth \
    ca-certificates \
    procps \
    fonts-freefont-ttf \
 && rm -rf /var/lib/apt/lists/*

COPY --from=build build/build/${AMIBERRY_TYPE} /usr/bin/amiberry

COPY --from=build build/controllers /usr/share/${AMIBERRY_TYPE}/controllers
COPY --from=build build/data /usr/share/${AMIBERRY_TYPE}/data
COPY --from=build build/roms /usr/share/${AMIBERRY_TYPE}/roms
COPY --from=build build/whdboot /usr/share/${AMIBERRY_TYPE}/whdboot
COPY --chmod=755 entrypoint.sh /root

VOLUME ["/amiberry"]

WORKDIR /amiberry

RUN touch /root/.Xauthority

EXPOSE 5900

CMD [ "--help" ]
ENTRYPOINT [ "/root/entrypoint.sh" ]
