# syntax=docker/dockerfile:1
# gorcon/rcon-cli (MIT), built from source: `rcon -a host:port -p password command`, used by eggs' stop traps.
FROM golang:1.23-bookworm AS rcon
ARG RCON_CLI_VERSION=v0.10.3
RUN CGO_ENABLED=0 GOBIN=/out go install "github.com/gorcon/rcon-cli/cmd/gorcon@${RCON_CLI_VERSION}"

# Microsoft's ASP.NET Core 8 runtime (includes the .NET runtime), copied into the SteamCMD image: Eco.
FROM mcr.microsoft.com/dotnet/aspnet:8.0-bookworm-slim AS dotnet

FROM debian:bookworm-slim
LABEL org.opencontainers.image.source="https://github.com/sneakywrld/octail-yolks" \
      org.opencontainers.image.title="octail-yolks" \
      org.opencontainers.image.description="Octail runtime: SteamCMD servers with the .NET 8 / ASP.NET Core 8 runtime on Debian 12"

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
        file
COPY --from=rcon /out/gorcon /usr/local/bin/rcon
COPY --from=dotnet /usr/share/dotnet /usr/share/dotnet
RUN ln -s /usr/share/dotnet/dotnet /usr/bin/dotnet

COPY --chmod=0755 common/entrypoint.sh /entrypoint.sh
COPY --chmod=0644 common/hooks/50-steamcmd-update.sh /etc/octail/entrypoint.d/50-steamcmd-update.sh

ENV HOME=/home/container \
    USER=container \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    DOTNET_ROOT=/usr/share/dotnet \
    DOTNET_CLI_TELEMETRY_OPTOUT=1

USER container
WORKDIR /home/container
STOPSIGNAL SIGINT
ENTRYPOINT ["/usr/bin/tini", "-g", "--"]
CMD ["/entrypoint.sh"]
