# octail-yolks

[![build](https://github.com/sneakywrld/octail-yolks/actions/workflows/build.yml/badge.svg)](https://github.com/sneakywrld/octail-yolks/actions/workflows/build.yml)
[![GHCR](https://img.shields.io/badge/ghcr.io-sneakywrld%2Foctail--yolks-2496ED?logo=docker&logoColor=white)](https://github.com/sneakywrld/octail-yolks/pkgs/container/octail-yolks)
[![rebuilt weekly](https://img.shields.io/badge/rebuilt-weekly-brightgreen)](#how-updates-work)
![licence: not chosen yet](https://img.shields.io/badge/licence-not%20chosen%20yet-lightgrey)

The container images [Octail](https://github.com/sneakywrld) game servers and egg install scripts run in, published as
`ghcr.io/sneakywrld/octail-yolks:<tag>`: one image per runtime (Java, .NET, SteamCMD, Wine, Proton, ...), each with
Octail's own entrypoint. The eggs in [octail-eggs](https://github.com/sneakywrld/octail-eggs) use them.

**Policy:** built only from official upstream bases (`bases.txt`); nothing here comes from Pterodactyl, Pelican or
parkervcp images or scripts, and CI fails a Dockerfile that tries.

- [Tags](#tags): [runtimes](#runtimes) · [SteamCMD and game images](#steamcmd-and-game-images) ·
  [Wine and Proton](#wine-and-proton) · [installers](#installers)
- [Using an image in an egg](#using-an-image-in-an-egg) · [Building locally](#building-locally) ·
  [How updates work](#how-updates-work) · [Supply chain: scans, SBOMs, signatures](#supply-chain-scans-sboms-signatures)
- Reference: [what every runtime image does](#what-every-runtime-image-does) ·
  [hooks and their variables](#hooks-and-their-variables) · [Proton notes](#proton-notes) · [layout](#layout)
- [Contributing](CONTRIBUTING.md) · [Security](SECURITY.md) · [Licence](#licence)

## Tags

Every tag is `ghcr.io/sneakywrld/octail-yolks:<tag>` and is also pushed as `<tag>-<yyyymmdd>` (the build date) so a
node can pin one build. `images.json` is the list CI builds from (tag, folder, platforms, kind, the boot-test command,
description, the third-party
images each tag stands in for, and the shipped eggs that use it); the tables below follow it, and
`test/check-images.sh` fails when a tag has no row here. The egg names are the files in Octail's `eggs/` folder (see
[octail-eggs](https://github.com/sneakywrld/octail-eggs) for where each is published).

### Runtimes

| Tag | Platforms | Contents | Octail eggs using it |
| --- | --- | --- | --- |
| <a name="java_8"></a>`java_8` | amd64, arm64 | Java 8 (Eclipse Temurin JDK, Ubuntu 24.04): Minecraft up to 1.16 | minecraft-fabric, -forge, -neoforge, -paper, -velocity |
| <a name="java_11"></a>`java_11` | amd64, arm64 | Java 11 (Eclipse Temurin JDK) | minecraft-fabric, -forge, -neoforge, -paper, -velocity |
| <a name="java_17"></a>`java_17` | amd64, arm64 | Java 17 (Eclipse Temurin JDK): Minecraft 1.17–1.20.4 | mindustry, minecraft-* |
| <a name="java_21"></a>`java_21` | amd64, arm64 | Java 21 (Eclipse Temurin JDK): Minecraft 1.20.5+ | mindustry, minecraft-* |
| <a name="java_25"></a>`java_25` | amd64, arm64 | Java 25 (Eclipse Temurin JDK) | minecraft-* |
| <a name="dotnet_8"></a>`dotnet_8` | amd64, arm64 | .NET 8 runtime (Debian 12) | terraria-tmodloader, vintage-story |
| <a name="dotnet_9"></a>`dotnet_9` | amd64, arm64 | .NET 9 runtime (Debian 12); .NET 9 support ends November 2026 | terraria-tshock |
| <a name="dotnet_10"></a>`dotnet_10` | amd64, arm64 | .NET 10 runtime (Ubuntu 24.04) | space-station-14, terraria-tshock, vintage-story |
| <a name="mono"></a>`mono` | amd64, arm64 | Debian's `mono-complete` | – |
| <a name="nodejs_20"></a>`nodejs_20` | amd64, arm64 | Node.js 20 (Debian 12), git, native-module build tools | – |
| <a name="nodejs_22"></a>`nodejs_22` | amd64, arm64 | Node.js 22 (Debian 12), git, native-module build tools | – |
| <a name="python_3.12"></a>`python_3.12` | amd64, arm64 | Python 3.12 (Debian 12), git, a C compiler for wheels | – |
| <a name="go_1.23"></a>`go_1.23` | amd64, arm64 | Go 1.23 (Debian 12); `GOPATH`/`GOCACHE` in the server folder | – |
| <a name="debian"></a>`debian` | amd64, arm64 | Debian 12 with common game-server libraries (SDL, ICU, LZO, fontconfig, SQLite, ffmpeg, ...) | beammp, factorio, minecraft-bedrock, openrct2, openttd, terraria-vanilla |
| <a name="alpine"></a>`alpine` | amd64, arm64 | Small Alpine runtime (bash, libstdc++) | test-game |

Node.js 20 and Go 1.23 are past their upstream end of life; they are here because eggs ask for them.

### SteamCMD and game images

| Tag | Platforms | Contents | Octail eggs using it |
| --- | --- | --- | --- |
| <a name="steamcmd_debian"></a>`steamcmd_debian` | amd64 | SteamCMD servers on Debian 12: i386 + 32-bit libs for SteamCMD/steamclient, Xvfb + xauth, libpulse0 + libatomic1 (Valheim), ICU, libcurl(-gnutls), `rcon`, `nc` and `telnet` (7 Days to Die's console), auto-update hook | 7-days-to-die, american-truck-simulator, ark-survival-evolved, arma-reforger, assetto-corsa, avorion, barotrauma, conan-exiles, core-keeper, counter-strike-source, craftopia, dont-starve-together, euro-truck-simulator-2, holdfast, hurtworld, killing-floor-2, mordhau, necesse, palworld, project-zomboid, rising-world, satisfactory, scp-secret-laboratory, soulmask, squad, steamcmd-generic, the-front, the-isle, unturned, valheim, valheim-bepinex |
| <a name="steamcmd_ubuntu"></a>`steamcmd_ubuntu` | amd64 | The same on Ubuntu 24.04 (newer glibc/libstdc++, libc++; `libc++.so` is the library itself, not Ubuntu's linker script, so Pavlov can load it) | insurgency-sandstorm, pavlov-vr, stationeers |
| <a name="steamcmd_dotnet"></a>`steamcmd_dotnet` | amd64 | `steamcmd_debian` + Microsoft's ASP.NET Core 8 runtime (`dotnet` on PATH) | eco |
| <a name="steamcmd_sniper"></a>`steamcmd_sniper` | amd64 | Valve's Steam Runtime 3 "sniper" + tini, `rcon`, auto-update hook | counter-strike-2 |
| <a name="source"></a>`source` | amd64 | `steamcmd_debian` + the 32-bit libraries srcds and hlds need (curl, ncurses5/tinfo5, bz2, tcmalloc, OpenSSL 3 and zlib for Sven Co-op); updates before start by default | counter-strike-16, counter-strike-condition-zero, day-of-defeat, day-of-defeat-source, deathmatch-classic, garrysmod, half-life-deathmatch, left-4-dead-2, source-engine, sven-co-op, team-fortress-2, team-fortress-classic |
| <a name="rust"></a>`rust` | amd64 | `steamcmd_debian` + the `FRAMEWORK` hook (vanilla, oxide, carbon); updates before start by default | rust |

### Wine and Proton

| Tag | Platforms | Contents | Octail eggs using it |
| --- | --- | --- | --- |
| <a name="proton"></a>`proton` | amd64 | GE-Proton (`proton run ./Server.exe`), Python 3, Xvfb, SteamCMD update (with app 1007) | abiotic-factor, ark-survival-ascended, astroneer, enshrouded, steamcmd-generic |
| <a name="wine"></a>`wine` | amd64 | WineHQ stable, winetricks, Wine Mono/Gecko baked in, Xvfb (on unless `XVFB=0`), prefix + `WINETRICKS_RUN` hook, SteamCMD update (with app 1007) | aska, empyrion, icarus, myth-of-empires, night-of-the-dead, pixark, return-to-moria, sons-of-the-forest, space-engineers, stormworks, the-forest |
| <a name="wine_staging"></a>`wine_staging` | amd64 | The same with WineHQ staging | empyrion, stormworks, v-rising |

SteamCMD, Wine, Proton and Source images are amd64 only: SteamCMD, the Steam client libraries and Windows servers are
x86.

### Installers

Images for egg install scripts: no entrypoint, run as root (see [below](#what-every-runtime-image-does)).

| Tag | Platforms | Contents | Octail eggs using it |
| --- | --- | --- | --- |
| <a name="installer_debian"></a>`installer_debian` | amd64, arm64 | Install scripts (root): Debian 12, i386 libs for SteamCMD, curl, wget, jq, xq, unzip, zip, 7z, git, dos2unix, rsync, Python 3; apt works | every egg with a Debian installer (74 of them) |
| <a name="installer_alpine"></a>`installer_alpine` | amd64, arm64 | Install scripts (root): Alpine with bash, curl, wget, jq, unzip, git | minecraft-paper, minecraft-velocity, openttd, test-game |
| <a name="installer_java_8"></a>`installer_java_8` | amd64, arm64 | Install scripts that run Java 8 (Temurin JDK + the installer tools): Forge, whose installers (up to 26.x) are Java 8 code | minecraft-forge |
| <a name="installer_java_11"></a>`installer_java_11` | amd64, arm64 | The same with Java 11 | minecraft-fabric |
| <a name="installer_java_21"></a>`installer_java_21` | amd64, arm64 | The same with Java 21: NeoForge (no OpenJDK from apt at every install), the Quilt installer | minecraft-neoforge, minecraft-quilt |
| <a name="installer_java_25"></a>`installer_java_25` | amd64, arm64 | The same with Java 25: Spigot's BuildTools, whose current Minecraft builds (1.21.8 and newer, 26.x) run on Java 25 (older ones download a fitting Temurin JDK at install) | minecraft-spigot |

## Using an image in an egg

Name the tag in the egg's `docker_images` (the label is what the panel shows when a server picks its image) and,
for the install script, an `installer_*` tag as the installation container:

```json
{
  "docker_images": {
    "Java 21": "ghcr.io/sneakywrld/octail-yolks:java_21",
    "Java 17": "ghcr.io/sneakywrld/octail-yolks:java_17"
  },
  "startup": "java -Xms128M -XX:MaxRAMPercentage=95.0 -jar {{SERVER_JARFILE}}",
  "scripts": {
    "installation": {
      "container": "ghcr.io/sneakywrld/octail-yolks:installer_alpine",
      "entrypoint": "ash",
      "script": "..."
    }
  }
}
```

- The startup may use `{{VAR}}` or `${VAR}`; the entrypoint fills both in and runs the line once (see
  [what every runtime image does](#what-every-runtime-image-does)).
- Variables the hooks read (`AUTO_UPDATE`, `SRCDS_APPID`, `WINETRICKS_RUN`, `FRAMEWORK`, `XVFB`, ...) are listed under
  [hooks and their variables](#hooks-and-their-variables); give them to the egg as variables so server owners can
  change them.
- To pin a build, use the dated tag (`java_21-20261005`); the plain tag moves with every rebuild.
- An egg imported from elsewhere that still names a Pterodactyl, Pelican or parkervcp image: Octail's
  `scripts/eggs/switch-images.mjs` rewrites it to these tags (the map is under
  [replacing other images](#replacing-pterodactyl-pelican-and-parkervcp-images)).
- The images are built for Octail's node daemon, Tentacle (non-root `container` user, `/etc/passwd` mounted by the
  daemon, SIGINT to stop). Other panels' daemons aren't tested.

## Building locally

The build context is the repository root (images copy `common/`). With Docker Buildx:

```bash
scripts/build.sh java_21                                   # your platform, loaded into Docker
PLATFORMS=linux/amd64,linux/arm64 PUSH=1 scripts/build.sh java_21   # multi-arch, pushed (docker login ghcr.io first)
docker buildx build -f images/wine/Dockerfile -t octail-yolks:wine .  # the same by hand
```

Build arguments for pinned upstream versions: `GE_PROTON_VERSION` (proton), `WINE_BRANCH` and `WINETRICKS_VERSION`
(wine*), `RCON_CLI_VERSION` (SteamCMD-family images).

Boot test of a built image, the one CI runs before every push (see [Boot tests](#boot-tests)):
`scripts/build.sh java_21 && scripts/smoke.sh ghcr.io/sneakywrld/octail-yolks:java_21 java_21`.

Checks, without Docker: `test/check-images.sh` (folders, allowed bases, every tag with a `smoke` command,
`.github/dependabot.yml` and this README's tag table in sync with `images.json`), `test/run.sh` (that,
`scripts/smoke.sh` against a fake `docker`, entrypoint behaviour: `{{VAR}}`/`${VAR}`, masking, values
never re-evaluated, exit codes, hooks, the SteamCMD retry with a fake `steamcmd.sh`, SIGINT reaching a foreground server
and an egg-style trapped background server; uses `tini` when installed),
`shellcheck -x common/*.sh common/hooks/*.sh scripts/*.sh test/*.sh` and
`hadolint --config .hadolint.yaml images/*/Dockerfile`. [CONTRIBUTING.md](CONTRIBUTING.md) has the steps for a new
image.

## How updates work

- **Weekly rebuild**: every Monday at 04:17 UTC CI rebuilds every image from its (floating) base tag, so the images
  pick up their bases' security fixes without a commit here. A rebuild only **pushes** when the image's content
  changed (a new base digest, a package upgrade, a changed input; see [Rebuild policy](#rebuild-policy)), so tags and
  dated tags don't move for nothing.
- **Dated tags**: each build pushes `<tag>` and `<tag>-<yyyymmdd>`. The plain tag always points at the newest build;
  dated tags stay, so a node or egg can pin one and roll back to an earlier one.
- **Changes**: a push to `main` rebuilds the images whose folder changed (all of them when `common/`, `images.json` or
  the workflow changed). Pull requests run the tests, build and boot-test without pushing.
- **Dependabot** (`.github/dependabot.yml`, generated by `scripts/dependabot.sh`) proposes GitHub Actions updates and
  patch updates of the bases' tags each week. A tag never moves to a new major/minor base by itself (`java_8` stays
  on Java 8); that is a new tag or a deliberate Dockerfile change.
- Upstream versions pinned in the Dockerfiles (GE-Proton, winetricks, rcon-cli) are bumped by hand after a test run.
- A new `WINETRICKS_VERSION` needs its commit and sha256 in `common/wine-checksums.sh`; a Wine release that asks for a
  Wine Mono or Gecko version not listed there stops the build and prints the sha256 Wine's `addons.c` names, to check
  against the download and add.

### How CI publishes

`.github/workflows/build.yml`:

- **test**: shellcheck, hadolint, actionlint, `test/check-images.sh` (`images.json` matches the `images/` folders,
  bases only from `bases.txt`, every tag has a `smoke` command, generated files in sync), `test/check-workflows.sh`
  (actions pinned by SHA, tool downloads by sha256, the scan and sign steps in place), `test/run.sh`.
- **plan**: picks the images (`scripts/select-images.sh`): on a push to `main`, those whose folder changed (all of them
  when `common/`, `images.json` or the workflow changed); weekly (Monday 04:17 UTC) and on a manual run without input,
  all; a manual run (Actions → build → Run workflow) can name tags (`java_21,wine`) and tick **force** to push even
  when the content is unchanged.
- **build**: one job per image, Buildx (+ QEMU for arm64), pushed with the workflow's `GITHUB_TOKEN`
  (`packages: write`) as `ghcr.io/sneakywrld/octail-yolks:<tag>` and `:<tag>-<yyyymmdd>`, with the
  `org.opencontainers.image.source` label (and index annotation for multi-arch) pointing at this repository so the
  package links to it. Pull requests build without pushing. Before the push, the job builds the `linux/amd64` image
  with `--load` (the multi-arch build then reuses its layers) and boot-tests it with `scripts/smoke.sh`; a failed
  boot test ends the job, so neither `:<tag>` nor `:<tag>-<yyyymmdd>` moves. The job summary shows each tag's size
  (uncompressed, amd64) and boot-test result, with the output's tail when it failed. After the boot test the image is
  scanned (`scripts/scan.sh`, a fixable CRITICAL in our own layers stops the push), the content check decides whether
  anything changed (`scripts/content-check.sh`, [Rebuild policy](#rebuild-policy)), then every platform in
  `images.json` is built and pushed with BuildKit's SBOM and SLSA provenance attestations, signed and attested with
  cosign (`scripts/sign.sh`; see [Supply chain](#supply-chain-scans-sboms-signatures)), and the image's facts are
  collected for the build report (`scripts/report.sh fact`).
- **report**: after all builds (also when some failed; never for pull requests), merges the facts into
  `stats/images.json` on the `stats` branch ([Build report](#build-report-statsimagesjson)). It is the only job with
  `contents: write`; every other job has a read-only token plus exactly what it needs (`packages: write`,
  `id-token: write`, `security-events: write` in build).

### Platforms

Each tag lists its platforms in `images.json` and CI builds exactly those (Buildx, arm64 through QEMU on the amd64
runner; the boot test and the scan run on the amd64 image). `linux/arm64` is built for every image whose base and
contents exist for arm64: the Java, .NET, Node.js, Python, Go, Mono, Debian and Alpine runtimes and every installer
(`installer_debian` adds its 32-bit SteamCMD libraries on amd64 only, behind a `TARGETARCH` check). The SteamCMD
family (`steamcmd_*`, `source`, `rust`) and `proton`/`wine*` are **linux/amd64 only**: SteamCMD, the Source engine and
Wine/Proton's Windows binaries are x86 (32-bit libraries included). `test/check-images.sh` enforces this: every tag
lists `linux/amd64` (plus optionally `linux/arm64`), and those families, or a Dockerfile installing `:i386` packages
without a `TARGETARCH` guard, can't list arm64.

### Rebuild policy

`scripts/content-check.sh` runs after the scan and before the push. It computes the image's **content fingerprint**,
the sha256 of:

- the build inputs: every file in the image's folder and in `common/` (by content) and its `images.json` entry
  (`tag`, `folder`, `kind`, `platforms`, `description`; `eggs`/`replaces` don't go into the image);
- the digest of every image a `FROM` pulls (index digests, so a new arm64 base counts too);
- the packages in the freshly built amd64 image's SBOM (package URLs with versions, and the OS release).

The pushed image carries it as the label `org.octail.yolks.fingerprint`. When the published `:<tag>` has the same
fingerprint, the job skips the multi-arch build, push and signing (the summary says "no push" and why), but still
reports the fresh CVE counts. It pushes when the fingerprint differs, when nothing with a fingerprint is published
yet, when something could not be read (better a needless push than a missed fix), and when a manual run asks for
**force**. Timestamps, the build date and the commit are not part of the fingerprint.

### Boot tests

A build can succeed and still produce an image that can't start a server: tini missing, the wrong user, a broken
hook, a runtime binary that isn't there or doesn't load. `scripts/smoke.sh <image> <tag>` starts the image the way
Tentacle does and runs the tag's `smoke` command from `images.json`:

- **runtime** images: `STARTUP=<smoke>` through the image's own `tini -g -- /entrypoint.sh` and hooks, with a
  read-only root filesystem, a 100 MB `/tmp` tmpfs, a writable `/home/container` bind, a uid the image doesn't know
  (with Tentacle's two-line `/etc/passwd` and `/etc/group`), `--cap-drop ALL`, `no-new-privileges` and a PID limit.
  Before the smoke command the startup checks that PID 1 is tini, the uid isn't 0 and the server folder is writable,
  and the output must show the entrypoint's `container~` line. Smoke commands: the runtime's version (`java -version`,
  `dotnet --list-runtimes`, `node -v`, `python3 -V`, `go version`, `mono --version`, grepped for the tag's version);
  SteamCMD-family images: `rcon` is there and `ldd` of the 32-bit libraries finds everything (SteamCMD itself comes
  with the egg's installer); Wine: `wine --version` and the prefix the Wine hook created under Xvfb; Proton:
  GE-Proton's own `wine --version`.
- **installer** images: `bash -c <smoke>` as root (the image's own ENTRYPOINT stays, like on a node) with
  `--cap-drop ALL` plus the capabilities Tentacle gives installers, `no-new-privileges` and the server folder at
  `/mnt/server`. Smoke commands: `curl --version && jq --version`, plus `java -version` in the Java installers.

The test passes when the container exits 0 within `SMOKE_TIMEOUT` seconds (600); nothing is downloaded. A new tag
needs a `smoke` command (`test/check-images.sh` fails without one): keep it fast and offline, and make it fail when
what the image exists for is missing (`grep` the version, `test -f` what a hook should have made).

### Supply chain: scans, SBOMs, signatures

- **Vulnerability scan** before every push: [Trivy](https://trivy.dev) on the boot-tested amd64 image
  (`scripts/scan.sh`). HIGH and CRITICAL findings go to the job summary (per tag: counts, and a table with package,
  versions and whether the finding is in the base image's layers or ours) and, as SARIF, to code scanning (needs
  GitHub Advanced Security on a private repository; otherwise that upload is skipped with a warning).
- **Policy**: the build fails only on a **CRITICAL** finding that **has a fix** and is in **a layer we added**.
  Findings in the official base's own layers and findings without a fix are reported, never fatal: the base's
  publisher fixes them and the weekly rebuild picks the fix up. Exceptions go into `.trivyignore`, each with a comment
  line saying why and an expiry date (`CVE-2026-12345 exp:2026-12-31`).
- **SBOM** (CycloneDX) per platform, made from the pushed image, kept with the Trivy report and SARIF as the
  `supply-chain-<tag>` build artifact (90 days) and attached to each platform image as a signed attestation. BuildKit
  also attaches its own SBOM (`sbom: true`) as an in-registry attestation.
- **Provenance**: BuildKit's SLSA provenance (`provenance: mode=max`: the source, the build's parameters and steps) is
  attached to every push as an in-registry attestation, and `scripts/sign.sh` attests the same provenance per platform
  with cosign, so it is signed with the workflow identity (`cosign verify-attestation --type slsaprovenance`, same
  flags as below). GitHub's own artifact attestations (`actions/attest-build-provenance`) are not used: they need
  GitHub Enterprise Cloud on a private repository, and the cosign attestation gives the same guarantee anywhere.
- **Signature**: `cosign sign` keyless with the workflow's GitHub OIDC identity (Sigstore Fulcio + the public Rekor
  log), recursively over the index and its platform images (`scripts/sign.sh`). Verify on any host (cosign v3+):

  ```bash
  cosign verify ghcr.io/sneakywrld/octail-yolks:java_21 \
    --certificate-identity https://github.com/sneakywrld/octail-yolks/.github/workflows/build.yml@refs/heads/main \
    --certificate-oidc-issuer https://token.actions.githubusercontent.com
  ```

  The SBOM: `cosign verify-attestation --type cyclonedx` with the same two flags, on a platform image's digest
  (`docker buildx imagetools inspect --raw <image>` lists them); the provenance: `--type slsaprovenance`.
- **Pinning**: every third-party action is pinned to a full commit SHA with its version as a comment (Dependabot keeps
  both current); hadolint, shellcheck and actionlint downloads are checked against pinned sha256 sums; Trivy and
  cosign are installed at exact versions (`TRIVY_VERSION`, `COSIGN_VERSION`, bumped by hand). `test/check-workflows.sh`
  fails a workflow that breaks any of this (and checks the step order, the content-gated push, the attestations, the
  weekly schedule and that only the report job can write to the repository).

### Build report (stats/images.json)

After every build on `main`, the weekly rebuild and manual runs, the **report** job writes `stats/images.json` on the
**`stats` branch** of this repository (not `main`: `main` is published from the Octail monorepo, a CI commit there
would break the next publish). `stats/images.json` on `main` is a placeholder with the same shape and no images.
Read the live file with `gh api 'repos/sneakywrld/octail-yolks/contents/stats/images.json?ref=stats' -H 'Accept:
application/vnd.github.raw'` (or, once the repository is public,
`https://raw.githubusercontent.com/sneakywrld/octail-yolks/stats/stats/images.json`). Each image's entry is replaced
when it is built again (also when the push was skipped: fresh CVE counts for the published image); images that
weren't built keep their last entry; tags removed from `images.json` disappear.

```jsonc
{
  "schema": 1,                                  // bumped on incompatible changes
  "registry": "ghcr.io/sneakywrld/octail-yolks",
  "generatedAt": "2026-10-26T04:41:09Z",        // when this file was written (UTC)
  "source": "https://github.com/sneakywrld/octail-yolks/actions/runs/123",  // the run, or null
  "images": [                                   // in images.json order
    {
      "tag": "java_21",
      "image": "ghcr.io/sneakywrld/octail-yolks:java_21",
      "kind": "runtime",                        // or "installer"
      "digest": "sha256:…",                     // the published :<tag> (multi-arch index), null if not readable
      "platforms": ["linux/amd64", "linux/arm64"],
      "compressedSize": { "linux/amd64": 201326592, "linux/arm64": 197132288 },  // bytes pulled: layers + config
      "base": "eclipse-temurin:21-jdk-noble",   // the final stage's FROM
      "builtAt": "2026-10-26T04:22:51Z",        // org.opencontainers.image.created of the published image
      "revision": "0123abc…",                   // the commit it was built from
      "fingerprint": "…",                       // content fingerprint (Rebuild policy)
      "pushed": true,                           // false: this run found the content unchanged and pushed nothing
      "checkedAt": "2026-10-26T04:25:02Z",      // when this entry was written
      "vulnerabilities": { "critical": 0, "high": 3, "medium": 21, "low": 40, "unknown": 0 },  // Trivy, amd64
      "fixable": { "critical": 0, "high": 1, "medium": 4, "low": 0, "unknown": 0 },          // of those, with a fix
      "scan": { "platform": "linux/amd64", "scanner": "trivy v0.74.0",
                "policy": { "passed": true, "blocking": 0 } }   // blocking: fixable CRITICAL in our layers
    }
  ]
}
```

Counts are deduplicated per vulnerability, package, version and target, after `.trivyignore`. Fields may be `null`
when the source wasn't readable (an image not yet published, a failed scan). New fields can be added without bumping
`schema`; readers should ignore what they don't know.

### What the owner sets in GitHub

- **Settings → Actions → General → Workflow permissions**: "Read repository contents" is enough (each job asks for
  what it needs); keep "Allow GitHub Actions to create and approve pull requests" off.
- **The `stats` branch** must accept pushes from the workflow's `GITHUB_TOKEN`: no branch protection or ruleset on
  `stats` (or one that lets GitHub Actions bypass). Protect `main` as you like; CI never pushes to it.
- **Code scanning** (SARIF upload) needs GitHub Advanced Security on a private repository; without it the upload
  step warns and the findings stay in the job summary and artifacts.
- **Package visibility**: see [Making the images pullable by the nodes](#making-the-images-pullable-by-the-nodes).

### Making the images pullable by the nodes

GHCR creates the `octail-yolks` package with the visibility of the repository that first pushed it, so a private
repository gives a **private** package that nodes can't pull anonymously. Either:

- make the package public (recommended — the images contain nothing secret): GitHub → your profile → **Packages** →
  `octail-yolks` → **Package settings** → **Danger Zone** → **Change visibility** → Public. It is one package with many
  tags, so this is done once. (If the option is greyed out, allow public packages under Settings → Packages first.)
- or keep it private and log each node in: a classic personal access token with only `read:packages`, then
  `docker login ghcr.io -u <user>` (Podman: `podman login ghcr.io`) as the user the container engine pulls as.

Check from a node: `docker pull ghcr.io/sneakywrld/octail-yolks:debian`.

## Replacing Pterodactyl, Pelican and parkervcp images

Every egg Octail ships uses these images; none uses a Pterodactyl, Pelican or parkervcp image any more (Octail's
`panel/test/eggs-shipped.test.js` checks it, and the generated octail-eggs workflow refuses them). The third-party
image → tag map is in `images.json` (`replaces`) and in Octail's `scripts/eggs/yolks-map.json`, which
`scripts/eggs/switch-images.mjs` applies to eggs imported from elsewhere. In short:

| Old image | Tag |
| --- | --- |
| `ghcr.io/pelican-eggs/yolks:java_8` / `java_11` / `java_17` / `java_21` / `java_25` | `java_8` / `java_11` / `java_17` / `java_21` / `java_25` |
| `ghcr.io/pelican-eggs/yolks:java_16` | `java_17` (Java 16 is gone upstream; 1.17 runs on 17) |
| `ghcr.io/parkervcp/yolks:dotnet_6`, `pelican-eggs/yolks:dotnet_7`, `*/yolks:dotnet_8` | `dotnet_8` |
| `ghcr.io/pelican-eggs/yolks:dotnet_9` | `dotnet_9` |
| `ghcr.io/pelican-eggs/yolks:dotnet_10` | `dotnet_10` |
| `ghcr.io/parkervcp/yolks:debian`, `pelican-eggs/yolks:debian` | `debian` |
| `ghcr.io/pterodactyl/yolks:alpine` | `alpine` |
| `ghcr.io/parkervcp/steamcmd:debian`, `pelican-eggs/steamcmd:debian`, `parkervcp/games:valheim` | `steamcmd_debian` |
| `ghcr.io/parkervcp/steamcmd:ubuntu` | `steamcmd_ubuntu` |
| `ghcr.io/parkervcp/steamcmd:dotnet` | `steamcmd_dotnet` |
| `ghcr.io/parkervcp/steamcmd:sniper` | `steamcmd_sniper` |
| `ghcr.io/parkervcp/games:source`, `pelican-eggs/games:source` | `source` |
| `ghcr.io/pelican-eggs/games:rust` | `rust` |
| `ghcr.io/parkervcp/steamcmd:proton`, `pelican-eggs/steamcmd:proton` | `proton` |
| `ghcr.io/parkervcp/yolks:wine_latest`, `pelican-eggs/yolks:wine_latest` | `wine` |
| `ghcr.io/parkervcp/yolks:wine_staging` | `wine_staging` |
| `ghcr.io/parkervcp/installers:debian`, `pelican-eggs/installers:debian` | `installer_debian` |
| `ghcr.io/pelican-eggs/installers:alpine`, `pterodactyl/installers:alpine`, `alpine:latest` | `installer_alpine` |
| `ghcr.io/pelican-eggs/installers:java_8` / `java_11` | `installer_java_8` / `installer_java_11` |

## What every runtime image does

- Runs as the non-root user `container`, `HOME=/home/container`, `WORKDIR /home/container`, `STOPSIGNAL SIGINT`.
  Tentacle runs the container as the node's server user and mounts an `/etc/passwd` naming it `container`, so there is no
  nss_wrapper and no `LD_PRELOAD` (nss_wrapper made Valheim's PlayFab logger crash).
- PID 1 is `tini -g`: a stop signal (Ctrl+C = SIGINT from Tentacle) goes to the server's whole process group, as Ctrl+C
  in a terminal would, so servers run in the foreground of the startup get it directly. Servers started in the background
  (`proton run ... & PID=$!`) ignore SIGINT as background jobs of a script do; their eggs trap INT/TERM and forward it
  (`trap "kill -INT $PID; wait $PID" INT TERM`). Wine's own server process survives SIGINT (it only stops accepting new
  clients), so the forwarded signal reaches the game.
- `/entrypoint.sh` (`common/entrypoint.sh`):
  1. `cd /home/container`, export `INTERNAL_IP` (the address `ip route get` picks).
  2. Source the image's hooks from `/etc/octail/entrypoint.d/*.sh` (below).
  3. Turn `{{VAR}}` / `{{ VAR }}` into `${VAR}`. Tentacle already sends `${VAR}`; eggs imported from elsewhere may not.
     Anything else between `{{ }}` stays as written.
  4. Print `container~ <startup>` with every `${VAR}` filled in, except that values of names containing PASS, PWD,
     SECRET, TOKEN, KEY, AUTH, GSLT, STEAM_ACC or a `PW` part (`SRV_PW`) show as `********`. Extra names:
     `OCTAIL_SECRET_VARS=NAME1,NAME2`. This line is built as text; nothing in it is run.
  5. `eval` the startup once. A variable's value is expanded as a parameter (word-split like any unquoted `${VAR}`),
     never parsed as shell again, so `; rm -rf ~` or `$(...)` in a customer's value is only text — the behaviour
     Tentacle's `test/startup-injection.test.js` checks. The startup's own `$(...)` runs once. Unlike Pterodactyl's
     images there is no `echo -e` pass, so backslashes mean what the startup's quoting says, and newlines are kept.
  6. The container exits with the startup's exit code.
- Locale `en_US.UTF-8` (Alpine and sniper: `C.UTF-8`), `tzdata` (Tentacle's `TZ` works), `curl`, `jq`, `envsubst`,
  `tar`/`unzip`/`xz`, `ip`.

### Hooks and their variables

| Hook | Images | Variables |
| --- | --- | --- |
| `10-java-info.sh` | java_* | prints `java -version` |
| `20-display.sh` | proton, wine* | `XVFB=1` starts Xvfb on `DISPLAY` (`:0`), `DISPLAY_WIDTH`/`HEIGHT`/`DEPTH` (1024×768×16). Unset: the image's `OCTAIL_XVFB_DEFAULT`, on in the Wine images (eggs written for other Wine images expect a display), off in proton |
| `30-wine.sh` | wine* | `WINEPREFIX` (`~/.wine`), `WINEDEBUG` (`-all`), `WINEARCH` (`win64`), `WINEDLLOVERRIDES` exported even when empty (so `WINEDLLOVERRIDES="winhttp=n,b"; wine ...` in a startup reaches Wine); creates the prefix (Mono/Gecko from the image); `WINETRICKS_RUN="vcrun2022 corefonts ..."` installs each verb once (marker in `$WINEPREFIX/.octail-winetricks/`, failures retried next start); `mono` / `gecko` install the baked MSIs |
| `30-proton.sh` | proton | `STEAM_COMPAT_DATA_PATH` (`~/.proton`), `STEAM_COMPAT_CLIENT_INSTALL_PATH` (`~/.steam/steam`), `SteamAppId`/`SteamGameId` from `SRCDS_APPID`, `PROTON_LOG=1`. A prefix left by another Proton image in `~/.steam/steam/steamapps/compatdata/<SRCDS_APPID>` is used while `~/.proton` doesn't exist. Start watch: when the container has no open port (a listening TCP socket or an unconnected UDP one) `OCTAIL_PROTON_WATCH` seconds after the start (300; `0` = off), prints one report: threads against the pids limit and how often it was hit, memory and OOM kills, open-files limit, `/tmp` and `/dev/shm` use, each process's state, threads, memory, CPU, kernel wait channel and command line, with the same secret values masked as in the `container~` line (see "Proton notes") |
| `50-steamcmd-update.sh` | steamcmd_*, source, rust, proton, wine* | Runs when `AUTO_UPDATE=1` (unset: the image default, on for `source` and `rust`; unlike the Pelican/parkervcp images, an unset `AUTO_UPDATE` does not update elsewhere, so eggs carry the variable) and `SRCDS_APPID` is a number, with the SteamCMD the installer left in `./steamcmd`: `SRCDS_BETAID`, `SRCDS_BETAPASS`, `WINDOWS_INSTALL=1`, `STEAM_SDK=1` (app 1007 too; unset: the image's `OCTAIL_STEAM_SDK_DEFAULT`, on in wine* and proton, whose Windows servers take `steamclient64.dll` from it), `HLDS_GAME` (GoldSrc, app 90: `+app_set_config 90 mod <game>` before `app_update`), `VALIDATE=1`, `STEAM_USER`/`STEAM_PASS`/`STEAM_AUTH` (else anonymous). With a Steam account Tentacle sends `STEAM_USER` and an empty `STEAM_PASS` plus `STEAM_LOGIN_CACHE` (the account's saved login, as for the install); the hook links `./steamcmd/config` to it if the installer didn't, so `+login <user>` uses the saved token (a Steam Guard prompt here makes Tentacle stop the server: reinstall to log in again). `app_update` is tried up to 3 times (SteamCMD's first run fails with "Missing configuration"); passwords are masked in the console; `~/.steam/sdk32|64/steamclient.so` are refreshed afterwards. A failed update starts the installed files. |
| `60-rust-framework.sh` | rust | Puts `RustDedicated_Data/Plugins/x86_64` and the server folder on `LD_LIBRARY_PATH`. `FRAMEWORK=vanilla` (default), `oxide`/`umod`, `carbon`, `carbon-edge`, `carbon-staging`: downloaded and unpacked after the update; Carbon's Doorstop variables are set |

### Proton notes

- GE-Proton is pinned to 10-34. Other hosts report GE-Proton 11 (11-1 to 11-7) hanging ARK: Survival Ascended before
  the engine logs a line (the console stops after `wineserver: using server-side synchronization`, memory stays flat,
  CPU near 0) and keeping Astroneer from starting; both run on 10-34. GE-Proton 11 also needs glibc 2.38 (Debian 12
  has 2.36), so `common/install-proton.sh` fails the build for a GE-Proton the base image can't load. Before moving to
  11, run ASA and Astroneer on it.
- `PROTON_USE_XALIA=0`: Proton otherwise starts Xalia (a .NET gamepad-UI helper) next to the game; it needs a display
  and only adds a crashing process to a server.
- Reading the start-watch report: a server process in state `S` with almost no CPU and a `futex_wait`/`do_epoll_wait`
  channel is waiting on something (a lock, a dialog no one sees, the network); `D` is disk; a thread count at the pids
  limit (Tentacle's `runtime.pids_limit`, 512) or a non-zero "limit reached" means the server couldn't start threads;
  OOM kills mean memory. `PROTON_LOG=1` adds Proton's own log (`steam-<appid>.log`, can grow by gigabytes).

Installer images have no entrypoint: Tentacle runs them as root with `bash /mnt/install/install.sh` (or `ash`) in
`/mnt/server`.

## Layout

```
common/entrypoint.sh        the entrypoint every runtime image runs
common/hooks/*.sh           image hooks (copied per image into /etc/octail/entrypoint.d)
common/setup-apt.sh         build-time: packages, locale, `container` user (Debian/Ubuntu)
common/setup-apk.sh         the same for Alpine
common/install-wine.sh      build-time: WineHQ, winetricks, Wine Mono/Gecko (checksum-verified)
common/wine-checksums.sh    pinned sha256 of winetricks and the Wine Mono/Gecko installers
common/install-proton.sh    build-time: GE-Proton (checksum-verified)
images/<tag>/Dockerfile     one folder per tag
images.json                 tag -> folder -> platforms -> kind, smoke command, description, replaced images, eggs
bases.txt                   the official base images Dockerfiles may use (allowlist)
scripts/select-images.sh    CI matrix
scripts/build.sh            local build
scripts/dependabot.sh       prints .github/dependabot.yml from images.json
scripts/smoke.sh            boot test of a built image (CI runs it before every push)
scripts/scan.sh             Trivy scan + SBOM of a built image, the vulnerability policy (before every push)
scripts/sign.sh             cosign signature + SBOM and provenance attestations of a pushed image (after every push)
scripts/content-check.sh    content fingerprint: push only when the image changed (rebuild policy)
scripts/report.sh           build report: per-image facts, merged into stats/images.json on the stats branch
stats/images.json           placeholder of the build report (the live file is on the stats branch)
.trivyignore                accepted vulnerability findings (reason + expiry each)
test/run.sh                 entrypoint, smoke.sh and supply-chain tests (also runs check-images.sh, check-workflows.sh)
test/check-images.sh        images.json <-> folders, smoke commands, base-image allowlist, generated files in sync
test/check-workflows.sh     actions pinned by SHA, downloads by sha256, scan/sign steps, .trivyignore, actionlint
test/supply-chain.sh        tests of check-workflows.sh, scan.sh, sign.sh, content-check.sh, report.sh (sourced by run.sh)
```

## Where the images come from

Images start from official upstream bases only (`debian:bookworm-slim`, `ubuntu:24.04`, `alpine`, `eclipse-temurin`,
`mcr.microsoft.com/dotnet/*`, `node`, `python`, `golang`, Valve's Steam Runtime
`registry.gitlab.steamos.cloud/steamrt/sniper/platform`) plus upstream software from its own publishers (WineHQ's
repository, winetricks, GE-Proton, gorcon/rcon-cli built from source). Nothing here is `FROM` a Pterodactyl, Pelican,
parkervcp or "yolks" image, and no script is copied from them: the entrypoint and hooks are written for Octail and
Tentacle, and the other projects' behaviour was only read to learn what game eggs expect from an image. The allowed
bases are listed in `bases.txt`; `test/check-images.sh` (run by `test/run.sh` and CI) fails when a Dockerfile's
`FROM`, `COPY --from=` or `RUN --mount=from=` names anything else, and when `images.json` and the `images/` folders
disagree. Adding a line to `bases.txt` is a policy decision: official images from the software's own publisher only.

## Licence

None chosen yet. Until the owner picks one, all rights are reserved; the upstream software inside the images keeps its
own licences.
