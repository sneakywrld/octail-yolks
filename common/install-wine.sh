#!/bin/bash
# Build-time: Wine from WineHQ's own Debian repository, winetricks, and the Wine Mono / Gecko installers the
# installed Wine version asks for (put in /usr/share/wine, where Wine finds them without downloading).
#   install-wine.sh <stable|staging|devel> <winetricks release tag>
# Needs setup-apt.sh --i386 first (curl, ca-certificates, the i386 architecture).
set -euo pipefail

branch=${1:?wine branch: stable, staging or devel}
winetricks_tag=${2:?winetricks release tag}
export DEBIAN_FRONTEND=noninteractive

. /etc/os-release
install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://dl.winehq.org/wine-builds/winehq.key -o /etc/apt/keyrings/winehq-archive.key
curl -fsSL "https://dl.winehq.org/wine-builds/debian/dists/${VERSION_CODENAME}/winehq-${VERSION_CODENAME}.sources" \
	-o "/etc/apt/sources.list.d/winehq-${VERSION_CODENAME}.sources"
apt-get update
apt-get install -y --install-recommends "winehq-${branch}"
apt-get clean
rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*.deb

curl -fsSL "https://raw.githubusercontent.com/Winetricks/winetricks/${winetricks_tag}/src/winetricks" \
	-o /usr/local/bin/winetricks
chmod 0755 /usr/local/bin/winetricks

# The addon versions this Wine expects are in its source (dlls/appwiz.cpl/addons.c) for the same tag.
version=$(wine --version | awk '{print $1}')
addons=$(curl -fsSL "https://gitlab.winehq.org/wine/wine/-/raw/${version}/dlls/appwiz.cpl/addons.c")
mono=$(sed -n 's/^#define MONO_VERSION "\(.*\)"/\1/p' <<<"${addons}")
gecko=$(sed -n 's/^#define GECKO_VERSION "\(.*\)"/\1/p' <<<"${addons}")
if [ -z "${mono}" ] || [ -z "${gecko}" ]; then
	echo "could not read the Mono/Gecko versions for ${version}" >&2
	exit 1
fi
echo "${version}: Wine Mono ${mono}, Wine Gecko ${gecko}"
mkdir -p /usr/share/wine/mono /usr/share/wine/gecko
curl -fsSL "https://dl.winehq.org/wine/wine-mono/${mono}/wine-mono-${mono}-x86.msi" \
	-o "/usr/share/wine/mono/wine-mono-${mono}-x86.msi"
for arch in x86 x86_64; do
	curl -fsSL "https://dl.winehq.org/wine/wine-gecko/${gecko}/wine-gecko-${gecko}-${arch}.msi" \
		-o "/usr/share/wine/gecko/wine-gecko-${gecko}-${arch}.msi"
done
