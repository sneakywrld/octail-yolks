# syntax=docker/dockerfile:1
# Go 1.23: servers built from Go source. The Go caches live in the server folder (the image is read-only).
FROM golang:1.23-bookworm
LABEL org.opencontainers.image.source="https://github.com/sneakywrld/octail-yolks" \
      org.opencontainers.image.title="octail-yolks" \
      org.opencontainers.image.description="Octail runtime: Go 1.23 on Debian 12"

RUN --mount=type=bind,source=common,target=/tmp/octail \
    bash /tmp/octail/setup-apt.sh \
        git \
        sqlite3 \
        file

COPY --chmod=0755 common/entrypoint.sh /entrypoint.sh

ENV HOME=/home/container \
    USER=container \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    GOPATH=/home/container/.go \
    GOCACHE=/home/container/.cache/go-build \
    GOTOOLCHAIN=local

USER container
WORKDIR /home/container
STOPSIGNAL SIGINT
ENTRYPOINT ["/usr/bin/tini", "-g", "--"]
CMD ["/entrypoint.sh"]
