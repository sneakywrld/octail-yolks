# syntax=docker/dockerfile:1
# Java 8 for Minecraft up to 1.16 (Forge, Paper, Spigot, Sponge, ...) and other JVM servers that need Java 8.
# The floating base tag gets the newest Temurin patch release with every (weekly) rebuild.
FROM eclipse-temurin:8-jdk-noble
LABEL org.opencontainers.image.source="https://github.com/sneakywrld/octail-yolks" \
      org.opencontainers.image.title="octail-yolks" \
      org.opencontainers.image.description="Octail runtime: Java 8 (Eclipse Temurin JDK) on Ubuntu 24.04"

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
# The console banner's image line (common/entrypoint.sh): CI passes the dated tag it pushes, <tag>-<yyyymmdd>.
# Metadata only, last, so a new date never rebuilds a layer.
ARG OCTAIL_IMAGE=
ENV OCTAIL_IMAGE=${OCTAIL_IMAGE}
ENTRYPOINT ["/usr/bin/tini", "-g", "--"]
CMD ["/entrypoint.sh"]
