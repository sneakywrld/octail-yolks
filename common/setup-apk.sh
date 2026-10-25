#!/bin/sh
# Build-time setup for Alpine based images (run once in the Dockerfile, as root):
#   setup-apk.sh [package ...]
# Upgrades the base image's packages, installs what every Octail image has (bash for the entrypoint, tini, curl, ca-certificates, iproute2 for
# INTERNAL_IP, tar/unzip/xz, tzdata, jq, gettext for envsubst) plus the ones given, and creates the
# non-root `container` user (home /home/container).
set -eu

# The base image's packages at the branch's current security fixes (see setup-apt.sh for common/.refresh).
apk upgrade --no-cache
apk add --no-cache bash ca-certificates curl gettext iproute2 jq tar tini tzdata unzip xz "$@"

# Debian's tini lives in /usr/bin; keep one path for every image's ENTRYPOINT.
[ -e /usr/bin/tini ] || ln -s /sbin/tini /usr/bin/tini

if ! id container >/dev/null 2>&1; then
	adduser -D -h /home/container -s /bin/bash container
fi
mkdir -p /home/container /etc/octail/entrypoint.d
chown container:container /home/container
