# syntax=docker/dockerfile:1
# .NET 8 runtime: tModLoader, Vintage Story and other .NET servers.
FROM mcr.microsoft.com/dotnet/runtime:8.0-bookworm-slim
LABEL org.opencontainers.image.source="https://github.com/sneakywrld/octail-yolks" \
      org.opencontainers.image.title="octail-yolks" \
      org.opencontainers.image.description="Octail runtime: .NET 8 runtime on Debian 12"

RUN --mount=type=bind,source=common,target=/tmp/octail \
    bash /tmp/octail/setup-apt.sh \
        libicu72 \
        libsqlite3-0 \
        sqlite3 \
        git \
        file

COPY --chmod=0755 common/entrypoint.sh /entrypoint.sh

ENV HOME=/home/container \
    USER=container \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    DOTNET_CLI_TELEMETRY_OPTOUT=1

USER container
WORKDIR /home/container
STOPSIGNAL SIGINT
ENTRYPOINT ["/usr/bin/tini", "-g", "--"]
CMD ["/entrypoint.sh"]
