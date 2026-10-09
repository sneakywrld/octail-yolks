# syntax=docker/dockerfile:1
# Java 21 for Minecraft (Paper, Fabric, Forge, NeoForge, Velocity), Mindustry and other JVM servers.
FROM eclipse-temurin:21-jdk-noble
LABEL org.opencontainers.image.source="https://github.com/sneakywrld/octail-yolks" \
      org.opencontainers.image.title="octail-yolks" \
      org.opencontainers.image.description="Octail runtime: Java 21 (Eclipse Temurin JDK) on Ubuntu 24.04"

RUN --mount=type=bind,source=common,target=/tmp/octail \
    bash /tmp/octail/setup-apt.sh \
        git \
        sqlite3 \
        fontconfig \
        libfreetype6 \
        openssl

COPY --chmod=0755 common/entrypoint.sh /entrypoint.sh
COPY --chmod=0644 common/hooks/10-java-info.sh /etc/octail/entrypoint.d/10-java-info.sh

ENV HOME=/home/container \
    USER=container \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8

USER container
WORKDIR /home/container
STOPSIGNAL SIGINT
ENTRYPOINT ["/usr/bin/tini", "-g", "--"]
CMD ["/entrypoint.sh"]
