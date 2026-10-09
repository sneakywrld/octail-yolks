#!/bin/bash
# Build-time setup for Debian/Ubuntu based images (run once in the Dockerfile, as root):
#   setup-apt.sh [--i386] [package ...]
# Installs the packages every Octail runtime image has (tini, bash, curl, ca-certificates, iproute2 for
# INTERNAL_IP, tar/unzip/xz, tzdata, locales, jq, gettext-base for envsubst, procps) plus the ones given,
# generates the en_US.UTF-8 locale, creates the non-root `container` user (home /home/container) and
# cleans the apt caches. --i386 enables the i386 architecture first (SteamCMD and 32-bit servers).
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

if [ "${1:-}" = --i386 ]; then
	shift
	dpkg --add-architecture i386
fi

base=(
	bash ca-certificates curl gettext-base iproute2 jq locales procps tar tini tzdata unzip xz-utils
)

apt-get update
apt-get install -y --no-install-recommends "${base[@]}" "$@"
apt-get clean
rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*.deb

# en_US.UTF-8: Debian lists it commented out in /etc/locale.gen, Ubuntu's locale-gen takes it as an argument.
if [ -f /etc/locale.gen ]; then
	sed -i 's/^# *\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen
	grep -q '^en_US.UTF-8 UTF-8' /etc/locale.gen || echo 'en_US.UTF-8 UTF-8' >>/etc/locale.gen
	locale-gen
else
	locale-gen en_US.UTF-8
fi

# The image user. Tentacle runs the container as the node's server user and mounts an /etc/passwd naming it
# `container` with home /home/container, so this entry only matters when the image runs elsewhere.
if ! id container >/dev/null 2>&1; then
	useradd --create-home --home-dir /home/container --shell /bin/bash container
fi
mkdir -p /home/container /etc/octail/entrypoint.d
chown container:container /home/container
