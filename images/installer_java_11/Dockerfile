# syntax=docker/dockerfile:1
# Installer with a Java 11 JDK (runs as root): Forge / Fabric / NeoForge installers run java at install time.
FROM eclipse-temurin:11-jdk-noble
LABEL org.opencontainers.image.source="https://github.com/sneakywrld/octail-yolks" \
      org.opencontainers.image.title="octail-yolks" \
      org.opencontainers.image.description="Octail installer: Java 11 (Eclipse Temurin JDK) with the usual install-script tools"

RUN --mount=type=bind,source=common,target=/tmp/octail \
    bash /tmp/octail/setup-apt.sh \
        wget \
        file \
        git \
        xq \
        dos2unix \
        zip \
        p7zip-full \
        rsync \
        bzip2 \
        gzip \
        openssl \
        sqlite3 \
        gawk

ENV LANG=C.UTF-8
# Tentacle runs installers as root with their own command (bash /mnt/install/install.sh).
WORKDIR /mnt/server
CMD ["/bin/bash"]
