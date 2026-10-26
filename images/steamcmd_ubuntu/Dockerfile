# syntax=docker/dockerfile:1
# gorcon/rcon-cli (MIT), built from source: `rcon -a host:port -p password command`, used by eggs' stop traps.
# Built with a supported Go release: the binary carries that Go's standard library, which the image scan checks.
FROM golang:1.27-bookworm AS rcon
ARG RCON_CLI_VERSION=v0.10.3
RUN CGO_ENABLED=0 GOBIN=/out go install -trimpath -ldflags="-s -w" "github.com/gorcon/rcon-cli/cmd/gorcon@${RCON_CLI_VERSION}"

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
        xvfb \
        xauth \
        sqlite3 \
        file \
        netcat-openbsd \
        telnet
# Pavlov VR dlopen()s the unversioned libc++.so. Ubuntu's libc++-dev ships that name as a linker script
# (INPUT(...)) dlopen can't load, so instead of the -dev package (headers and static libraries, tens of MB) the
# unversioned names point straight at the runtime libraries.
RUN test -e /usr/lib/x86_64-linux-gnu/libc++.so.1 \
    && test -e /usr/lib/x86_64-linux-gnu/libc++abi.so.1 \
    && ln -sf libc++.so.1 /usr/lib/x86_64-linux-gnu/libc++.so \
    && ln -sf libc++abi.so.1 /usr/lib/x86_64-linux-gnu/libc++abi.so
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
# The console banner's image line (common/entrypoint.sh): CI passes the dated tag it pushes, <tag>-<yyyymmdd>.
# Metadata only, last, so a new date never rebuilds a layer.
ARG OCTAIL_IMAGE=
ENV OCTAIL_IMAGE=${OCTAIL_IMAGE}
ENTRYPOINT ["/usr/bin/tini", "-g", "--"]
CMD ["/entrypoint.sh"]
