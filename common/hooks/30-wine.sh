# shellcheck shell=bash
# Octail hook (Wine images): the Wine prefix and the WINETRICKS_RUN verbs.
#
# WINEPREFIX defaults to ~/.wine (inside the server folder), WINEDEBUG to -all, WINEARCH to win64. A missing
# prefix is created with `wineboot --init`; Wine Mono and Gecko come from /usr/share/wine (baked into the
# image for the image's Wine version), so that needs no download. WINETRICKS_RUN is a space-separated list of
# winetricks verbs installed once each (a marker in $WINEPREFIX/.octail-winetricks/ records success, a failed
# verb is tried again at the next start). `mono` and `gecko` are not winetricks verbs: they install the baked
# Wine Mono / Gecko MSI into an older prefix that lacks them.

export WINEPREFIX=${WINEPREFIX:-${HOME:-/home/container}/.wine}
export WINEDEBUG=${WINEDEBUG:--all}
export WINEARCH=${WINEARCH:-win64}
# Exported even when empty: eggs set it in their startup without `export` (`WINEDLLOVERRIDES="winhttp=n,b";
# wine ...`), which only reaches Wine when the variable is already in the environment.
export WINEDLLOVERRIDES=${WINEDLLOVERRIDES-}

# Runs "$@" with a display: the current one, or a throwaway Xvfb through xvfb-run.
octail_with_display() {
	if [ -n "${DISPLAY:-}" ] || ! command -v xvfb-run >/dev/null 2>&1; then
		"$@"
	else
		xvfb-run -a "$@"
	fi
}

octail_wine_msi() {
	local kind=$1 msi
	for msi in /usr/share/wine/"${kind}"/*.msi; do
		[ -f "${msi}" ] || continue
		echo "octail: installing $(basename "${msi}") into the Wine prefix"
		octail_with_display wine msiexec /i "${msi}" /qn || return 1
	done
	return 0
}

octail_wine_setup() {
	local markers verb
	if [ ! -f "${WINEPREFIX}/system.reg" ]; then
		echo "octail: creating the Wine prefix in ${WINEPREFIX} (first start takes a while)"
		mkdir -p "${WINEPREFIX}"
		octail_with_display wineboot --init
		wineserver -w
	fi
	[ -n "${WINETRICKS_RUN:-}" ] || return 0
	markers="${WINEPREFIX}/.octail-winetricks"
	mkdir -p "${markers}"
	for verb in ${WINETRICKS_RUN}; do
		if ! [[ ${verb} =~ ^[A-Za-z0-9_.=-]+$ ]]; then
			echo "octail: skipping the winetricks verb '${verb}' (unexpected characters)"
			continue
		fi
		[ -e "${markers}/${verb}" ] && continue
		case "${verb}" in
		mono)
			if [ -d "${WINEPREFIX}/drive_c/windows/mono" ] || octail_wine_msi mono; then
				touch "${markers}/${verb}"
			fi
			;;
		gecko)
			if octail_wine_msi gecko; then touch "${markers}/${verb}"; fi
			;;
		*)
			echo "octail: winetricks ${verb}"
			if octail_with_display winetricks -q "${verb}"; then
				touch "${markers}/${verb}"
			else
				echo "octail: winetricks ${verb} failed; it is tried again at the next start."
			fi
			;;
		esac
	done
	wineserver -w
}

octail_wine_setup
