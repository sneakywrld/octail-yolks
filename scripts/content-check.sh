#!/bin/bash
# Did this build change the image's content? CI runs it after the scan, before the push, so a rebuild whose content
# is the same as the published image (the weekly rebuild when no base or package moved) pushes nothing:
#   scripts/content-check.sh <tag> <sbom> <output folder>
#   e.g. scripts/content-check.sh java_21 out/java_21.cdx.json out
#
# The image's content fingerprint is the sha256 of (written to <output folder>/<tag>.fingerprint.txt):
#   - the build inputs: every file in the image's folder and in common/ (path and sha256), and its images.json entry
#     (tag, folder, kind, platforms, description; not `eggs`/`replaces`, they don't go into the image);
#   - the digest of every image a FROM line pulls (multi-arch index digests, so a new arm64 base counts too);
#   - the packages in the freshly built image's SBOM (scripts/scan.sh's CycloneDX, linux/amd64): package URLs with
#     their versions, so an apt/apk/language-package upgrade counts even when the base didn't move.
# Timestamps, the build date and the git commit are not part of it: rebuilding the same content gives the same value.
# The pushed image carries it as the label org.octail.yolks.fingerprint; this script reads the published image's
# label and compares.
#
# Prints and (with GITHUB_OUTPUT set) outputs:
#   fingerprint=<sha256>   push=true|false   published=<the published image's fingerprint or empty>   reason=<why>
# push is true when FORCE=1, when nothing is published yet or the published image has no fingerprint, when the
# fingerprint differs, or when it could not be computed (a missing SBOM or base: better a needless push than a
# missed security fix); false only when the published image has the same fingerprint.
#
# Environment: IMAGES_JSON (default: images.json next to this script's folder), DOCKER (default docker; the tests
# use a fake), FORCE (1 = push even when unchanged), GITHUB_OUTPUT, GITHUB_STEP_SUMMARY.
# Exit: 0 decided (either way), 2 usage (unknown tag).
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
images_json=${IMAGES_JSON:-${here}/../images.json}
root=$(cd "$(dirname "${images_json}")" && pwd)
docker=${DOCKER:-docker}
label=org.octail.yolks.fingerprint

if [ "$#" -ne 3 ]; then
	echo 'usage: content-check.sh <tag> <sbom> <output folder>' >&2
	exit 2
fi
tag=$1
sbom=$2
out=$3

entry=$(jq -c --arg t "${tag}" '.images[] | select(.tag == $t) | {tag, folder, kind, platforms, description}' "${images_json}") || exit 2
if [ -z "${entry}" ]; then
	echo "content-check: unknown image tag: ${tag}" >&2
	exit 2
fi
registry=$(jq -r '.registry' "${images_json}")
folder=$(jq -r '.folder' <<<"${entry}")
mkdir -p "${out}" || exit 2

problems=()
lines="${out}/${tag}.fingerprint.txt"
{
	echo "entry ${entry}"
	# Build inputs, by content (the build context is the repository root; images copy from their folder and common/).
	(cd "${root}" && find "${folder}" common -type f 2>/dev/null | LC_ALL=C sort | while IFS= read -r f; do
		printf 'file %s %s\n' "$(sha256sum <"${f}" | cut -d' ' -f1)" "${f}"
	done)
} >"${lines}"

# Every image a FROM pulls (stage names and scratch skipped), by its current digest.
declare -A stages=()
while read -r -a words; do
	if [ "${#words[@]}" -eq 0 ] || [ "${words[0],,}" != from ]; then continue; fi
	i=1
	while [ "${i}" -lt "${#words[@]}" ] && [[ ${words[i]} == --* ]]; do i=$((i + 1)); done
	ref=${words[i]:-}
	as=${words[i + 1]:-}
	name=${words[i + 2]:-}
	if [ "${as,,}" = as ] && [ -n "${name}" ]; then stages[${name,,}]=1; fi
	if [ -z "${ref}" ] || [ "${ref,,}" = scratch ] || [ -n "${stages[${ref,,}]:-}" ]; then continue; fi
	if digest=$("${docker}" buildx imagetools inspect --format '{{json .Manifest}}' "${ref}" 2>/dev/null |
		jq -er '.digest | select(startswith("sha256:"))' 2>/dev/null); then
		echo "base ${ref} ${digest}" >>"${lines}"
	else
		problems+=("the digest of ${ref}")
	fi
done < <(sed 's/\r$//' "${root}/${folder}/Dockerfile" 2>/dev/null)

# The packages of the built image.
if [ -s "${sbom}" ] && pkgs=$(jq -r '[.metadata.component? // empty | select(.type == "operating-system")
	| "os \(.name) \(.version // "")"] + [.components[]? | "pkg \(.purl // "\(.type)/\(.name)@\(.version // "")")"]
	| unique | .[]' "${sbom}" 2>/dev/null); then
	[ -z "${pkgs}" ] || printf '%s\n' "${pkgs}" >>"${lines}"
else
	problems+=("the SBOM ${sbom}")
fi

fingerprint=$(sha256sum <"${lines}" | cut -d' ' -f1)

# The published image's fingerprint (its linux/amd64 config's label; every platform carries the same one).
published=$("${docker}" buildx imagetools inspect --format '{{json .Image}}' "${registry}:${tag}" 2>/dev/null |
	jq -r --arg l "${label}" 'if (has("config") or has("rootfs")) then . else (.["linux/amd64"] // ([.[]][0])) end
		| .config.Labels[$l] // empty' 2>/dev/null) || published=''

if [ "${FORCE:-0}" = 1 ]; then
	push=true reason='forced'
elif [ "${#problems[@]}" -gt 0 ]; then
	push=true reason="could not read $(
		IFS=,
		echo "${problems[*]}"
	), pushing to be safe"
elif [ -z "${published}" ]; then
	push=true reason="nothing published with a fingerprint yet"
elif [ "${published}" = "${fingerprint}" ]; then
	push=false reason='unchanged: same base digests, packages and inputs as the published image'
else
	push=true reason='content changed'
fi

echo "content-check: ${tag}: fingerprint ${fingerprint} (published: ${published:-none}): push=${push} (${reason})"
if [ -n "${GITHUB_OUTPUT:-}" ]; then
	{
		echo "fingerprint=${fingerprint}"
		echo "push=${push}"
		echo "published=${published}"
		echo "reason=${reason}"
	} >>"${GITHUB_OUTPUT}"
fi
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
	{
		echo "#### Content: \`${tag}\`"
		echo
		echo "Fingerprint \`${fingerprint}\`, published \`${published:-none}\`: **$([ "${push}" = true ] && echo push || echo 'no push')** (${reason})."
		echo
	} >>"${GITHUB_STEP_SUMMARY}"
fi
exit 0
