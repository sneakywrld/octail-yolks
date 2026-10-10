# syntax=docker/dockerfile:1
# gorcon/rcon-cli (MIT), built from source: `rcon -a host:port -p password command`, used by eggs' stop traps.
FROM golang:1.23-bookworm AS rcon
ARG RCON_CLI_VERSION=v0.10.3
RUN CGO_ENABLED=0 GOBIN=/out go install "github.com/gorcon/rcon-cli/cmd/gorcon@${RCON_CLI_VERSION}"

# Windows-only servers through GE-Proton: `proton run ./Server.exe`. XVFB=1 starts a virtual display. The
# SteamCMD update also updates app 1007 (the Windows Steam client libraries) unless STEAM_SDK=0.
# GE-Proton stays on 10-34 for now: other hosts report GE-Proton 11 (11-1 to 11-7) hanging ARK: Survival Ascended
# before its engine writes a line and keeping Astroneer from starting, both fine on 10-34. GE-Proton 11 also needs
# glibc 2.38, newer than Debian 12's 2.36; install-proton.sh refuses a GE-Proton the base can't load.
# PROTON_USE_XALIA=0: no Xalia (Proton's gamepad UI helper, a .NET program that fails without a display).
FROM debian:bookworm-slim
ARG GE_PROTON_VERSION=GE-Proton10-34
LABEL org.opencontainers.image.source="https://github.com/sneakywrld/octail-yolks" \
      org.opencontainers.image.title="octail-yolks" \
      org.opencontainers.image.description="Octail runtime: Windows servers through GE-Proton on Debian 12"

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
        python3 \
        libfreetype6 \
        libfontconfig1 \
        libgnutls30 \
        libvulkan1 \
        dbus \
        cabextract \
        winbind
RUN --mount=type=bind,source=common,target=/tmp/octail \
    bash /tmp/octail/install-proton.sh "${GE_PROTON_VERSION}"
COPY --from=rcon /out/gorcon /usr/local/bin/rcon

COPY --chmod=0755 common/entrypoint.sh /entrypoint.sh
COPY --chmod=0644 common/hooks/20-display.sh /etc/octail/entrypoint.d/20-display.sh
COPY --chmod=0644 common/hooks/30-proton.sh /etc/octail/entrypoint.d/30-proton.sh
COPY --chmod=0644 common/hooks/50-steamcmd-update.sh /etc/octail/entrypoint.d/50-steamcmd-update.sh

ENV HOME=/home/container \
    USER=container \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    PROTON_NO_FSYNC=1 \
    PROTON_USE_XALIA=0 \
    OCTAIL_STEAM_SDK_DEFAULT=1

USER container
WORKDIR /home/container
STOPSIGNAL SIGINT
ENTRYPOINT ["/usr/bin/tini", "-g", "--"]
CMD ["/entrypoint.sh"]
