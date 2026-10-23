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
	printf '{"images":[{"tag":"%s","folder":"images/%s","platforms":["linux/amd64"],"kind":"runtime","smoke":"true"}]}\n' "$1" "$1" >"${work}/tree/images.json"
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
printf '{"images":[{"tag":"ok","folder":"images/ok","platforms":["linux/amd64"],"kind":"runtime","smoke":"true"},{"tag":"gone","folder":"images/gone","platforms":["linux/amd64"],"kind":"runtime","smoke":"true"}]}\n' >"${work}/tree/images.json"
expect_check 'an images.json entry without a folder fails' fail 'images/gone, which does not exist'
fake_tree ok 'FROM alpine:3.22'
printf '{"images":[{"tag":"ok","folder":"images/ok","platforms":["linux/amd64"],"kind":"runtime"}]}\n' >"${work}/tree/images.json"
expect_check 'a tag without a smoke command fails' fail 'ok has no smoke command'
printf '{"images":[{"tag":"ok","folder":"images/ok","platforms":["linux/amd64"],"kind":"runtime","smoke":"  "}]}\n' >"${work}/tree/images.json"
expect_check 'a blank smoke command fails' fail 'ok has no smoke command'
printf '{"images":[{"tag":"ok","folder":"images/ok","platforms":["linux/amd64"],"kind":"server","smoke":"true"}]}\n' >"${work}/tree/images.json"
expect_check 'an unknown kind fails' fail "kind 'server'"
# platforms: what CI builds (multi-arch), checked against what the image can run on.
plat_tree() { # tag platforms-json [dockerfile-content]
	fake_tree "$1" "${3:-FROM alpine:3.22}"
	printf '{"images":[{"tag":"%s","folder":"images/%s","platforms":%s,"kind":"runtime","smoke":"true"}]}\n' "$1" "$1" "$2" >"${work}/tree/images.json"
}
plat_tree ok '["linux/amd64","linux/arm64"]'
expect_check 'platforms: amd64 and arm64 pass' pass
printf '{"images":[{"tag":"ok","folder":"images/ok","kind":"runtime","smoke":"true"}]}\n' >"${work}/tree/images.json"
expect_check 'platforms: a tag without platforms fails' fail 'ok needs "platforms"'
plat_tree ok '[]'
expect_check 'platforms: an empty list fails' fail 'ok needs "platforms"'
plat_tree ok '["linux/arm64"]'
expect_check 'platforms: arm64 without amd64 fails (the boot test runs on amd64)' fail 'must include linux/amd64'
plat_tree ok '["linux/amd64","linux/riscv64"]'
expect_check 'platforms: an unknown platform fails' fail "platform 'linux/riscv64'"
plat_tree ok '["linux/amd64","linux/amd64"]'
expect_check 'platforms: a platform listed twice fails' fail 'lists a platform twice'
plat_tree steamcmd_x '["linux/amd64","linux/arm64"]'
expect_check 'platforms: a SteamCMD image with arm64 fails' fail 'steamcmd_x must be linux/amd64 only'
plat_tree wine_x '["linux/amd64"]'
expect_check 'platforms: a Wine image on amd64 only passes' pass
plat_tree game '["linux/amd64","linux/arm64"]' $'FROM debian:bookworm-slim\nRUN apt-get install -y lib32gcc-s1:i386'
expect_check 'platforms: unguarded i386 packages with arm64 fail' fail 'installs i386 packages'
plat_tree game '["linux/amd64","linux/arm64"]' $'FROM debian:bookworm-slim\nARG TARGETARCH\nRUN [ "$TARGETARCH" != amd64 ] || apt-get install -y lib32gcc-s1:i386'
expect_check 'platforms: i386 packages behind a TARGETARCH guard pass with arm64' pass

