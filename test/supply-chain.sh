# shellcheck shell=bash disable=SC2154
# Tests for the supply-chain scripts, sourced by test/run.sh (uses its ok/not_ok/expect_* helpers, ${work}, ${root}):
#   test/check-workflows.sh   actions pinned by SHA, downloads by sha256, the scan/sign steps, .trivyignore
#   scripts/scan.sh           the vulnerability policy (fixable CRITICAL in our own layers fails), with a fake trivy
#   scripts/sign.sh           cosign signature and per-platform SBOM and provenance attestations, with fake
#                             cosign/docker/trivy
#   scripts/content-check.sh  the rebuild policy (push only when the content fingerprint changed), with a fake docker
#   scripts/report.sh         the build report (facts, merge, publish to the stats branch of a local bare repository)

# --- test/check-workflows.sh ----------------------------------------------------------------------------
check_wf="${root}/test/check-workflows.sh"
if out=$("${check_wf}" 2>&1); then ok 'the repository passes check-workflows.sh'; else not_ok 'the repository passes check-workflows.sh' "${out}"; fi

pin='actions/checkout@0123456789abcdef0123456789abcdef01234567 # v6.1.0'
wf_tree() { # workflow-content [trivyignore-content]
	rm -rf "${work:?}/wf"
	mkdir -p "${work}/wf/.github/workflows"
	printf '%s\n' "$1" >"${work}/wf/.github/workflows/ci.yml"
	printf 'version: 2\nupdates:\n  - package-ecosystem: github-actions\n    directory: /\n' >"${work}/wf/.github/dependabot.yml"
	[ -z "${2:-}" ] || printf '%s\n' "$2" >"${work}/wf/.trivyignore"
}
expect_wf() { # name pass|fail [needle]
	local out rc
	out=$(ACTIONLINT=true "${check_wf}" "${work}/wf" 2>&1)
	rc=$?
	if [ "$2" = pass ] && [ "${rc}" = 0 ]; then
		ok "$1"
	elif [ "$2" = fail ] && [ "${rc}" != 0 ] && [[ ${out} == *"${3:-}"* ]]; then
		ok "$1"
	else
		not_ok "$1" "rc=${rc}: ${out}"
	fi
}
wf_ok=$'on: push\npermissions:\n  contents: read\njobs:\n  a:\n    runs-on: ubuntu-24.04\n    steps:\n      - uses: '"${pin}"$'\n      - uses: ./.github/actions/local\n      - uses: docker://alpine@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
wf_tree "${wf_ok}"
expect_wf 'workflows: SHA pins with a version comment, local actions and docker digests pass' pass
wf_tree "${wf_ok/${pin}/actions/checkout@v4}"
expect_wf 'workflows: an action pinned to a tag fails' fail 'not pinned to a full commit SHA'
wf_tree "${wf_ok/${pin}/\"actions/checkout@main\"}"
expect_wf 'workflows: an action pinned to a branch fails (also quoted)' fail 'not pinned to a full commit SHA'
wf_tree "${wf_ok/ # v6.1.0/}"
expect_wf 'workflows: a SHA pin without its version comment fails' fail 'needs its version as a comment'
wf_tree "${wf_ok/sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef/}"
expect_wf 'workflows: a docker:// action without a digest fails' fail 'not pinned by digest'
wf_tree "${wf_ok/$'permissions:\n  contents: read\n'/}"
expect_wf 'workflows: a workflow without top-level permissions fails' fail 'no top-level permissions'
wf_dl=$'\nenv:\n  TOOL_VERSION: v1.0.0\n  TOOL_SHA256: 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef\n'
wf_run=$'\n      - run: |\n          curl -fsSLo tool "https://github.com/o/tool/releases/download/${TOOL_VERSION}/tool"\n'
wf_tree "${wf_ok}${wf_dl}${wf_run}"$'          echo "${TOOL_SHA256}  tool" | sha256sum -c -'
expect_wf 'workflows: a download checked against its pinned sha256 passes' pass
wf_tree "${wf_ok}${wf_dl}${wf_run}"
expect_wf 'workflows: a release download without sha256sum -c fails' fail 'without a sha256sum -c check'
wf_tree "${wf_ok}${wf_dl/TOOL_SHA256/OTHER_SHA256}${wf_run}"$'          sha256sum -c sums'
expect_wf 'workflows: a downloaded version without its _SHA256 fails' fail 'TOOL_VERSION is downloaded but has no TOOL_SHA256'
wf_tree "${wf_ok}" $'# proton: bundled curl, fixed in the next release\nCVE-2026-1 exp:2026-12-31'
expect_wf 'trivyignore: an entry with a reason and an expiry passes' pass
wf_tree "${wf_ok}" $'# proton: bundled curl\nCVE-2026-1'
expect_wf 'trivyignore: an entry without an expiry fails' fail 'needs an expiry date'
wf_tree "${wf_ok}" $'# header\n\nCVE-2026-1 exp:2026-12-31'
expect_wf 'trivyignore: an entry without a reason right above it fails' fail 'needs a comment line'
wf_tree "${wf_ok}"
command rm -f "${work}/wf/.github/dependabot.yml"
expect_wf 'workflows: no Dependabot config fails' fail 'dependabot.yml is missing'
wf_tree "${wf_ok}"
cp "${root}/.github/workflows/build.yml" "${work}/wf/.github/workflows/build.yml"
sed -i '/name: Vulnerability scan/,/scripts\/scan.sh/d' "${work}/wf/.github/workflows/build.yml"
expect_wf 'workflows: build.yml without the scan step fails' fail "no 'name: Vulnerability scan' step"
cp "${root}/.github/workflows/build.yml" "${work}/wf/.github/workflows/build.yml"
sed -i 's/TRIVY_VERSION: v[0-9.]*/TRIVY_VERSION: latest/' "${work}/wf/.github/workflows/build.yml"
expect_wf 'workflows: Trivy at "latest" fails' fail 'TRIVY_VERSION must be an exact version'
cp "${root}/.github/workflows/build.yml" "${work}/wf/.github/workflows/build.yml"
sed -i "/name: Sign/{n;d}" "${work}/wf/.github/workflows/build.yml"
expect_wf 'workflows: a Sign step that runs for pull requests fails' fail 'must not run for pull requests'

