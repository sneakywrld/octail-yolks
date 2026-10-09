#!/bin/bash
# Which images to build, as a JSON array for a GitHub Actions matrix ({tag, folder, platforms}):
#   select-images.sh all
#   select-images.sh changed <base-sha> <head-sha>   images whose folder changed; everything when common/,
#                                                    images.json or the workflow changed (or base is unknown)
#   select-images.sh java_21,wine                    the named tags
# Run from the repository root (needs jq and, for `changed`, git).
set -euo pipefail

images_json=${IMAGES_JSON:-images.json}
mode=${1:-all}

all_tags() { jq -r '.images[].tag' "${images_json}"; }

matrix() { # tags on stdin
	jq -R . | jq -s --slurpfile db "${images_json}" -c '
		. as $want
		| [ $db[0].images[] | select(.tag as $t | $want | index($t))
		    | { tag, folder, platforms: (.platforms | join(",")) } ]'
}

case "${mode}" in
all)
	all_tags | matrix
	;;
changed)
	base=${2:-}
	head=${3:-HEAD}
	if [ -z "${base}" ] || [[ ${base} =~ ^0+$ ]] || ! git cat-file -e "${base}^{commit}" 2>/dev/null; then
		all_tags | matrix
		exit 0
	fi
	# --relative: paths from here, so this also works inside the monorepo the repository is split from.
	files=$(git diff --relative --name-only "${base}" "${head}")
	if grep -qE '^(common/|images\.json$|\.github/workflows/build\.yml$)' <<<"${files}"; then
		all_tags | matrix
		exit 0
	fi
	jq -r '.images[] | "\(.tag) \(.folder)"' "${images_json}" | while read -r tag folder; do
		if grep -q "^${folder}/" <<<"${files}"; then
			echo "${tag}"
		fi
	done | matrix
	;;
*)
	tr ',' '\n' <<<"${mode}" | sed '/^$/d' | while read -r tag; do
		if ! jq -e --arg t "${tag}" '.images[] | select(.tag == $t)' "${images_json}" >/dev/null; then
			echo "unknown image tag: ${tag}" >&2
			exit 1
		fi
		echo "${tag}"
	done | matrix
	;;
esac
