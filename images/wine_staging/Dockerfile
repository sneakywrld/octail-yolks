# syntax=docker/dockerfile:1
# gorcon/rcon-cli (MIT), built from source: `rcon -a host:port -p password command`, used by eggs' stop traps.
# Built with a supported Go release: the binary carries that Go's standard library, which the image scan checks.
FROM golang:1.27-bookworm AS rcon
ARG RCON_CLI_VERSION=v0.10.3
RUN CGO_ENABLED=0 GOBIN=/out go install -trimpath -ldflags="-s -w" "github.com/gorcon/rcon-cli/cmd/gorcon@${RCON_CLI_VERSION}"

# Windows-only servers through Wine (staging branch from WineHQ), winetricks, Wine Mono and Gecko.
# Hooks: virtual display (on unless XVFB=0), the Wine prefix and WINETRICKS_RUN verbs, SteamCMD update
# (with app 1007, the Windows Steam client libraries, unless STEAM_SDK=0).
FROM debian:bookworm-slim
ARG WINE_BRANCH=staging
ARG WINETRICKS_VERSION=20260125
LABEL org.opencontainers.image.source="https://github.com/sneakywrld/octail-yolks" \
      org.opencontainers.image.title="octail-yolks" \
      org.opencontainers.image.description="Octail runtime: Windows servers through Wine (staging) on Debian 12"

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
        cabextract \
        p7zip-full \
        winbind
RUN --mount=type=bind,source=common,target=/tmp/octail \
    bash /tmp/octail/install-wine.sh "${WINE_BRANCH}" "${WINETRICKS_VERSION}"
COPY --from=rcon /out/gorcon /usr/local/bin/rcon

COPY --chmod=0755 common/entrypoint.sh /entrypoint.sh
COPY --chmod=0644 common/hooks/20-display.sh /etc/octail/entrypoint.d/20-display.sh
COPY --chmod=0644 common/hooks/30-wine.sh /etc/octail/entrypoint.d/30-wine.sh
COPY --chmod=0644 common/hooks/50-steamcmd-update.sh /etc/octail/entrypoint.d/50-steamcmd-update.sh

ENV HOME=/home/container \
    USER=container \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    WINEPREFIX=/home/container/.wine \
    WINEDEBUG=-all \
    OCTAIL_XVFB_DEFAULT=1 \
    OCTAIL_STEAM_SDK_DEFAULT=1

USER container
WORKDIR /home/container
STOPSIGNAL SIGINT
# The console banner's image line (common/entrypoint.sh): CI passes the dated tag it pushes, <tag>-<yyyymmdd>.
# Metadata only, last, so a new date never rebuilds a layer.
ARG OCTAIL_IMAGE=
ENV OCTAIL_IMAGE=${OCTAIL_IMAGE}
ENTRYPOINT ["/usr/bin/tini", "-g", "--"]
CMD ["/entrypoint.sh"]