# --- scripts/scan.sh with a fake trivy and docker ------------------------------------------------------
# The fake trivy logs its arguments and writes FAKE_REPORT (a file) as the JSON report, `{}` for the other formats.
# The fake docker answers `pull` (FAKE_PULL_RC) and `image inspect` with FAKE_LAYERS (the base's diff IDs).
mkdir -p "${work}/scbin" "${work}/sc/images/game"
cat >"${work}/scbin/trivy" <<'EOF'
#!/bin/bash
{
	echo '--call--'
	printf '%s\n' "$@"
} >>"${FAKE_LOG}"
format='' output=''
while [ "$#" -gt 0 ]; do
	case "$1" in
	--format) format=$2; shift ;;
	--output) output=$2; shift ;;
	esac
	shift
done
[ "${FAKE_TRIVY_RC:-0}" = 0 ] || exit "${FAKE_TRIVY_RC}"
if [ "${format}" = json ]; then cat "${FAKE_REPORT}" >"${output}"; else echo '{}' >"${output}"; fi
EOF
cat >"${work}/scbin/docker" <<'EOF'
#!/bin/bash
{
	echo '--call--'
	printf '%s\n' "$@"
} >>"${FAKE_LOG}"
case "$1 ${2:-} ${3:-}" in
pull*) exit "${FAKE_PULL_RC:-0}" ;;
'image inspect'*) echo "${FAKE_LAYERS:-[]}" ;;
'buildx imagetools inspect')
	if [ "$4" = --raw ]; then
		echo "${FAKE_RAW}"
	elif [[ ${5:-} == *Provenance* ]]; then
		echo "${FAKE_PROVENANCE:-{\}}"
	else
		echo "${FAKE_CONFIG:-{\}}"
	fi
	;;
esac
EOF
cat >"${work}/scbin/cosign" <<'EOF'
#!/bin/bash
{
	echo '--call--'
	printf '%s\n' "$@"
} >>"${FAKE_LOG}"
exit "${FAKE_COSIGN_RC:-0}"
EOF
chmod +x "${work}/scbin/"*
printf '{"images":[{"tag":"game","folder":"images/game","kind":"runtime","smoke":"true"}]}\n' >"${work}/sc/images.json"
printf 'FROM golang:1.23-bookworm AS build\nFROM --platform=linux/amd64 debian:bookworm-slim AS base\nFROM base\nCOPY --from=build /a /a\n' \
	>"${work}/sc/images/game/Dockerfile"
vuln() { # id severity fixed diffid
	printf '{"VulnerabilityID":"%s","PkgName":"pkg-%s","InstalledVersion":"1.0","FixedVersion":"%s","Severity":"%s"%s}' \
		"$1" "$1" "$3" "$2" "$([ -n "$4" ] && printf ',"Layer":{"DiffID":"%s"}' "$4")"
}
report() { # vuln json objects...
	local IFS=,
	printf '{"ArtifactName":"x","Results":[{"Target":"x (debian 12.7)","Vulnerabilities":[%s]}]}\n' "$*" >"${work}/report.json"
}
run_scan() { # VAR=value ... : output in SCAN_OUT, exit code in SCAN_RC, calls in SCAN_LOG, summary in SCAN_SUMMARY
	rm -rf "${work:?}/scan.log" "${work:?}/scan-summary.md" "${work:?}/scan-out"
	SCAN_OUT=$(env FAKE_LOG="${work}/scan.log" FAKE_REPORT="${work}/report.json" IMAGES_JSON="${work}/sc/images.json" \
		DOCKER="${work}/scbin/docker" TRIVY="${work}/scbin/trivy" TRIVY_IGNOREFILE="${work}/none" \
		GITHUB_STEP_SUMMARY="${work}/scan-summary.md" FAKE_LAYERS='["sha256:base1","sha256:base2"]' "$@" \
		"${root}/scripts/scan.sh" smoke-img:game game "${work}/scan-out" 2>&1)
	SCAN_RC=$?
	SCAN_LOG=$(cat "${work}/scan.log" 2>/dev/null)
	SCAN_SUMMARY=$(cat "${work}/scan-summary.md" 2>/dev/null)
}
report "$(vuln CVE-1 CRITICAL 2.0 sha256:base1)" "$(vuln CVE-2 CRITICAL '' sha256:ours1)" \
	"$(vuln CVE-3 HIGH 2.0 sha256:ours1)" "$(vuln CVE-4 LOW 2.0 sha256:ours1)"
