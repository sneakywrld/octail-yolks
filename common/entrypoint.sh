#!/bin/bash
# Octail yolks entrypoint: runs a game server's startup command (STARTUP) inside its container.
#
#   1. enter the server folder (/home/container), export INTERNAL_IP, a UTF-8 LANG when the image has none
#   2. print a short banner: image, OS, user, TZ, and the container's limits (OCTAIL_BANNER=0: off)
#   3. source the image's hooks (/etc/octail/entrypoint.d/*.sh): Wine prefix, Proton, SteamCMD update, ...
#   4. run the server owner's pre-start scripts (/home/container/.octail/hooks/pre-start.d/*.sh), if any
#   5. turn {{VAR}} into ${VAR} (Tentacle already sends ${VAR}; eggs imported from elsewhere may still use {{VAR}})
#   6. print "container~ <startup>" with the ${VAR}s filled in, values of secret-looking names masked
#   7. eval the startup ONCE: a variable's value is expanded as a parameter, never read again as shell; the
#      container exits with the startup's exit code
#
# PID 1 is tini (`tini -g`), so a stop signal (Ctrl+C = SIGINT) reaches every process of the server's
# process group, the way Ctrl+C in a terminal does. This script stays the startup's parent (no exec: a startup
# may be several commands), and bash, waiting for a foreground command, lets that command handle the SIGINT
# and then exits with its code. No nss_wrapper / LD_PRELOAD: Tentacle mounts an /etc/passwd that names the
# container user.
#
# OCTAIL_DEBUG=1 (or a file .octail/debug in the server folder) prints the raw startup, each hook's run time
# and the environment, secret values masked like in the container~ line.
#
# OCTAIL_HOME, OCTAIL_HOOK_DIR, OCTAIL_CGROUP, OCTAIL_ZONEINFO, OCTAIL_OS_RELEASE and OCTAIL_IMAGE_FILE exist for
# the tests (test/run.sh, test/entrypoint.sh); images never set them.

OCTAIL_HOME=${OCTAIL_HOME:-/home/container}
OCTAIL_HOOK_DIR=${OCTAIL_HOOK_DIR:-/etc/octail/entrypoint.d}

cd "${OCTAIL_HOME}" || {
	echo "octail: cannot enter ${OCTAIL_HOME}" >&2
	exit 1
}

# Every image sets LANG; this only covers an image (or an egg's override to "") that doesn't, so Java, .NET and
# Python don't fall back to ASCII and mangle player names.
[ -n "${LANG-}" ] || export LANG=C.UTF-8

octail_debug=0
case "${OCTAIL_DEBUG-}" in
1 | true | TRUE | yes) octail_debug=1 ;;
0 | false | FALSE | no) ;;
*) [ -f "${OCTAIL_HOME}/.octail/debug" ] && octail_debug=1 ;;
esac

# The container's own address (what `ip route get` would use to reach the internet).
octail_internal_ip() {
	local route word prev=
	route=$(ip -4 route get 1.1.1.1 2>/dev/null) || return 0
	for word in ${route}; do
		if [ "${prev}" = src ]; then
			printf '%s' "${word}"
			return 0
		fi
		prev=${word}
	done
}
INTERNAL_IP=$(octail_internal_ip)
export INTERNAL_IP

# Names whose values never show in the printed startup line.
octail_is_secret() {
	local name=${1^^} extra
	# bash's own working-directory variables ("PWD" isn't a password: masking it would hide every /home/container
	# path in a masked line) and the list of secret names itself (names, not values; Tentacle skips it too).
	case "${name}" in PWD | OLDPWD | OCTAIL_SECRET_VARS) return 1 ;; esac
	[[ ${name} =~ PASS|PWD|SECRET|TOKEN|KEY|AUTH|GSLT|STEAM_ACC|(^|_)PW($|_) ]] && return 0
	for extra in ${OCTAIL_SECRET_VARS//,/ }; do
		[ "${name}" = "${extra^^}" ] && return 0
	done
	return 1
}

