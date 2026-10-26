# syntax=docker/dockerfile:1
# Python 3.15: bots and Python servers.
FROM python:3.15-slim-bookworm
LABEL org.opencontainers.image.source="https://github.com/sneakywrld/octail-yolks" \
      org.opencontainers.image.title="octail-yolks" \
      org.opencontainers.image.description="Octail runtime: Python 3.15 on Debian 12"

RUN --mount=type=bind,source=common,target=/tmp/octail \
    bash /tmp/octail/setup-apt.sh \
        git \
        sqlite3 \
        file \
        gcc \
        libc6-dev

COPY --chmod=0755 common/entrypoint.sh /entrypoint.sh

ENV HOME=/home/container \
    USER=container \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONUNBUFFERED=1

USER container
WORKDIR /home/container
STOPSIGNAL SIGINT
# The console banner's image line (common/entrypoint.sh): CI passes the dated tag it pushes, <tag>-<yyyymmdd>.
# Metadata only, last, so a new date never rebuilds a layer.
ARG OCTAIL_IMAGE=
ENV OCTAIL_IMAGE=${OCTAIL_IMAGE}
ENTRYPOINT ["/usr/bin/tini", "-g", "--"]
CMD ["/entrypoint.sh"]
