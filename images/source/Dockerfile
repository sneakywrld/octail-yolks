# syntax=docker/dockerfile:1
# gorcon/rcon-cli (MIT), built from source: `rcon -a host:port -p password command`, used by eggs' stop traps.
# Built with a supported Go release: the binary carries that Go's standard library, which the image scan checks.
FROM golang:1.27-bookworm AS rcon
ARG RCON_CLI_VERSION=v0.10.3
RUN CGO_ENABLED=0 GOBIN=/out go install -trimpath -ldflags="-s -w" "github.com/gorcon/rcon-cli/cmd/gorcon@${RCON_CLI_VERSION}"

# Source engine dedicated servers (srcds_run: TF2, L4D2, GMod, CS:S, DoD:S, ...) and GoldSrc ones (hlds_run:
# Counter-Strike 1.6, Half-Life Deathmatch; svends_run: Sven Co-op): the 32-bit libraries srcds and hlds need on top
# of the SteamCMD image. Sven Co-op's svends_i686 also loads 32-bit OpenSSL 3 and zlib; libcurl4:i386 pulls both in
# today, they are named here so they stay when that changes. These eggs have no AUTO_UPDATE variable and old servers
# refuse current clients, so the update before start is on unless AUTO_UPDATE=0.
# The 64-bit srcds_linux64 builds (TF2, CS:S, DoD:S, HL2DM since 2025; GMod's x86-64 branch) want the 64-bit
# ncurses 5 / tinfo 5 for the console where the 32-bit ones load the i386 ones; both are installed (~1 MB), so a
# server switched to its 64-bit binary doesn't stop on a missing libtinfo.so.5.
FROM debian:bookworm-slim
LABEL org.opencontainers.image.source="https://github.com/sneakywrld/octail-yolks" \
      org.opencontainers.image.title="octail-yolks" \
      org.opencontainers.image.description="Octail runtime: Source (SRCDS) and GoldSrc (HLDS) servers on Debian 12"

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
        libncurses5 \
        libtinfo5 \
        libncurses5:i386 \
        libtinfo5:i386 \
        libbz2-1.0:i386 \
        libtcmalloc-minimal4:i386 \
        libstdc++6:i386 \
        libssl3:i386 \
        zlib1g:i386
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
# The console banner's image line (common/entrypoint.sh): CI passes the dated tag it pushes, <tag>-<yyyymmdd>.
# Metadata only, last, so a new date never rebuilds a layer.
ARG OCTAIL_IMAGE=
ENV OCTAIL_IMAGE=${OCTAIL_IMAGE}
ENTRYPOINT ["/usr/bin/tini", "-g", "--"]
CMD ["/entrypoint.sh"]