# stdin to stdout with the values of secret-looking variables (octail_is_secret) replaced by ********, for
# hooks that print command lines (the Proton start watch's process list shows the game's arguments, which
# hold e.g. ?ServerAdminPassword=...). Longer values first, so a secret that contains another isn't half
# shown; values shorter than 4 characters are left alone (masking "1" would garble every number).
octail_mask() {
	local name value line values=()
	while IFS= read -r name; do
		value=${!name-}
		[ "${#value}" -ge 4 ] && [[ ${value} != *$'\n'* ]] && octail_is_secret "${name}" && values+=("${value}")
	done < <(compgen -e)
	if [ "${#values[@]}" -gt 1 ]; then
		mapfile -t values < <(for value in "${values[@]}"; do printf '%s\t%s\n' "${#value}" "${value}"; done |
			sort -rn | cut -f2-)
	fi
	while IFS= read -r line || [ -n "${line}" ]; do
		for value in "${values[@]}"; do
			line=${line//"${value}"/********}
		done
		printf '%s\n' "${line}"
	done
}

# {{NAME}} / {{ NAME }} -> ${NAME}; anything else between {{ }} is left alone. Result in OCTAIL_OUT.
octail_braces() {
	local rest=$1 match
	OCTAIL_OUT=
	while [[ ${rest} =~ \{\{[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*\}\} ]]; do
		match=${BASH_REMATCH[0]}
		OCTAIL_OUT+="${rest%%"${match}"*}\${${BASH_REMATCH[1]}}"
		rest=${rest#*"${match}"}
	done
	OCTAIL_OUT+=${rest}
}

# The startup as shown in the console: every ${NAME} replaced by its value (masked when secret). Pure
# text work, nothing is evaluated, so a $(...) in the startup only runs once (in step 5). Result in OCTAIL_OUT.
octail_display() {
	local rest=$1 match name out=
	while [[ ${rest} =~ \$\{([A-Za-z_][A-Za-z0-9_]*)\} ]]; do
		match=${BASH_REMATCH[0]}
		name=${BASH_REMATCH[1]}
		out+=${rest%%"${match}"*}
		rest=${rest#*"${match}"}
		if [ -n "${!name-}" ] && octail_is_secret "${name}"; then
			out+='********'
		else
			out+=${!name-}
		fi
	done
	OCTAIL_OUT=${out}${rest}
}

# Microseconds since the epoch (bash 5), or whole seconds as microseconds on an older bash.
octail_now() {
	local now=${EPOCHREALTIME-}
	if [ -n "${now}" ]; then
		printf '%s' "${now//[.,]/}"
	else
		printf '%s' "$((SECONDS * 1000000))"
	fi
}

# OCTAIL_DEBUG: "<what> took 1.234 s" since a start from octail_now.
octail_took() { # what start
	[ "${octail_debug}" = 1 ] || return 0
	local us=$(($(octail_now) - $2))
	printf 'octail: debug: %s took %d.%03d s\n' "$1" "$((us / 1000000))" "$((us / 1000 % 1000))"
}

# A cgroup file's first line ("" when it can't be read). OCTAIL_CGROUP exists for the tests.
octail_cgroup() {
	local value=
	[ -r "${OCTAIL_CGROUP:-/sys/fs/cgroup}/$1" ] && read -r value <"${OCTAIL_CGROUP:-/sys/fs/cgroup}/$1"
	printf '%s' "${value}"
}

# The banner: which image, OS and user, the time zone, and the limits the server gets (what a host asks for first
# when a server runs out of memory or threads). Nothing secret: no variable values.
octail_banner() {
	local image=${OCTAIL_IMAGE-} file=${OCTAIL_IMAGE_FILE:-/etc/octail/image} os='' key value line limits=()
	if [ -z "${image}" ] && [ -r "${file}" ]; then
		IFS= read -r image <"${file}"
	fi
	if [ -r "${OCTAIL_OS_RELEASE:-/etc/os-release}" ]; then
		while IFS='=' read -r key value; do
			[ "${key}" = PRETTY_NAME ] || continue
			value=${value#\"}
			os=${value%\"}
		done <"${OCTAIL_OS_RELEASE:-/etc/os-release}"
	fi
	line="octail: image ${image:-(no build info)}"
	[ -n "${os}" ] && line+=" on ${os}"
	line+=", user $(id -un 2>/dev/null || echo '?') (uid $(id -u 2>/dev/null || echo '?')), TZ ${TZ:-UTC}, umask $(umask)"
	line=${line//[^[:print:]]/}
	printf '%s\n' "${line:0:300}"

	# Memory: cgroup v2 memory.max, else v1's memory.limit_in_bytes (a huge number there means no limit).
	value=$(octail_cgroup memory.max)
	[ -n "${value}" ] || value=$(octail_cgroup memory/memory.limit_in_bytes)
	if [[ ${value} =~ ^[0-9]+$ ]] && [ "${#value}" -lt 18 ]; then
		line="memory $((value / 1048576)) MiB"
		[[ ${SERVER_MEMORY-} =~ ^[0-9]+$ ]] && [ "${SERVER_MEMORY}" -gt 0 ] && line+=" (server ${SERVER_MEMORY} MiB)"
		limits+=("${line}")
	elif [ -n "${value}" ]; then
		limits+=("memory unlimited")
	fi
	# CPU: cgroup v2 cpu.max "<quota> <period>", in percent of one core like the panel's CPU limit.
	value=$(octail_cgroup cpu.max)
	if [[ ${value} =~ ^([0-9]+)\ ([0-9]+)$ ]] && [ "${BASH_REMATCH[2]}" -gt 0 ]; then
		limits+=("CPU $((BASH_REMATCH[1] * 100 / BASH_REMATCH[2]))%")
	elif [[ ${value} == max* ]]; then
		limits+=("CPU unlimited")
	fi
	value=$(octail_cgroup pids.max)
	[ -n "${value}" ] && limits+=("threads ${value/max/unlimited}")
	limits+=("open files $(ulimit -n)")
	value=$(df -Pm /tmp 2>/dev/null | awk 'NR == 2 { print $2 }')
	[[ ${value} =~ ^[0-9]+$ ]] && limits+=("/tmp ${value} MiB")
	line="octail: limits:"
	for value in "${limits[@]}"; do
		line+=" ${value},"
	done
	printf '%s\n' "${line%,}"
}

# A TZ the image has no zone file for makes the C library fall back to UTC without a word; say so once. POSIX
# rules (UTC0, EST5EDT, <+03>-3: they hold a digit) need no file.
octail_check_tz() {
	local tz=${TZ-} zoneinfo=${OCTAIL_ZONEINFO:-/usr/share/zoneinfo}
	tz=${tz#:}
	[ -n "${tz}" ] || return 0
	[[ ${tz} == *[0-9]* ]] && return 0
	case "${tz}" in UTC | GMT | UCT | Etc/UTC | Etc/GMT | Universal | Zulu) return 0 ;; esac
	if [[ ${tz} == */../* || ${tz} == ../* || ! -f "${zoneinfo}/${tz}" ]]; then
		printf 'octail: TZ=%s is not a time zone this image knows; times will be UTC.\n' "${tz//[^[:print:]]/}"
	fi
}

# OCTAIL_DEBUG: the environment the server gets, sorted, secret values masked (the names' own values, and those
# values wherever they appear in another one).
octail_debug_env() {
	local name value
	while IFS= read -r name; do
		case "${name}" in STARTUP | _) continue ;; esac
		value=${!name-}
		[ -n "${value}" ] && octail_is_secret "${name}" && value='********'
		value=${value//$'\n'/\\n}
		printf 'octail: debug: env %s=%s\n' "${name}" "${value:0:500}"
	done < <(compgen -e | LC_ALL=C sort) | octail_mask
}

# The server owner's pre-start scripts: every *.sh in .octail/hooks/pre-start.d/ of the server folder, in name
# order, each run by its own bash in the server folder with the server's environment and no console input (so it
# can't swallow commands typed for the server). Nothing runs unless the owner creates that folder, and the scripts
# run as the server itself does, in the same container, so they can do nothing the server's own files (a plugin,
# a mod, a jar) couldn't. A script that fails stops the start with its exit code. OCTAIL_USER_HOOKS=0 turns them
# off (for a host that doesn't want them: Tentacle or an egg can set it).
octail_user_hooks() {
	local dir="${OCTAIL_HOME}/.octail/hooks/pre-start.d" hook name start rc
	case "${OCTAIL_USER_HOOKS-}" in 0 | false | FALSE | no) return 0 ;; esac
	[ -d "${dir}" ] || return 0
	for hook in "${dir}"/*.sh; do
		if [ ! -f "${hook}" ] || [ ! -r "${hook}" ]; then
			continue
		fi
		name=${hook#"${OCTAIL_HOME}/"}
		echo "octail: running ${name}"
		start=$(octail_now)
		(cd "${OCTAIL_HOME}" && exec bash "${hook}") </dev/null
		rc=$?
		octail_took "${name}" "${start}"
		if [ "${rc}" != 0 ]; then
			echo "octail: ${name} failed with exit code ${rc}; the server is not started. Fix or remove it in the file manager." >&2
			exit "${rc}"
		fi
	done
}

if [ -z "${STARTUP-}" ]; then
	echo "octail: STARTUP is empty, nothing to run" >&2
	exit 1
fi

case "${OCTAIL_BANNER-}" in 0 | false | FALSE | no) ;; *) octail_banner ;; esac
octail_check_tz

# Image hooks. Sourced at the top level (not from a function, where a hook's `declare` would be local), so they
# can export variables (WINEPREFIX, DISPLAY, ...) for the server.
if [ -d "${OCTAIL_HOOK_DIR}" ]; then
	for octail_hook in "${OCTAIL_HOOK_DIR}"/*.sh; do
		[ -r "${octail_hook}" ] || continue
		octail_hook_start=$(octail_now)
		# shellcheck source=/dev/null
		. "${octail_hook}"
		cd "${OCTAIL_HOME}" || exit 1
		octail_took "image hook ${octail_hook##*/}" "${octail_hook_start}"
	done
	unset octail_hook octail_hook_start
fi

octail_user_hooks

octail_braces "${STARTUP}"
OCTAIL_STARTUP=${OCTAIL_OUT}
if [ "${octail_debug}" = 1 ]; then
	printf 'octail: debug: startup as sent: %s\n' "${STARTUP}" | octail_mask
	octail_debug_env
fi
octail_display "${OCTAIL_STARTUP}"
# Through octail_mask as well: a secret's value inside another variable's (JAVA_OPTS=-Drcon.password=...) or
# written into the startup itself doesn't show either.
printf '%s\n' "${OCTAIL_OUT}" | octail_mask | {
	IFS= read -r octail_line
	printf '\033[1m\033[33mcontainer~ \033[0m%s\n' "${octail_line}"
	cat
}
unset OCTAIL_OUT

eval "${OCTAIL_STARTUP}"
