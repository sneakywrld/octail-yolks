# shellcheck shell=bash disable=SC2154
# Tests for the supply-chain scripts, sourced by test/run.sh (uses its ok/not_ok/expect_* helpers, ${work}, ${root}):
#   test/check-workflows.sh   actions pinned by SHA, downloads by sha256, the scan/sign steps, .trivyignore
#   scripts/scan.sh           the vulnerability policy (fixable CRITICAL in our own layers fails), with a fake trivy
#   scripts/sign.sh           cosign signature and per-platform SBOM attestations, with fake cosign/docker/trivy

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
	if [ "$4" = --raw ]; then echo "${FAKE_RAW}"; else echo "${FAKE_CONFIG:-{\}}"; fi
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
expect_contains 'scan: ... the SARIF with HIGH and CRITICAL' "${SCAN_LOG}" $'--severity\nHIGH,CRITICAL\n--format\nsarif'
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
