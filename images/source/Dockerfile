# syntax=docker/dockerfile:1
# gorcon/rcon-cli (MIT), built from source: `rcon -a host:port -p password command`, used by eggs' stop traps.
FROM golang:1.23-bookworm AS rcon
ARG RCON_CLI_VERSION=v0.10.3
RUN CGO_ENABLED=0 GOBIN=/out go install "github.com/gorcon/rcon-cli/cmd/gorcon@${RCON_CLI_VERSION}"

# Source engine dedicated servers (srcds_run: TF2, L4D2, GMod, CS:S, DoD:S, ...): the 32-bit libraries
# srcds needs on top of the SteamCMD image. These eggs have no AUTO_UPDATE variable and old servers
# refuse current clients, so the update before start is on unless AUTO_UPDATE=0.
FROM debian:bookworm-slim
LABEL org.opencontainers.image.source="https://github.com/sneakywrld/octail-yolks" \
      org.opencontainers.image.title="octail-yolks" \
      org.opencontainers.image.description="Octail runtime: Source engine (SRCDS) servers on Debian 12"

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
        libcurl4:i386 \
        libcurl3-gnutls:i386 \
        libncurses5:i386 \
        libtinfo5:i386 \
        libbz2-1.0:i386 \
        libtcmalloc-minimal4:i386 \
        libstdc++6:i386
COPY --from=rcon /out/gorcon /usr/local/bin/rcon

COPY --chmod=0755 common/entrypoint.sh /entrypoint.sh
COPY --chmod=0644 common/hooks/50-steamcmd-update.sh /etc/octail/entrypoint.d/50-steamcmd-update.sh

ENV HOME=/home/container \
    USER=container \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    OCTAIL_AUTO_UPDATE_DEFAULT=1

USER container
WORKDIR /home/container
STOPSIGNAL SIGINT
ENTRYPOINT ["/usr/bin/tini", "-g", "--"]
CMD ["/entrypoint.sh"]
