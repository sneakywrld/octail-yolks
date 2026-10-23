#!/bin/bash
# The startups in this file are single-quoted on purpose: the entrypoint expands them, not this script.
# shellcheck disable=SC2016
# Tests for common/entrypoint.sh's banner, TZ check, locale fallback, server-owner pre-start scripts and
# OCTAIL_DEBUG. Plain bash, no Docker, no jq or python, so it also runs in Git Bash on Windows:
#   yolks/test/entrypoint.sh
# test/run.sh sources it (sharing its helpers and counters); run alone, it brings its own.
set -uo pipefail

if ! declare -F run_ep >/dev/null; then
	ep_standalone=1
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
	expect_contains() {
		if [[ $2 == *"$3"* ]]; then ok "$1"; else not_ok "$1" "expected to find: $3"$'\n'"in: $2"; fi
	}
	expect_not_contains() {
		if [[ $2 != *"$3"* ]]; then ok "$1"; else not_ok "$1" "did not expect: $3"$'\n'"in: $2"; fi
	}
	fresh() {
		rm -rf "${work:?}/home" "${work:?}/hooks"
		mkdir -p "${work}/home" "${work}/hooks"
	}
	run_ep() {
		env -i PATH="${PATH}" HOME="${work}/home" OCTAIL_HOME="${work}/home" OCTAIL_HOOK_DIR="${work}/hooks" "$@" \
			bash "${entrypoint}" 2>&1
	}
fi

# --- banner ----------------------------------------------------------------------------------------------
fresh
rm -rf "${work:?}/epcg"
mkdir -p "${work}/epcg"
printf '4938792960\n' >"${work}/epcg/memory.max"
printf '250000 100000\n' >"${work}/epcg/cpu.max"
printf '512\n' >"${work}/epcg/pids.max"
printf 'java_21-20261023 (abc1234)\n' >"${work}/image"
printf 'NAME="Ubuntu"\nPRETTY_NAME="Ubuntu 24.04.3 LTS"\nID=ubuntu\n' >"${work}/os-release"
banner_env=(OCTAIL_CGROUP="${work}/epcg" OCTAIL_IMAGE_FILE="${work}/image" OCTAIL_OS_RELEASE="${work}/os-release")
out=$(run_ep "${banner_env[@]}" SERVER_MEMORY=4096 TZ=UTC RCON_PASSWORD=hunter2 STARTUP='echo started')
expect_contains 'banner: names the image build and the OS' "${out}" 'octail: image java_21-20261023 (abc1234) on Ubuntu 24.04.3 LTS, user '
expect_contains 'banner: shows TZ and umask' "${out}" ', TZ UTC, umask 0'
expect_contains 'banner: memory limit next to the server'\''s plan' "${out}" 'memory 4710 MiB (server 4096 MiB)'
expect_contains 'banner: CPU in percent of a core, like the panel' "${out}" 'CPU 250%'
expect_contains 'banner: thread (pids) limit' "${out}" 'threads 512'
expect_contains 'banner: open files limit' "${out}" 'open files '
expect_not_contains 'banner: no variable values in it' "${out}" 'hunter2'
if [[ ${out} == *'octail: image'*'container~'*started* ]]; then ok 'banner: before the startup line'; else not_ok 'banner: before the startup line' "${out}"; fi

printf 'max\n' >"${work}/epcg/memory.max"
printf 'max 100000\n' >"${work}/epcg/cpu.max"
printf 'max\n' >"${work}/epcg/pids.max"
out=$(run_ep "${banner_env[@]}" STARTUP='true')
expect_contains 'banner: no memory limit says so' "${out}" 'memory unlimited'
expect_contains 'banner: no CPU limit says so' "${out}" 'CPU unlimited'
expect_contains 'banner: no thread limit says so' "${out}" 'threads unlimited'
expect_contains 'banner: no TZ shows the C library default' "${out}" 'TZ UTC'
rm -f "${work}/epcg/memory.max"
mkdir -p "${work}/epcg/memory"
printf '9223372036854771712\n' >"${work}/epcg/memory/memory.limit_in_bytes"
out=$(run_ep "${banner_env[@]}" STARTUP='true')
expect_contains 'banner: cgroup v1 "no limit" is unlimited' "${out}" 'memory unlimited'
printf '1073741824\n' >"${work}/epcg/memory/memory.limit_in_bytes"
out=$(run_ep "${banner_env[@]}" STARTUP='true')
expect_contains 'banner: cgroup v1 memory limit' "${out}" 'memory 1024 MiB'

