#!/bin/bash
# Vulnerability scan and SBOM of a built image (CI runs it after the boot test, before the push):
#   scripts/scan.sh <image reference> <tag> <output folder>     e.g. scripts/scan.sh octail-yolks-smoke:java_21 java_21 out
#
# Writes to <output folder>:
#   <tag>.trivy.json    Trivy's full report (vulnerabilities of every severity, after .trivyignore)
#   <tag>.sarif         HIGH and CRITICAL only, for GitHub code scanning
#   <tag>.cdx.json      the image's SBOM (CycloneDX)
# and prints (and, with GITHUB_STEP_SUMMARY set, adds to the job summary) a table of the HIGH and CRITICAL findings.
#
# The policy (docs/dev/yolks.md, "Vulnerability scans"): the scan fails only on a CRITICAL vulnerability that has a
# fixed version AND sits in a layer we added. Findings in the base image's own layers (the final stage's FROM) are
# reported, never fatal: they are fixed by the base's publisher and picked up by the weekly rebuild. Unfixable
# findings are reported, never fatal. A finding Trivy can't place in a layer counts as ours. Exceptions go into
# yolks/.trivyignore with a reason and an expiry date (test/check-workflows.sh enforces both).
#
# Environment: IMAGES_JSON (default: images.json next to this script's folder), DOCKER (default docker), TRIVY
# (default trivy; the tests use fakes for both), SCAN_PLATFORM (default linux/amd64: the platform of the image and of
# the base whose layers are compared), TRIVY_IGNOREFILE (default: yolks/.trivyignore).
# Exit: 0 passed, 1 a fixable CRITICAL in our layers, 2 usage or tool error (unknown tag, base not pullable, no scan).
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
images_json=${IMAGES_JSON:-${here}/../images.json}
docker=${DOCKER:-docker}
trivy=${TRIVY:-trivy}
platform=${SCAN_PLATFORM:-linux/amd64}
ignorefile=${TRIVY_IGNOREFILE:-${here}/../.trivyignore}

if [ "$#" -ne 3 ]; then
	echo 'usage: scan.sh <image reference> <tag> <output folder>' >&2
	exit 2
fi
image=$1
tag=$2
out=$3

folder=$(jq -r --arg t "${tag}" '.images[] | select(.tag == $t) | .folder' "${images_json}") || exit 2
if [ -z "${folder}" ]; then
	echo "scan: unknown image tag: ${tag}" >&2
	exit 2
fi
dockerfile="$(dirname "${images_json}")/${folder}/Dockerfile"
if [ ! -f "${dockerfile}" ]; then
	echo "scan: ${dockerfile} does not exist" >&2
	exit 2
fi
mkdir -p "${out}" || exit 2

# The image the final stage starts from, following stage names (FROM build AS x ... FROM x).
final_base() {
	local line ref as name i words
	local -A stages=()
	ref=''
	while IFS= read -r line || [ -n "${line}" ]; do
		read -r -a words <<<"${line}"
		if [ "${#words[@]}" -eq 0 ] || [ "${words[0],,}" != from ]; then continue; fi
		i=1
		while [ "${i}" -lt "${#words[@]}" ] && [[ ${words[i]} == --* ]]; do i=$((i + 1)); done
		ref=${words[i]:-}
		as=${words[i + 1]:-}
		name=${words[i + 2]:-}
		if [ -n "${stages[${ref,,}]:-}" ]; then ref=${stages[${ref,,}]}; fi
		if [ "${as,,}" = as ] && [ -n "${name}" ]; then stages[${name,,}]=${ref}; fi
	done <"$1"
	printf '%s' "${ref}"
}

base=$(final_base "${dockerfile}")
base_layers='[]'
if [ -z "${base}" ]; then
	echo "scan: ${dockerfile} has no FROM" >&2
	exit 2
elif [ "${base,,}" != scratch ]; then
	if ! "${docker}" pull --quiet --platform "${platform}" "${base}" >/dev/null ||
		! base_layers=$("${docker}" image inspect --format '{{json .RootFS.Layers}}' "${base}") ||
		! jq -e 'type == "array"' <<<"${base_layers}" >/dev/null; then
		echo "scan: could not read the layers of the base image ${base} (${platform})" >&2
		exit 2
	fi