run_scan
expect_rc 'scan: fixable CRITICAL in the base, unfixable CRITICAL and fixable HIGH in ours pass' 0 "${SCAN_RC}" "${SCAN_OUT}"
expect_contains 'scan: the base is the final stage, followed through stage names' "${SCAN_LOG}" $'pull\n--quiet\n--platform\nlinux/amd64\ndebian:bookworm-slim'
expect_contains 'scan: Trivy writes the JSON report' "${SCAN_LOG}" $'--format\njson'
expect_contains 'scan: ... the SARIF with fixable HIGH and CRITICAL' "${SCAN_LOG}" $'--severity\nHIGH,CRITICAL\n--ignore-unfixed\n--format\nsarif'
expect_contains 'scan: ... and a CycloneDX SBOM' "${SCAN_LOG}" $'--format\ncyclonedx'
for f in game.trivy.json game.sarif game.cdx.json; do
	if [ -f "${work}/scan-out/${f}" ]; then ok "scan: writes ${f}"; else not_ok "scan: writes ${f}"; fi
done
expect_contains 'scan: the summary counts CRITICAL findings' "${SCAN_SUMMARY}" '| CRITICAL | 2 | 1 | 1 | 0 |'
expect_contains 'scan: ... and HIGH ones' "${SCAN_SUMMARY}" '| HIGH | 1 | 1 | 1 | 1 |'
expect_contains 'scan: the summary lists HIGH/CRITICAL findings with their layer' "${SCAN_SUMMARY}" '| CRITICAL | CVE-1 | pkg-CVE-1 | 1.0 | 2.0 | base |'
expect_not_contains 'scan: LOW findings stay out of the summary' "${SCAN_SUMMARY}" 'CVE-4'
expect_contains 'scan: the summary states the policy result' "${SCAN_SUMMARY}" 'Policy: passed'

report "$(vuln CVE-1 CRITICAL 2.0 sha256:base1)" "$(vuln CVE-5 CRITICAL 3.1 sha256:ours1)"
run_scan
expect_rc 'scan: a fixable CRITICAL in our own layer fails' 1 "${SCAN_RC}" "${SCAN_OUT}"
expect_contains 'scan: ... naming it' "${SCAN_OUT}" '| CRITICAL | CVE-5 | pkg-CVE-5 | 1.0 | 3.1 | ours |'
expect_not_contains 'scan: ... and not the base one' "$(grep 'CVE-1' <<<"${SCAN_OUT}")" 'ours'
expect_contains 'scan: the summary says why' "${SCAN_SUMMARY}" 'FAILED: 1 fixable CRITICAL'
report "$(vuln CVE-6 CRITICAL 3.1 '')"
run_scan
expect_rc 'scan: a fixable CRITICAL Trivy cannot place in a layer counts as ours' 1 "${SCAN_RC}" "${SCAN_OUT}"
report "$(vuln CVE-5 CRITICAL 3.1 sha256:ours1)"
run_scan FAKE_LAYERS='["sha256:base1","sha256:ours1"]'
expect_rc 'scan: the same finding in a base layer passes' 0 "${SCAN_RC}" "${SCAN_OUT}"
report
run_scan
expect_rc 'scan: no findings pass' 0 "${SCAN_RC}" "${SCAN_OUT}"
run_scan TRIVY_IGNOREFILE="${root}/.trivyignore"
expect_contains 'scan: .trivyignore is handed to Trivy' "${SCAN_LOG}" $'--ignorefile\n'"${root}/.trivyignore"
run_scan FAKE_PULL_RC=1
expect_rc 'scan: a base that cannot be pulled is a tool error, not a pass' 2 "${SCAN_RC}" "${SCAN_OUT}"
run_scan FAKE_TRIVY_RC=1
expect_rc 'scan: a failed Trivy run is a tool error, not a pass' 2 "${SCAN_RC}" "${SCAN_OUT}"
SCAN_OUT=$(IMAGES_JSON="${work}/sc/images.json" "${root}/scripts/scan.sh" smoke-img:x nope "${work}/scan-out" 2>&1)
expect_rc 'scan: an unknown tag is a usage error' 2 "$?" "${SCAN_OUT}"

