#!/bin/bash
# The machine-readable build report, stats/images.json (schema: README.md, "Build report"):
#   scripts/report.sh fact <tag> <folder>      after an image's build: the facts of the published image (digest,
#                                              compressed size per platform, build date, revision, fingerprint, from
#                                              the registry) and of this run's scan (<folder>/<tag>.scan.json from
#                                              scripts/scan.sh) -> <folder>/<tag>.stats.json
#   scripts/report.sh merge <previous> <dir>   the report with every <dir>/*.stats.json replacing its tag's entry in
#                                              <previous> (a file, or empty for none), in images.json order, tags no
#                                              longer in images.json dropped -> stdout
#   scripts/report.sh publish <dir>            merge into stats/images.json on the `stats` branch of the git remote
#                                              and push it (CI's report job; retried when another run pushed first)
# The report lives on its own branch because main is published from the monorepo (publish-github.sh pushes it as a
# fast-forward of the split history): a CI commit on main would break the next publish.
#
# Environment: IMAGES_JSON (default: images.json next to this script's folder), DOCKER (default docker; the tests use
# a fake), PUSHED (fact: 1 when this run pushed the image, 0 when the content check skipped the push), CHECKED_AT
# (fact: default now), RUN_URL (merge: the workflow run, recorded as `source`), GENERATED_AT (merge: default now),
# STATS_REMOTE (publish: default origin), STATS_BRANCH (publish: default stats), STATS_OUT (publish: also write the
# merged report to this file), GIT (default git).
# Exit: 0 done, 1 a step failed, 2 usage.
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
images_json=${IMAGES_JSON:-${here}/../images.json}
docker=${DOCKER:-docker}
git=${GIT:-git}
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

usage() {
	echo 'usage: report.sh fact <tag> <folder> | merge <previous file or ""> <facts folder> | publish <facts folder>' >&2
	exit 2
}

