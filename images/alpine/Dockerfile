# syntax=docker/dockerfile:1
# Small generic runtime (Alpine, musl): scripts and statically linked servers.
FROM alpine:3.22
LABEL org.opencontainers.image.source="https://github.com/sneakywrld/octail-yolks" \
      org.opencontainers.image.title="octail-yolks" \
      org.opencontainers.image.description="Octail runtime: small generic Alpine Linux"

RUN --mount=type=bind,source=common,target=/tmp/octail \
    sh /tmp/octail/setup-apk.sh libstdc++ libgcc file

COPY --chmod=0755 common/entrypoint.sh /entrypoint.sh

ENV HOME=/home/container \
    USER=container \
    LANG=C.UTF-8

USER container
WORKDIR /home/container
STOPSIGNAL SIGINT
ENTRYPOINT ["/usr/bin/tini", "-g", "--"]
CMD ["/entrypoint.sh"]