# --- scripts/sign.sh with fake cosign, docker and trivy --------------------------------------------------
run_sign() { # VAR=value ... -- args : output in SIGN_OUT, exit code in SIGN_RC, calls in SIGN_LOG, summary in SIGN_SUMMARY
	local vars=()
	while [ "$1" != -- ]; do
		vars+=("$1")
		shift
	done
	shift
	rm -rf "${work:?}/sign.log" "${work:?}/sign-summary.md" "${work:?}/sign-out"
	SIGN_OUT=$(env FAKE_LOG="${work}/sign.log" FAKE_REPORT="${work}/report.json" COSIGN="${work}/scbin/cosign" \
		DOCKER="${work}/scbin/docker" TRIVY="${work}/scbin/trivy" GITHUB_STEP_SUMMARY="${work}/sign-summary.md" \
		"${vars[@]}" "${root}/scripts/sign.sh" "$@" 2>&1)
	SIGN_RC=$?
	SIGN_LOG=$(cat "${work}/sign.log" 2>/dev/null)
	SIGN_SUMMARY=$(cat "${work}/sign-summary.md" 2>/dev/null)
}
index='{"manifests":[{"digest":"sha256:amd","platform":{"os":"linux","architecture":"amd64"}},{"digest":"sha256:arm","platform":{"os":"linux","architecture":"arm64"}},{"digest":"sha256:att","platform":{"os":"unknown","architecture":"unknown"}}]}'
identity='https://github.com/sneakywrld/octail-yolks/.github/workflows/build.yml@refs/heads/main'
run_sign "FAKE_RAW=${index}" "SIGN_IDENTITY=${identity}" -- ghcr.io/o/y sha256:idx game "${work}/sign-out"
expect_rc 'sign: a multi-arch image is signed and attested' 0 "${SIGN_RC}" "${SIGN_OUT}"
expect_contains 'sign: cosign signs the index recursively, keyless' "${SIGN_LOG}" $'sign\n--yes\n--recursive\nghcr.io/o/y@sha256:idx'
expect_contains 'sign: the amd64 SBOM comes from the registry' "${SIGN_LOG}" $'--image-src\nremote\n--platform\nlinux/amd64\n--format\ncyclonedx\n--output\n'"${work}/sign-out/game-linux-amd64.cdx.json"$'\nghcr.io/o/y@sha256:amd'
expect_contains 'sign: the amd64 SBOM is attested to the amd64 image' "${SIGN_LOG}" $'attest\n--yes\n--type\ncyclonedx\n--predicate\n'"${work}/sign-out/game-linux-amd64.cdx.json"$'\nghcr.io/o/y@sha256:amd'
expect_contains 'sign: ... and the arm64 one to the arm64 image' "${SIGN_LOG}" $'game-linux-arm64.cdx.json\nghcr.io/o/y@sha256:arm'
expect_not_contains 'sign: attestation manifests (unknown platform) are skipped' "${SIGN_LOG}" 'sha256:att'
expect_contains 'sign: the summary has the hosts'\'' verify command' "${SIGN_SUMMARY}" "cosign verify ghcr.io/o/y:game"
expect_contains 'sign: ... with the workflow identity' "${SIGN_SUMMARY}" "--certificate-identity '${identity}'"
run_sign 'FAKE_RAW={"mediaType":"application/vnd.oci.image.manifest.v1+json","layers":[]}' \
	'FAKE_CONFIG={"os":"linux","architecture":"amd64"}' -- ghcr.io/o/y sha256:one wine "${work}/sign-out"
expect_rc 'sign: a single-platform image is signed and attested' 0 "${SIGN_RC}" "${SIGN_OUT}"
expect_contains 'sign: ... its own digest gets the SBOM' "${SIGN_LOG}" $'wine-linux-amd64.cdx.json\nghcr.io/o/y@sha256:one'
run_sign "FAKE_RAW=${index}" FAKE_COSIGN_RC=1 -- ghcr.io/o/y sha256:idx game "${work}/sign-out"
expect_rc 'sign: a failed signature fails the job' 1 "${SIGN_RC}" "${SIGN_OUT}"
run_sign -- ghcr.io/o/y latest game "${work}/sign-out"
expect_rc 'sign: a tag instead of a digest is a usage error' 2 "${SIGN_RC}" "${SIGN_OUT}"

