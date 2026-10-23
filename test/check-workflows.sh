#!/bin/bash
# Static checks of the CI workflows and the supply-chain files, no Docker or network needed (run by test/run.sh and CI):
#   - every `uses:` in .github/workflows/*.yml and .github/actions/*/action.yml is pinned to a full commit SHA with
#     its version as a comment (`owner/repo@<40 hex> # v1.2.3`, the form Dependabot keeps updated), a local action
#     (`./…`) or a `docker://…@sha256:` image;
#   - every workflow sets top-level `permissions:` (the GITHUB_TOKEN is read-only unless a job asks for more);
#   - every tool a workflow downloads with curl from a release page is checked against a pinned sha256
#     (every `${<NAME>_VERSION}` a curl line uses needs a `<NAME>_SHA256` env, and a `sha256sum -c` must run);
#   - build.yml keeps the supply-chain steps in order: boot test, vulnerability scan, SARIF upload, content check,
#     push, signing, build report, with Trivy and cosign at pinned versions and the permissions they need; the push
#     carries BuildKit's SBOM and SLSA provenance and only happens when the content check says so; the weekly
#     schedule and the manual run (image filter, force) stay; only the report job may write to the repository;
#   - .github/dependabot.yml updates the github-actions ecosystem;
#   - every entry in .trivyignore has a reason (a comment line right above it) and an expiry date (exp:YYYY-MM-DD);
#   - actionlint, when it is on PATH (or ACTIONLINT names it), finds nothing (it runs shellcheck on `run:` blocks
#     when shellcheck is on PATH too).
#   yolks/test/check-workflows.sh            check the repository
#   yolks/test/check-workflows.sh <root>     check another tree with the same layout (used by test/run.sh)
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=${1:-$(dirname "${here}")}

errors=0
err() {
	errors=$((errors + 1))
	printf 'check-workflows: %s\n' "$1" >&2
}

