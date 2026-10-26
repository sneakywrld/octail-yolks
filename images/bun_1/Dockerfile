# syntax=docker/dockerfile:1
# Bun 1: JavaScript/TypeScript bots and servers run with Bun. Bun is the release binary from oven-sh/bun on GitHub,
# checked against the sha256 pinned below (the release's SHASUMS256.txt); amd64 takes the "baseline" build, which
# runs on CPUs without AVX2 (many VPS CPU models). Bump BUN_VERSION and both sums together, by hand.
FROM debian:bookworm-slim
LABEL org.opencontainers.image.source="https://github.com/sneakywrld/octail-yolks" \
      org.opencontainers.image.title="octail-yolks" \
      org.opencontainers.image.description="Octail runtime: Bun 1 on Debian 12"

ARG BUN_VERSION=1.4.4
ARG BUN_SHA256_AMD64=e0446eb55995772eb9894bebae9a6be368d985a8b9271ee124486f9946eedd76
ARG BUN_SHA256_ARM64=baa6bb36f51d6e58561e02bbea825038a9df454f673d6d776e8bbf86f8c7850e
ARG TARGETARCH

RUN --mount=type=bind,source=common,target=/tmp/octail \
    bash /tmp/octail/setup-apt.sh \
        git \
        sqlite3 \
        file \
        python3 \
        make \
        g++

RUN set -eu; \
    case "${TARGETARCH:-amd64}" in \
        amd64) asset=bun-linux-x64-baseline; sum=${BUN_SHA256_AMD64} ;; \
        arm64) asset=bun-linux-aarch64; sum=${BUN_SHA256_ARM64} ;; \
        *) echo "no Bun build for ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /tmp/bun.zip "https://github.com/oven-sh/bun/releases/download/bun-v${BUN_VERSION}/${asset}.zip"; \
    printf '%s  /tmp/bun.zip\n' "${sum}" >/tmp/bun.zip.sha256; \
    sha256sum -c /tmp/bun.zip.sha256; \
    unzip -q /tmp/bun.zip -d /tmp; \
    install -m 0755 "/tmp/${asset}/bun" /usr/local/bin/bun; \
    ln -s bun /usr/local/bin/bunx; \
    rm -rf /tmp/bun.zip /tmp/bun.zip.sha256 "/tmp/${asset}"; \
    bun --version

COPY --chmod=0755 common/entrypoint.sh /entrypoint.sh

ENV HOME=/home/container \
    USER=container \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    BUN_INSTALL=/home/container/.bun \
    BUN_RUNTIME_TRANSPILER_CACHE_PATH=/home/container/.cache/bun/transpiler \
    DO_NOT_TRACK=1

USER container
WORKDIR /home/container
STOPSIGNAL SIGINT
# The console banner's image line (common/entrypoint.sh): CI passes the dated tag it pushes, <tag>-<yyyymmdd>.
# Metadata only, last, so a new date never rebuilds a layer.
ARG OCTAIL_IMAGE=
ENV OCTAIL_IMAGE=${OCTAIL_IMAGE}
ENTRYPOINT ["/usr/bin/tini", "-g", "--"]
CMD ["/entrypoint.sh"]
