# shellcheck shell=bash
# Octail hook (rust image): the modding framework chosen in FRAMEWORK, installed after the SteamCMD update
# (an update replaces the game's managed DLLs that Oxide patches, so it goes first).
#
#   vanilla (default)  nothing; files left by Oxide/Carbon stay until a start with VALIDATE=1
#   oxide | umod       latest Oxide.Rust for Linux from GitHub, unpacked over the server
#   carbon             Carbon's production build; carbon-edge / carbon-staging pick those builds
# A failed download leaves the installed framework as it was and the server starts anyway.
# RustDedicated loads its native plugins (RustDedicated_Data/Plugins/x86_64) and steamclient.so from the
# server folder, which must be on LD_LIBRARY_PATH or the server doesn't start.

export LD_LIBRARY_PATH="${OCTAIL_HOME}/RustDedicated_Data/Plugins/x86_64:${OCTAIL_HOME}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"

octail_rust_framework() {
	local fw=${FRAMEWORK:-vanilla} url tmp
	fw=${fw,,}
	case "${fw}" in
	vanilla | '') return 0 ;;
	oxide | umod)
		url=https://github.com/OxideMod/Oxide.Rust/releases/latest/download/Oxide.Rust-linux.zip
		;;
	carbon | carbon-production)
		url=https://github.com/CarbonCommunity/Carbon/releases/download/production_build/Carbon.Linux.Release.tar.gz
		;;
	carbon-edge)
		url=https://github.com/CarbonCommunity/Carbon/releases/download/edge_build/Carbon.Linux.Debug.tar.gz
		;;
	carbon-staging)
		url=https://github.com/CarbonCommunity/Carbon/releases/download/rustbeta_staging_build/Carbon.Linux.Debug.tar.gz
		;;
	*)
		echo "octail: unknown FRAMEWORK '${FRAMEWORK}' (vanilla, oxide, carbon, carbon-edge, carbon-staging); starting vanilla."
		return 0
		;;
	esac
	tmp=$(mktemp -d /tmp/octail-rust.XXXXXX) || return 0
	echo "octail: installing ${fw} from ${url}"
	if curl -fsSL --retry 3 -o "${tmp}/framework" "${url}"; then
		case "${url}" in
		*.zip) unzip -oq "${tmp}/framework" -d "${OCTAIL_HOME}" || echo "octail: could not unpack ${fw}." ;;
		*) tar -xzf "${tmp}/framework" -C "${OCTAIL_HOME}" || echo "octail: could not unpack ${fw}." ;;
		esac
	else
		echo "octail: could not download ${fw}; starting with what is installed."
	fi
	rm -rf "${tmp}"
	case "${fw}" in
	carbon*)
		# Carbon loads through Unity Doorstop; its own script sets the variables when it ships one.
		if [ -f "${OCTAIL_HOME}/carbon/tools/environment.sh" ]; then
			# shellcheck source=/dev/null
			. "${OCTAIL_HOME}/carbon/tools/environment.sh"
		else
			export DOORSTOP_ENABLED=1
			export DOORSTOP_TARGET_ASSEMBLY="${OCTAIL_HOME}/carbon/managed/Carbon.Preloader.dll"
			export LD_PRELOAD="${OCTAIL_HOME}/libdoorstop.so${LD_PRELOAD:+:${LD_PRELOAD}}"
		fi
		;;
	esac
}

octail_rust_framework
