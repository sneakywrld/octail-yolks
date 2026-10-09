# syntax=docker/dockerfile:1
# Small installer (runs as root) for scripts written for ash/bash on Alpine.
FROM alpine:3.22
LABEL org.opencontainers.image.source="https://github.com/sneakywrld/octail-yolks" \
      org.opencontainers.image.title="octail-yolks" \
      org.opencontainers.image.description="Octail installer: Alpine Linux with the usual install-script tools"

RUN --mount=type=bind,source=common,target=/tmp/octail \
    sh /tmp/octail/setup-apk.sh wget file git dos2unix zip rsync openssl coreutils findutils sed gawk \
        bzip2 gzip sqlite

ENV LANG=C.UTF-8
# Tentacle runs installers as root with their own command (bash /mnt/install/install.sh).
WORKDIR /mnt/server
CMD ["/bin/bash"]