out=$(run_ep "${banner_env[@]}" OCTAIL_IMAGE='wine-20261101' STARTUP='true')
expect_contains 'banner: OCTAIL_IMAGE wins over the file' "${out}" 'octail: image wine-20261101 on'
out=$(run_ep OCTAIL_IMAGE_FILE="${work}/none" OCTAIL_OS_RELEASE="${work}/none" STARTUP='true')
expect_contains 'banner: an image without build info says so' "${out}" 'octail: image (no build info), user'
printf 'evil\033[2Jname\n' >"${work}/image2"
out=$(run_ep OCTAIL_IMAGE_FILE="${work}/image2" STARTUP='true')
expect_contains 'banner: control characters are dropped' "${out}" 'octail: image evil[2Jname'
out=$(run_ep "${banner_env[@]}" OCTAIL_BANNER=0 STARTUP='echo started')
expect_not_contains 'OCTAIL_BANNER=0 turns the banner off' "${out}" 'octail: image'
expect_contains '... and the server still starts' "${out}" 'started'

# --- TZ --------------------------------------------------------------------------------------------------
mkdir -p "${work}/zoneinfo/Europe"
: >"${work}/zoneinfo/Europe/Paris"
for tz in Europe/Paris :Europe/Paris UTC Etc/UTC UTC0 EST5EDT '<+03>-3'; do
	out=$(run_ep OCTAIL_ZONEINFO="${work}/zoneinfo" OCTAIL_BANNER=0 TZ="${tz}" STARTUP='true')
	expect_not_contains "TZ=${tz} is accepted quietly" "${out}" 'not a time zone'
done
for tz in Mars/Olympus_Mons Europe/../../../etc/passwd; do
	out=$(run_ep OCTAIL_ZONEINFO="${work}/zoneinfo" OCTAIL_BANNER=0 TZ="${tz}" STARTUP='echo started')
	expect_contains "TZ=${tz} gets a warning" "${out}" "TZ=${tz} is not a time zone this image knows"
	expect_contains "... and the server starts anyway (${tz})" "${out}" 'started'
done

# --- locale ----------------------------------------------------------------------------------------------
out=$(run_ep OCTAIL_BANNER=0 STARTUP='echo "lang=[${LANG}]"')
expect_contains 'a missing LANG becomes C.UTF-8' "${out}" 'lang=[C.UTF-8]'
out=$(run_ep OCTAIL_BANNER=0 LANG=en_US.UTF-8 STARTUP='echo "lang=[${LANG}]"')
expect_contains 'the image'\''s LANG is kept' "${out}" 'lang=[en_US.UTF-8]'

# --- an empty STARTUP stops before any hook (no SteamCMD update for nothing) ------------------------------
fresh
printf 'touch "%s/hook-ran"\n' "${work}" >"${work}/hooks/50-x.sh"
rm -f "${work}/hook-ran"
run_ep OCTAIL_BANNER=0 >/dev/null
if [ ! -e "${work}/hook-ran" ]; then ok 'an empty STARTUP fails before the image hooks'; else not_ok 'an empty STARTUP fails before the image hooks'; fi

# --- the server owner's pre-start scripts ------------------------------------------------------------------
fresh
out=$(run_ep OCTAIL_BANNER=0 STARTUP='echo started')
expect_not_contains 'pre-start: nothing without the folder' "${out}" 'octail: running'
pre="${work}/home/.octail/hooks/pre-start.d"
mkdir -p "${pre}"
printf 'echo "first in $(pwd) port=${SERVER_PORT}"\necho one >> order\ncd /\nexport FROM_PRE=leaked\n' >"${pre}/10-first.sh"
printf 'echo two >> order\nif read -r line; then echo "hook read [${line}]"; else echo "hook stdin empty"; fi\n' >"${pre}/20-second.sh"
printf 'echo not-a-script >> order\n' >"${pre}/30-notes.txt"
mkdir -p "${pre}/40-dir.sh"
out=$(printf 'say hello\n' | run_ep OCTAIL_BANNER=0 SERVER_PORT=25565 \
	STARTUP='read -r cmd; echo "server got [${cmd}] in $(pwd) from_pre=[${FROM_PRE-}]"')
