# syntax=docker/dockerfile:1
# Node.js 20: bots and JavaScript servers.
FROM node:20-bookworm-slim
LABEL org.opencontainers.image.source="https://github.com/sneakywrld/octail-yolks" \
      org.opencontainers.image.title="octail-yolks" \
      org.opencontainers.image.description="Octail runtime: Node.js 20 on Debian 12"

RUN --mount=type=bind,source=common,target=/tmp/octail \
    bash /tmp/octail/setup-apt.sh \
        git \
        sqlite3 \
        file \
        python3 \
        make \
        g++

COPY --chmod=0755 common/entrypoint.sh /entrypoint.sh

ENV HOME=/home/container \
    USER=container \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    NPM_CONFIG_UPDATE_NOTIFIER=false \
    NPM_CONFIG_FUND=false

USER container
WORKDIR /home/container
STOPSIGNAL SIGINT
ENTRYPOINT ["/usr/bin/tini", "-g", "--"]
CMD ["/entrypoint.sh"]
