#!/bin/bash
# Octail yolks entrypoint: runs a game server's startup command (STARTUP) inside its container.
#
#   1. enter the server folder (/home/container) and export INTERNAL_IP
#   2. source the image's hooks (/etc/octail/entrypoint.d/*.sh): Wine prefix, Proton, SteamCMD update, ...
#   3. turn {{VAR}} into ${VAR} (Tentacle already sends ${VAR}; eggs imported from elsewhere may still use {{VAR}})
#   4. print "container~ <startup>" with the ${VAR}s filled in, values of secret-looking names masked
#   5. eval the startup ONCE: a variable's value is expanded as a parameter, never read again as shell
#
# PID 1 is tini (`tini -g`), so a stop signal (Ctrl+C = SIGINT) reaches every process of the server's
# process group, the way Ctrl+C in a terminal does. No nss_wrapper / LD_PRELOAD: Tentacle mounts an
# /etc/passwd that names the container user.
#
# OCTAIL_HOME and OCTAIL_HOOK_DIR exist for the tests (test/run.sh); images never set them.

OCTAIL_HOME=${OCTAIL_HOME:-/home/container}
OCTAIL_HOOK_DIR=${OCTAIL_HOOK_DIR:-/etc/octail/entrypoint.d}

cd "${OCTAIL_HOME}" || {
	echo "octail: cannot enter ${OCTAIL_HOME}" >&2
	exit 1
}

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
	[[ ${name} =~ PASS|PWD|SECRET|TOKEN|KEY|AUTH|GSLT|STEAM_ACC|(^|_)PW($|_) ]] && return 0
	for extra in ${OCTAIL_SECRET_VARS//,/ }; do
		[ "${name}" = "${extra^^}" ] && return 0
	done
	return 1
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

# Image hooks. Sourced, so they can export variables (WINEPREFIX, DISPLAY, ...) for the server.
if [ -d "${OCTAIL_HOOK_DIR}" ]; then
	for octail_hook in "${OCTAIL_HOOK_DIR}"/*.sh; do
		[ -r "${octail_hook}" ] || continue
		# shellcheck source=/dev/null
		. "${octail_hook}"
		cd "${OCTAIL_HOME}" || exit 1
	done
	unset octail_hook
fi

if [ -z "${STARTUP-}" ]; then
	echo "octail: STARTUP is empty, nothing to run" >&2
	exit 1
fi

octail_braces "${STARTUP}"
OCTAIL_STARTUP=${OCTAIL_OUT}
octail_display "${OCTAIL_STARTUP}"
printf '\033[1m\033[33mcontainer~ \033[0m%s\n' "${OCTAIL_OUT}"
unset OCTAIL_OUT

eval "${OCTAIL_STARTUP}"