expect_contains 'pre-start: scripts run in the server folder with the server'\''s variables' "${out}" "first in ${work}/home port=25565"
expect_contains 'pre-start: each is announced' "${out}" 'octail: running .octail/hooks/pre-start.d/10-first.sh'
if [ "$(tr '\n' ' ' <"${work}/home/order")" = 'one two ' ]; then ok 'pre-start: *.sh files only, in name order'; else not_ok 'pre-start: *.sh files only, in name order' "$(cat "${work}/home/order")"; fi
expect_contains 'pre-start: scripts get no console input' "${out}" 'hook stdin empty'
expect_contains 'pre-start: console input still reaches the server' "${out}" 'server got [say hello]'
expect_contains 'pre-start: the server starts in its folder whatever a script did' "${out}" "in ${work}/home from_pre=[]"
if [[ ${out} == *'octail: running'*'container~'* ]]; then ok 'pre-start: before the startup line'; else not_ok 'pre-start: before the startup line' "${out}"; fi

# After the image hooks (a script can patch what the SteamCMD update just wrote).
printf 'echo image >> order\n' >"${work}/hooks/50-update.sh"
rm -f "${work}/home/order"
run_ep OCTAIL_BANNER=0 STARTUP='true' </dev/null >/dev/null
if [ "$(tr '\n' ' ' <"${work}/home/order")" = 'image one two ' ]; then ok 'pre-start: after the image hooks'; else not_ok 'pre-start: after the image hooks' "$(cat "${work}/home/order")"; fi
rm -f "${work}/hooks/50-update.sh"

rm -f "${work}/home/order"
out=$(run_ep OCTAIL_BANNER=0 OCTAIL_USER_HOOKS=0 STARTUP='echo started' </dev/null)
if [ ! -e "${work}/home/order" ]; then ok 'pre-start: OCTAIL_USER_HOOKS=0 turns them off'; else not_ok 'pre-start: OCTAIL_USER_HOOKS=0 turns them off'; fi
expect_contains '... and the server starts' "${out}" 'started'

printf 'echo "breaking"\nexit 3\n' >"${pre}/15-broken.sh"
out=$(run_ep OCTAIL_BANNER=0 STARTUP='echo server-ran' </dev/null)
rc=$?
if [ "${rc}" = 3 ]; then ok 'pre-start: a failing script stops the start with its exit code'; else not_ok 'pre-start: a failing script stops the start with its exit code' "rc=${rc}: ${out}"; fi
expect_contains '... and says which one' "${out}" '15-broken.sh failed with exit code 3; the server is not started'
expect_not_contains '... the server did not run' "${out}" 'server-ran'
expect_not_contains '... nor the scripts after it' "$(cat "${work}/home/order")" 'two'
rm -f "${pre}/15-broken.sh"

out=$(run_ep OCTAIL_BANNER=0 STARTUP='exit 5' </dev/null)
rc=$?
if [ "${rc}" = 5 ]; then ok 'pre-start: the exit code is still the startup'\''s'; else not_ok 'pre-start: the exit code is still the startup'\''s' "rc=${rc}"; fi

# A variable's value can't reach a script's shell: the script runs from its file, values are only environment.
fresh
mkdir -p "${work}/home/.octail/hooks/pre-start.d"
printf 'echo "name=[${SERVER_NAME}]"\n' >"${work}/home/.octail/hooks/pre-start.d/10.sh"
out=$(run_ep OCTAIL_BANNER=0 SERVER_NAME='$(touch pwned)' STARTUP='true' </dev/null)
expect_contains 'pre-start: values are text to the scripts too' "${out}" 'name=[$(touch pwned)]'
if [ ! -e "${work}/home/pwned" ]; then ok 'pre-start: no command from a value ran'; else not_ok 'pre-start: no command from a value ran'; fi