# --- libraries the eggs' native servers link (no Docker: the package lists in the Dockerfiles) ----------
# apt_packages <folder>: the packages a Dockerfile hands to setup-apt.sh, one per line.
apt_packages() {
	sed -n '/setup-apt.sh/,/^$/p' "${root}/$1/Dockerfile" | tr -d '\134' | tr -s ' \t' '\n' | grep -E '^[a-z0-9][a-z0-9.+-]*$'
}
# OpenRCT2's Linux-bookworm build (libopenrct2.so NEEDED): crypto, curl, ICU 72, fontconfig, freetype, png, zlib,
# libzip and zstd. bookworm-slim happens to carry libzstd1 for apt itself; it is listed so it can't vanish.
debian_pkgs=$(apt_packages images/debian)
for pkg in libssl3 libcurl4 libicu72 libfontconfig1 libfreetype6 libpng16-16 zlib1g libzip4 libzstd1 libstdc++6; do
	if grep -qxF "${pkg}" <<<"${debian_pkgs}"; then ok "debian has ${pkg} (OpenRCT2)"; else not_ok "debian has ${pkg} (OpenRCT2)" "${debian_pkgs}"; fi
done
# TShock 6 is a framework-dependent .NET 9 app and Space Station 14's Robust.Server a .NET 10 one: each image
# starts from Microsoft's runtime of that version and has ICU for .NET globalization.
for pair in 'dotnet_9:runtime:9.0' 'dotnet_10:runtime:10.0'; do
	tag=${pair%%:*}
	if grep -q "^FROM mcr.microsoft.com/dotnet/${pair#*:}-" "${root}/images/${tag}/Dockerfile"; then ok "${tag} starts from the .NET ${pair##*:} runtime"; else not_ok "${tag} starts from the .NET ${pair##*:} runtime"; fi
	if apt_packages "images/${tag}" | grep -q '^libicu[0-9]*$'; then ok "${tag} has ICU"; else not_ok "${tag} has ICU"; fi
done

# --- the boot test (scripts/smoke.sh) with a fake docker ------------------------------------------------
# The fake logs each call's arguments (one per line, calls separated by "--call--") and answers `image inspect`
# with FAKE_SIZE / FAKE_PLATFORM; `run` prints FAKE_OUT, sleeps FAKE_SLEEP and exits FAKE_RC.
smoke="${root}/scripts/smoke.sh"
mkdir -p "${work}/fakebin"
cat >"${work}/fakebin/docker" <<'EOF'
#!/bin/bash
{
	echo '--call--'
	printf '%s\n' "$@"
} >>"${FAKE_LOG}"
case "$1 ${2:-}" in
'image inspect')
	[ -n "${FAKE_SIZE:-}" ] || exit 1
	case "$4" in
	*Size*) echo "${FAKE_SIZE}" ;;
	*) echo "${FAKE_PLATFORM:-linux/amd64}" ;;
	esac
	;;
run*)
	printf '%b' "${FAKE_OUT:-}"
	sleep "${FAKE_SLEEP:-0}"
	exit "${FAKE_RC:-0}"
	;;
esac
exit 0
EOF
chmod +x "${work}/fakebin/docker"
run_smoke() { # VAR=value ... -- image tag : output in SMOKE_OUT, exit code in SMOKE_RC, docker calls in SMOKE_LOG
	local vars=()
	while [ "$1" != -- ]; do
		vars+=("$1")
		shift
	done
	shift
	rm -f "${work}/docker.log" "${work}/summary.md"
	SMOKE_OUT=$(env FAKE_LOG="${work}/docker.log" DOCKER="${work}/fakebin/docker" GITHUB_STEP_SUMMARY="${work}/summary.md" \
		FAKE_SIZE=123456789 "${vars[@]}" "${smoke}" "$@" 2>&1)
	SMOKE_RC=$?
	SMOKE_LOG=$(cat "${work}/docker.log" 2>/dev/null)
	# The `docker run` call alone.
	SMOKE_RUN=$(awk '/^--call--$/ { first = 1; keep = 0; next } first { keep = ($0 == "run"); first = 0 } keep' \
		"${work}/docker.log" 2>/dev/null)
	SMOKE_SUMMARY=$(cat "${work}/summary.md" 2>/dev/null)
}
expect_rc() { # name expected actual output
	if [ "$2" = "$3" ]; then ok "$1"; else not_ok "$1" "exit code $3 (expected $2): $4"; fi
}

