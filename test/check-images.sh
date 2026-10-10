#!/bin/bash
# Static checks of images/ and images.json, no Docker needed (run by test/run.sh and CI):
#   - every images/<folder> is in images.json and every images.json entry has a folder with a Dockerfile;
#   - tags are unique;
#   - no Dockerfile starts from or copies from a Pterodactyl / Pelican / parkervcp / pelican-eggs image, nor
#     from any image that isn't on the allowlist in bases.txt. Build stages of the same Dockerfile are fine; an
#     image named through a variable (FROM ${BASE}) fails, since it can't be checked;
#   - (the repository only) .github/dependabot.yml is what scripts/dependabot.sh prints, and README.md's tag table
#     has one anchored row per tag.
#   yolks/test/check-images.sh            check the repository
#   yolks/test/check-images.sh <root>     check another tree with the same layout (used by test/run.sh)
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=${1:-$(dirname "${here}")}
repo_mode=0
[ "$#" -eq 0 ] && repo_mode=1
bases_file="${here}/../bases.txt"
[ -f "${root}/bases.txt" ] && bases_file="${root}/bases.txt"

errors=0
err() {
	errors=$((errors + 1))
	printf 'check-images: %s\n' "$1" >&2
}

if ! command -v jq >/dev/null 2>&1; then
	echo 'check-images: jq is needed' >&2
	exit 2
fi

# --- images.json <-> images/ ---------------------------------------------------------------------------
if ! listed=$(jq -r '.images[].folder' "${root}/images.json" | sort); then
	echo "check-images: ${root}/images.json is not valid JSON" >&2
	exit 1
fi
present=$(cd "${root}" && find images -mindepth 1 -maxdepth 1 -type d | sort)
while IFS= read -r folder; do
	[ -n "${folder}" ] || continue
	grep -qxF "${folder}" <<<"${listed}" || err "${folder} is not in images.json"
done <<<"${present}"
while IFS= read -r folder; do
	[ -n "${folder}" ] || continue
	if ! grep -qxF "${folder}" <<<"${present}"; then
		err "images.json lists ${folder}, which does not exist"
	elif [ ! -f "${root}/${folder}/Dockerfile" ]; then
		err "${folder} has no Dockerfile"
	fi
done <<<"${listed}"
dupes=$(jq -r '.images[].tag' "${root}/images.json" | sort | uniq -d)
[ -z "${dupes}" ] || err "tags listed twice in images.json: ${dupes//$'\n'/, }"

# --- base images ---------------------------------------------------------------------------------------
allowed=$(grep -v '^[[:space:]]*\(#\|$\)' "${bases_file}" | tr -d '[:blank:]')

# An image reference without tag/digest, Docker Hub official images without docker.io/library/.
repository() {
	local ref=${1,,}
	ref=${ref%%@*}
	# A tag is the part after the last ':' unless that ':' belongs to a registry host:port.
	if [[ ${ref##*/} == *:* ]]; then ref=${ref%:*}; fi
	ref=${ref#docker.io/}
	ref=${ref#index.docker.io/}
	ref=${ref#library/}
	printf '%s' "${ref}"
}

# check_source <dockerfile> <line no> <image or stage> <stages seen so far, space-separated>
check_source() {
	local file=$1 line=$2 ref=$3 stages=" $4 " repo
	if [[ ${stages} == *" ${ref,,} "* ]]; then return 0; fi
	if [[ ${ref,,} =~ pterodactyl|pelican|parkervcp ]]; then
		err "${file}:${line}: ${ref} is a Pterodactyl/Pelican/parkervcp image; octail-yolks starts from official bases only"
		return 0
	fi
	if [[ ${ref} == *'$'* ]]; then
		err "${file}:${line}: ${ref} is built from a variable, so it can't be checked against bases.txt"
		return 0
	fi
	repo=$(repository "${ref}")
	grep -qxF "${repo}" <<<"${allowed}" ||
		err "${file}:${line}: ${ref} is not an allowed base (yolks/bases.txt)"
}

for dockerfile in "${root}"/images/*/Dockerfile; do
	[ -f "${dockerfile}" ] || continue
	name=${dockerfile#"${root}/"}
	stages=''
	n=0
	# Continuation lines are joined so a `COPY \` + `--from=x` on the next line is still seen.
	logical=''
	start=0
	while IFS= read -r raw || [ -n "${raw}" ]; do
		n=$((n + 1))
		[ -z "${logical}" ] && start=${n}
		if [[ ${raw} == *\\ ]]; then
			logical+="${raw%\\} "
			continue
		fi
		logical+=${raw}
		read -r -a words <<<"${logical}"
		logical=''
		[ "${#words[@]}" -gt 0 ] || continue
		case "${words[0],,}" in
		from)
			i=1
			while [ "${i}" -lt "${#words[@]}" ] && [[ ${words[i]} == --* ]]; do i=$((i + 1)); done
			ref=${words[i]:-}
			if [ -z "${ref}" ]; then
				err "${name}:${start}: FROM without an image"
				continue
			fi
			if [ "${ref,,}" != scratch ]; then check_source "${name}" "${start}" "${ref}" "${stages}"; fi
			as=${words[i + 1]:-}
			stage=${words[i + 2]:-}
			if [ "${as,,}" = as ] && [ -n "${stage}" ]; then stages+=" ${stage,,}"; fi
			;;
		copy | add | run)
			for word in "${words[@]:1}"; do
				case "${word}" in
				--from=*) check_source "${name}" "${start}" "${word#--from=}" "${stages}" ;;
				--mount=*from=*)
					src=${word#*from=}
					src=${src%%,*}
					check_source "${name}" "${start}" "${src}" "${stages}"
					;;
				--*) ;;
				*) break ;;
				esac
			done
			;;
		esac
	done <"${dockerfile}"
done

# --- files kept in sync with images.json (only when checking the repository itself) ---------------------
if [ "${repo_mode}" = 1 ]; then
	if ! expected=$(cd "${root}" && IMAGES_JSON=images.json scripts/dependabot.sh); then
		err 'scripts/dependabot.sh failed'
	elif [ "${expected}" != "$(cat "${root}/.github/dependabot.yml" 2>/dev/null)" ]; then
		err '.github/dependabot.yml is out of date: run scripts/dependabot.sh > .github/dependabot.yml'
	fi
	# Every tag has exactly one row in the README's tag table, starting with its anchor (the octail-eggs README and
	# the Octail docs link to https://github.com/sneakywrld/octail-yolks#<tag>).
	while IFS= read -r tag; do
		[ -n "${tag}" ] || continue
		rows=$(grep -cF "| <a name=\"${tag}\"></a>\`${tag}\` |" "${root}/README.md")
		[ "${rows}" = 1 ] || err "README.md: the tag table should have one row for ${tag} (found ${rows})"
	done < <(jq -r '.images[].tag' "${root}/images.json")
fi

if [ "${errors}" -gt 0 ]; then
	echo "check-images: ${errors} problem(s)" >&2
	exit 1
fi
echo "check-images: $(wc -l <<<"${listed}") images, folders and bases ok"
