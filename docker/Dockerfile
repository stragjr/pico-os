# Build environment for the Pico kernel, BusyBox and boot image.
# Works on Intel and Apple Silicon hosts: on arm64 it builds natively, on amd64 it cross-compiles.
FROM debian:bookworm

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends \
      build-essential flex bison bc libssl-dev libelf-dev git python3 \
      ca-certificates curl bzip2 xz-utils file rsync kmod \
 && if [ "$(dpkg --print-architecture)" = "amd64" ]; then \
      apt-get install -y -qq --no-install-recommends crossbuild-essential-arm64; \
    fi \
 && rm -rf /var/lib/apt/lists/*