run_smoke 'FAKE_OUT=\033[1m\033[33mcontainer~ \033[0mjava -version\nopenjdk version "21"\n' -- smoke-img:java_21 java_21
expect_rc 'smoke: a runtime image that starts passes' 0 "${SMOKE_RC}" "${SMOKE_OUT}"
run_log=${SMOKE_RUN}
for arg in run --read-only $'--cap-drop\nALL' $'--security-opt\nno-new-privileges' --pids-limit \
	':/home/container' ':/etc/passwd:ro,z' ':/etc/group:ro,z' '/tmp:rw,exec,nosuid' 'STARTUP=' 'java -version'; do
	expect_contains "smoke: runtime containers run with ${arg//$'\n'/ }" "${run_log}" "${arg}"
done
expect_contains 'smoke: the startup checks PID 1 is tini' "${run_log}" '/proc/1/comm)" = tini'
expect_not_contains 'smoke: runtime containers keep the image entrypoint' "${run_log}" '--entrypoint'
expect_not_contains 'smoke: runtime containers do not run as root' "${run_log}" $'--user\n0:'
if [[ $(tail -n 1 <<<"${run_log}") == smoke-img:java_21 ]]; then ok 'smoke: runtime containers get no command'; else not_ok 'smoke: runtime containers get no command' "${run_log}"; fi
expect_contains 'smoke: the size is printed' "${SMOKE_OUT}" '123 MB'
expect_contains 'smoke: the job summary has the size and result' "${SMOKE_SUMMARY}" '| `java_21` | runtime | linux/amd64 | 123 MB | passed in'
expect_contains 'smoke: the container is removed afterwards' "${SMOKE_LOG}" $'rm\n-f\nocta'
# The STARTUP smoke.sh sends goes through the real entrypoint ({{ }}, display, eval) intact: here PID 1 isn't
# tini, so its first check stops it with smoke.sh's message.
startup=$(grep '^STARTUP=' <<<"${run_log}")
if [ "$(cat /proc/1/comm 2>/dev/null)" != tini ]; then
	fresh
	out=$(run_ep "${startup}")
	expect_contains 'smoke: the startup runs through the entrypoint and checks PID 1' "${out}" 'not tini'
fi
run_smoke SMOKE_UID=0 -- smoke-img:java_21 java_21
expect_rc 'smoke: runtime images are never tested as root' 2 "${SMOKE_RC}" "${SMOKE_OUT}"
run_smoke SMOKE_UID=4321 SMOKE_GID=4322 'FAKE_OUT=container~ x\n' -- smoke-img:java_21 java_21
expect_contains 'smoke: SMOKE_UID/SMOKE_GID pick the container user' "${SMOKE_LOG}" $'--user\n4321:4322'

run_smoke 'FAKE_OUT=container~ java -version\nError: could not find libjava.so\n' FAKE_RC=1 -- smoke-img:java_21 java_21
expect_rc 'smoke: a failing startup fails' 1 "${SMOKE_RC}" "${SMOKE_OUT}"
expect_contains 'smoke: the summary says why' "${SMOKE_SUMMARY}" 'FAILED: exit code 1'
expect_contains 'smoke: the summary shows the output tail' "${SMOKE_SUMMARY}" 'could not find libjava.so'
run_smoke 'FAKE_OUT=/usr/bin/tini: exec /entrypoint.sh failed\n' -- smoke-img:java_21 java_21
expect_rc 'smoke: exit 0 without the "container~" line fails' 1 "${SMOKE_RC}" "${SMOKE_OUT}"
expect_contains 'smoke: ... and says the entrypoint never got there' "${SMOKE_OUT}" 'never printed'
run_smoke SMOKE_TIMEOUT=1 FAKE_SLEEP=3 -- smoke-img:java_21 java_21
expect_rc 'smoke: a hanging startup fails after SMOKE_TIMEOUT' 1 "${SMOKE_RC}" "${SMOKE_OUT}"
expect_contains 'smoke: ... as a timeout' "${SMOKE_OUT}" 'timed out after 1 s'

