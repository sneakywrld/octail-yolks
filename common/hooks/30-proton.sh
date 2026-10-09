# shellcheck shell=bash
# Octail hook (Proton image): the environment `proton run ./Server.exe` needs outside Steam.
#
# STEAM_COMPAT_CLIENT_INSTALL_PATH defaults to ~/.steam/steam and STEAM_COMPAT_DATA_PATH to ~/.proton (the
# prefix lives in its pfx/ folder); both are created. SteamAppId / SteamGameId follow SRCDS_APPID unless set.
# PROTON_LOG=1 makes Proton write steam-<appid>.log into the server folder.

export STEAM_COMPAT_CLIENT_INSTALL_PATH=${STEAM_COMPAT_CLIENT_INSTALL_PATH:-${HOME:-/home/container}/.steam/steam}
export STEAM_COMPAT_DATA_PATH=${STEAM_COMPAT_DATA_PATH:-${HOME:-/home/container}/.proton}
mkdir -p "${STEAM_COMPAT_CLIENT_INSTALL_PATH}" "${STEAM_COMPAT_DATA_PATH}"
if [ -n "${SRCDS_APPID:-}" ]; then
	export SteamAppId=${SteamAppId:-${SRCDS_APPID}}
	export SteamGameId=${SteamGameId:-${SRCDS_APPID}}
fi
if [ "${PROTON_LOG:-0}" != 1 ]; then
	unset PROTON_LOG
else
	export PROTON_LOG_DIR=${PROTON_LOG_DIR:-${HOME:-/home/container}}
fi
