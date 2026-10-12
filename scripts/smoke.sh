#!/bin/bash
# Boot test of a built image, run the way Tentacle runs it (CI runs it after the build, before the push):
#   scripts/smoke.sh <image reference> <tag>        e.g. scripts/smoke.sh octail-yolks-smoke:java_21 java_21
#
# The command is the tag's `smoke` field in images.json.
#   runtime images    a game server container: read-only root filesystem, a 100 MB /tmp tmpfs, the server folder
#                     bound writable at /home/container, a non-root uid the image doesn't know (with the two-line
#                     /etc/passwd and /etc/group Tentacle mounts), --cap-drop ALL, no-new-privileges, a PID limit,
#                     and the image's own ENTRYPOINT/CMD (tini -> /entrypoint.sh -> hooks) with STARTUP=<smoke>.
#                     Before the smoke command, the startup checks that PID 1 is tini, the uid isn't 0 and the
#                     server folder is writable; the output must show the entrypoint's "container~" line.
#   installer images  an install container: root, --cap-drop ALL plus the capabilities Tentacle gives installers,
#                     no-new-privileges, the server folder at /mnt/server, the image's own ENTRYPOINT and
#                     `bash -c <smoke>` as the command (Tentacle's is `bash /mnt/install/install.sh`).
# Passes when the container exits 0 within SMOKE_TIMEOUT seconds (default 600). Prints the image's size; with
# GITHUB_STEP_SUMMARY set, adds the tag's size and result (and the output's tail on failure) to the job summary.
#
# Environment: IMAGES_JSON (default: images.json next to this script's folder), DOCKER (default docker; the tests
# use a fake), SMOKE_TIMEOUT, SMOKE_UID / SMOKE_GID (the container user of runtime images; default: the caller's,
# or 1000 when the caller is root, which then hands the server folder to that uid).
# Exit: 0 passed, 1 failed, 2 usage (unknown tag, no smoke command, image not found).
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
images_json=${IMAGES_JSON:-${here}/../images.json}
docker=${DOCKER:-docker}
timeout_s=${SMOKE_TIMEOUT:-600}

if [ "$#" -ne 2 ]; then
	echo 'usage: smoke.sh <image reference> <tag>' >&2
	exit 2
fi
image=$1
tag=$2

entry=$(jq -c --arg t "${tag}" '.images[] | select(.tag == $t)' "${images_json}") || exit 2
if [ -z "${entry}" ]; then
	echo "smoke: unknown image tag: ${tag}" >&2
	exit 2
fi
kind=$(jq -r '.kind // "runtime"' <<<"${entry}")
smoke=$(jq -r '.smoke // ""' <<<"${entry}")
if [ -z "${smoke}" ]; then
	echo "smoke: ${tag} has no smoke command in images.json" >&2
	exit 2
fi

if ! bytes=$("${docker}" image inspect --format '{{.Size}}' "${image}") || ! [[ ${bytes} =~ ^[0-9]+$ ]]; then
	echo "smoke: ${image} is not a local image" >&2
	exit 2
fi
platform=$("${docker}" image inspect --format '{{.Os}}/{{.Architecture}}' "${image}" 2>/dev/null) || platform='?'
size=$(awk -v b="${bytes}" 'BEGIN { printf "%.0f MB", b / 1000000 }')
echo "smoke: ${tag} (${platform}) is ${size} uncompressed"

name="octail-smoke-${tag//[^A-Za-z0-9_.-]/-}-$$"
work=$(mktemp -d)
cleanup() {
	"${docker}" rm -f "${name}" >/dev/null 2>&1
	rm -rf "${work:?}"
}
trap cleanup EXIT
mkdir -p "${work}/server"

args=(run --rm --name "${name}" --security-opt no-new-privileges --cap-drop ALL
	--tmpfs "/tmp:rw,exec,nosuid,size=100m")