run_smoke 'FAKE_OUT=curl 8.5.0\njq-1.7\n' -- smoke-img:installer_debian installer_debian
expect_rc 'smoke: an installer image passes without the "container~" line' 0 "${SMOKE_RC}" "${SMOKE_OUT}"
run_log=${SMOKE_RUN}
for arg in $'--user\n0:0' $'--cap-drop\nALL' $'--cap-add\nCHOWN' $'--cap-add\nDAC_OVERRIDE' $'--security-opt\nno-new-privileges' \
	':/mnt/server' $'smoke-img:installer_debian\nbash\n-c' 'curl --version && jq --version'; do
	expect_contains "smoke: installers run with ${arg//$'\n'/ }" "${run_log}" "${arg}"
done
expect_not_contains 'smoke: installers have a writable root filesystem, as on a node' "${run_log}" '--read-only'

# Every smoke command in images.json is valid bash (the entrypoint evals it, installers run it with bash -c).
bad_smoke=''
while IFS=$'\t' read -r tag cmd; do
	bash -n -c "${cmd}" 2>/dev/null || bad_smoke+=" ${tag}"
done < <(jq -r '.images[] | [.tag, .smoke] | @tsv' "${root}/images.json")
if [ -z "${bad_smoke}" ]; then ok 'smoke: every smoke command in images.json parses'; else not_ok 'smoke: every smoke command in images.json parses' "${bad_smoke}"; fi

run_smoke -- smoke-img:nope nope
expect_rc 'smoke: an unknown tag is a usage error' 2 "${SMOKE_RC}" "${SMOKE_OUT}"
run_smoke FAKE_SIZE= -- smoke-img:java_21 java_21
expect_rc 'smoke: a missing image is a usage error' 2 "${SMOKE_RC}" "${SMOKE_OUT}"
printf '{"images":[{"tag":"t","folder":"images/t","kind":"runtime"}]}\n' >"${work}/nosmoke.json"
run_smoke IMAGES_JSON="${work}/nosmoke.json" -- smoke-img:t t
expect_rc 'smoke: a tag without a smoke command is a usage error' 2 "${SMOKE_RC}" "${SMOKE_OUT}"

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

# app 1007 (the Steam client libraries): STEAM_SDK, or the image's OCTAIL_STEAM_SDK_DEFAULT (Wine, Proton).
run_ep AUTO_UPDATE=1 SRCDS_APPID=896660 STARTUP='true' >/dev/null
expect_not_contains 'no app 1007 by default' "$(cat "${work}/home/steamcmd/args")" '1007'
run_ep AUTO_UPDATE=1 SRCDS_APPID=896660 OCTAIL_STEAM_SDK_DEFAULT=1 STARTUP='true' >/dev/null
expect_contains 'the image default adds app 1007' "$(cat "${work}/home/steamcmd/args")" $'+app_update\n1007\n+app_update\n896660'
run_ep AUTO_UPDATE=1 SRCDS_APPID=896660 OCTAIL_STEAM_SDK_DEFAULT=1 STEAM_SDK=0 STARTUP='true' >/dev/null
expect_not_contains 'STEAM_SDK=0 wins over the default' "$(cat "${work}/home/steamcmd/args")" '1007'

# GoldSrc (app 90): the mod is set before app_update, and only for app 90.
run_ep AUTO_UPDATE=1 SRCDS_APPID=90 HLDS_GAME=cstrike STARTUP='true' >/dev/null
expect_contains 'HLDS: the mod is set before app_update' "$(cat "${work}/home/steamcmd/args")" $'+app_set_config\n90\nmod\ncstrike\n+app_update\n90'
run_ep AUTO_UPDATE=1 SRCDS_APPID=276060 HLDS_GAME=cstrike STARTUP='true' >/dev/null
expect_not_contains 'no HLDS mod for other apps' "$(cat "${work}/home/steamcmd/args")" 'app_set_config'