shopt -s nullglob
workflows=("${root}"/.github/workflows/*.yml "${root}"/.github/workflows/*.yaml)
actions=("${root}"/.github/actions/*/action.yml "${root}"/.github/actions/*/action.yaml)
[ "${#workflows[@]}" -gt 0 ] || err "no workflows in ${root}/.github/workflows"

# --- actions pinned by SHA -----------------------------------------------------------------------------
sha_re='^[A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+@[0-9a-f]{40}$'
for file in "${workflows[@]}" "${actions[@]}"; do
	name=${file#"${root}/"}
	n=0
	while IFS= read -r line || [ -n "${line}" ]; do
		n=$((n + 1))
		[[ ${line} =~ ^[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]*(.*)$ ]] || continue
		value=${BASH_REMATCH[2]}
		comment=''
		if [[ ${value} == *'#'* ]]; then
			comment=${value#*#}
			value=${value%%#*}
		fi
		value=${value%"${value##*[![:space:]]}"}
		value=${value//\"/}
		value=${value//\'/}
		case "${value}" in
		./*) continue ;;
		docker://*)
			[[ ${value} =~ @sha256:[0-9a-f]{64}$ ]] || err "${name}:${n}: ${value} is not pinned by digest (docker://…@sha256:…)"
			continue
			;;
		esac
		if ! [[ ${value} =~ ${sha_re} ]]; then
			err "${name}:${n}: ${value} is not pinned to a full commit SHA (owner/repo@<40 hex> # vX.Y.Z)"
		elif ! [[ ${comment} =~ ^[[:space:]]*v?[0-9]+(\.[0-9]+)*[[:space:]]*$ ]]; then
			err "${name}:${n}: ${value} needs its version as a comment (# vX.Y.Z) so Dependabot can keep it updated"
		fi
	done <"${file}"
done

# --- permissions and tool downloads ---------------------------------------------------------------------
for file in "${workflows[@]}"; do
	name=${file#"${root}/"}
	grep -qE '^permissions:' "${file}" || err "${name}: no top-level permissions: (set contents: read and widen per job)"
	# The version variables named in curl lines (${HADOLINT_VERSION}, ${ACTIONLINT_VERSION}, ...).
	while IFS= read -r var; do
		grep -qE "^[[:space:]]+${var}_SHA256:[[:space:]]*\"?[0-9a-f]{64}\"?[[:space:]]*$" "${file}" ||
			err "${name}: ${var}_VERSION is downloaded but has no ${var}_SHA256 (a pinned sha256 of the download)"
	done < <(grep -E 'curl ' "${file}" | grep -oE '\$\{?[A-Z0-9_]+_VERSION' | sed -E 's/^\$\{?//; s/_VERSION$//' | sort -u)
	if grep -qE 'curl .*releases/download' "${file}" && ! grep -qE 'sha256sum (-c|--check)' "${file}"; then
		err "${name}: release downloads without a sha256sum -c check"
	fi
done

# --- build.yml: scan before push, sign after -------------------------------------------------------------
build="${root}/.github/workflows/build.yml"
if [ -f "${build}" ]; then
	line_of() { grep -nE "$1" "${build}" | head -n 1 | cut -d: -f1; }
	order=('name: Boot test' 'name: Vulnerability scan' 'upload-sarif@' 'name: Content check' 'name: Build and push'
		'name: Sign' 'name: Build report' '^  report:')
	prev=0
	prev_name=''
	for step in "${order[@]}"; do
		at=$(line_of "${step}")
		if [ -z "${at}" ]; then
			err ".github/workflows/build.yml: no '${step}' step"
		elif [ "${at}" -le "${prev}" ]; then
			err ".github/workflows/build.yml: '${step}' must come after '${prev_name}'"
		else
			prev=${at}
		fi
		prev_name=${step}
	done
	# shellcheck disable=SC2016 # literal GitHub expressions (${{ … }}), not shell ones
	for needle in 'scripts/scan.sh' 'scripts/sign.sh' 'id-token: write' 'security-events: write' \
		'aquasecurity/setup-trivy@' 'sigstore/cosign-installer@' 'actions/upload-artifact@' \
		'scripts/content-check.sh' 'scripts/report.sh fact' 'scripts/report.sh publish' 'provenance: mode=max' \
		'sbom: true' 'org.octail.yolks.fingerprint=${{ steps.check.outputs.fingerprint }}' \
		"push: \${{ github.event_name != 'pull_request' && steps.check.outputs.push == 'true' }}" \
		'actions/download-artifact@' 'scripts/select-images.sh' 'force:'; do
		grep -qF "${needle}" "${build}" || err ".github/workflows/build.yml: ${needle} is missing"
	done
	for tool in TRIVY COSIGN; do
		grep -qE "^[[:space:]]+${tool}_VERSION:[[:space:]]*v[0-9]+\.[0-9]+\.[0-9]+[[:space:]]*$" "${build}" ||
			err ".github/workflows/build.yml: ${tool}_VERSION must be an exact version (vX.Y.Z), never latest"
	done
	# Signing and pushing never happen for pull requests.
	if ! grep -A3 -E 'name: Sign' "${build}" | grep -qF "github.event_name != 'pull_request'"; then
		err ".github/workflows/build.yml: the Sign step must not run for pull requests"
	fi
	# The weekly rebuild (base images' security fixes).
	grep -qE '^[[:space:]]+-[[:space:]]+cron:' "${build}" || err ".github/workflows/build.yml: no weekly schedule (cron)"
	# Least privilege: contents: write only in the report job (it pushes the stats branch, never main).
	report_at=$(line_of '^  report:')
	while IFS=: read -r at _; do
		[ -n "${at}" ] || continue
		if [ -z "${report_at}" ] || [ "${at}" -lt "${report_at}" ]; then
			err ".github/workflows/build.yml:${at}: contents: write outside the report job"
		fi
	done < <(grep -nE '^[[:space:]]+contents:[[:space:]]*write' "${build}")
	if ! grep -A1 -E '^permissions:' "${build}" | grep -qE '^[[:space:]]+contents:[[:space:]]*read'; then
		err ".github/workflows/build.yml: the top-level permissions must be contents: read"
	fi
fi

dependabot="${root}/.github/dependabot.yml"
if [ -f "${dependabot}" ]; then
	grep -qE 'package-ecosystem:[[:space:]]*"?github-actions' "${dependabot}" ||
		err '.github/dependabot.yml: no github-actions updates (the SHA pins would go stale)'
else
	err '.github/dependabot.yml is missing'
fi

# --- .trivyignore ---------------------------------------------------------------------------------------
if [ -f "${root}/.trivyignore" ]; then
	n=0
	previous=''
	while IFS= read -r line || [ -n "${line}" ]; do
		n=$((n + 1))
		trimmed=${line#"${line%%[![:space:]]*}"}
		if [ -n "${trimmed}" ] && [[ ${trimmed} != '#'* ]]; then
			[[ ${trimmed} =~ ^[A-Za-z0-9._:-]+[[:space:]]+exp:[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] ||
				err ".trivyignore:${n}: '${trimmed}' needs an expiry date (<ID> exp:YYYY-MM-DD)"
			[[ ${previous} =~ ^[[:space:]]*#[[:space:]]*[^[:space:]] ]] ||
				err ".trivyignore:${n}: '${trimmed}' needs a comment line right above it saying why"
		fi
		previous=${line}
	done <"${root}/.trivyignore"
fi

# --- actionlint ------------------------------------------------------------------------------------------
actionlint=${ACTIONLINT:-$(command -v actionlint 2>/dev/null || true)}
if [ -n "${actionlint}" ] && [ "${#workflows[@]}" -gt 0 ]; then
	if ! out=$(cd "${root}" && "${actionlint}" "${workflows[@]}" 2>&1); then
		err "actionlint:"$'\n'"${out}"
	fi
else
	echo 'check-workflows: actionlint not found, skipped (CI installs it)'
fi

if [ "${errors}" -gt 0 ]; then
	echo "check-workflows: ${errors} problem(s)" >&2
	exit 1
fi
echo "check-workflows: ${#workflows[@]} workflow(s): actions pinned, downloads checked, scan/sign steps in place"
