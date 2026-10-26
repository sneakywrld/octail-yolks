# syntax=docker/dockerfile:1
# Deno 2: JavaScript/TypeScript bots and servers run with Deno. Deno is the release binary from denoland/deno on
# GitHub, checked against the sha256 pinned below (the release's .sha256sum files). The module cache (DENO_DIR)
# lives in the server folder (the image is read-only). Bump DENO_VERSION and both sums together, by hand.
FROM debian:bookworm-slim
LABEL org.opencontainers.image.source="https://github.com/sneakywrld/octail-yolks" \
      org.opencontainers.image.title="octail-yolks" \
      org.opencontainers.image.description="Octail runtime: Deno 2 on Debian 12"

ARG DENO_VERSION=2.9.8
ARG DENO_SHA256_AMD64=e890975bc2549807bbcc0b584ffafda72cc7c93349dd99c80483dd784f6c4609
ARG DENO_SHA256_ARM64=d49596c20b9788cf8f5d8ddf644103d4bde56ed239753f0bdb92ba9361d51905
ARG TARGETARCH

RUN --mount=type=bind,source=common,target=/tmp/octail \
    bash /tmp/octail/setup-apt.sh \
        git \
        sqlite3 \
        file

RUN set -eu; \
    case "${TARGETARCH:-amd64}" in \
        amd64) asset=deno-x86_64-unknown-linux-gnu; sum=${DENO_SHA256_AMD64} ;; \
        arm64) asset=deno-aarch64-unknown-linux-gnu; sum=${DENO_SHA256_ARM64} ;; \
        *) echo "no Deno build for ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /tmp/deno.zip "https://github.com/denoland/deno/releases/download/v${DENO_VERSION}/${asset}.zip"; \
    printf '%s  /tmp/deno.zip\n' "${sum}" >/tmp/deno.zip.sha256; \
    sha256sum -c /tmp/deno.zip.sha256; \
    unzip -q /tmp/deno.zip deno -d /usr/local/bin; \
    chmod 0755 /usr/local/bin/deno; \
    rm -f /tmp/deno.zip /tmp/deno.zip.sha256; \
    deno --version

COPY --chmod=0755 common/entrypoint.sh /entrypoint.sh

ENV HOME=/home/container \
    USER=container \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    DENO_DIR=/home/container/.cache/deno \
    DENO_INSTALL_ROOT=/home/container/.deno \
    DENO_NO_UPDATE_CHECK=1 \
    DENO_NO_PROMPT=1

USER container
WORKDIR /home/container
STOPSIGNAL SIGINT
# The console banner's image line (common/entrypoint.sh): CI passes the dated tag it pushes, <tag>-<yyyymmdd>.
# Metadata only, last, so a new date never rebuilds a layer.
ARG OCTAIL_IMAGE=
ENV OCTAIL_IMAGE=${OCTAIL_IMAGE}
ENTRYPOINT ["/usr/bin/tini", "-g", "--"]
CMD ["/entrypoint.sh"]