# Display hook: XVFB, or the image's OCTAIL_XVFB_DEFAULT (Wine). A malformed DISPLAY shows the hook got that far
# without needing Xvfb here.
fresh
cp "${root}/common/hooks/20-display.sh" "${work}/hooks/"
out=$(run_ep DISPLAY=bad STARTUP='true')
expect_not_contains 'no Xvfb by default' "${out}" 'DISPLAY must look like'
out=$(run_ep DISPLAY=bad OCTAIL_XVFB_DEFAULT=1 STARTUP='true')
expect_contains 'the image default starts Xvfb' "${out}" 'DISPLAY must look like'
out=$(run_ep DISPLAY=bad OCTAIL_XVFB_DEFAULT=1 XVFB=0 STARTUP='true')
expect_not_contains 'XVFB=0 wins over the default' "${out}" 'DISPLAY must look like'

# Wine hook: an existing prefix and no verbs need no Wine; WINEDLLOVERRIDES set without `export` reaches programs.
fresh
cp "${root}/common/hooks/30-wine.sh" "${work}/hooks/"
mkdir -p "${work}/home/.wine"
touch "${work}/home/.wine/system.reg"
out=$(run_ep STARTUP='WINEDLLOVERRIDES="winhttp=n,b"; env | grep "^WINE"')
expect_contains 'WINEDLLOVERRIDES set in the startup reaches Wine' "${out}" 'WINEDLLOVERRIDES=winhttp=n,b'
expect_contains 'the prefix is in the server folder' "${out}" "WINEPREFIX=${work}/home/.wine"

# Proton hook: a prefix left by another Proton image (compatdata/<appid>) is kept until ~/.proton exists.
fresh
cp "${root}/common/hooks/30-proton.sh" "${work}/hooks/"
out=$(run_ep SRCDS_APPID=2278520 STARTUP='echo "data=${STEAM_COMPAT_DATA_PATH} app=${SteamAppId}"')
expect_contains 'the Proton prefix lives in ~/.proton' "${out}" "data=${work}/home/.proton app=2278520"
rm -rf "${work}/home/.proton"
mkdir -p "${work}/home/.steam/steam/steamapps/compatdata/2278520/pfx"
out=$(run_ep SRCDS_APPID=2278520 STARTUP='echo "data=${STEAM_COMPAT_DATA_PATH}"')
expect_contains 'an existing compatdata prefix is kept' "${out}" "data=${work}/home/.steam/steam/steamapps/compatdata/2278520"
mkdir -p "${work}/home/.proton"
out=$(run_ep SRCDS_APPID=2278520 STARTUP='echo "data=${STEAM_COMPAT_DATA_PATH}"')
expect_contains 'a .proton folder wins once it exists' "${out}" "data=${work}/home/.proton"

# Proton start watch: one report when no port is open after OCTAIL_PROTON_WATCH seconds, none once one is.
mkdir -p "${work}/proc/net" "${work}/cg"
printf '  sl  local_address rem_address   st\n   0: 0100007F:9C40 0100007F:A3B2 01 0\n' >"${work}/proc/net/tcp"
printf '  sl  local_address rem_address   st\n   1: 0A00000F:D2F0 08080808:0035 01 0\n' >"${work}/proc/net/udp"
printf '37\n' >"${work}/cg/pids.current"
printf '512\n' >"${work}/cg/pids.max"
printf 'max 3\n' >"${work}/cg/pids.events"
printf '629145600\n' >"${work}/cg/memory.current"
printf '9663676416\n' >"${work}/cg/memory.max"
printf 'low 0\noom_kill 0\n' >"${work}/cg/memory.events"
watch_env=(SRCDS_APPID=2430930 OCTAIL_PROTON_WATCH=1 OCTAIL_PROC="${work}/proc" OCTAIL_CGROUP="${work}/cg")
out=$(run_ep "${watch_env[@]}" STARTUP='sleep 3; echo started')
expect_contains 'the watch reports a server without an open port' "${out}" 'no game port is open 1 s after the start'
expect_contains 'the report names the thread limit and how often it was hit' "${out}" 'threads 37 of 512 (limit reached 3 times)'
expect_contains 'the report gives memory in MiB' "${out}" 'memory 600 MiB of 9216 MiB (OOM kills 0)'
expect_contains 'the report lists the processes' "${out}" 'sleep 3'
expect_contains 'the startup still runs' "${out}" 'started'
# The process list goes through octail_proton_masked: the game's arguments carry its passwords, and the console
# is read by subusers too. (On a test host ps lists the host's processes, so the filter is checked on its own.)
out=$(run_ep ADMIN_PASSWORD=hunter2hunter2 RCON_PASS=hunter2 MAP=Island \
	STARTUP='printf "%s\n" "42 S game ?Map=${MAP}?ServerAdminPassword=${ADMIN_PASSWORD} -rcon=${RCON_PASS} -n=1" | octail_proton_masked')