# --- OCTAIL_DEBUG ----------------------------------------------------------------------------------------
fresh
printf 'export FROM_HOOK=hooked\n' >"${work}/hooks/10-a.sh"
debug_vars=(OCTAIL_BANNER=0 SERVER_PORT=25565 RCON_PASSWORD=hunter2hunter2 API_KEY=abc MOTD=Welcome
	JAVA_OPTS='-Drcon=hunter2hunter2 -Xmx1G' HIDDEN=topsecretvalue OCTAIL_SECRET_VARS=HIDDEN)
out=$(run_ep "${debug_vars[@]}" STARTUP='true java {{JAVA_OPTS}} --rcon ${RCON_PASSWORD} --motd "${MOTD}"')
expect_not_contains 'debug: off by default' "${out}" 'octail: debug:'
expect_contains 'the startup line masks a secret inside another variable' "$(grep 'container~' <<<"${out}")" \
	'true java -Drcon=******** -Xmx1G --rcon ******** --motd "Welcome"'
out=$(run_ep OCTAIL_BANNER=0 MAP=Island STARTUP=$'true one ${MAP}\ntrue two')
expect_contains 'a multi-line startup still prints all its lines' "${out}" $'container~ \033[0mtrue one Island\ntrue two'
out=$(run_ep "${debug_vars[@]}" OCTAIL_DEBUG=1 STARTUP='true java {{JAVA_OPTS}} --rcon ${RCON_PASSWORD} --motd "${MOTD}"')
expect_contains 'debug: the startup as sent' "${out}" 'octail: debug: startup as sent: true java {{JAVA_OPTS}} --rcon ${RCON_PASSWORD} --motd "${MOTD}"'
expect_contains 'debug: plain variables are listed' "${out}" 'octail: debug: env SERVER_PORT=25565'
expect_contains 'debug: hook exports are listed' "${out}" 'octail: debug: env FROM_HOOK=hooked'
expect_contains 'debug: secret-looking names are masked' "${out}" 'octail: debug: env RCON_PASSWORD=********'
expect_contains 'debug: short secrets too' "${out}" 'octail: debug: env API_KEY=********'
expect_contains 'debug: OCTAIL_SECRET_VARS names are masked' "${out}" 'octail: debug: env HIDDEN=********'
expect_contains 'debug: a secret inside another value is masked' "${out}" 'octail: debug: env JAVA_OPTS=-Drcon=******** -Xmx1G'
expect_not_contains 'debug: no secret value anywhere' "${out}" 'hunter2'
expect_not_contains 'debug: no hidden value anywhere' "${out}" 'topsecretvalue'
expect_contains 'debug: image hooks are timed' "${out}" 'octail: debug: image hook 10-a.sh took '
mkdir -p "${work}/home/.octail/hooks/pre-start.d"
printf 'true\n' >"${work}/home/.octail/hooks/pre-start.d/10.sh"
out=$(run_ep "${debug_vars[@]}" OCTAIL_DEBUG=1 STARTUP='true' </dev/null)
expect_contains 'debug: pre-start scripts are timed' "${out}" 'octail: debug: .octail/hooks/pre-start.d/10.sh took '
touch "${work}/home/.octail/debug"
out=$(run_ep "${debug_vars[@]}" STARTUP='true' </dev/null)
expect_contains 'debug: .octail/debug in the server folder turns it on' "${out}" 'octail: debug: env SERVER_PORT=25565'
out=$(run_ep "${debug_vars[@]}" OCTAIL_DEBUG=0 STARTUP='true' </dev/null)
expect_not_contains 'debug: OCTAIL_DEBUG=0 wins over the file' "${out}" 'octail: debug:'

# --- masking leaves the working directory alone (bash exports PWD, whose name looks like a password) --------
fresh
out=$(run_ep OCTAIL_BANNER=0 STARTUP='printf "%s\n" "cwd=$(pwd)" | octail_mask')
expect_contains 'octail_mask does not hide the server folder (PWD)' "${out}" "cwd=${work}/home"
out=$(run_ep OCTAIL_BANNER=0 STARTUP='echo "[${PWD}]"')
expect_contains 'the startup line shows ${PWD}' "$(grep 'container~' <<<"${out}")" "[${work}/home]"

if [ -n "${ep_standalone:-}" ]; then
	echo
	echo "${pass} passed, ${fail} failed"
	[ "${fail}" = 0 ]
fi