case "${kind}" in
installer)
	# Run by bash -c as root inside the container, not here.
	# shellcheck disable=SC2016
	preamble='[ "$(id -u)" = 0 ] || { echo "smoke: the installer does not run as root" >&2; exit 97; }; touch /mnt/server/.octail-smoke || { echo "smoke: /mnt/server is not writable" >&2; exit 97; }; '
	args+=(--user 0:0 --pids-limit 1024
		--cap-add CHOWN --cap-add DAC_OVERRIDE --cap-add FOWNER --cap-add SETUID --cap-add SETGID
		-v "${work}/server:/mnt/server" -w /mnt/server
		"${image}" bash -c "${preamble}${smoke}")
	;;
*)
	uid=${SMOKE_UID:-$(id -u)}
	gid=${SMOKE_GID:-$(id -g)}
	if [ -z "${SMOKE_UID:-}" ] && [ "${uid}" = 0 ]; then
		uid=1000
		gid=1000
	fi
	if [ "${uid}" = 0 ]; then
		echo 'smoke: runtime images are tested as a non-root user; SMOKE_UID must not be 0' >&2
		exit 2
	fi
	[ "$(id -u)" = 0 ] && chown "${uid}:${gid}" "${work}/server"
	printf 'root:x:0:0:root:/root:/bin/sh\ncontainer:x:%s:%s:container:/home/container:/usr/sbin/nologin\n' \
		"${uid}" "${gid}" >"${work}/passwd"
	printf 'root:x:0:\ncontainer:x:%s:\n' "${gid}" >"${work}/group"
	# Evaluated by the image's entrypoint, not here.
	# shellcheck disable=SC2016
	preamble='[ "$(cat /proc/1/comm)" = tini ] || { echo "smoke: PID 1 is $(cat /proc/1/comm), not tini" >&2; exit 97; }; [ "$(id -u)" != 0 ] || { echo "smoke: the server runs as root" >&2; exit 97; }; touch /home/container/.octail-smoke || { echo "smoke: /home/container is not writable" >&2; exit 97; }; '
	args+=(--read-only --user "${uid}:${gid}" --pids-limit 512
		-v "${work}/server:/home/container"
		-v "${work}/passwd:/etc/passwd:ro,z" -v "${work}/group:/etc/group:ro,z"
		-e "STARTUP=${preamble}${smoke}" -e TZ=UTC -e SERVER_MEMORY=1024 -e SERVER_IP=0.0.0.0 -e SERVER_PORT=25565
		"${image}")
	;;
esac

echo "smoke: ${kind} ${tag}: ${smoke}"
started=${SECONDS}
timeout --kill-after=10 "${timeout_s}" "${docker}" "${args[@]}" 2>&1 | tee "${work}/out"
rc=${PIPESTATUS[0]}
took=$((SECONDS - started))

result=''
if [ "${rc}" = 124 ]; then
	result="timed out after ${timeout_s} s"
elif [ "${rc}" != 0 ]; then
	result="exit code ${rc}"
elif [ "${kind}" != installer ] && ! grep -qF 'container~ ' "${work}/out"; then
	result='the entrypoint never printed its "container~" startup line'
fi

if [ -z "${result}" ]; then
	verdict="passed in ${took} s"
	echo "smoke: ${tag} ${verdict}"
else
	verdict="FAILED: ${result}"
	echo "smoke: ${tag} ${verdict}" >&2
fi

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
	{
		echo "| Tag | Kind | Platform | Size (uncompressed) | Boot test |"
		echo "| --- | --- | --- | --- | --- |"
		echo "| \`${tag}\` | ${kind} | ${platform} | ${size} | ${verdict} |"
		if [ -n "${result}" ]; then
			echo
			echo "<details><summary>Last 40 lines of the output</summary>"
			echo
			echo '```text'
			# shellcheck disable=SC2016
			tail -n 40 "${work}/out" | sed 's/```/` ` `/g; s/\x1b\[[0-9;]*m//g'
			echo '```'
			echo
			echo "</details>"
		fi
	} >>"${GITHUB_STEP_SUMMARY}"
fi

[ -z "${result}" ]
