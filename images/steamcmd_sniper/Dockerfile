# syntax=docker/dockerfile:1
# gorcon/rcon-cli (MIT), built from source: `rcon -a host:port -p password command`, used by eggs' stop traps.
FROM golang:1.23-bookworm AS rcon
ARG RCON_CLI_VERSION=v0.10.3
RUN CGO_ENABLED=0 GOBIN=/out go install "github.com/gorcon/rcon-cli/cmd/gorcon@${RCON_CLI_VERSION}"

# tini (static) from Debian for PID 1.
FROM debian:bookworm-slim AS tini
RUN apt-get update \
 && apt-get install -y --no-install-recommends tini \
 && rm -rf /var/lib/apt/lists/*

# Valve's Steam Runtime 3 "sniper" (the runtime Counter-Strike 2 is built for), with our entrypoint.
FROM registry.gitlab.steamos.cloud/steamrt/sniper/platform:latest-container-runtime-depot
LABEL org.opencontainers.image.source="https://github.com/sneakywrld/octail-yolks" \
      org.opencontainers.image.title="octail-yolks" \
      org.opencontainers.image.description="Octail runtime: Steam Runtime 3 (sniper) for Counter-Strike 2"

COPY --from=tini /usr/bin/tini-static /usr/bin/tini
COPY --from=rcon /out/gorcon /usr/local/bin/rcon
RUN (id container >/dev/null 2>&1 || useradd --create-home --home-dir /home/container --shell /bin/bash container) \
 && mkdir -p /home/container /etc/octail/entrypoint.d \
 && chown container:container /home/container

COPY --chmod=0755 common/entrypoint.sh /entrypoint.sh
COPY --chmod=0644 common/hooks/50-steamcmd-update.sh /etc/octail/entrypoint.d/50-steamcmd-update.sh

ENV HOME=/home/container \
    USER=container \
    LANG=C.UTF-8

USER container
WORKDIR /home/container
STOPSIGNAL SIGINT
ENTRYPOINT ["/usr/bin/tini", "-g", "--"]
CMD ["/entrypoint.sh"]
