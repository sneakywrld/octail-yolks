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
# WineHQ's packages without their Recommends, plus the recommended libraries a Windows server can need, for both
# the 64-bit and the 32-bit half (WineHQ's Debian packages are multilib: wine-*-amd64 + wine-*-i386). With
# --install-recommends apt also pulled the Recommends of every dependency (SANE scanner backends, gphoto, the
# GStreamer plugin sets, GTK themes and icons for staging, CUPS, V4L), a few hundred MB no server uses.
#   gnutls          TLS (bcrypt/secur32 schannel): HTTPS, EOS/PlayFab/Steam web APIs
#   krb5, gssapi    Kerberos/Negotiate auth in secur32 (NTLM goes through winbind's ntlm_auth, in the Dockerfile)
#   freetype, fontconfig  font rendering; without them GDI/GDI+ text (WinForms consoles, .NET System.Drawing) fails
#   X11 extensions  what winex11.drv loads under Xvfb (render, randr, xi, cursor, composite, xinerama, xfixes, vidmode)
#   GLU (+ Mesa)    OpenGL for wined3d, for servers that create a D3D device even headless
#   dbus, odbc, png, jpeg  device enumeration, database servers using ODBC, image codecs some launchers load
# Not installed (Recommends no server needs): cups, sane, gphoto, v4l, capi, gsm, gtk/cairo (staging's theming).
wine_libs=(
	libgnutls30 libkrb5-3 libgssapi-krb5-2 libfreetype6 libfontconfig1
	libxrender1 libxrandr2 libxi6 libxcursor1 libxcomposite1 libxinerama1 libxfixes3 libxxf86vm1
	libglu1-mesa libdbus-1-3 libodbc2 libpng16-16 libjpeg62-turbo
)
pkgs=("winehq-${branch}")
for lib in "${wine_libs[@]}"; do
	pkgs+=("${lib}" "${lib}:i386")
done
apt-get install -y --no-install-recommends "${pkgs[@]}"
apt-get clean
rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*.deb

install_winetricks "${winetricks_tag}" /usr/local/bin/winetricks

# The addon versions this Wine expects are in its source (dlls/appwiz.cpl/addons.c) for the same tag; each
# installer is checked against the sha256 pinned in wine-checksums.sh.
version=$(wine --version | awk '{print $1}')
addons=$(curl -fsSL "https://gitlab.winehq.org/wine/wine/-/raw/${version}/dlls/appwiz.cpl/addons.c")
echo "${version}:"
install_addons "${addons}" /usr/share/wine/mono /usr/share/wine/gecko