# --- scripts/sign.sh: BuildKit's SLSA provenance, attested with cosign -----------------------------------
slsa_map='{"linux/amd64":{"SLSA":{"buildType":"https://mobyproject.org/buildkit@v1","for":"amd"}},"linux/arm64":{"SLSA":{"buildType":"https://mobyproject.org/buildkit@v1","for":"arm"}}}'
run_sign "FAKE_RAW=${index}" "FAKE_PROVENANCE=${slsa_map}" -- ghcr.io/o/y sha256:idx game "${work}/sign-out"
expect_rc 'sign: an image with BuildKit provenance is signed and attested' 0 "${SIGN_RC}" "${SIGN_OUT}"
expect_contains 'sign: the amd64 provenance is attested to the amd64 image' "${SIGN_LOG}" $'attest\n--yes\n--type\nslsaprovenance\n--predicate\n'"${work}/sign-out/game-linux-amd64.provenance.json"$'\nghcr.io/o/y@sha256:amd'
expect_contains 'sign: ... and the arm64 one to the arm64 image' "${SIGN_LOG}" $'game-linux-arm64.provenance.json\nghcr.io/o/y@sha256:arm'
expect_contains 'sign: the predicate is that platform'\''s SLSA provenance' "$(jq -r .for "${work}/sign-out/game-linux-arm64.provenance.json" 2>/dev/null)" 'arm'
expect_contains 'sign: the summary says the provenance is attested' "${SIGN_SUMMARY}" 'SLSA provenance attested'
expect_contains 'sign: ... and has the verify-attestation command' "${SIGN_SUMMARY}" 'cosign verify-attestation --type slsaprovenance ghcr.io/o/y:game'
run_sign "FAKE_RAW=${index}" 'FAKE_PROVENANCE={"SLSA":{"for":"single"}}' -- ghcr.io/o/y sha256:idx solo "${work}/sign-out"
expect_contains 'sign: a single-platform provenance ({"SLSA": ...}) is attested too' "$(jq -r .for "${work}/sign-out/solo-linux-amd64.provenance.json" 2>/dev/null)" 'single'
run_sign "FAKE_RAW=${index}" -- ghcr.io/o/y sha256:idx game "${work}/sign-out"
expect_rc 'sign: an image without provenance is still signed (an older push)' 0 "${SIGN_RC}" "${SIGN_OUT}"
expect_not_contains 'sign: ... with no provenance attestation' "${SIGN_LOG}" 'slsaprovenance'
expect_contains 'sign: ... and the summary says so' "${SIGN_SUMMARY}" 'no provenance'

# --- scripts/scan.sh: <tag>.scan.json for the build report -----------------------------------------------
report "$(vuln CVE-1 CRITICAL 2.0 sha256:base1)" "$(vuln CVE-2 CRITICAL '' sha256:ours1)" \
	"$(vuln CVE-3 HIGH 2.0 sha256:ours1)" "$(vuln CVE-4 LOW 2.0 sha256:ours1)" "$(vuln CVE-4 LOW 2.0 sha256:ours1)"
run_scan TRIVY_VERSION=v0.74.0
# jq_of <file> <filter>: the filter's raw output (string templates keep the tests independent of key order).
jq_of() { jq -r "$2" "$1" 2>/dev/null; }
sev='\(.critical) \(.high) \(.medium) \(.low) \(.unknown)'
scan_file="${work}/scan-out/game.scan.json"
expect_contains 'scan: game.scan.json counts every severity, deduplicated' "$(jq_of "${scan_file}" ".vulnerabilities | \"${sev}\"")" '2 1 0 1 0'
expect_contains 'scan: ... and those with a fix' "$(jq_of "${scan_file}" ".fixable | \"${sev}\"")" '1 1 0 1 0'
expect_contains 'scan: ... with the final base' "$(jq_of "${scan_file}" .base)" 'debian:bookworm-slim'
expect_contains 'scan: ... the scanner version' "$(jq_of "${scan_file}" .scanner)" 'trivy v0.74.0'
expect_contains 'scan: ... and the policy result' "$(jq_of "${scan_file}" '"\(.policy.passed) \(.policy.blocking)"')" 'true 0'
report "$(vuln CVE-5 CRITICAL 3.1 sha256:ours1)"
run_scan
expect_contains 'scan: a failed policy is in game.scan.json too' "$(jq_of "${scan_file}" '"\(.policy.passed) \(.policy.blocking)"')" 'false 1'

# --- scripts/content-check.sh and scripts/report.sh with a fake docker ------------------------------------
# The fake docker answers `buildx imagetools inspect`:
#   --format '{{json .Manifest}}' <ref>   {"digest": sha256 of ref + FAKE_SALT} (FAKE_MANIFEST_RC=1: not found)
#   --format '{{json .Image}}' <ref>      FAKE_IMAGE (unset: not found)
#   --raw <repo>@sha256:amd / :arm        a platform manifest (layers 100+200 / 90, config 10)
#   --raw <anything else>                 FAKE_RAW (default: an index of amd64, arm64 and an attestation manifest)
mkdir -p "${work}/ccbin" "${work}/cc/images/game" "${work}/cc/images/other" "${work}/cc/common"
cat >"${work}/ccbin/docker" <<'EOF'
#!/bin/bash
{
	echo '--call--'
	printf '%s\n' "$@"
} >>"${FAKE_LOG}"
ref=${!#}
index='{"manifests":[{"digest":"sha256:amd","platform":{"os":"linux","architecture":"amd64"}},{"digest":"sha256:arm","platform":{"os":"linux","architecture":"arm64"}},{"digest":"sha256:att","platform":{"os":"unknown","architecture":"unknown"}}]}'
case "$*" in
*'{{json .Manifest}}'*)
	[ "${FAKE_MANIFEST_RC:-0}" = 0 ] || exit 1
	printf '{"mediaType":"application/vnd.oci.image.index.v1+json","digest":"sha256:%s"}\n' "$(printf '%s%s' "${ref}" "${FAKE_SALT:-}" | sha256sum | cut -c1-64)"
	;;
*'{{json .Image}}'*)
	[ -n "${FAKE_IMAGE:-}" ] || exit 1
	echo "${FAKE_IMAGE}"
	;;
