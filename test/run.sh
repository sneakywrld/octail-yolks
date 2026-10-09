#!/bin/bash
# The startups in this file are single-quoted on purpose: the entrypoint expands them, not this script.
# shellcheck disable=SC2016
# Tests for common/entrypoint.sh and the hooks that can run without an image. Plain bash, no Docker:
#   yolks/test/run.sh
# Uses `tini` from PATH for the signal test when it is installed (CI installs it), and otherwise sends the
# signal to the process group the way `tini -g` does.
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(dirname "${here}")
entrypoint="${root}/common/entrypoint.sh"
work=$(mktemp -d)
trap 'rm -rf "${work}"' EXIT

pass=0
fail=0
ok() {
	pass=$((pass + 1))
	printf 'ok   %s\n' "$1"
}
not_ok() {
	fail=$((fail + 1))
	printf 'FAIL %s\n' "$1"
	[ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/     /'
}
expect_contains() { # name haystack needle
	if [[ $2 == *"$3"* ]]; then ok "$1"; else not_ok "$1" "expected to find: $3"$'\n'"in: $2"; fi
}
expect_not_contains() {
	if [[ $2 != *"$3"* ]]; then ok "$1"; else not_ok "$1" "did not expect: $3"$'\n'"in: $2"; fi
}

# A fresh server folder and an empty hook folder per run.
fresh() {
	rm -rf "${work:?}/home" "${work:?}/hooks"
	mkdir -p "${work}/home" "${work}/hooks"
}

# run_ep VAR=value ... : the entrypoint with only these variables (plus PATH), output on stdout.
run_ep() {
	env -i PATH="${PATH}" HOME="${work}/home" OCTAIL_HOME="${work}/home" OCTAIL_HOOK_DIR="${work}/hooks" "$@" \
		bash "${entrypoint}" 2>&1
}

# --- images.json, folders and base images (test/check-images.sh) ---------------------------------------
check="${here}/check-images.sh"
if out=$("${check}" 2>&1); then ok 'the repository passes check-images.sh'; else not_ok 'the repository passes check-images.sh' "${out}"; fi

# A small fake tree per case: images.json + images/<tag>/Dockerfile.
fake_tree() { # tag dockerfile-content
	rm -rf "${work:?}/tree"
	mkdir -p "${work}/tree/images/$1"
	printf '%s\n' "$2" >"${work}/tree/images/$1/Dockerfile"
	printf '{"images":[{"tag":"%s","folder":"images/%s"}]}\n' "$1" "$1" >"${work}/tree/images.json"
}
expect_check() { # name pass|fail [needle]
	local out rc
	out=$("${check}" "${work}/tree" 2>&1)
	rc=$?
	if [ "$2" = pass ] && [ "${rc}" = 0 ]; then
		ok "$1"
	elif [ "$2" = fail ] && [ "${rc}" != 0 ] && [[ ${out} == *"${3:-}"* ]]; then
		ok "$1"
	else
		not_ok "$1" "rc=${rc}: ${out}"
	fi
}
fake_tree ok $'FROM golang:1.23-bookworm AS build\nFROM docker.io/library/debian:bookworm-slim@sha256:abc\nCOPY --from=build /a /a\nCOPY --from=mcr.microsoft.com/dotnet/aspnet:8.0 /b /b'
expect_check 'official bases, stages and digests pass' pass
fake_tree bad 'FROM ghcr.io/parkervcp/yolks:debian'
expect_check 'a parkervcp base fails' fail 'Pterodactyl/Pelican/parkervcp'
fake_tree bad 'FROM ghcr.io/pelican-eggs/yolks:java_21'
expect_check 'a pelican-eggs base fails' fail 'Pterodactyl/Pelican/parkervcp'
fake_tree bad $'FROM debian:bookworm-slim\nCOPY \\\n  --from=ghcr.io/pterodactyl/yolks:java_17 /entrypoint.sh /entrypoint.sh'
expect_check 'COPY --from a Pterodactyl image fails (also across a line break)' fail 'Pterodactyl/Pelican/parkervcp'
fake_tree bad $'FROM debian:bookworm-slim\nRUN --mount=type=bind,from=quay.io/someone/thing,target=/x true'
expect_check 'RUN --mount from an unlisted image fails' fail 'not an allowed base'
fake_tree bad 'FROM randomuser/debian:12'
expect_check 'an image not in bases.txt fails' fail 'not an allowed base'
fake_tree bad $'ARG BASE=debian:bookworm-slim\nFROM ${BASE}'
expect_check 'a FROM through a variable fails' fail "can't be checked"
fake_tree ok 'FROM alpine:3.22'
mkdir -p "${work}/tree/images/extra"
expect_check 'a folder missing from images.json fails' fail 'images/extra is not in images.json'
fake_tree ok 'FROM alpine:3.22'
printf '{"images":[{"tag":"ok","folder":"images/ok"},{"tag":"gone","folder":"images/gone"}]}\n' >"${work}/tree/images.json"
expect_check 'an images.json entry without a folder fails' fail 'images/gone, which does not exist'

# --- {{VAR}} and ${VAR} --------------------------------------------------------------------------------
fresh
out=$(run_ep SERVER_PORT=25565 SERVER_JARFILE=server.jar \
	STARTUP='printf "<%s>" {{SERVER_PORT}} "{{ SERVER_JARFILE }}" ${SERVER_PORT} {{server.build.memory}}')
expect_contains '{{VAR}} and {{ VAR }} become ${VAR}' "${out}" '<25565><server.jar><25565>'
expect_contains 'non-name {{...}} is left as text' "${out}" '<{{server.build.memory}}>'
expect_contains 'the startup line is printed' "${out}" 'container~ '

# --- masking -------------------------------------------------------------------------------------------
fresh
out=$(run_ep RCON_PASSWORD=hunter2 API_KEY=k3y STEAM_ACC=gslt0 SRV_PW=pw0 SERVER_NAME=Visible EMPTY_PASSWORD= \
	STARTUP='true --name "${SERVER_NAME}" --rcon ${RCON_PASSWORD} --key ${API_KEY} +sv_setsteamaccount ${STEAM_ACC} -pw ${SRV_PW} -e "${EMPTY_PASSWORD}"')
line=$(grep 'container~' <<<"${out}")
expect_contains 'plain values are shown' "${line}" '--name "Visible"'
expect_not_contains 'RCON_PASSWORD is masked' "${line}" 'hunter2'
expect_not_contains 'API_KEY is masked' "${line}" 'k3y'
expect_not_contains 'STEAM_ACC (a GSLT) is masked' "${line}" 'gslt0'
expect_not_contains 'SRV_PW is masked' "${line}" 'pw0'
expect_contains 'masked values show as stars' "${line}" '--rcon ********'
expect_contains 'empty secrets stay empty' "${line}" '-e ""'
out=$(run_ep MOTD=secretish OCTAIL_SECRET_VARS=motd,OTHER STARTUP='true ${MOTD}')
expect_not_contains 'OCTAIL_SECRET_VARS masks extra names' "${out}" 'secretish'

# --- values are never read as shell -------------------------------------------------------------------
fresh
out=$(run_ep \
	SERVER_NAME='My "server"; touch pwned-name; echo "' \
	OPTIONS='--fast $(touch pwned-subst) `touch pwned-tick` ; touch pwned-semi && touch pwned-and' \
	STARTUP='printf "[%s]" --name "${SERVER_NAME}" {{OPTIONS}}')
made=$(ls -A "${work}/home")
if [ -z "${made}" ]; then ok 'no command from a variable ran'; else not_ok 'no command from a variable ran' "${made}"; fi
expect_contains 'a quoted value stays one word' "${out}" '[My "server"; touch pwned-name; echo "]'
expect_contains 'an unquoted value is only word-split' "${out}" '[--fast][$(touch][pwned-subst)]'
expect_contains 'the printed line shows the value as text' "${out}" 'touch pwned-subst'

# The startup itself runs exactly once (its own $(...) included), also with the display line.
fresh
run_ep STARTUP='echo x >> count; n=$(wc -l < count); echo "runs=${n}"' >"${work}/out"
expect_contains 'the startup is evaluated once' "$(cat "${work}/out")" 'runs=1'
if [ "$(wc -l <"${work}/home/count")" = 1 ]; then ok 'command substitutions run once'; else not_ok 'command substitutions run once'; fi

# Backslashes reach the program as the startup's quoting says (no echo -e pass).
fresh
out=$(run_ep STARTUP='printf "<%s>" Z:\\home\\container "a\nb"')
expect_contains 'backslashes are not pre-processed' "${out}" '<Z:\home\container><a\nb>'

# Multi-line startups and exit codes.
fresh
run_ep STARTUP=$'echo one\necho two\nexit 7' >"${work}/out"
rc=$?
expect_contains 'multi-line startups keep their lines' "$(cat "${work}/out")" $'one\ntwo'
if [ "${rc}" = 7 ]; then ok 'the exit code is the startup'\''s'; else not_ok 'the exit code is the startup'\''s' "rc=${rc}"; fi
run_ep >"${work}/out"
rc=$?
if [ "${rc}" != 0 ]; then ok 'an empty STARTUP fails'; else not_ok 'an empty STARTUP fails'; fi

# Working directory, INTERNAL_IP is exported (may be empty without a route), no nss_wrapper.
fresh
out=$(run_ep STARTUP='pwd; env | grep -c "^INTERNAL_IP=" ; echo "pre=[${LD_PRELOAD-}]"')
expect_contains 'runs in the server folder' "${out}" "${work}/home"
expect_contains 'INTERNAL_IP is exported' "${out}" $'\n1\n'
expect_contains 'no LD_PRELOAD (nss_wrapper) is set' "${out}" 'pre=[]'

# --- hooks ---------------------------------------------------------------------------------------------
fresh
printf 'export FROM_HOOK=hooked\ncd /\n' >"${work}/hooks/10-a.sh"
printf 'echo "second sees ${FROM_HOOK}"\n' >"${work}/hooks/20-b.sh"
out=$(run_ep STARTUP='echo "server sees ${FROM_HOOK} in $(pwd)"')
expect_contains 'hooks run in order and share variables' "${out}" 'second sees hooked'
expect_contains 'hook exports reach the server, folder restored' "${out}" "server sees hooked in ${work}/home"

# SteamCMD update hook with a fake steamcmd.sh that fails twice ("Missing configuration") then works.
fresh
cp "${root}/common/hooks/50-steamcmd-update.sh" "${work}/hooks/"
mkdir -p "${work}/home/steamcmd/linux64"
echo fake >"${work}/home/steamcmd/linux64/steamclient.so"
cat >"${work}/home/steamcmd/steamcmd.sh" <<'EOF'
#!/bin/bash
n=$(cat "${0%/*}/tries" 2>/dev/null || echo 0)
n=$((n + 1))
echo "${n}" >"${0%/*}/tries"
printf '%s\n' "$@" >"${0%/*}/args"
[ "${n}" -ge 3 ] && exit 0
echo "Missing configuration"
exit 8
EOF
chmod +x "${work}/home/steamcmd/steamcmd.sh"
out=$(run_ep AUTO_UPDATE=1 SRCDS_APPID=896660 SRCDS_BETAID=public-test SRCDS_BETAPASS=bpass STEAM_USER=me \
	STEAM_PASS=spass WINDOWS_INSTALL=1 STARTUP='echo started')
expect_contains 'SteamCMD is retried until it works' "$(cat "${work}/home/steamcmd/tries")" '3'
args=$(cat "${work}/home/steamcmd/args")
expect_contains 'app_update gets the app id' "${args}" $'+app_update\n896660\n-beta\npublic-test\n-betapassword\nbpass'
expect_contains 'the Windows depot is forced when asked' "${args}" '+@sSteamCmdForcePlatformType'
expect_contains 'logs in with the Steam account' "${args}" $'+login\nme\nspass'
expect_not_contains 'passwords are masked in the console' "${out}" 'spass'
expect_contains 'the server starts after the update' "${out}" 'started'
if [ -f "${work}/home/.steam/sdk64/steamclient.so" ]; then ok 'steamclient.so is refreshed'; else not_ok 'steamclient.so is refreshed'; fi

rm -f "${work}/home/steamcmd/tries"
out=$(run_ep SRCDS_APPID=896660 STARTUP='echo started')
if [ ! -f "${work}/home/steamcmd/tries" ]; then ok 'no update without AUTO_UPDATE'; else not_ok 'no update without AUTO_UPDATE'; fi
out=$(run_ep OCTAIL_AUTO_UPDATE_DEFAULT=1 SRCDS_APPID=896660 STARTUP='echo started')
if [ -f "${work}/home/steamcmd/tries" ]; then ok 'the image default turns the update on'; else not_ok 'the image default turns the update on'; fi
rm -f "${work}/home/steamcmd/tries"
out=$(run_ep AUTO_UPDATE=0 OCTAIL_AUTO_UPDATE_DEFAULT=1 SRCDS_APPID=896660 STARTUP='echo started')
if [ ! -f "${work}/home/steamcmd/tries" ]; then ok 'AUTO_UPDATE=0 wins over the default'; else not_ok 'AUTO_UPDATE=0 wins over the default'; fi
out=$(run_ep AUTO_UPDATE=1 SRCDS_APPID='1; touch pwned' STARTUP='echo started')
expect_contains 'a non-numeric app id is refused' "${out}" 'not a number'

# A Steam account's saved login (Tentacle: STEAM_LOGIN_CACHE, STEAM_USER, empty STEAM_PASS).
mkdir -p "${work}/cache" "${work}/home/steamcmd/config"
echo token >"${work}/cache/config.vdf"
echo old >"${work}/home/steamcmd/config/config.vdf"
rm -f "${work}/home/steamcmd/tries"
out=$(run_ep AUTO_UPDATE=1 SRCDS_APPID=896660 STEAM_USER=me STEAM_PASS= STEAM_LOGIN_CACHE="${work}/cache" STARTUP='echo started')
expect_contains 'the saved Steam login is used' "${out}" 'using the saved Steam login for me'
if [ "$(readlink "${work}/home/steamcmd/config")" = "${work}/cache" ]; then ok 'steamcmd/config is linked to the login cache'; else not_ok 'steamcmd/config is linked to the login cache' "$(ls -la "${work}/home/steamcmd")"; fi
expect_contains 'logs in by name only (token from the cache)' "$(cat "${work}/home/steamcmd/args")" $'+login\nme\n+app_update'
out=$(run_ep AUTO_UPDATE=1 SRCDS_APPID=896660 STEAM_USER=me STEAM_LOGIN_CACHE="${work}/cache" STARTUP='echo started')
expect_not_contains 'an existing link is kept quietly' "${out}" 'using the saved Steam login'
rm -f "${work}/home/steamcmd/config" "${work}/cache/config.vdf"
mkdir -p "${work}/home/steamcmd/config"
echo own >"${work}/home/steamcmd/config/config.vdf"
run_ep AUTO_UPDATE=1 SRCDS_APPID=896660 STEAM_USER=me STEAM_LOGIN_CACHE="${work}/cache" STARTUP='true' >/dev/null
if [ ! -L "${work}/home/steamcmd/config" ] && [ -f "${work}/home/steamcmd/config/config.vdf" ]; then ok 'a server'\''s own login is kept while the cache is empty'; else not_ok 'a server'\''s own login is kept while the cache is empty'; fi
run_ep AUTO_UPDATE=1 SRCDS_APPID=896660 STEAM_LOGIN_CACHE="${work}/cache" STARTUP='true' >/dev/null
if [ ! -L "${work}/home/steamcmd/config" ]; then ok 'anonymous logins leave steamcmd/config alone'; else not_ok 'anonymous logins leave steamcmd/config alone'; fi

# --- signals: Ctrl+C (SIGINT) reaches the server --------------------------------------------------------
# The fake server saves on SIGINT and exits 0, like a game server's graceful stop. It runs once in the
# foreground of the startup, and once in the background with the egg-style trap that forwards the signal.
write_server() {
	# Python, not bash: like a real server it installs its SIGINT handler itself, which also works in a
	# background job (bash cannot trap a signal it inherited as ignored).
	cat >"${work}/home/server.sh" <<'EOF'
#!/usr/bin/env python3
import signal, sys, time
def save(*_):
    with open("saves", "a") as f:
        f.write("saved %s\n" % sys.argv[1])
    sys.exit(0)
signal.signal(signal.SIGINT, save)
open("ready." + sys.argv[1], "w").close()
while True:
    time.sleep(0.1)
EOF
	chmod +x "${work}/home/server.sh"
}

# Starts the entrypoint in its own session, like a container (under tini -g when tini is installed). A
# background job of this non-interactive script starts with SIGINT ignored, which a container's PID 1
# never has, so python resets it, starts a new session and execs (keeping the PID that $! names).
launch='import os, signal, sys
signal.signal(signal.SIGINT, signal.SIG_DFL)
os.setsid()
os.execvp(sys.argv[1], sys.argv[1:])'
start_container() {
	local pid1=()
	command -v tini >/dev/null 2>&1 && pid1=(tini -s -g --)
	python3 -c "${launch}" env -i PATH="${PATH}" HOME="${work}/home" OCTAIL_HOME="${work}/home" OCTAIL_HOOK_DIR="${work}/hooks" \
		STARTUP="$1" "${pid1[@]}" bash "${entrypoint}" >"${work}/sig.out" 2>&1 &
	CONTAINER_PID=$!
}
wait_for() { # file, tenths of a second
	local i
	for ((i = 0; i < $2; i++)); do
		[ -e "$1" ] && return 0
		sleep 0.1
	done
	return 1
}
# Waits up to 10 s for the container to end: its exit code, or 124 (and the group killed) when it hangs.
wait_container() {
	local i
	for ((i = 0; i < 100; i++)); do
		if ! kill -0 "${CONTAINER_PID}" 2>/dev/null; then
			wait "${CONTAINER_PID}"
			return
		fi
		sleep 0.1
	done
	kill -KILL -- "-${CONTAINER_PID}" 2>/dev/null
	wait "${CONTAINER_PID}" 2>/dev/null
	return 124
}
# What `docker kill -s INT` does: the signal goes to PID 1. With tini -g, tini hands it to the child's whole
# process group; without tini the test signals that group itself.
send_int() {
	if command -v tini >/dev/null 2>&1; then
		kill -INT "${CONTAINER_PID}"
	else
		kill -INT -- "-${CONTAINER_PID}"
	fi
}

if ! command -v python3 >/dev/null 2>&1; then
	not_ok 'signal tests need python3 (to start the fake container with default signal handling)'
else
	fresh
	write_server
	start_container './server.sh fg'
	if wait_for "${work}/home/ready.fg" 50; then
		send_int
		wait_container
		rc=$?
		expect_contains 'SIGINT reaches a foreground server' "$(cat "${work}/home/saves" 2>/dev/null)" 'saved fg'
		if [ "${rc}" = 0 ]; then ok 'the container ends with the server'\''s exit code'; else not_ok 'the container ends with the server'\''s exit code' "rc=${rc}"; fi
	else
		not_ok 'SIGINT reaches a foreground server' "the fake server did not start: $(cat "${work}/sig.out")"
		kill -KILL -- "-${CONTAINER_PID}" 2>/dev/null
	fi

	# Background server + `trap ... INT` + wait, as the Wine/Proton eggs do (background jobs of a
	# non-interactive shell ignore SIGINT, so the trap forwards it).
	fresh
	write_server
	start_container './server.sh bg & PID=$!; trap "kill -INT ${PID}; wait ${PID}" INT TERM; wait ${PID}'
	if wait_for "${work}/home/ready.bg" 50; then
		send_int
		wait_container
		expect_contains 'SIGINT is forwarded to a background server by the egg trap' "$(cat "${work}/home/saves" 2>/dev/null)" 'saved bg'
	else
		not_ok 'SIGINT is forwarded to a background server by the egg trap' "$(cat "${work}/sig.out")"
		kill -KILL -- "-${CONTAINER_PID}" 2>/dev/null
	fi
fi

echo
echo "${pass} passed, ${fail} failed"
[ "${fail}" = 0 ]