expect_contains 'the start watch masks secret values in the process list' "${out}" \
	'42 S game ?Map=Island?ServerAdminPassword=******** -rcon=******** -n=1'
expect_not_contains 'no part of a secret is left (longer values first)' "${out}" 'hunter2'
if grep -q 'args= .*|$' "${root}/common/hooks/30-proton.sh" && grep -q '^[[:space:]]*octail_proton_masked |' "${root}/common/hooks/30-proton.sh"; then
	ok 'the report pipes ps through octail_proton_masked'
else
	not_ok 'the report pipes ps through octail_proton_masked'
fi
printf '  sl  local_address rem_address   st\n   0: 00000000:9389 00000000:0000 07 0\n' >"${work}/proc/net/udp"
out=$(run_ep "${watch_env[@]}" STARTUP='sleep 3; echo started')
expect_not_contains 'a bound UDP port keeps the watch quiet' "${out}" 'no game port is open'
printf '  sl  local_address rem_address   st\n' >"${work}/proc/net/udp"
printf '  sl  local_address rem_address   st\n   0: 00000000:6987 00000000:0000 0A 0\n' >"${work}/proc/net/tcp"
out=$(run_ep "${watch_env[@]}" STARTUP='sleep 3; echo started')
expect_not_contains 'a listening TCP port keeps the watch quiet' "${out}" 'no game port is open'
started=${SECONDS}
out=$(run_ep "${watch_env[@]}" OCTAIL_PROTON_WATCH=60 STARTUP='echo quick; wait')
expect_contains 'a startup with a bare wait ends' "${out}" 'quick'
if [ $((SECONDS - started)) -lt 10 ]; then ok 'the watch ends with the startup'; else not_ok 'the watch ends with the startup' "took $((SECONDS - started)) s"; fi
out=$(run_ep "${watch_env[@]}" OCTAIL_PROTON_WATCH=0 STARTUP='sleep 2')
expect_not_contains 'OCTAIL_PROTON_WATCH=0 turns the watch off' "${out}" 'no game port is open'

# Rust hook: the server's own libraries on LD_LIBRARY_PATH; vanilla downloads nothing.
fresh
cp "${root}/common/hooks/60-rust-framework.sh" "${work}/hooks/"
out=$(run_ep FRAMEWORK=vanilla LD_LIBRARY_PATH=/x STARTUP='echo "lib=${LD_LIBRARY_PATH}"')
expect_contains 'RustDedicated finds its plugins' "${out}" "lib=${work}/home/RustDedicated_Data/Plugins/x86_64:${work}/home:/x"
expect_not_contains 'vanilla installs no framework' "${out}" 'installing'

