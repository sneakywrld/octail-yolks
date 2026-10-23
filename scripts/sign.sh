#!/bin/bash
# Signs a pushed image and attests its SBOMs (CI runs it right after the push, never on pull requests):
#   scripts/sign.sh <repository> <digest> <tag> <output folder>
#   e.g. scripts/sign.sh ghcr.io/sneakywrld/octail-yolks sha256:0123… java_21 out
#
#   1. cosign sign, keyless (the workflow's GitHub OIDC identity, Sigstore's public Fulcio and Rekor), --recursive:
#      the multi-arch index and every platform's image get a signature.
#   2. Per platform: Trivy writes the image's SBOM (CycloneDX) from the registry to <output folder>/<tag>-<os>-<arch>.cdx.json
#      and `cosign attest --type cyclonedx` attaches it, signed, to that platform's image digest.
#   3. Per platform: the SLSA provenance BuildKit attached to the push (build-push-action `provenance: mode=max`, an
#      unsigned in-registry attestation) is read back to <output folder>/<tag>-<os>-<arch>.provenance.json and
#      `cosign attest --type slsaprovenance` attaches it, signed, to the same digest. An image without BuildKit
#      provenance (an older push) is noted, not failed.
# With GITHUB_STEP_SUMMARY set, the digests and the hosts' verify command go into the job summary.
#
# Environment: COSIGN, DOCKER, TRIVY (defaults cosign, docker, trivy; the tests use fakes), SIGN_IDENTITY (the
# certificate identity printed in the verify command; CI passes the workflow's ref).
# Exit: 0 signed and attested, 1 a step failed, 2 usage.
set -uo pipefail

cosign=${COSIGN:-cosign}
docker=${DOCKER:-docker}
trivy=${TRIVY:-trivy}
issuer=https://token.actions.githubusercontent.com

if [ "$#" -ne 4 ] || [[ $2 != sha256:* ]]; then
	echo 'usage: sign.sh <repository> <sha256:digest> <tag> <output folder>' >&2
	exit 2
fi
repo=$1
digest=$2
tag=$3
out=$4
mkdir -p "${out}" || exit 2
identity=${SIGN_IDENTITY:-}

ref="${repo}@${digest}"
echo "sign: ${tag}: ${ref}"
if ! "${cosign}" sign --yes --recursive "${ref}"; then
	echo "sign: cosign could not sign ${ref}" >&2
	exit 1
fi

# The platform images: the index's manifests (attestation manifests, platform unknown, skipped), or the image itself.
if ! raw=$("${docker}" buildx imagetools inspect --raw "${ref}") || ! jq -e . <<<"${raw}" >/dev/null 2>&1; then
	echo "sign: could not read the manifest of ${ref}" >&2
	exit 1
fi
if jq -e '.manifests' <<<"${raw}" >/dev/null; then
	platforms=$(jq -r '.manifests[] | select(.platform.os != "unknown" and .platform.architecture != "unknown")
		| "\(.platform.os)/\(.platform.architecture)\(if .platform.variant then "/" + .platform.variant else "" end) \(.digest)"' <<<"${raw}")
else
	config=$("${docker}" buildx imagetools inspect --format '{{json .Image}}' "${ref}") || config='{}'
	platforms="$(jq -r '"\(.os // "linux")/\(.architecture // "amd64")"' <<<"${config}") ${digest}"
fi

# BuildKit's provenance: {"SLSA": …} for a single-platform push, {"<os/arch>": {"SLSA": …}, …} for a multi-arch one.
provenance=$("${docker}" buildx imagetools inspect --format '{{json .Provenance}}' "${ref}" 2>/dev/null) || provenance=''
jq -e 'type == "object"' <<<"${provenance}" >/dev/null 2>&1 || provenance='{}'

failed=0
summary=()
while read -r platform pdigest; do
	[ -n "${platform}" ] || continue
	sbom="${out}/${tag}-${platform//\//-}.cdx.json"
	if ! "${trivy}" image --quiet --image-src remote --platform "${platform}" --format cyclonedx --output "${sbom}" \
		"${repo}@${pdigest}"; then
		echo "sign: trivy could not write the SBOM of ${platform}" >&2
		failed=1
		continue
	fi
	if ! "${cosign}" attest --yes --type cyclonedx --predicate "${sbom}" "${repo}@${pdigest}"; then
		echo "sign: cosign could not attest the SBOM of ${platform}" >&2
		failed=1
		continue
	fi
	status='signed, CycloneDX SBOM attested'
	slsa="${out}/${tag}-${platform//\//-}.provenance.json"
	if jq -e --arg p "${platform}" '(if has("SLSA") then .SLSA else .[$p].SLSA end) // empty' <<<"${provenance}" >"${slsa}" 2>/dev/null; then
		if ! "${cosign}" attest --yes --type slsaprovenance --predicate "${slsa}" "${repo}@${pdigest}"; then
			echo "sign: cosign could not attest the provenance of ${platform}" >&2
			failed=1
			continue
		fi
		status="${status}, SLSA provenance attested"
	else
		rm -f "${slsa}"
		echo "sign: ${platform} has no BuildKit provenance, none attested"
		status="${status}, no provenance"
	fi
	echo "sign: ${tag} ${platform} ${pdigest}: ${status}"
	summary+=("| ${platform} | \`${pdigest}\` | ${status} |")
done <<<"${platforms}"

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
	{
		echo "#### Signature: \`${tag}\`"
		echo
		echo "| Platform | Digest | |"
		echo "| --- | --- | --- |"
		echo "| index | \`${digest}\` | signed (keyless) |"
		printf '%s\n' "${summary[@]}"
		echo
		echo '```bash'
		echo "cosign verify ${repo}:${tag} \\"
		echo "  --certificate-identity '${identity:-<workflow identity>}' \\"
		echo "  --certificate-oidc-issuer ${issuer}"
		echo "cosign verify-attestation --type slsaprovenance ${repo}:${tag} \\"
		echo "  --certificate-identity '${identity:-<workflow identity>}' \\"
		echo "  --certificate-oidc-issuer ${issuer}"
		echo '```'
		echo
	} >>"${GITHUB_STEP_SUMMARY}"
fi

exit "${failed}"