*--raw*)
	case "${ref}" in
	*@sha256:amd) echo '{"config":{"size":10},"layers":[{"size":100},{"size":200}]}' ;;
	*@sha256:arm) echo '{"config":{"size":10},"layers":[{"size":90}]}' ;;
	*) echo "${FAKE_RAW:-${index}}" ;;
	esac
	;;
*) exit 1 ;;
esac
EOF
chmod +x "${work}/ccbin/docker"
cc_db() { # eggs-of-game
	printf '{"registry":"ghcr.io/o/y","images":[{"tag":"game","folder":"images/game","platforms":["linux/amd64","linux/arm64"],"kind":"runtime","smoke":"true","description":"Game","eggs":[%s]},{"tag":"other","folder":"images/other","platforms":["linux/amd64"],"kind":"runtime","smoke":"true","description":"Other"}]}\n' "${1:-}" >"${work}/cc/images.json"
}
cc_db '"a"'
printf 'FROM golang:1.23-bookworm AS build\nFROM debian:bookworm-slim\nCOPY --from=build /a /a\n' >"${work}/cc/images/game/Dockerfile"
printf 'FROM alpine:3.22\n' >"${work}/cc/images/other/Dockerfile"
printf '#!/bin/bash\necho entry\n' >"${work}/cc/common/entrypoint.sh"
cc_sbom() { # version-of-libssl3
	printf '{"bomFormat":"CycloneDX","serialNumber":"urn:uuid:%s","metadata":{"timestamp":"%s","component":{"type":"operating-system","name":"debian","version":"12.7"}},"components":[{"type":"library","name":"libssl3","version":"%s","purl":"pkg:deb/debian/libssl3@%s"},{"type":"library","name":"bash","version":"5.2","purl":"pkg:deb/debian/bash@5.2"}]}\n' \
		"${RANDOM}" "$(date +%s%N)" "$1" "$1" >"${work}/cc/game.cdx.json"
}
cc_sbom 3.0.15
run_cc() { # VAR=value ... [-- tag sbom] : output in CC_OUT, exit code in CC_RC, outputs in CC_GH, calls in CC_LOG
	local vars=() args=(game "${work}/cc/game.cdx.json")
	while [ "$#" -gt 0 ] && [ "$1" != -- ]; do
		vars+=("$1")
		shift
	done
	if [ "${1:-}" = -- ]; then
		shift
		args=("$@")
	fi
	rm -rf "${work:?}/cc.log" "${work:?}/cc-gh" "${work:?}/cc-out"
	CC_OUT=$(env FAKE_LOG="${work}/cc.log" IMAGES_JSON="${work}/cc/images.json" DOCKER="${work}/ccbin/docker" \
		GITHUB_OUTPUT="${work}/cc-gh" GITHUB_STEP_SUMMARY="${work}/cc-summary.md" "${vars[@]}" \
		"${root}/scripts/content-check.sh" "${args[@]}" "${work}/cc-out" 2>&1)
	CC_RC=$?
	CC_GH=$(cat "${work}/cc-gh" 2>/dev/null)
	CC_LOG=$(cat "${work}/cc.log" 2>/dev/null)
	CC_FP=$(sed -n 's/^fingerprint=//p' "${work}/cc-gh" 2>/dev/null)
}
published() { printf '{"linux/amd64":{"config":{"Labels":{"org.octail.yolks.fingerprint":"%s"}}},"linux/arm64":{"config":{"Labels":{}}}}' "$1"; }

run_cc
expect_rc 'content: a first build is decided' 0 "${CC_RC}" "${CC_OUT}"
expect_contains 'content: nothing published yet pushes' "${CC_GH}" 'push=true'
expect_contains 'content: ... and says why' "${CC_GH}" 'reason=nothing published with a fingerprint yet'
fp=${CC_FP}
if [[ ${fp} =~ ^[0-9a-f]{64}$ ]]; then ok 'content: the fingerprint is a sha256'; else not_ok 'content: the fingerprint is a sha256' "${CC_GH}"; fi
lines=$(cat "${work}/cc-out/game.fingerprint.txt" 2>/dev/null)
expect_contains 'content: the fingerprint covers the base images by digest' "${lines}" 'base debian:bookworm-slim sha256:'
expect_contains 'content: ... build stages'\'' bases too' "${lines}" 'base golang:1.23-bookworm sha256:'
expect_not_contains 'content: ... but not stage names' "${lines}" 'base build '
expect_contains 'content: ... the image folder and common/ by content' "${lines}" 'common/entrypoint.sh'
expect_contains 'content: ... the packages of the built image' "${lines}" 'pkg pkg:deb/debian/libssl3@3.0.15'
expect_contains 'content: ... its OS' "${lines}" 'os debian 12.7'
expect_contains 'content: the registry image'\''s label is read' "${CC_LOG}" $'{{json .Image}}\nghcr.io/o/y:game'

