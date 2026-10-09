# shellcheck shell=bash
# Octail hook (Wine / Proton images): a virtual X display when XVFB=1.
#
# Starts Xvfb on DISPLAY (default :0) with DISPLAY_WIDTH x DISPLAY_HEIGHT x DISPLAY_DEPTH (1024x768x16) and
# exports DISPLAY. Servers that start their own Xvfb (or use `xvfb-run`) leave XVFB unset.

octail_start_xvfb() {
	case "${XVFB:-0}" in
	1 | true | TRUE | yes) ;;
	*) return 0 ;;
	esac
	local display=${DISPLAY:-:0}
	local screen="${DISPLAY_WIDTH:-1024}x${DISPLAY_HEIGHT:-768}x${DISPLAY_DEPTH:-16}"
	if ! [[ ${display} =~ ^:[0-9]+$ ]] || ! [[ ${screen} =~ ^[0-9]+x[0-9]+x[0-9]+$ ]]; then
		echo "octail: DISPLAY must look like :0 and the screen like 1024x768x16; not starting Xvfb."
		return 0
	fi
	rm -f "/tmp/.X${display#:}-lock"
	echo "octail: starting Xvfb on ${display} (${screen})"
	Xvfb "${display}" -screen 0 "${screen}" -nolisten tcp -ac >/dev/null 2>&1 &
	export DISPLAY=${display}
	local wait
	for wait in 1 2 3 4 5 6 7 8 9 10; do
		[ -e "/tmp/.X11-unix/X${display#:}" ] && return 0
		sleep 0.5
		: "${wait}"
	done
	echo "octail: Xvfb did not come up within 5 seconds; carrying on."
}

octail_start_xvfb
