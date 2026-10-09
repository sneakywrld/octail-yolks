# syntax=docker/dockerfile:1
# gorcon/rcon-cli (MIT), built from source: `rcon -a host:port -p password command`, used by eggs' stop traps.
FROM golang:1.23-bookworm AS rcon
ARG RCON_CLI_VERSION=v0.10.3
RUN CGO_ENABLED=0 GOBIN=/out go install "github.com/gorcon/rcon-cli/cmd/gorcon@${RCON_CLI_VERSION}"

# SteamCMD servers that need a newer glibc/libstdc++ or libc++ (Insurgency: Sandstorm, Pavlov VR, Stationeers).
FROM ubuntu:24.04
LABEL org.opencontainers.image.source="https://github.com/sneakywrld/octail-yolks" \
      org.opencontainers.image.title="octail-yolks" \
      org.opencontainers.image.description="Octail runtime: SteamCMD servers on Ubuntu 24.04"

RUN --mount=type=bind,source=common,target=/tmp/octail \
    bash /tmp/octail/setup-apt.sh \
        --i386 \
        lib32gcc-s1 \
        lib32stdc++6 \
        lib32z1 \
        libsdl2-2.0-0:i386 \
        libsdl2-2.0-0 \
        libcurl4t64 \
        libcurl3t64-gnutls \
        libssl3t64 \
        libicu74 \
        libatomic1 \
        libpulse0 \
        libsqlite3-0 \
        libc++1 \
        libc++abi1 \
        libc++-dev \
        xvfb \
        xauth \
        sqlite3 \
        file \
        netcat-openbsd \
        telnet
# Pavlov VR dlopen()s libc++.so, which Ubuntu ships as a linker script (INPUT(...)) that dlopen can't load.
RUN test -e /usr/lib/x86_64-linux-gnu/libc++.so.1 \
    && ln -sf libc++.so.1 /usr/lib/x86_64-linux-gnu/libc++.so
COPY --from=rcon /out/gorcon /usr/local/bin/rcon

COPY --chmod=0755 common/entrypoint.sh /entrypoint.sh
COPY --chmod=0644 common/hooks/50-steamcmd-update.sh /etc/octail/entrypoint.d/50-steamcmd-update.sh

ENV HOME=/home/container \
    USER=container \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8

USER container
WORKDIR /home/container
STOPSIGNAL SIGINT
ENTRYPOINT ["/usr/bin/tini", "-g", "--"]
CMD ["/entrypoint.sh"]
