# syntax=docker/dockerfile:1
# gorcon/rcon-cli (MIT), built from source: `rcon -a host:port -p password command`, used by eggs' stop traps.
# Built with a supported Go release: the binary carries that Go's standard library, which the image scan checks.
FROM golang:1.27-bookworm AS rcon
ARG RCON_CLI_VERSION=v0.10.3
RUN CGO_ENABLED=0 GOBIN=/out go install -trimpath -ldflags="-s -w" "github.com/gorcon/rcon-cli/cmd/gorcon@${RCON_CLI_VERSION}"

# SteamCMD servers on Debian 12: 32-bit libraries for SteamCMD and Steam clients, Xvfb (Core Keeper),
# libpulse/libatomic (Valheim), ICU (.NET/Unity servers), gorcon `rcon`, nc and telnet (7 Days to Die's
# console waits for its telnet port). SteamCMD itself is installed into the server folder by the egg's
# installer (./steamcmd); the auto-update hook uses that one.
FROM debian:bookworm-slim
LABEL org.opencontainers.image.source="https://github.com/sneakywrld/octail-yolks" \
      org.opencontainers.image.title="octail-yolks" \
      org.opencontainers.image.description="Octail runtime: SteamCMD servers on Debian 12"

RUN --mount=type=bind,source=common,target=/tmp/octail \
    bash /tmp/octail/setup-apt.sh \
        --i386 \
        lib32gcc-s1 \
        lib32stdc++6 \
        lib32z1 \
        libsdl2-2.0-0:i386 \
        libsdl2-2.0-0 \
        libcurl4 \
        libcurl3-gnutls \
        libssl3 \
        libicu72 \
        libatomic1 \
        libpulse0 \
        libsqlite3-0 \
        libxi6 \
        libxrandr2 \
        libglu1-mesa \
        libnss3 \
        libgdiplus \
        xvfb \
        xauth \
        sqlite3 \
        file \
        netcat-openbsd \
        telnet
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