# --- Wine build downloads are checksum-verified (common/wine-checksums.sh) -------------------------------
# A fake downloader: serves "${work}/dl/<url with / as _>" and logs every URL it is asked for.
fake_curl() {
	local url="" out="" key
	while [ $# -gt 0 ]; do
		case "$1" in
		-o)
			out=$2
			shift 2
			;;
		-*) shift ;;
		*)
			url=$1
			shift
			;;
		esac
	done
	printf '%s\n' "${url}" >>"${work}/dl/calls"
	key=${url//\//_}
	[ -f "${work}/dl/${key}" ] || return 22
	cp "${work}/dl/${key}" "${out}"
}
serve() { # url content
	printf '%s' "$2" >"${work}/dl/${1//\//_}"
}
sha_of() { printf '%s' "$1" | sha256sum | awk '{print $1}'; }
fresh_dl() {
	rm -rf "${work:?}/dl" "${work:?}/out"
	mkdir -p "${work}/dl" "${work}/out"
	: >"${work}/dl/calls"
}
wine_sh() { # runs "$@" with wine-checksums.sh sourced and the fake downloader; output and rc on stdout
	(
		# shellcheck source-path=SCRIPTDIR source=../common/wine-checksums.sh
		. "${root}/common/wine-checksums.sh"
		CURL=fake_curl "$@" 2>&1
		echo "rc=$?"
	)
}
addons_c() { # mono-version gecko-version: the parts of addons.c the script reads, with an arm64 block too
	printf '#define GECKO_VERSION "%s"\n#ifdef __i386__\n#define GECKO_ARCH "x86"\n#define GECKO_SHA "%s"\n#elif defined(__x86_64__)\n#define GECKO_ARCH "x86_64"\n#define GECKO_SHA "%s"\n#else\n#define GECKO_ARCH ""\n#define GECKO_SHA "???"\n#endif\n\n#define MONO_VERSION "%s"\n#if defined(__i386__) || defined(__x86_64__)\n#define MONO_ARCH "x86"\n#define MONO_SHA "%s"\n#elif defined(__aarch64__)\n#define MONO_ARCH "arm64"\n#define MONO_SHA "%s"\n#endif\n' \
		"$2" "$(sha_of gx86)" "$(sha_of gx64)" "$1" "$(sha_of mono)" "$(sha_of monoarm)"
}

