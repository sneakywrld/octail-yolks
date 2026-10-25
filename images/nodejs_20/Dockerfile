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

# npm's own dependencies (tar, minimatch, undici, ...) get their fixes with npm releases, not with Node's: the image
# carries a pinned npm newer than the one Node bundles (11.x supports Node 20.17+, 22 and 24). Raise it when Trivy
# reports one of npm's bundled packages and a newer npm has the fix.
ARG NPM_VERSION=11.21.1
RUN npm install -g --no-fund --no-audit "npm@${NPM_VERSION}" \
 && npm cache clean --force \
 && npm --version | grep -qx "${NPM_VERSION}"

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