cc_sbom 3.0.15
run_cc "FAKE_IMAGE=$(published "${fp}")"
expect_contains 'content: the same content as published does not push (SBOM timestamps ignored)' "${CC_GH}" 'push=false'
expect_contains 'content: ... and records the published fingerprint' "${CC_GH}" "published=${fp}"
run_cc "FAKE_IMAGE={\"config\":{\"Labels\":{\"org.octail.yolks.fingerprint\":\"${fp}\"}}}"
expect_contains 'content: a single-platform published image is read too' "${CC_GH}" 'push=false'
run_cc "FAKE_IMAGE=$(published "${fp}")" FORCE=1
expect_contains 'content: FORCE=1 pushes anyway' "${CC_GH}" 'push=true'
run_cc "FAKE_IMAGE=$(published "${fp}")" FAKE_SALT=new
expect_contains 'content: a new base image digest pushes' "${CC_GH}" 'reason=content changed'
cc_sbom 3.0.16
run_cc "FAKE_IMAGE=$(published "${fp}")"
expect_contains 'content: a package upgrade pushes' "${CC_GH}" 'push=true'
cc_sbom 3.0.15
cc_db '"a","b"'
run_cc "FAKE_IMAGE=$(published "${fp}")"
expect_contains 'content: an egg list change in images.json does not push' "${CC_GH}" 'push=false'
printf '#!/bin/bash\necho entry2\n' >"${work}/cc/common/entrypoint.sh"
run_cc "FAKE_IMAGE=$(published "${fp}")"
expect_contains 'content: a changed file in common/ pushes' "${CC_GH}" 'push=true'
printf '#!/bin/bash\necho entry\n' >"${work}/cc/common/entrypoint.sh"
run_cc "FAKE_IMAGE=$(published "${fp}")" -- game "${work}/cc/missing.cdx.json"
expect_contains 'content: a missing SBOM pushes to be safe' "${CC_GH}" 'push=true'
expect_contains 'content: ... and says why' "${CC_GH}" 'reason=could not read the SBOM'
run_cc "FAKE_IMAGE=$(published "${fp}")" FAKE_MANIFEST_RC=1
expect_contains 'content: an unreadable base pushes to be safe' "${CC_GH}" 'could not read the digest of'
run_cc -- nope "${work}/cc/game.cdx.json"
expect_rc 'content: an unknown tag is a usage error' 2 "${CC_RC}" "${CC_OUT}"

# report.sh fact: the published image's facts plus this run's scan.
run_report() { # VAR=value ... -- args : output in RP_OUT, exit code in RP_RC
	local vars=()
	while [ "$1" != -- ]; do
		vars+=("$1")
		shift
	done
	shift
	RP_OUT=$(env FAKE_LOG="${work}/rp.log" IMAGES_JSON="${work}/cc/images.json" DOCKER="${work}/ccbin/docker" \
		"${vars[@]}" "${root}/scripts/report.sh" "$@" 2>&1)
	RP_RC=$?
}
labels='{"org.opencontainers.image.created":"2026-10-23T04:17:00Z","org.opencontainers.image.revision":"abc123","org.octail.yolks.fingerprint":"f00"}'
rm -rf "${work:?}/facts"
mkdir -p "${work}/facts"
printf '{"tag":"game","platform":"linux/amd64","base":"debian:bookworm-slim","scanner":"trivy v0.74.0","vulnerabilities":{"critical":1,"high":2,"medium":3,"low":4,"unknown":0},"fixable":{"critical":0,"high":1,"medium":1,"low":0,"unknown":0},"policy":{"passed":true,"blocking":0}}\n' >"${work}/facts/game.scan.json"
run_report "FAKE_IMAGE={\"linux/amd64\":{\"config\":{\"Labels\":${labels}}}}" CHECKED_AT=2026-10-23T05:00:00Z PUSHED=1 -- fact game "${work}/facts"
expect_rc 'report: fact writes the facts of a published image' 0 "${RP_RC}" "${RP_OUT}"
fact_file="${work}/facts/game.stats.json"
expect_contains 'report: fact has the tag, kind and image' "$(jq_of "${fact_file}" '"\(.tag) \(.kind) \(.image)"')" 'game runtime ghcr.io/o/y:game'
expect_contains 'report: ... the index digest' "$(jq_of "${fact_file}" .digest)" 'sha256:'
expect_contains 'report: ... the platforms' "$(jq_of "${fact_file}" '.platforms | join(",")')" 'linux/amd64,linux/arm64'
expect_contains 'report: ... the compressed size per platform (layers + config, attestations skipped)' \
	"$(jq_of "${fact_file}" '.compressedSize | "\(.["linux/amd64"]) \(.["linux/arm64"]) \(length)"')" '310 100 2'
expect_contains 'report: ... the base from the scan' "$(jq_of "${fact_file}" .base)" 'debian:bookworm-slim'
expect_contains 'report: ... the build date, revision and fingerprint from the labels' \
	"$(jq_of "${fact_file}" '"\(.builtAt) \(.revision) \(.fingerprint)"')" '2026-10-23T04:17:00Z abc123 f00'
