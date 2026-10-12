#!/bin/bash
# Build-time: Wine from WineHQ's own Debian repository, winetricks, and the Wine Mono / Gecko installers the
# installed Wine version asks for (put in /usr/share/wine, where Wine finds them without downloading).
#   install-wine.sh <stable|staging|devel> <winetricks release tag>
# Every download after the WineHQ packages (which apt verifies) is checked against wine-checksums.sh.
# Needs setup-apt.sh --i386 first (curl, ca-certificates, the i386 architecture).
set -euo pipefail

branch=${1:?wine branch: stable, staging or devel}
winetricks_tag=${2:?winetricks release tag}
export DEBIAN_FRONTEND=noninteractive
# shellcheck source-path=SCRIPTDIR source=wine-checksums.sh
. "$(dirname "${BASH_SOURCE[0]}")/wine-checksums.sh"

. /etc/os-release
install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://dl.winehq.org/wine-builds/winehq.key -o /etc/apt/keyrings/winehq-archive.key
curl -fsSL "https://dl.winehq.org/wine-builds/debian/dists/${VERSION_CODENAME}/winehq-${VERSION_CODENAME}.sources" \
	-o "/etc/apt/sources.list.d/winehq-${VERSION_CODENAME}.sources"
apt-get update
apt-get install -y --install-recommends "winehq-${branch}"
apt-get clean
rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*.deb

install_winetricks "${winetricks_tag}" /usr/local/bin/winetricks

# The addon versions this Wine expects are in its source (dlls/appwiz.cpl/addons.c) for the same tag; each
# installer is checked against the sha256 pinned in wine-checksums.sh.
version=$(wine --version | awk '{print $1}')
addons=$(curl -fsSL "https://gitlab.winehq.org/wine/wine/-/raw/${version}/dlls/appwiz.cpl/addons.c")
echo "${version}:"
install_addons "${addons}" /usr/share/wine/mono /usr/share/wine/gecko
