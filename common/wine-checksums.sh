#!/bin/bash
# Sourced by install-wine.sh (and yolks/test/run.sh): the sha256 of every download the Wine images make at build
# time, pinned here, and fetch_verified, which refuses a file that doesn't match. WineHQ publishes no checksum
# files next to the Wine Mono / Gecko installers; the values below were checked against the downloads and against
# the GECKO_SHA / MONO_SHA that Wine's own dlls/appwiz.cpl/addons.c carries for the Wine release that wants them.
# (Wine Mono 11.2.1, which no Wine tag asks for yet, was checked against the download and the sha256 digest GitHub
# shows for the wine-mono/wine-mono release asset; Wine 11.0 stable wants 10.4.1, 11.10/11.11 want 11.1.0, master
# 11.3.0, all pinned, as of 2026-10-23.)
#
# A new Wine release that asks for a Mono or Gecko version not listed here stops the build with the value from
# addons.c to check and add. A new winetricks release tag needs its commit and the sha256 of src/winetricks.

# winetricks release tag → "<commit> <sha256 of src/winetricks>"
winetricks_pin() {
	case "$1" in
	20260125) echo 'b76e1ee79ac57d7aceb384f74518fc423265810c 431f82fc74000e6c864409f1d8fb495d696c03928808e3e8acffc45179312a7b' ;;
	*) return 1 ;;
	esac
}

# addon_sha256 mono <version> x86 | addon_sha256 gecko <version> <x86|x86_64>
addon_sha256() {
	case "$1/$2/$3" in
	mono/9.4.0/x86) echo cf6173ae94b79e9de13d9a74cdb2560a886fc3d271f9489acb1cfdbd961cacb2 ;;
	mono/10.3.0/x86) echo cece5c63180094dffdf01d0fbe362a4b606e5280b98cdfd1b8568cdf9b572f98 ;;
	mono/10.4.1/x86) echo 071f4b2887e1c97a11d791ff3d65be9429eed6dec4c2708888bfd546ba358e23 ;;
	mono/11.0.0/x86) echo d7efede0b9bdcf52134f8cd6ced59d9fece976f70b11a400bdb47b864569cd27 ;;
	mono/11.1.0/x86) echo deb0341431f8260b209fff6bc79ddcc5414b97f8e9236ab9fbdca4ce59e0a9b9 ;;
	mono/11.2.0/x86) echo b4525679e7da30d4658ceb85739cbc55c771791054abbb4b3152fe96ded0b897 ;;
	mono/11.2.1/x86) echo e38810c017ccb64d450bbd6095d41c0b50e3fd967c306f6d2c64c3a48945cc92 ;;
	mono/11.3.0/x86) echo df2dfc1665c2511882e7cabd56eafd0c0a3d94e5a7e86f969277f6c189d418d3 ;;
	gecko/2.47.4/x86) echo 26cecc47706b091908f7f814bddb074c61beb8063318e9efc5a7f789857793d6 ;;
	gecko/2.47.4/x86_64) echo e590b7d988a32d6aa4cf1d8aa3aa3d33766fdd4cf4c89c2dcc2095ecb28d066f ;;
	*) return 1 ;;
	esac
}

# addons_sha <addons.c text> <MONO|GECKO> <arch>: the sha256 Wine's addons.c names for that arch (a hint for the
# error message when a version isn't pinned; never trusted on its own).
addons_sha() {
	awk -v p="$2" -v want="\"$3\"" '
		$1 == "#define" && $2 == p "_ARCH" { arch = $3 }
		$1 == "#define" && $2 == p "_SHA" && arch == want { gsub(/"/, "", $3); print $3; exit }
	' <<<"$1"
}

# fetch_verified <url> <dest> <sha256>: downloads to a temporary file next to dest and moves it into place only
# when the sha256 matches. CURL (default curl) is the downloader, called as `$CURL -fsSL <url> -o <file>`.
fetch_verified() {
	local url=$1 dest=$2 want=$3 tmp got
	tmp="${dest}.part"
	rm -f "${tmp}"
	if ! "${CURL:-curl}" -fsSL "${url}" -o "${tmp}"; then
		rm -f "${tmp}"
		echo "download failed: ${url}" >&2
		return 1
	fi
	got=$(sha256sum "${tmp}" | awk '{print $1}')
	if [ "${got}" != "${want}" ]; then
		rm -f "${tmp}"
		echo "checksum mismatch for ${url}: expected ${want}, got ${got}" >&2
		return 1
	fi
	mv -f "${tmp}" "${dest}"
}

# install_addons <addons.c text> <mono dir> <gecko dir>: the Wine Mono / Gecko installers this Wine asks for,
# each verified against the pinned sha256. Fails (before downloading anything) when a version has no pin.
install_addons() {
	local addons=$1 mono_dir=$2 gecko_dir=$3 mono gecko arch sha
	mono=$(sed -n 's/^#define MONO_VERSION "\(.*\)"/\1/p' <<<"${addons}")
	gecko=$(sed -n 's/^#define GECKO_VERSION "\(.*\)"/\1/p' <<<"${addons}")
	if [ -z "${mono}" ] || [ -z "${gecko}" ]; then
		echo "could not read the Mono/Gecko versions from addons.c" >&2
		return 1
	fi
	echo "Wine Mono ${mono}, Wine Gecko ${gecko}"
	local missing=0
	if ! addon_sha256 mono "${mono}" x86 >/dev/null; then
		echo "no known sha256 for Wine Mono ${mono} (x86): add it to common/wine-checksums.sh after checking the download; Wine's addons.c says $(addons_sha "${addons}" MONO x86)" >&2
		missing=1
	fi
	for arch in x86 x86_64; do
		if ! addon_sha256 gecko "${gecko}" "${arch}" >/dev/null; then
			echo "no known sha256 for Wine Gecko ${gecko} (${arch}): add it to common/wine-checksums.sh after checking the download; Wine's addons.c says $(addons_sha "${addons}" GECKO "${arch}")" >&2
			missing=1
		fi
	done
	[ "${missing}" = 0 ] || return 1
	mkdir -p "${mono_dir}" "${gecko_dir}"
	sha=$(addon_sha256 mono "${mono}" x86)
	fetch_verified "https://dl.winehq.org/wine/wine-mono/${mono}/wine-mono-${mono}-x86.msi" \
		"${mono_dir}/wine-mono-${mono}-x86.msi" "${sha}" || return 1
	for arch in x86 x86_64; do
		sha=$(addon_sha256 gecko "${gecko}" "${arch}")
		fetch_verified "https://dl.winehq.org/wine/wine-gecko/${gecko}/wine-gecko-${gecko}-${arch}.msi" \
			"${gecko_dir}/wine-gecko-${gecko}-${arch}.msi" "${sha}" || return 1
	done
}

# install_winetricks <release tag> <dest>: winetricks from the pinned commit of that tag, sha256-checked.
install_winetricks() {
	local pin commit sha
	if ! pin=$(winetricks_pin "$1"); then
		echo "no pinned commit/sha256 for winetricks ${1}: add it to common/wine-checksums.sh" >&2
		return 1
	fi
	read -r commit sha <<<"${pin}"
	fetch_verified "https://raw.githubusercontent.com/Winetricks/winetricks/${commit}/src/winetricks" "$2" "${sha}" || return 1
	chmod 0755 "$2"
}