fresh_dl
serve https://example.test/a.bin 'hello'
out=$(wine_sh fetch_verified https://example.test/a.bin "${work}/out/a.bin" "$(sha_of hello)")
expect_contains 'a download with the pinned sha256 is kept' "${out}" 'rc=0'
if [ "$(cat "${work}/out/a.bin" 2>/dev/null)" = hello ]; then ok 'it lands at its destination'; else not_ok 'it lands at its destination'; fi

out=$(wine_sh fetch_verified https://example.test/a.bin "${work}/out/b.bin" "$(sha_of other)")
expect_contains 'a download with another sha256 is refused' "${out}" 'checksum mismatch for https://example.test/a.bin'
expect_not_contains 'a refused download fails the step' "${out}" 'rc=0'
if [ ! -e "${work}/out/b.bin" ] && [ ! -e "${work}/out/b.bin.part" ]; then ok 'a refused download leaves no file'; else not_ok 'a refused download leaves no file' "$(ls "${work}/out")"; fi
out=$(wine_sh fetch_verified https://example.test/missing "${work}/out/c.bin" "$(sha_of x)")
expect_contains 'a failed download fails the step' "${out}" 'download failed: https://example.test/missing'

# Every pinned value is a sha256, and the versions images use today are pinned.
pins=$(sed -n 's/.*) echo \([^ ;]*\) ;;$/\1/p; s/.*) echo '\''[0-9a-f]* \([^'\'']*\)'\'' ;;$/\1/p' "${root}/common/wine-checksums.sh")
if [ -n "${pins}" ] && ! grep -qvE '^[0-9a-f]{64}$' <<<"${pins}"; then ok 'every pin is a sha256'; else not_ok 'every pin is a sha256' "${pins}"; fi
for f in "${root}"/images/wine*/Dockerfile; do
	tag=$(sed -n 's/^ARG WINETRICKS_VERSION=//p' "${f}")
	out=$(wine_sh winetricks_pin "${tag}")
	expect_contains "winetricks ${tag} ($(basename "$(dirname "${f}")")) is pinned" "${out}" 'rc=0'
done

# The addons: an unpinned version stops the build before any download, naming addons.c's value.
fresh_dl
out=$(wine_sh install_addons "$(addons_c 99.0.0 2.47.4)" "${work}/out/mono" "${work}/out/gecko")
expect_contains 'an unpinned Wine Mono version fails' "${out}" 'no known sha256 for Wine Mono 99.0.0 (x86)'
expect_contains 'the failure names the x86 sha256 from addons.c (not arm64)' "${out}" "addons.c says $(sha_of mono)"
expect_not_contains 'an unpinned version fails the step' "${out}" 'rc=0'
if [ ! -s "${work}/dl/calls" ]; then ok 'nothing is downloaded for an unpinned version'; else not_ok 'nothing is downloaded for an unpinned version' "$(cat "${work}/dl/calls")"; fi
out=$(wine_sh install_addons "$(addons_c 11.3.0 9.9.9)" "${work}/out/mono" "${work}/out/gecko")
expect_contains 'an unpinned Wine Gecko version fails, per arch' "${out}" 'no known sha256 for Wine Gecko 9.9.9 (x86_64)'

# Pinned versions whose download doesn't match (here: the fake files) are refused.
fresh_dl
serve https://dl.winehq.org/wine/wine-mono/11.3.0/wine-mono-11.3.0-x86.msi 'not the real msi'
out=$(wine_sh install_addons "$(addons_c 11.3.0 2.47.4)" "${work}/out/mono" "${work}/out/gecko")
expect_contains 'a pinned Mono version with another file is refused' "${out}" 'checksum mismatch for https://dl.winehq.org/wine/wine-mono/11.3.0/wine-mono-11.3.0-x86.msi'
if [ ! -e "${work}/out/mono/wine-mono-11.3.0-x86.msi" ]; then ok 'the refused Mono installer is not kept'; else not_ok 'the refused Mono installer is not kept'; fi

# With matching files (the pins swapped for the fake files' sums), all three land where Wine looks.
fresh_dl
serve https://dl.winehq.org/wine/wine-mono/11.3.0/wine-mono-11.3.0-x86.msi mono
serve https://dl.winehq.org/wine/wine-gecko/2.47.4/wine-gecko-2.47.4-x86.msi gx86
serve https://dl.winehq.org/wine/wine-gecko/2.47.4/wine-gecko-2.47.4-x86_64.msi gx64
fake_pins() {
	# shellcheck disable=SC2317 # called by install_addons
	addon_sha256() {
		case "$1/$3" in
		mono/x86) sha_of mono ;;
		gecko/x86) sha_of gx86 ;;
		gecko/x86_64) sha_of gx64 ;;
		esac
	}
	install_addons "$@"
}
out=$(wine_sh fake_pins "$(addons_c 11.3.0 2.47.4)" "${work}/out/mono" "${work}/out/gecko")
expect_contains 'matching Mono and Gecko installers are installed' "${out}" 'rc=0'
if [ -f "${work}/out/mono/wine-mono-11.3.0-x86.msi" ] && [ -f "${work}/out/gecko/wine-gecko-2.47.4-x86.msi" ] &&
	[ -f "${work}/out/gecko/wine-gecko-2.47.4-x86_64.msi" ]; then
	ok 'the installers are in the Mono and Gecko folders'
else
	not_ok 'the installers are in the Mono and Gecko folders' "$(find "${work}/out")"
fi

# winetricks comes from the pinned commit, not the movable tag, and is checked too.
fresh_dl
out=$(wine_sh install_winetricks 19990101 "${work}/out/winetricks")
expect_contains 'an unpinned winetricks tag fails' "${out}" 'no pinned commit/sha256 for winetricks 19990101'
serve https://raw.githubusercontent.com/Winetricks/winetricks/b76e1ee79ac57d7aceb384f74518fc423265810c/src/winetricks '#!/bin/sh'
out=$(wine_sh install_winetricks 20260125 "${work}/out/winetricks")
expect_contains 'winetricks is fetched by commit' "$(cat "${work}/dl/calls")" '/b76e1ee79ac57d7aceb384f74518fc423265810c/src/winetricks'
expect_contains 'a winetricks file with another sha256 is refused' "${out}" 'checksum mismatch'
if [ ! -e "${work}/out/winetricks" ]; then ok 'the refused winetricks is not installed'; else not_ok 'the refused winetricks is not installed'; fi

# --- supply chain: workflows, scripts/scan.sh, scripts/sign.sh (test/supply-chain.sh) ---------------------
# shellcheck source=test/supply-chain.sh
. "${here}/supply-chain.sh"

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
