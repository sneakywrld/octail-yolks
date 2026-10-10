# octail-yolks

The container images Octail runs game servers and their install scripts in, published as
`ghcr.io/sneakywrld/octail-yolks:<tag>`. One image per runtime (Java, .NET, SteamCMD, Wine, Proton, ...), each with
Octail's own entrypoint.

**Policy: no Pterodactyl / Pelican dependency.** Nothing here is `FROM` a Pterodactyl, Pelican, parkervcp or "yolks"
image, and no script is copied from them. Images start from official upstream bases only (`debian:bookworm-slim`,
`ubuntu:24.04`, `alpine`, `eclipse-temurin`, `mcr.microsoft.com/dotnet/*`, `node`, `python`, `golang`, Valve's Steam
Runtime `registry.gitlab.steamos.cloud/steamrt/sniper/platform`) plus upstream software from its own publishers
(WineHQ's repository, winetricks, GE-Proton, gorcon/rcon-cli built from source). The entrypoint and hooks are written for
Octail and Tentacle. The other projects' behaviour was only read to learn what game eggs expect from an image.
The allowed bases are listed in `bases.txt`; `test/check-images.sh` (run by `test/run.sh` and CI) fails when a
Dockerfile's `FROM`, `COPY --from=` or `RUN --mount=from=` names anything else, and when `images.json` and the
`images/` folders disagree.

**Licence:** none chosen yet. Until the owner picks one, all rights are reserved; the upstream software inside the
images keeps its own licences.

## Tags

`images.json` is the list CI builds from (tag, folder, platforms, description, the third-party images each tag stands in
for, and the shipped eggs that use it). Every tag is also pushed as `<tag>-<yyyymmdd>` so a node can pin a build.

| Tag | Platforms | Contents | Octail eggs using it |
| --- | --- | --- | --- |
| `java_8` | amd64, arm64 | Java 8 (Eclipse Temurin JDK, Ubuntu 24.04): Minecraft up to 1.16 | minecraft-fabric, -forge, -neoforge, -paper, -velocity |
| `java_11` | amd64, arm64 | Java 11 (Eclipse Temurin JDK) | minecraft-fabric, -forge, -neoforge, -paper, -velocity |
| `java_17` | amd64, arm64 | Java 17 (Eclipse Temurin JDK): Minecraft 1.17–1.20.4 | mindustry, minecraft-* |
| `java_21` | amd64, arm64 | Java 21 (Eclipse Temurin JDK): Minecraft 1.20.5+ | mindustry, minecraft-* |
| `java_25` | amd64, arm64 | Java 25 (Eclipse Temurin JDK) | minecraft-* |
| `dotnet_8` | amd64, arm64 | .NET 8 runtime (Debian 12) | terraria-tmodloader, vintage-story |
| `dotnet_10` | amd64, arm64 | .NET 10 runtime (Ubuntu 24.04) | vintage-story |
| `nodejs_20` | amd64, arm64 | Node.js 20 (Debian 12), git, native-module build tools | – |
| `nodejs_22` | amd64, arm64 | Node.js 22 (Debian 12), git, native-module build tools | – |
| `python_3.12` | amd64, arm64 | Python 3.12 (Debian 12), git, a C compiler for wheels | – |
| `go_1.23` | amd64, arm64 | Go 1.23 (Debian 12); `GOPATH`/`GOCACHE` in the server folder | – |
| `debian` | amd64, arm64 | Debian 12 with common game-server libraries (SDL, ICU, LZO, fontconfig, SQLite, ffmpeg, ...) | factorio, minecraft-bedrock, openttd, terraria-vanilla |
| `alpine` | amd64, arm64 | Small Alpine runtime (bash, libstdc++) | test-game |
| `steamcmd_debian` | amd64 | SteamCMD servers on Debian 12: i386 + 32-bit libs for SteamCMD/steamclient, Xvfb + xauth, libpulse0 + libatomic1 (Valheim), ICU, libcurl(-gnutls), `rcon`, `nc` and `telnet` (7 Days to Die's console), auto-update hook | 7-days-to-die, ark-survival-evolved, arma-reforger, avorion, barotrauma, conan-exiles, core-keeper, counter-strike-source, craftopia, dont-starve-together, euro-truck-simulator-2, hurtworld, killing-floor-2, mordhau, necesse, palworld, project-zomboid, satisfactory, soulmask, squad, steamcmd-generic, the-front, unturned, valheim, valheim-bepinex |
| `steamcmd_ubuntu` | amd64 | The same on Ubuntu 24.04 (newer glibc/libstdc++, libc++; `libc++.so` is the library itself, not Ubuntu's linker script, so Pavlov can load it) | insurgency-sandstorm, pavlov-vr, stationeers |
| `steamcmd_dotnet` | amd64 | `steamcmd_debian` + Microsoft's ASP.NET Core 8 runtime (`dotnet` on PATH) | eco |
| `steamcmd_sniper` | amd64 | Valve's Steam Runtime 3 "sniper" + tini, `rcon`, auto-update hook | counter-strike-2 |
| `source` | amd64 | `steamcmd_debian` + the 32-bit libraries srcds needs (curl, ncurses5/tinfo5, bz2, tcmalloc); updates before start by default | day-of-defeat-source, garrysmod, left-4-dead-2, source-engine, team-fortress-2 |
| `rust` | amd64 | `steamcmd_debian` + the `FRAMEWORK` hook (vanilla, oxide, carbon); updates before start by default | rust |
| `proton` | amd64 | GE-Proton (`proton run ./Server.exe`), Python 3, Xvfb, SteamCMD update (with app 1007) | abiotic-factor, ark-survival-ascended, astroneer, enshrouded, steamcmd-generic |
| `wine` | amd64 | WineHQ stable, winetricks, Wine Mono/Gecko baked in, Xvfb (on unless `XVFB=0`), prefix + `WINETRICKS_RUN` hook, SteamCMD update (with app 1007) | icarus, sons-of-the-forest, space-engineers |
| `wine_staging` | amd64 | The same with WineHQ staging | v-rising |
| `mono` | amd64, arm64 | Debian's `mono-complete` | – |
| `installer_debian` | amd64, arm64 | Install scripts (root): Debian 12, i386 libs for SteamCMD, curl, wget, jq, xq, unzip, zip, 7z, git, dos2unix, rsync, Python 3; apt works | every egg with a Debian installer (50 of them) |
| `installer_alpine` | amd64, arm64 | Install scripts (root): Alpine with bash, curl, wget, jq, unzip, git | minecraft-paper, minecraft-velocity, openttd, test-game |
| `installer_java_8` | amd64, arm64 | Install scripts that run Java 8 (Temurin JDK + the installer tools): Forge, whose installers (up to 26.x) are Java 8 code | minecraft-forge |
| `installer_java_11` | amd64, arm64 | The same with Java 11 | minecraft-fabric |
| `installer_java_21` | amd64, arm64 | The same with Java 21: NeoForge (no OpenJDK from apt at every install) | minecraft-neoforge |

SteamCMD, Wine, Proton and Source images are amd64 only: SteamCMD, the Steam client libraries and Windows servers are
x86. Node.js 20 and Go 1.23 are past their upstream end of life; they are here because eggs ask for them.

### The eggs' switch (done)

Every egg Octail ships uses these images; none uses a Pterodactyl, Pelican or parkervcp image any more (Octail's
`panel/test/eggs-shipped.test.js` checks it, and the generated octail-eggs workflow refuses them). The third-party
image → tag map is in `images.json` (`replaces`) and in Octail's `scripts/eggs/yolks-map.json`, which
`scripts/eggs/switch-images.mjs` applies to eggs imported from elsewhere. In short:

| Old image | Tag |
| --- | --- |
| `ghcr.io/pelican-eggs/yolks:java_8` / `java_11` / `java_17` / `java_21` / `java_25` | `java_8` / `java_11` / `java_17` / `java_21` / `java_25` |
| `ghcr.io/pelican-eggs/yolks:java_16` | `java_17` (Java 16 is gone upstream; 1.17 runs on 17) |
| `ghcr.io/parkervcp/yolks:dotnet_6`, `pelican-eggs/yolks:dotnet_7`, `*/yolks:dotnet_8` | `dotnet_8` |
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
| `30-proton.sh` | proton | `STEAM_COMPAT_DATA_PATH` (`~/.proton`), `STEAM_COMPAT_CLIENT_INSTALL_PATH` (`~/.steam/steam`), `SteamAppId`/`SteamGameId` from `SRCDS_APPID`, `PROTON_LOG=1`. A prefix left by another Proton image in `~/.steam/steam/steamapps/compatdata/<SRCDS_APPID>` is used while `~/.proton` doesn't exist. Start watch: when the container has no open port (a listening TCP socket or an unconnected UDP one) `OCTAIL_PROTON_WATCH` seconds after the start (300; `0` = off), prints one report: threads against the pids limit and how often it was hit, memory and OOM kills, open-files limit, `/tmp` and `/dev/shm` use, each process's state, threads, memory, CPU and kernel wait channel (see "Proton notes") |
| `50-steamcmd-update.sh` | steamcmd_*, source, rust, proton, wine* | Runs when `AUTO_UPDATE=1` (unset: the image default, on for `source` and `rust`; unlike the Pelican/parkervcp images, an unset `AUTO_UPDATE` does not update elsewhere, so eggs carry the variable) and `SRCDS_APPID` is a number, with the SteamCMD the installer left in `./steamcmd`: `SRCDS_BETAID`, `SRCDS_BETAPASS`, `WINDOWS_INSTALL=1`, `STEAM_SDK=1` (app 1007 too; unset: the image's `OCTAIL_STEAM_SDK_DEFAULT`, on in wine* and proton, whose Windows servers take `steamclient64.dll` from it), `HLDS_GAME`, `VALIDATE=1`, `STEAM_USER`/`STEAM_PASS`/`STEAM_AUTH` (else anonymous). With a Steam account Tentacle sends `STEAM_USER` and an empty `STEAM_PASS` plus `STEAM_LOGIN_CACHE` (the account's saved login, as for the install); the hook links `./steamcmd/config` to it if the installer didn't, so `+login <user>` uses the saved token (a Steam Guard prompt here makes Tentacle stop the server: reinstall to log in again). `app_update` is tried up to 3 times (SteamCMD's first run fails with "Missing configuration"); passwords are masked in the console; `~/.steam/sdk32|64/steamclient.so` are refreshed afterwards. A failed update starts the installed files. |
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

## Building locally

The build context is the repository root (images copy `common/`). With Docker Buildx:

```bash
scripts/build.sh java_21                                   # your platform, loaded into Docker
PLATFORMS=linux/amd64,linux/arm64 PUSH=1 scripts/build.sh java_21   # multi-arch, pushed (docker login ghcr.io first)
docker buildx build -f images/wine/Dockerfile -t octail-yolks:wine .  # the same by hand
```

Build arguments for pinned upstream versions: `GE_PROTON_VERSION` (proton), `WINE_BRANCH` and `WINETRICKS_VERSION`
(wine*), `RCON_CLI_VERSION` (SteamCMD-family images).

Checks, without Docker: `test/check-images.sh` (folders and allowed bases), `test/run.sh` (that, entrypoint behaviour: `{{VAR}}`/`${VAR}`, masking, values never re-evaluated,
exit codes, hooks, the SteamCMD retry with a fake `steamcmd.sh`, SIGINT reaching a foreground server and an egg-style
trapped background server; uses `tini` when installed), `shellcheck -x common/*.sh common/hooks/*.sh scripts/*.sh test/*.sh`
and `hadolint --config .hadolint.yaml images/*/Dockerfile`.

## How CI publishes

`.github/workflows/build.yml`:

- **test**: shellcheck, hadolint, `test/check-images.sh` (`images.json` matches the `images/` folders, bases only
  from `bases.txt`), `test/run.sh`.
- **plan**: picks the images (`scripts/select-images.sh`): on a push to `main`, those whose folder changed (all of them
  when `common/`, `images.json` or the workflow changed); weekly (Monday 04:17 UTC) and on a manual run without input,
  all; a manual run can name tags (`java_21,wine`).
- **build**: one job per image, Buildx (+ QEMU for arm64), pushed with the workflow's `GITHUB_TOKEN`
  (`packages: write`) as `ghcr.io/sneakywrld/octail-yolks:<tag>` and `:<tag>-<yyyymmdd>`, with the
  `org.opencontainers.image.source` label (and index annotation for multi-arch) pointing at this repository so the
  package links to it. Pull requests build without pushing.

### Making the images pullable by the nodes

The repository is private, so the `octail-yolks` package GHCR creates on the first push is **private** too, and nodes
can't pull anonymously. Either:

- make the package public (recommended — the images contain nothing secret): GitHub → your profile → **Packages** →
  `octail-yolks` → **Package settings** → **Danger Zone** → **Change visibility** → Public. It is one package with many
  tags, so this is done once. (If the option is greyed out, allow public packages under Settings → Packages first.)
- or keep it private and log each node in: a classic personal access token with only `read:packages`, then
  `docker login ghcr.io -u <user>` (Podman: `podman login ghcr.io`) as the user the container engine pulls as.

Check from a node: `docker pull ghcr.io/sneakywrld/octail-yolks:debian`.

## Layout

```
common/entrypoint.sh        the entrypoint every runtime image runs
common/hooks/*.sh           image hooks (copied per image into /etc/octail/entrypoint.d)
common/setup-apt.sh         build-time: packages, locale, `container` user (Debian/Ubuntu)
common/setup-apk.sh         the same for Alpine
common/install-wine.sh      build-time: WineHQ, winetricks, Wine Mono/Gecko
common/install-proton.sh    build-time: GE-Proton (checksum-verified)
images/<tag>/Dockerfile     one folder per tag
images.json                 tag -> folder -> platforms -> description, replaced images, eggs
bases.txt                   the official base images Dockerfiles may use (allowlist)
scripts/select-images.sh    CI matrix
scripts/build.sh            local build
test/run.sh                 entrypoint tests (also runs check-images.sh)
test/check-images.sh        images.json <-> folders, base-image allowlist
```
