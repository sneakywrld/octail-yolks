# shellcheck shell=bash
# Octail hook (SteamCMD images): update the server with SteamCMD before it starts.
#
# Runs when AUTO_UPDATE is 1/true (unset: the image's OCTAIL_AUTO_UPDATE_DEFAULT, 0 unless the image says
# otherwise) and SRCDS_APPID is set. Uses the SteamCMD the egg's installer put in ./steamcmd. Variables:
#   SRCDS_APPID, SRCDS_BETAID, SRCDS_BETAPASS, WINDOWS_INSTALL=1 (Windows depot), STEAM_SDK=1 (app 1007 too),
#   HLDS_GAME (GoldSrc mod), VALIDATE=1, STEAM_USER/STEAM_PASS/STEAM_AUTH (else anonymous), STEAM_LOGIN_CACHE
#   (Tentacle's saved login for a Steam account: ./steamcmd/config is linked to it).
# SteamCMD's first run on a fresh folder often fails with "Missing configuration", so app_update is tried
# up to 3 times. Afterwards the Steam client libraries in ~/.steam/sdk32|sdk64 are refreshed.

octail_truthy() {
	case "${1,,}" in
	1 | true | yes | on) return 0 ;;
	*) return 1 ;;
	esac
}

# A logged-in Steam account (eggs with Octail's `steam_login` feature): Tentacle binds the account's login cache
# into the container and names it in STEAM_LOGIN_CACHE, and sends STEAM_USER with an empty STEAM_PASS, so
# `+login <user>` only works with the token SteamCMD keeps in its config folder. The egg's installer links
# ./steamcmd/config to the cache; this does the same when it isn't (a reinstalled SteamCMD, an imported egg).
# A server folder that already holds its own login while the cache is still empty is left as it is.
octail_steam_login_cache() {
	local cache=${STEAM_LOGIN_CACHE:-} config="${OCTAIL_HOME}/steamcmd/config"
	[ -n "${cache}" ] && [ -d "${cache}" ] || return 0
	[ -n "${STEAM_USER:-}" ] && [ "${STEAM_USER}" != anonymous ] || return 0
	if [ -L "${config}" ] && [ "$(readlink "${config}")" = "${cache}" ]; then return 0; fi
	if [ -d "${config}" ] && [ ! -L "${config}" ] && [ -f "${config}/config.vdf" ] && [ ! -f "${cache}/config.vdf" ]; then
		return 0
	fi
	echo "octail: using the saved Steam login for ${STEAM_USER}."
	rm -rf "${config}" && ln -s "${cache}" "${config}"
}

octail_steamcmd_update() {
	local steamcmd="${OCTAIL_HOME}/steamcmd/steamcmd.sh" try login=(anonymous) args=() shown=()
	octail_truthy "${AUTO_UPDATE:-${OCTAIL_AUTO_UPDATE_DEFAULT:-0}}" || return 0
	if [ -z "${SRCDS_APPID:-}" ]; then
		echo "octail: automatic update is on but SRCDS_APPID is empty; not updating."
		return 0
	fi
	if ! [[ ${SRCDS_APPID} =~ ^[0-9]+$ ]]; then
		echo "octail: SRCDS_APPID is not a number; not updating."
		return 0
	fi
	if [ ! -x "${steamcmd}" ]; then
		echo "octail: ${steamcmd} is missing; reinstall the server to get SteamCMD back. Starting without an update."
		return 0
	fi
	if [ -n "${STEAM_USER:-}" ] && [ "${STEAM_USER}" != anonymous ]; then
		login=("${STEAM_USER}")
		[ -n "${STEAM_PASS:-}" ] && login+=("${STEAM_PASS}")
		[ -n "${STEAM_AUTH:-}" ] && login+=("${STEAM_AUTH}")
		octail_steam_login_cache
	fi
	args=(+force_install_dir "${OCTAIL_HOME}")
	[ "${WINDOWS_INSTALL:-0}" = 1 ] && args+=(+@sSteamCmdForcePlatformType windows)
	args+=(+login "${login[@]}")
	[ "${STEAM_SDK:-0}" = 1 ] && args+=(+app_update 1007)
	args+=(+app_update "${SRCDS_APPID}")
	[ -n "${SRCDS_BETAID:-}" ] && args+=(-beta "${SRCDS_BETAID}")
	[ -n "${SRCDS_BETAPASS:-}" ] && args+=(-betapassword "${SRCDS_BETAPASS}")
	[ -n "${HLDS_GAME:-}" ] && args+=(+app_set_config 90 mod "${HLDS_GAME}")
	octail_truthy "${VALIDATE:-0}" && args+=(validate)
	args+=(+quit)

	# The command as printed: passwords masked.
	shown=("${args[@]}")
	local i
	for i in "${!shown[@]}"; do
		if [ "${shown[i]}" = "${STEAM_PASS:-}" ] || [ "${shown[i]}" = "${STEAM_AUTH:-}" ] ||
			[ "${shown[i]}" = "${SRCDS_BETAPASS:-}" ]; then
			[ -n "${shown[i]}" ] && shown[i]='********'
		fi
	done
	echo "octail: updating app ${SRCDS_APPID} with SteamCMD: steamcmd.sh ${shown[*]}"

	for try in 1 2 3; do
		if "${steamcmd}" "${args[@]}"; then
			break
		fi
		if [ "${try}" = 3 ]; then
			echo "octail: SteamCMD failed 3 times; starting the files already installed."
			return 0
		fi
		echo "octail: SteamCMD did not finish (attempt ${try} of 3), trying again."
	done

	local bits
	for bits in 32 64; do
		if [ -f "${OCTAIL_HOME}/steamcmd/linux${bits}/steamclient.so" ]; then
			mkdir -p "${HOME:-${OCTAIL_HOME}}/.steam/sdk${bits}" &&
				cp -f "${OCTAIL_HOME}/steamcmd/linux${bits}/steamclient.so" "${HOME:-${OCTAIL_HOME}}/.steam/sdk${bits}/steamclient.so"
		fi
	done
	return 0
}

octail_steamcmd_update
