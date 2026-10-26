# syntax=docker/dockerfile:1
# .NET 9 runtime: TShock 6 (Terraria) and other .NET 9 servers. Microsoft supports .NET 9 until November 2026;
# TShock 6 is built for it (framework-dependent, its official Docker image uses runtime:9.0), so it stays until
# TShock moves to .NET 10.
FROM mcr.microsoft.com/dotnet/runtime:9.0-bookworm-slim
LABEL org.opencontainers.image.source="https://github.com/sneakywrld/octail-yolks" \
      org.opencontainers.image.title="octail-yolks" \
      org.opencontainers.image.description="Octail runtime: .NET 9 runtime on Debian 12"

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
# The console banner's image line (common/entrypoint.sh): CI passes the dated tag it pushes, <tag>-<yyyymmdd>.
# Metadata only, last, so a new date never rebuilds a layer.
ARG OCTAIL_IMAGE=
ENV OCTAIL_IMAGE=${OCTAIL_IMAGE}
ENTRYPOINT ["/usr/bin/tini", "-g", "--"]
CMD ["/entrypoint.sh"]