# fact <tag> <folder>
fact() {
	local tag=$1 dir=$2 entry registry ref manifest digest raw config sizes='{}' scan='{}' platform pdigest size
	entry=$(jq -c --arg t "${tag}" '.images[] | select(.tag == $t)' "${images_json}") || return 2
	if [ -z "${entry}" ]; then
		echo "report: unknown image tag: ${tag}" >&2
		return 2
	fi
	registry=$(jq -r '.registry' "${images_json}")
	ref="${registry}:${tag}"
	if [ -f "${dir}/${tag}.scan.json" ]; then scan=$(jq -c . "${dir}/${tag}.scan.json" 2>/dev/null || echo '{}'); fi

	# The published image: its digest, its platforms' compressed sizes (layers + config, as pulled) and its labels.
	digest=''
	config='{}'
	if manifest=$("${docker}" buildx imagetools inspect --format '{{json .Manifest}}' "${ref}" 2>/dev/null) &&
		digest=$(jq -er '.digest | select(startswith("sha256:"))' <<<"${manifest}" 2>/dev/null) &&
		raw=$("${docker}" buildx imagetools inspect --raw "${registry}@${digest}" 2>/dev/null); then
		if jq -e '.manifests' <<<"${raw}" >/dev/null 2>&1; then
			while read -r platform pdigest; do
				[ -n "${platform}" ] || continue
				size=$("${docker}" buildx imagetools inspect --raw "${registry}@${pdigest}" 2>/dev/null |
					jq '([.layers[]?.size] | add // 0) + (.config.size // 0)' 2>/dev/null) || continue
				sizes=$(jq -c --arg p "${platform}" --argjson s "${size}" '.[$p] = $s' <<<"${sizes}")
			done < <(jq -r '.manifests[] | select(.platform.os != "unknown" and .platform.architecture != "unknown")
				| "\(.platform.os)/\(.platform.architecture)\(if .platform.variant then "/" + .platform.variant else "" end) \(.digest)"' <<<"${raw}")
		else
			size=$(jq '([.layers[]?.size] | add // 0) + (.config.size // 0)' <<<"${raw}")
			sizes=$(jq -c --argjson s "${size}" '{"linux/amd64": $s}' <<<'{}')
		fi
		config=$("${docker}" buildx imagetools inspect --format '{{json .Image}}' "${ref}" 2>/dev/null |
			jq -c 'if (has("config") or has("rootfs")) then . else (.["linux/amd64"] // ([.[]][0])) end' 2>/dev/null) || config='{}'
		if [ -z "${config}" ]; then config='{}'; fi
	else
		echo "report: ${ref} is not published (or not readable): digest and sizes left empty" >&2
	fi

	jq -n --argjson entry "${entry}" --arg registry "${registry}" --arg digest "${digest}" --argjson sizes "${sizes}" \
		--argjson config "${config}" --argjson scan "${scan}" --arg pushed "${PUSHED:-1}" \
		--arg checked "${CHECKED_AT:-$(now)}" '
		($config.config.Labels // {}) as $l
		| {
			tag: $entry.tag,
			image: "\($registry):\($entry.tag)",
			kind: $entry.kind,
			digest: (if $digest == "" then null else $digest end),
			platforms: $entry.platforms,
			compressedSize: $sizes,
			base: ($scan.base // null),
			builtAt: ($l["org.opencontainers.image.created"] // null),
			revision: ($l["org.opencontainers.image.revision"] // null),
			fingerprint: ($l["org.octail.yolks.fingerprint"] // null),
			pushed: ($pushed == "1"),
			checkedAt: $checked,
			vulnerabilities: ($scan.vulnerabilities // null),
			fixable: ($scan.fixable // null),
			scan: (if $scan.platform then {platform: $scan.platform, scanner: $scan.scanner, policy: $scan.policy} else null end)
		}' >"${dir}/${tag}.stats.json" || return 1
	echo "report: ${tag}: $(jq -c '{digest, compressedSize, vulnerabilities}' "${dir}/${tag}.stats.json")"
}

# merge <previous file or ""> <facts folder>
merge() {
	local previous=$1 dir=$2 prev='{}' facts
	if [ -n "${previous}" ] && [ -s "${previous}" ]; then
		prev=$(jq -c . "${previous}") || {
			echo "report: ${previous} is not JSON, starting over" >&2
			prev='{}'
		}
	fi
	shopt -s nullglob
	local files=("${dir}"/*.stats.json)
	shopt -u nullglob
	if [ "${#files[@]}" -gt 0 ]; then facts=$(jq -cs . "${files[@]}") || return 1; else facts='[]'; fi
	jq -n --slurpfile db "${images_json}" --argjson prev "${prev}" --argjson facts "${facts}" \
		--arg generated "${GENERATED_AT:-$(now)}" --arg source "${RUN_URL:-}" '
		($db[0]) as $db
		| (($prev.images // []) | map({key: .tag, value: .}) | from_entries) as $old
		| ($facts | map({key: .tag, value: .}) | from_entries) as $new
		| {
			schema: 1,
			registry: $db.registry,
			generatedAt: $generated,
			source: (if $source == "" then null else $source end),
			images: [$db.images[].tag | ($new[.] // $old[.]) | select(. != null)]
		}'
}

# publish <facts folder>
publish() {
	local dir=$1 remote=${STATS_REMOTE:-origin} branch=${STATS_BRANCH:-stats} attempt parent previous merged blob readme sub tree commit tags parent_args
	local tmp
	tmp=$(mktemp -d) || return 1
	# shellcheck disable=SC2064 # expand now: the folder of this call
	trap "rm -rf '${tmp}'" RETURN
	export GIT_AUTHOR_NAME=${GIT_AUTHOR_NAME:-github-actions[bot]}
	export GIT_AUTHOR_EMAIL=${GIT_AUTHOR_EMAIL:-41898283+github-actions[bot]@users.noreply.github.com}
	export GIT_COMMITTER_NAME=${GIT_COMMITTER_NAME:-${GIT_AUTHOR_NAME}}
	export GIT_COMMITTER_EMAIL=${GIT_COMMITTER_EMAIL:-${GIT_AUTHOR_EMAIL}}
	for ((attempt = 1; attempt <= ${STATS_ATTEMPTS:-5}; attempt++)); do
		parent=''
		previous=''
		if "${git}" fetch --quiet --depth=1 "${remote}" "+refs/heads/${branch}:refs/remotes/${remote}/${branch}" 2>/dev/null; then
			parent=$("${git}" rev-parse "refs/remotes/${remote}/${branch}") || return 1
			if "${git}" show "${parent}:stats/images.json" >"${tmp}/previous.json" 2>/dev/null; then
				previous="${tmp}/previous.json"
			fi
		fi
		merge "${previous}" "${dir}" >"${tmp}/images.json" || return 1
		merged="${tmp}/images.json"
		if [ -n "${STATS_OUT:-}" ]; then cp "${merged}" "${STATS_OUT}" || return 1; fi
		blob=$("${git}" hash-object -w "${merged}") || return 1
		# shellcheck disable=SC2016 # Markdown backticks, not command substitutions
		readme=$(printf '%s\n' '# octail-yolks build report' '' \
			'`stats/images.json` is written by the build workflow (`.github/workflows/build.yml`, report job) after every' \
			'build on main, the weekly rebuild and manual runs. Its schema is in the README on main ("Build report").' \
			'This branch is rewritten by CI only; do not edit it by hand.' | "${git}" hash-object -w --stdin) || return 1
		sub=$(printf '100644 blob %s\timages.json\n' "${blob}" | "${git}" mktree) || return 1
		tree=$(printf '100644 blob %s\tREADME.md\n040000 tree %s\tstats\n' "${readme}" "${sub}" | "${git}" mktree) || return 1
		if [ -n "${parent}" ] && [ "$("${git}" rev-parse "${parent}^{tree}")" = "${tree}" ]; then
			echo "report: stats/images.json unchanged"
			return 0
		fi
		tags=$(cd "${dir}" && find . -maxdepth 1 -name '*.stats.json' | sed 's|^\./||; s|\.stats\.json$||' | LC_ALL=C sort | paste -sd, - | sed 's/,/, /g')
		parent_args=()
		if [ -n "${parent}" ]; then parent_args=(-p "${parent}"); fi
		commit=$("${git}" commit-tree "${tree}" "${parent_args[@]}" -m "stats: ${tags:-no image facts}") || return 1
		if "${git}" push --quiet "${remote}" "${commit}:refs/heads/${branch}"; then
			echo "report: stats/images.json pushed to ${branch} ($(jq '.images | length' "${merged}") images)"
			return 0
		fi
		echo "report: push to ${branch} refused (attempt ${attempt}), fetching and merging again" >&2
		[ "${attempt}" -ge "${STATS_ATTEMPTS:-5}" ] || sleep "${attempt}"
	done
	echo "report: could not push stats/images.json to ${branch}" >&2
	return 1
}

case "${1:-}" in
fact)
	[ "$#" -eq 3 ] || usage
	mkdir -p "$3" || exit 2
	fact "$2" "$3"
	;;
merge)
	[ "$#" -eq 3 ] || usage
	merge "$2" "$3"
	;;
publish)
	[ "$#" -eq 2 ] || usage
	publish "$2"
	;;
*) usage ;;
esac
