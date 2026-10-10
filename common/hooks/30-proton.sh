# shellcheck shell=bash
# Octail hook (Proton image): the environment `proton run ./Server.exe` needs outside Steam.
#
# STEAM_COMPAT_CLIENT_INSTALL_PATH defaults to ~/.steam/steam and STEAM_COMPAT_DATA_PATH to ~/.proton (the
# prefix lives in its pfx/ folder); both are created. SteamAppId / SteamGameId follow SRCDS_APPID unless set.
# PROTON_LOG=1 makes Proton write steam-<appid>.log into the server folder.
# A server that ran on another Proton image has its prefix in ~/.steam/steam/steamapps/compatdata/<SRCDS_APPID>:
# while there is no ~/.proton yet, that one is used, so nothing kept in the prefix is lost.

octail_proton_data() {
	local home=${HOME:-/home/container} old
	old="${home}/.steam/steam/steamapps/compatdata/${SRCDS_APPID:-}"
	if [ -n "${SRCDS_APPID:-}" ] && [ ! -e "${home}/.proton" ] && [ -d "${old}/pfx" ]; then
		printf '%s' "${old}"
	else
		printf '%s' "${home}/.proton"
	fi
}

export STEAM_COMPAT_CLIENT_INSTALL_PATH=${STEAM_COMPAT_CLIENT_INSTALL_PATH:-${HOME:-/home/container}/.steam/steam}
export STEAM_COMPAT_DATA_PATH=${STEAM_COMPAT_DATA_PATH:-$(octail_proton_data)}
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

# Start watch. A Windows server that hangs under Proton does so silently: the console stops after "wineserver:
# using server-side synchronization". When the container still has no open port (no listening TCP socket, no
# unconnected UDP socket) OCTAIL_PROTON_WATCH seconds after the start (default 300, 0 = off), one report of the
# container's limits and processes is printed (state, threads, memory, kernel wait channel), then nothing more.
# OCTAIL_PROC / OCTAIL_CGROUP exist for the tests.

# Success when a socket of this container listens (TCP) or waits for packets (unconnected UDP).
octail_port_open() {
	local proc=${OCTAIL_PROC:-/proc} file sl addr rem st rest
	for file in "${proc}/net/tcp" "${proc}/net/tcp6"; do
		[ -r "${file}" ] || continue
		while read -r sl addr rem st rest; do
			[ "${st}" = 0A ] && return 0
		done <"${file}"
	done
	for file in "${proc}/net/udp" "${proc}/net/udp6"; do
		[ -r "${file}" ] || continue
		while read -r sl addr rem st rest; do
			[[ ${rem} =~ ^0+:0000$ ]] && [[ ${addr} != *:0000 ]] && [[ ${addr} == *:* ]] && return 0
		done <"${file}"
	done
	: "${sl}${st}${rest}"
	return 1
}

octail_cgroup_value() { # file [key]: a cgroup file's value, or the value after key in a flat-keyed file
	local file="${OCTAIL_CGROUP:-/sys/fs/cgroup}/$1" key value
	[ -r "${file}" ] || {
		printf '?'
		return 0
	}
	if [ -z "${2:-}" ]; then
		read -r value <"${file}"
		printf '%s' "${value:-?}"
		return 0
	fi
	while read -r key value; do
		[ "${key}" = "$2" ] && {
			printf '%s' "${value}"
			return 0
		}
	done <"${file}"
	printf '?'
}

octail_proton_report() {
	local mib='?' max
	max=$(octail_cgroup_value memory.max)
	[[ $(octail_cgroup_value memory.current) =~ ^[0-9]+$ ]] && mib=$(($(octail_cgroup_value memory.current) / 1048576))
	[[ ${max} =~ ^[0-9]+$ ]] && max="$((max / 1048576)) MiB"
	echo "octail: no game port is open $1 s after the start. If the server is still loading, wait; if it hangs, this is what it is doing (printed once):"
	echo "octail:   threads $(octail_cgroup_value pids.current) of $(octail_cgroup_value pids.max) (limit reached $(octail_cgroup_value pids.events max) times), memory ${mib} MiB of ${max} (OOM kills $(octail_cgroup_value memory.events oom_kill)), open files limit $(ulimit -n)"
	echo "octail:   /tmp $(df -Pm /tmp 2>/dev/null | awk 'NR==2 {print $3 " of " $2 " MiB used"}'), /dev/shm $(df -Pm /dev/shm 2>/dev/null | awk 'NR==2 {print $3 " of " $2 " MiB used"}')"
	echo "octail:   processes (STAT D = disk wait, S = sleeping; WCHAN = what the kernel waits for; the watch itself left out):"
	ps -N -p "${BASHPID}" --ppid "${BASHPID}" -o pid=,stat=,nlwp=,rss=,pcpu=,wchan:22=,args= 2>/dev/null |
		head -n 40 | cut -c1-200 | sed 's/^/octail:     /'
	echo "octail:   for Proton's own log set PROTON_LOG=1 (steam-<appid>.log in the server folder); see 'Proton notes' in the yolks README."
}

octail_proton_watch() {
	local after=${OCTAIL_PROTON_WATCH:-300} main=$$ waited=0
	[[ ${after} =~ ^[0-9]+$ ]] && [ "${after}" -gt 0 ] || return 0
	# Started from a subshell that ends at once, so the watch is nobody's job: a bare `wait` in a startup doesn't
	# wait for it. It ends with the startup shell.
	( (
		while [ "${waited}" -lt "${after}" ]; do
			sleep 1
			waited=$((waited + 1))
			kill -0 "${main}" 2>/dev/null || exit 0
		done
		octail_port_open || octail_proton_report "${after}"
	) &)
}

octail_proton_watch
