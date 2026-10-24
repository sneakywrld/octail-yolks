# octail-yolks: what it is and how it got here

This file is the long-form history of octail-yolks: why the images exist, how they are built, signed and scanned, every
image with its base and the eggs that use it, and a changelog of all image work so far, newest first. The
[README](README.md) is the reference (tags, hooks, variables, building); the eggs have their own history in
[octail-eggs' eggs.md](https://github.com/sneakywrld/octail-eggs/blob/main/eggs.md).

- [What octail-yolks is, and why](#what-octail-yolks-is-and-why)
- [How the images are built, tested, scanned and signed](#how-the-images-are-built-tested-scanned-and-signed)
- [The images](#the-images)
- [Which eggs use which image](#which-eggs-use-which-image)
- [Changelog](#changelog)

## What octail-yolks is, and why

Every Octail game server runs in a container, and every egg install script runs in one too. These are those
containers: one image per runtime (Java, .NET, Node.js, Python, Go, SteamCMD, Source, Wine, Proton, ...) plus the
installer images, published as `ghcr.io/sneakywrld/octail-yolks:<tag>`.

Octail started on the community images most panels use (Pterodactyl's, Pelican's and parkervcp's "yolks"). On
2026-10-09 the owner asked for our own instead, and since 2026-10-19 they are the only images Octail's own servers run:

- **No third-party images.** Every Dockerfile starts from an official upstream base (Debian, Ubuntu, Alpine, Eclipse
  Temurin, Microsoft's .NET images, the official Node.js, Python and Go images, Valve's Steam Runtime), listed in
  `bases.txt`. Nothing is `FROM` a Pterodactyl, Pelican, parkervcp or other "yolks" image and no script is copied from
  them; `test/check-images.sh` fails a Dockerfile that tries.
- **Our own entrypoint.** One entrypoint for every runtime image, written for Octail's node daemon (Tentacle): it fills
  in `{{VAR}}` and `${VAR}`, prints the startup line with secret values masked, and runs the startup once without ever
  re-reading a customer's value as shell. No `nss_wrapper` (the node mounts an `/etc/passwd`; the wrapper crashed
  Valheim), `tini` as PID 1 so a stop reaches the server's whole process group.
- **Knowing what runs.** With our own images we decide what is in them, can scan and sign them, and can fix a game's
  missing library ourselves the same day instead of waiting for someone else's image.
- **The panel enforces it.** Since 2026-10-19 the panel's `servers.allowed_images` setting allows only octail-yolks
  images by default (Root can bypass it), egg and Pterodactyl imports map foreign images to their octail-yolks
  replacement (`images.json` lists what each tag replaces), and every egg Octail ships uses these images only.

## How the images are built, tested, scanned and signed

All of it runs in this repository's `.github/workflows/build.yml`; the README has the details.

1. **Test**: shellcheck, hadolint, actionlint, `test/check-images.sh` (`images.json` matches the `images/` folders,
   bases only from `bases.txt`, every tag has a boot-test command, generated files in sync),
   `test/check-workflows.sh` (actions pinned by commit SHA, tool downloads by sha256, the scan and sign steps in place)
   and `test/run.sh` (the entrypoint's behaviour, hooks, the SteamCMD retry, stop signals).
2. **Plan**: a push to `main` rebuilds the images whose folder changed (all of them when `common/`, `images.json` or
   the workflow changed); every Monday at 04:17 UTC all images are rebuilt from their bases to pick up security fixes.
3. **Build and boot test**: Buildx (QEMU for arm64). Before anything is pushed, the amd64 image is started the way
   Tentacle starts it (read-only root, no capabilities, an unknown uid) and runs its tag's `smoke` command; a failure
   stops the push.
4. **Scan**: Trivy on the boot-tested image. HIGH and CRITICAL findings go to the job summary; the build fails only on a
   CRITICAL finding that has a fix and sits in a layer we added. Exceptions go into `.trivyignore` with a reason and an
   expiry date.
5. **Push**: `<tag>` and `<tag>-<yyyymmdd>`, so a node can pin one build and roll back.
6. **Sign**: keyless `cosign` signatures with the workflow's GitHub identity (Sigstore), plus CycloneDX SBOMs attached
   as signed attestations. `cosign verify` with the identity in the README checks an image on any host.
7. **Upstream pins**: GE-Proton, winetricks (by commit and sha256), Wine Mono and Gecko (by sha256) and rcon-cli are
   pinned and bumped by hand after a test run; Dependabot proposes Actions updates and patch bumps of the bases.

## The images

30 tags. "Base" is the final `FROM`; several images also build `rcon` from source in a `golang:1.23-bookworm` stage.

### Runtimes

| Tag           | Base                                                 | Purpose                                                                 |
| ------------- | ---------------------------------------------------- | ----------------------------------------------------------------------- |
| `java_8`      | `eclipse-temurin:8-jdk-noble`                        | Java 8: Minecraft up to 1.16, old modpacks                              |
| `java_11`     | `eclipse-temurin:11-jdk-noble`                       | Java 11                                                                 |
| `java_17`     | `eclipse-temurin:17-jdk-noble`                       | Java 17: Minecraft 1.17 to 1.20.4                                       |
| `java_21`     | `eclipse-temurin:21-jdk-noble`                       | Java 21: Minecraft 1.20.5 and newer                                     |
| `java_25`     | `eclipse-temurin:25-jdk-noble`                       | Java 25: current Minecraft, Hytale                                      |
| `dotnet_8`    | `mcr.microsoft.com/dotnet/runtime:8.0-bookworm-slim` | .NET 8 (tModLoader, older Vintage Story)                                |
| `dotnet_9`    | `mcr.microsoft.com/dotnet/runtime:9.0-bookworm-slim` | .NET 9 (TShock 6); .NET 9 support ends November 2026                    |
| `dotnet_10`   | `mcr.microsoft.com/dotnet/runtime:10.0-noble`        | .NET 10 (Space Station 14, Vintage Story 1.22+, TShock)                 |
| `mono`        | `debian:bookworm-slim`                               | Debian's `mono-complete`                                                |
| `nodejs_20`   | `node:20-bookworm-slim`                              | Node.js 20 with git and native-module build tools (past upstream EOL)   |
| `nodejs_22`   | `node:22-bookworm-slim`                              | Node.js 22 with git and native-module build tools                       |
| `python_3.12` | `python:3.12-slim-bookworm`                          | Python 3.12 with git and a C compiler for wheels                        |
| `go_1.23`     | `golang:1.23-bookworm`                               | Go 1.23 (past upstream EOL; kept because eggs ask for it)               |
| `debian`      | `debian:bookworm-slim`                               | Debian 12 with common game-server libraries (SDL, ICU, GLib, ffmpeg...) |
| `alpine`      | `alpine:3.22`                                        | A small Alpine runtime                                                  |

### SteamCMD and game images (amd64 only)

| Tag               | Base                                                     | Purpose                                                                                       |
| ----------------- | -------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| `steamcmd_debian` | `debian:bookworm-slim`                                   | SteamCMD servers: 32-bit libraries, Xvfb, `rcon`, `nc`/`telnet`, the auto-update hook         |
| `steamcmd_ubuntu` | `ubuntu:24.04`                                           | The same with Ubuntu's newer glibc and libc++ (Pavlov VR, Stationeers, Insurgency: Sandstorm) |
| `steamcmd_dotnet` | `debian:bookworm-slim` (+ ASP.NET Core 8 from Microsoft) | SteamCMD plus .NET for Eco                                                                    |
| `steamcmd_sniper` | Valve's Steam Runtime 3 "sniper" platform                | Counter-Strike 2                                                                              |
| `source`          | `debian:bookworm-slim`                                   | srcds and hlds (Source and GoldSrc); updates before start by default                          |
| `rust`            | `debian:bookworm-slim`                                   | Rust with the vanilla, Oxide/uMod or Carbon framework hook                                    |

### Wine and Proton (amd64 only)

| Tag            | Base                   | Purpose                                                                                |
| -------------- | ---------------------- | -------------------------------------------------------------------------------------- |
| `proton`       | `debian:bookworm-slim` | GE-Proton (pinned to 10-34) for Windows servers that need Proton, with a start watch   |
| `wine`         | `debian:bookworm-slim` | WineHQ stable, winetricks, Wine Mono and Gecko baked in, Xvfb, the Steam SDK on update |
| `wine_staging` | `debian:bookworm-slim` | The same with WineHQ staging                                                           |

### Installers (run as root, no entrypoint)

| Tag                 | Base                           | Purpose                                                                     |
| ------------------- | ------------------------------ | --------------------------------------------------------------------------- |
| `installer_debian`  | `debian:bookworm-slim`         | Install scripts: curl, jq, unzip, 7z, git, Python 3, i386 libs for SteamCMD |
| `installer_alpine`  | `alpine:3.22`                  | Install scripts on Alpine: bash, curl, jq, unzip, git                       |
| `installer_java_8`  | `eclipse-temurin:8-jdk-noble`  | Installers that are Java 8 code (Forge)                                     |
| `installer_java_11` | `eclipse-temurin:11-jdk-noble` | The same with Java 11 (Fabric)                                              |
| `installer_java_21` | `eclipse-temurin:21-jdk-noble` | The same with Java 21 (NeoForge, Quilt)                                     |
| `installer_java_25` | `eclipse-temurin:25-jdk-noble` | The same with Java 25 (Spigot's BuildTools)                                 |

## Which eggs use which image

From the `docker_images` and installer containers of the 158 eggs Octail ships, as of 2026-10-24. An egg that offers
several images (the Minecraft Java eggs offer Java 8 to 25) is listed under each.

- `java_8` (12): Arclight, Fabric, Forge, Java App (JAR), Mohist, NeoForge, Paper, Purpur, Quilt, Spigot, SpongeVanilla,
  Vanilla Minecraft.
- `java_11` (12): Arclight, Fabric, Forge, Java App (JAR), Mohist, NeoForge, Paper, Purpur, Quilt, Spigot,
  SpongeVanilla, Vanilla Minecraft.
- `java_17` (18): Arclight, BungeeCord, Fabric, Folia, Forge, Java App (JAR), Lavalink, Mindustry, Mohist, NeoForge,
  Paper, Pufferfish, Purpur, Quilt, Spigot, SpongeVanilla, Vanilla Minecraft, Velocity.
- `java_21` (22): Arclight, BungeeCord, Fabric, Folia, Forge, Geyser Standalone, Java App (JAR), Lavalink, Leaf,
  Mindustry, Mohist, NanoLimbo, NeoForge, Paper, PowerNukkitX, Pufferfish, Purpur, Quilt, Spigot, SpongeVanilla, Vanilla
  Minecraft, Velocity.
- `java_25` (20): BungeeCord, Fabric, Folia, Forge, Geyser Standalone, Hytale, Java App (JAR), Lavalink, Leaf,
  NanoLimbo, NeoForge, Paper, PowerNukkitX, Pufferfish, Purpur, Quilt, Spigot, SpongeVanilla, Vanilla Minecraft,
  Velocity.
- `dotnet_8` (2): tModloader, Vintage Story.
- `dotnet_9` (1): Terraria TShock.
- `dotnet_10` (3): Space Station 14, Terraria TShock, Vintage Story.
- `nodejs_20` (1): Node.js App.
- `nodejs_22` (2): Node.js App, Uptime Kuma.
- `nodejs_24` (1): Node.js App.
- `python_3.12` (1): Python App.
- `python_3.13` (1): Python App.
- `python_3.14` (1): Python App.
- `go_1.23` (1): Go App.
- `go_1.26` (1): Go App.
- `go_1.27` (1): Go App.
- `bun_1` (1): Bun App.
- `deno_2` (1): Deno App.
- `debian` (29): AssaultCube, BeamMP Server, Cuberite, DDraceNetwork (DDNet), ET: Legacy, Factorio, Gate, MariaDB,
  Mumble Server, OpenArena, OpenRA, OpenRCT2, OpenTTD, PocketMine-MP, PostgreSQL, Red Eclipse 2, Red-DiscordBot,
  SuperTuxKart, TeamSpeak 3 Server, Teeworlds, Terraria Vanilla, TES3MP (Morrowind multiplayer), Unreal Tournament
  (1999), Unreal Tournament 2004, Unvanquished, Urban Terror, Valkey (Redis-compatible), Vanilla Bedrock, Xonotic.
- `alpine` (2): Luanti, Octail Test Game.
- `steamcmd_debian` (47): 7 Days To Die, American Truck Simulator Dedicated Server, Ark: Survival Evolved, Arma 3, Arma
  Reforger, Assetto Corsa, Avorion, Ballistic Overkill, Barotrauma, Chivalry: Medieval Warfare, Conan Exiles Enhanced,
  Core Keeper, Counter-Strike: Source, Craftopia, DayZ, Don't Starve Together, Euro Truck Simulator 2 Dedicated Server,
  Generic SteamCMD game, Holdfast: Nations At War, Hurtworld, Killing Floor, Killing Floor 2, Mordhau, Natural Selection
  2, Necesse, Nightingale, Operation: Harsh Doorstop, Palworld, Project Zomboid, Quake Live, Rising World, RuneScape:
  Dragonwilds, Satisfactory, SCP: Secret Laboratory, Smalland: Survive the Wilds, Soulmask, Squad, Squad 44, Starbound,
  The Front, The Isle (Evrima), Unturned, Valheim, Valheim BepINex, VEIN, Warfork, Wurm Unlimited.
- `steamcmd_ubuntu` (3): Insurgency: Sandstorm, Pavlov VR, Stationeers.
- `steamcmd_dotnet` (1): Eco.
- `steamcmd_sniper` (1): Counter-Strike 2.
- `source` (21): Black Mesa: Deathmatch, Counter-Strike 1.6, Counter-Strike: Condition Zero, Day of Defeat, Day of
  Defeat: Source, Day of Infamy, Deathmatch Classic, Fistful of Frags, Garry's Mod, Half-Life 2: Deathmatch, Half-Life
  Deathmatch, Insurgency (2014), Left 4 Dead, Left 4 Dead 2, No More Room in Hell, Source Engine Game (SRCDS), Sven
  Co-op, Team Fortress 2, Team Fortress 2 Classified, Team Fortress Classic, Zombie Panic! Source.
- `rust` (1): Rust.
- `proton` (6): Abiotic Factor, ARK: Survival Ascended, Astroneer, Enshrouded, Generic SteamCMD game, Windrose.
- `wine_staging` (4): Empyrion - Galactic Survival, Ground Branch, Stormworks: Build and Rescue, V Rising BepInEx.
- `wine` (14): ASKA, Empyrion - Galactic Survival, FOUNDRY, Ground Branch, Icarus, Myth of Empires, Night of the Dead,
  PixARK, Risk of Rain 2, Sons Of The Forest, Space Engineers, Stormworks: Build and Rescue, The Forest, The Lord of the
  Rings: Return to Moria.
- `installer_debian` (132): every egg not listed under another installer below.
- `installer_alpine` (21): Arclight, BungeeCord, Cuberite, Folia, Gate, Geyser Standalone, Hytale, Leaf, Luanti, Mohist,
  NanoLimbo, Octail Test Game, OpenTTD, Paper, PocketMine-MP, PowerNukkitX, Pufferfish, Purpur, SpongeVanilla, Vanilla
  Minecraft, Velocity.
- `installer_java_8` (1): Forge.
- `installer_java_11` (1): Fabric.
- `installer_java_21` (2): NeoForge, Quilt.
- `installer_java_25` (1): Spigot.

## Changelog

Newest first. Dates are when the work landed in the Octail monorepo, where this repository's folder lives; "round" is
the batch of parallel work it came in.

### 2026-10-23: new runtimes, smaller Wine, signed build records (round 30)

- **New tags**: `nodejs_24` (the current LTS), `python_3.13`, `python_3.14`, `go_1.26`, `go_1.27`, `bun_1` and
  `deno_2` (Bun and Deno from their official release binaries, SHA-256 checked for amd64 and arm64), and
  `installer_java_17` (NeoForge 1.20.1 and Spigot BuildTools for 1.17 to 1.20.4). `nodejs_20` and `go_1.23` are past
  their end of life: marked deprecated, still built so existing servers keep working.
- **Java images**: DejaVu fonts for map renderers, and an opt-in jemalloc (`JEMALLOC=1`, a new hook that falls back
  to glibc with a console line when the library can't load) for Minecraft servers whose native memory keeps growing.
  Boot tests check the Java major version, the fonts and the hook.
- **SteamCMD, Wine and Proton**: Wine is installed without recommended packages, with the libraries servers use listed
  one by one (roughly 200 to 400 MB smaller per Wine image); the rcon tool is built with a supported Go release (the
  old one kept failing the vulnerability scan) and stripped; Proton servers with auto-update off get Steam's
  `steamclient.so` copied in; Wine prefixes are made without the menu helper they used to wait for; Alpine moved to
  3.24; the 64-bit Source servers get `libncurses5`/`libtinfo5`. GE-Proton stays on 10-34: version 11 needs a newer
  glibc than Debian 12 has.
- **The shared entrypoint**: a two-line banner at every start (image, OS, user, time zone and the container's memory,
  CPU, thread and `/tmp` limits; never variable values), a warning for an unknown time zone, `C.UTF-8` when no locale
  is set, owner pre-start scripts in `.octail/hooks/pre-start.d/` (opt out with `OCTAIL_USER_HOOKS=0`), a debug mode
  (`OCTAIL_DEBUG=1` or a `.octail/debug` file) that prints the startup and the environment with secrets masked, and
  two masking fixes (the working directory was hidden as if it were a secret). 69 new shell tests.
- **CI**: every image declares its platforms and the checks enforce it (the SteamCMD, Source, Rust, Wine and Proton
  families are amd64 only); pushes carry BuildKit's SBOM and SLSA provenance, which are signed with cosign too; the
  weekly rebuild only pushes an image whose content fingerprint changed (its files, its base image digests and its
  packages); and each build writes per-image facts (digest, size, platforms, CVE counts) to `stats/images.json` on a
  `stats` branch.
- **Statistics**: the README opens with generated statistics (`scripts/stats.mjs`: images per family, bases, which eggs
  use each image and how many of them passed a real run), and `docs/index.html` shows the same as a page for GitHub
  Pages.

### 2026-10-20: security re-audit

- The Rust framework hook downloads Oxide and Carbon with `curl --proto '=https'`, so a redirect can't downgrade the
  transfer (neither project publishes a checksum to pin; the hook says so).
- SECURITY.md gained a fallback contact for reporters who aren't collaborators.

### 2026-10-19: our images only, on every server (round 29)

- Every server on Octail's own nodes moved to octail-yolks images and foreign images were removed from the nodes. The
  panel's `servers.allowed_images` (octail-yolks only by default) is enforced by the panel and the node on create,
  clone, presets, image changes and imports; the replacement map for foreign images is generated from `images.json`.
- On Podman, the node now mounts the container's `/tmp` with `notmpcopyup` (a Valheim segfault on Podman was traced to
  Podman copying image files into the `/tmp` tmpfs).

### 2026-10-13: supply chain and Java 25 installs (rounds 26 and 27)

- **Supply chain**: a Trivy scan before every push (failing only on fixable CRITICAL findings in our own layers),
  CycloneDX SBOMs, keyless cosign signatures and SBOM attestations, every action pinned by commit SHA, tool downloads
  checked by sha256, `test/check-workflows.sh` and tests for the scan, sign and workflow checks; checkouts keep no git
  credentials.
- **`installer_java_25`**: Temurin 25 with the installer tools, so Spigot's BuildTools builds current Minecraft without
  downloading a JDK at every install. A merge had put Spigot back on `installer_java_21`; fixed the same day.
- Egg lists in `images.json` and the README followed the new eggs of these rounds (Leaf, Pufferfish, Quake Live, Unreal
  Tournament, Risk of Rain 2, Ground Branch, Wurm Unlimited, Hytale, TF2 Classified, Zombie Panic! Source and others).

### 2026-10-12: boot tests, pinned Wine add-ons, new runtimes (rounds 22 to 25)

- **Boot tests**: each tag got a `smoke` command in `images.json`, and `scripts/smoke.sh` starts the image the way the
  node does; CI runs it on the amd64 image before every push and shows sizes and results in the job summary.
- **Pinned Wine add-ons**: winetricks comes from a pinned commit and the Wine Mono and Gecko installers are checked
  against pinned sha256 values; an unknown version stops the build.
- **The Proton start watch masks secrets**: its process list showed game arguments with passwords
  (`?ServerAdminPassword=...`, `-rcon=...`) on a console subusers can read; it now masks them with the entrypoint's rule.
- **`dotnet_9`** for TShock 6; `libzstd1` on `debian` for OpenRCT2; library checks in `test/run.sh`.
- **`source` covers GoldSrc**: 32-bit OpenSSL 3 and zlib for Sven Co-op, and the SteamCMD hook sets the HLDS mod before
  `app_update`.
- Egg lists followed the 45 eggs added that day (voice, apps, GoldSrc, Wine, Minecraft and more).

### 2026-10-10: Proton fixed, a public-repository look (rounds 20 and 21)

- **GE-Proton 10-34** instead of 11-7: 11-7 needs glibc 2.38 and Debian 12 has 2.36, so every Proton server would have
  failed to load `ntdll.so`; other hosts also report GE-Proton 11 hanging ARK: Survival Ascended and breaking Astroneer.
  `install-proton.sh` now refuses a GE-Proton the base can't load. Proton's Xalia helper is off, and the Proton hook
  prints one diagnostic report (pids and memory limits, process states and wait channels) when no port is open five
  minutes after the start. With 10-34, ARK: Survival Ascended started in 37 s on a test node.
- **README reorganised**: badges, tag tables by kind with anchors, using, building and update sections; CONTRIBUTING,
  SECURITY, issue forms, a pull request template and a generated `dependabot.yml`, checked by `test/check-images.sh`.
- All 28 tags rebuilt and checked by reading their layers, after one CI run on 2026-10-09 never published.

### 2026-10-09: the first 28 images (rounds 18 and 19)

- **The repository is created**: our own entrypoint and hooks (SteamCMD update, Xvfb, Wine prefix and winetricks,
  Proton, the Rust framework), build-time setup scripts, bash tests, Dockerfiles for 28 images (Java 8 to 25, .NET 8 and
  10, Node.js 20 and 22, Python 3.12, Go 1.23, Debian, Alpine, Mono, SteamCMD on Debian, Ubuntu, .NET and sniper,
  Source, Rust, Proton, Wine and Wine staging, installers for Debian, Alpine and Java 8, 11 and 21), `images.json`
  with the upstream images each tag replaces, the GitHub Actions workflow (lint, tests, matrix build and push, weekly
  rebuild) and the README.
- **The no-upstream guard**: `bases.txt` and `test/check-images.sh` in the tests and CI.
- **The SteamCMD update hook reuses the node's saved Steam login** (`STEAM_LOGIN_CACHE`), so eggs with a Steam account
  update with the saved login token, as their install did.
- **First CI run**: 27 of 28 tags built; `installer_debian` failed on arm64 (the i386 packages only exist on amd64) and
  was fixed. The GHCR package was made public so nodes pull without logging in.
- **Fitting the eggs to the images**: Xvfb and the Steam SDK (app 1007) on by default in the Wine images,
  `WINEDLLOVERRIDES` exported even when empty (V Rising with BepInEx), Proton reusing an existing prefix, the Rust
  Plugins folder on `LD_LIBRARY_PATH`, `nc` and `telnet` for 7 Days to Die's console, the real `libc++.so` on
  `steamcmd_ubuntu` for Pavlov VR, GLib on `debian` for OpenTTD (the upstream image's lack of it had failed a real run).
  Every shipped egg switched to these images the same day.

### Before 2026-10-09: life on other people's images

Octail's first eggs ran on Pterodactyl, Pelican and parkervcp images. What we learned there shaped these images:
Octail turns `{{VAR}}` into `${VAR}` itself since a 2026-10-08 security review found that pasting values into the
startup let a subuser run commands through the upstream entrypoint's `eval`; a 2026-10-09 bisection traced Valheim's
crash for non-root users to the upstream images' `nss_wrapper`; and Rust's upstream image ran its startup twice.