fi
echo "scan: ${tag}: base ${base} ($(jq length <<<"${base_layers}") layers)"

common=(image --quiet --scanners vuln --timeout 20m)
[ -f "${ignorefile}" ] && common+=(--ignorefile "${ignorefile}")
report="${out}/${tag}.trivy.json"
if ! "${trivy}" "${common[@]}" --format json --output "${report}" "${image}" ||
	! jq -e '.Results != null or .ArtifactName != null' "${report}" >/dev/null 2>&1; then
	echo "scan: trivy could not scan ${image}" >&2
	exit 2
fi
"${trivy}" "${common[@]}" --severity HIGH,CRITICAL --format sarif --output "${out}/${tag}.sarif" "${image}" ||
	echo "scan: trivy could not write the SARIF report" >&2
# SBOM: packages only (no vulnerabilities, they go stale); attested to the pushed image by scripts/sign.sh.
"${trivy}" image --quiet --format cyclonedx --output "${out}/${tag}.cdx.json" "${image}" ||
	echo "scan: trivy could not write the SBOM" >&2

# One row per HIGH/CRITICAL finding (package + id, deduplicated), with where it is and whether a fix exists.
rows=$(jq -c --argjson base "${base_layers}" '
	[.Results[]? | .Target as $target | .Vulnerabilities[]?
		| select(.Severity == "CRITICAL" or .Severity == "HIGH")
		| (.Layer.DiffID // "") as $diff
		| {id: .VulnerabilityID, sev: .Severity, pkg: .PkgName, installed: (.InstalledVersion // ""),
			fixed: (.FixedVersion // ""), target: $target,
			ours: (($diff == "") or (any($base[]; . == $diff) | not))}]
	| unique_by([.sev, .id, .pkg, .installed, .target]) | sort_by(.sev != "CRITICAL", (.fixed == ""), (.ours | not), .id)
' "${report}") || exit 2
gate=$(jq -c '[.[] | select(.sev == "CRITICAL" and .fixed != "" and .ours)]' <<<"${rows}")
gate_n=$(jq length <<<"${gate}")

count() { jq --arg s "$1" "[.[] | select(.sev == \$s $2)] | length" <<<"${rows}"; }
table() {
	echo "| Severity | Findings | Fix available | In our layers | Fix available, in our layers |"
	echo "| --- | --- | --- | --- | --- |"
	for sev in CRITICAL HIGH; do
		echo "| ${sev} | $(count "${sev}" '') | $(count "${sev}" 'and .fixed != ""') | $(count "${sev}" 'and .ours') | $(count "${sev}" 'and .fixed != "" and .ours') |"
	done
}
findings() { # the first 100 rows as a markdown table
	echo "| Severity | ID | Package | Installed | Fixed in | Layer | Where |"
	echo "| --- | --- | --- | --- | --- | --- | --- |"
	jq -r '.[:100][] | "| \(.sev) | \(.id) | \(.pkg) | \(.installed) | \(if .fixed == "" then "–" else .fixed end) | \(if .ours then "ours" else "base" end) | \(.target | gsub("\\|"; "/")) |"' <<<"$1"
	local n
	n=$(jq length <<<"$1")
	[ "${n}" -le 100 ] || echo "| … | $((n - 100)) more in the report artifact | | | | | |"
}

if [ "${gate_n}" = 0 ]; then
	verdict='passed (no fixable CRITICAL in our layers)'
else
	verdict="FAILED: ${gate_n} fixable CRITICAL finding(s) in our layers"
fi
echo "scan: ${tag} (${platform})"
table
echo "scan: ${tag} ${verdict}"
[ "${gate_n}" = 0 ] || findings "${gate}" >&2

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
	{
		echo "#### Vulnerabilities: \`${tag}\` (${platform}, base \`${base}\`)"
		echo
		table
		echo
		echo "Policy: ${verdict}."
		if [ "${gate_n}" != 0 ]; then
			echo
			findings "${gate}"
		fi
		if [ "$(jq length <<<"${rows}")" != 0 ]; then
			echo
			echo "<details><summary>HIGH and CRITICAL findings</summary>"
			echo
			findings "${rows}"
			echo
			echo "</details>"
		fi
		echo
	} >>"${GITHUB_STEP_SUMMARY}"
fi

[ "${gate_n}" = 0 ]
