# syntax=docker/dockerfile:1
# Installer for eggs' install scripts (runs as root): SteamCMD's 32-bit libraries, curl/wget, jq, xq, unzip,
# git, dos2unix, Python 3. apt works, so scripts can add what else they need.
FROM debian:bookworm-slim
LABEL org.opencontainers.image.source="https://github.com/sneakywrld/octail-yolks" \
      org.opencontainers.image.title="octail-yolks" \
      org.opencontainers.image.description="Octail installer: Debian 12 with the usual install-script tools"

RUN --mount=type=bind,source=common,target=/tmp/octail \
    bash /tmp/octail/setup-apt.sh \
        --i386 \
        lib32gcc-s1 \
        lib32stdc++6 \
        wget \
        file \
        git \
        xq \
        dos2unix \
        zip \
        p7zip-full \
        rsync \
        python3 \
        python3-pip \
        bzip2 \
        gzip \
        openssl \
        sqlite3 \
        gawk \
        sed \
        findutils \
        coreutils \
        unzip \
        xz-utils \
        jq \
        curl

ENV LANG=C.UTF-8
# Tentacle runs installers as root with their own command (bash /mnt/install/install.sh).
WORKDIR /mnt/server
CMD ["/bin/bash"]
