# syntax=docker/dockerfile:1
# Generic Debian 12 runtime for native Linux servers: Factorio, OpenTTD, Terraria, Minecraft Bedrock, ...
FROM debian:bookworm-slim
LABEL org.opencontainers.image.source="https://github.com/sneakywrld/octail-yolks" \
      org.opencontainers.image.title="octail-yolks" \
      org.opencontainers.image.description="Octail runtime: generic Debian 12 with common game-server libraries"

RUN --mount=type=bind,source=common,target=/tmp/octail \
    bash /tmp/octail/setup-apt.sh \
        libstdc++6 \
        libgcc-s1 \
        libatomic1 \
        libssl3 \
        libcurl4 \
        libicu72 \
        libsqlite3-0 \
        sqlite3 \
        zlib1g \
        liblzo2-2 \
        liblzma5 \
        libpng16-16 \
        libfontconfig1 \
        libfreetype6 \
        libsdl2-2.0-0 \
        libsdl1.2debian \
        libunwind8 \
        libzip4 \
        libevent-2.1-7 \
        libfluidsynth3 \
        libmariadb3 \
        file \
        git \
        zip \
        p7zip-full \
        cabextract \
        ffmpeg \
        python3

COPY --chmod=0755 common/entrypoint.sh /entrypoint.sh

ENV HOME=/home/container \
    USER=container \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8

USER container
WORKDIR /home/container
STOPSIGNAL SIGINT
ENTRYPOINT ["/usr/bin/tini", "-g", "--"]
CMD ["/entrypoint.sh"]
