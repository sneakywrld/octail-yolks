# syntax=docker/dockerfile:1
# Java 17 for Minecraft 1.17-1.20.4 (Paper, Fabric, Forge, NeoForge, Velocity), Mindustry and other JVM servers.
# The floating base tag gets the newest Temurin patch release with every (weekly) rebuild.
FROM eclipse-temurin:17-jdk-noble
LABEL org.opencontainers.image.source="https://github.com/sneakywrld/octail-yolks" \
      org.opencontainers.image.title="octail-yolks" \
      org.opencontainers.image.description="Octail runtime: Java 17 (Eclipse Temurin JDK) on Ubuntu 24.04"

# fontconfig + fonts-dejavu-core + libfreetype6: AWT text for map renderers (Dynmap, BlueMap, squaremap) and
# image plugins; git and sqlite3 for plugins and scripts that call them; libjemalloc2 for JEMALLOC=1.
RUN --mount=type=bind,source=common,target=/tmp/octail \
    bash /tmp/octail/setup-apt.sh \
        git \
        sqlite3 \
        fontconfig \
        fonts-dejavu-core \
        libfreetype6 \
        libjemalloc2 \
        openssl

COPY --chmod=0755 common/entrypoint.sh /entrypoint.sh
COPY --chmod=0644 common/hooks/10-java-info.sh /etc/octail/entrypoint.d/10-java-info.sh
COPY --chmod=0644 common/hooks/15-jemalloc.sh /etc/octail/entrypoint.d/15-jemalloc.sh

# No heap or JVM flags here (no -Xmx, no JAVA_TOOL_OPTIONS): the JVM reads the container's memory and CPU limits
# itself, and the egg's startup sets the heap (-Xmx / -XX:MaxRAMPercentage).
ENV HOME=/home/container \
    USER=container \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8

USER container
WORKDIR /home/container
STOPSIGNAL SIGINT
ENTRYPOINT ["/usr/bin/tini", "-g", "--"]
CMD ["/entrypoint.sh"]