expect_contains 'report: ... whether this run pushed, and when it checked' "$(jq_of "${fact_file}" '"\(.pushed) \(.checkedAt)"')" 'true 2026-10-23T05:00:00Z'
expect_contains 'report: ... the CVE counts' "$(jq_of "${fact_file}" ".vulnerabilities | \"${sev}\"")" '1 2 3 4 0'
expect_contains 'report: ... and the scan'\''s platform and policy' "$(jq_of "${fact_file}" '"\(.scan.platform) \(.scan.policy.passed)"')" 'linux/amd64 true'
run_report FAKE_MANIFEST_RC=1 PUSHED=0 -- fact other "${work}/facts"
expect_rc 'report: fact of an unpublished image still writes' 0 "${RP_RC}" "${RP_OUT}"
expect_contains 'report: ... with an empty digest and no scan' "$(jq_of "${work}/facts/other.stats.json" '"\(.digest) \(.vulnerabilities) \(.pushed)"')" 'null null false'
run_report -- fact nope "${work}/facts"
expect_rc 'report: fact of an unknown tag is a usage error' 2 "${RP_RC}" "${RP_OUT}"

# report.sh merge: new facts replace their tag, the others are kept, gone tags dropped, images.json order.
printf '{"schema":1,"images":[{"tag":"gone","digest":"sha256:g"},{"tag":"other","digest":"sha256:old"},{"tag":"game","digest":"sha256:old"}]}\n' >"${work}/prev.json"
rm -rf "${work:?}/facts2"
mkdir -p "${work}/facts2"
cp "${work}/facts/game.stats.json" "${work}/facts2/"
run_report GENERATED_AT=2026-10-23T06:00:00Z RUN_URL=https://example.invalid/run/1 -- merge "${work}/prev.json" "${work}/facts2"
printf '%s\n' "${RP_OUT}" >"${work}/merged.json"
expect_contains 'report: merge writes schema 1 with the registry and run' \
	"$(jq_of "${work}/merged.json" '"\(.schema) \(.registry) \(.generatedAt) \(.source)"')" '1 ghcr.io/o/y 2026-10-23T06:00:00Z https://example.invalid/run/1'
expect_contains 'report: ... the new fact replaces its tag, in images.json order' "$(jq_of "${work}/merged.json" '.images[0] | "\(.tag) \(.pushed)"')" 'game true'
expect_contains 'report: ... the other tag is kept' "$(jq_of "${work}/merged.json" '.images[1] | "\(.tag) \(.digest)"')" 'other sha256:old'
expect_contains 'report: ... a tag gone from images.json is dropped' "$(jq_of "${work}/merged.json" '[.images[].tag] | join(",")')" 'game,other'
run_report -- merge '' "${work}/empty-facts"
expect_contains 'report: merge without a previous report or facts is an empty report' "$(jq -r '.images | length' <<<"${RP_OUT}" 2>/dev/null)" '0'

# report.sh publish: to the stats branch of a (local, bare) remote, merging with what is there.
rm -rf "${work:?}/remote.git" "${work:?}/clone"
git init --quiet --bare "${work}/remote.git"
git init --quiet "${work}/clone"
git -C "${work}/clone" remote add origin "${work}/remote.git"
pub() { (cd "${work}/clone" && env IMAGES_JSON="${work}/cc/images.json" STATS_OUT="${work}/stats-out.json" "$@" "${root}/scripts/report.sh" publish "${PUB_DIR}" 2>&1); }
remote_show() { git --git-dir="${work}/remote.git" "$@" 2>/dev/null; }
PUB_DIR="${work}/facts2"
out=$(pub)
expect_rc 'report: publish creates the stats branch' 0 "$?" "${out}"
expect_contains 'report: ... with stats/images.json' "$(remote_show show stats:stats/images.json | jq -c '[.images[].tag]')" '["game"]'
expect_contains 'report: ... and a README' "$(remote_show show stats:README.md)" 'build report'
expect_contains 'report: ... and writes STATS_OUT' "$(jq -c '[.images[].tag]' "${work}/stats-out.json" 2>/dev/null)" '["game"]'
rm -rf "${work:?}/facts3"
mkdir -p "${work}/facts3"
cp "${work}/facts/other.stats.json" "${work}/facts3/"
PUB_DIR="${work}/facts3"
out=$(pub)
expect_rc 'report: a second publish succeeds' 0 "$?" "${out}"
expect_contains 'report: ... keeping the earlier image and adding the new one' \
	"$(remote_show show stats:stats/images.json | jq -c '[.images[].tag]')" '["game","other"]'
expect_contains 'report: ... as a new commit on the branch' "$(remote_show rev-list --count stats)" '2'
expect_contains 'report: ... by the Actions bot' "$(remote_show log -1 --format=%an stats)" 'github-actions[bot]'
expect_contains 'report: ... naming the images' "$(remote_show log -1 --format=%s stats)" 'stats: other'
if remote_show rev-parse --verify --quiet refs/heads/main >/dev/null; then
	not_ok 'report: publish never touches main'
else
	ok 'report: publish never touches main'
fi
out=$(pub STATS_REMOTE=nowhere STATS_ATTEMPTS=1)
expect_rc 'report: a remote that cannot be pushed to fails' 1 "$?" "${out}"
