# Contributing to octail-yolks

Thanks for helping. Bugs and image requests go in [issues](https://github.com/sneakywrld/octail-yolks/issues/new/choose)
(the templates ask for what we need); security problems go through [SECURITY.md](SECURITY.md), not issues.

This repository is published from the `yolks/` folder of the Octail monorepo. Pull requests here are welcome; they are
applied there by hand and come back with the next publish, so your commit may arrive with a different hash.

## Ground rules

- **Official bases only.** A Dockerfile may only start from (`FROM`) or copy from (`COPY --from=`,
  `RUN --mount=…,from=`) its own build stages and the images listed in `bases.txt`. Nothing from Pterodactyl, Pelican,
  parkervcp or other "yolks" images, and no scripts copied from them. Adding a line to `bases.txt` is a policy
  decision: an official image from the software's own publisher, explained in the pull request.
- Upstream software comes from its publisher (a vendor repository, a release download with a checksum, or built from
  source), pinned through a build argument where it has versions.
- Runtime images run as the non-root user `container` in `/home/container`, with `tini -g` as PID 1,
  `STOPSIGNAL SIGINT` and `common/entrypoint.sh`. Installer images have no entrypoint and run as root.
- A tag is a promise: `java_17` stays Java 17. A new major runtime is a new tag, not an edit of an old one.

## Adding an image

1. **Folder**: `images/<tag>/Dockerfile`, with `# syntax=docker/dockerfile:1` and a comment saying what it is for.
   Start from a base in `bases.txt`, run `common/setup-apt.sh` (or `setup-apk.sh`) through a bind mount for the shared
   packages and the `container` user, copy `common/entrypoint.sh` to `/entrypoint.sh` and the hooks the image needs
   into `/etc/octail/entrypoint.d/`, then `USER container`, `WORKDIR /home/container`, `STOPSIGNAL SIGINT`,
   `ENTRYPOINT ["/usr/bin/tini", "-g", "--"]` and `CMD ["/entrypoint.sh"]`. `images/java_21/Dockerfile` is a short
   example; set the `org.opencontainers.image.*` labels the same way.
2. **`images.json`**: an entry with `tag`, `folder`, `platforms` (always `linux/amd64`; add `linux/arm64` when the
   base and everything inside exist for arm64, never for SteamCMD, Source, Proton, Wine or anything that needs
   32-bit x86 libraries; see [Platforms](README.md#platforms)), `kind` (`runtime` or `installer`), `smoke` (the boot test CI runs before pushing: a startup
   for a runtime image, a `bash -c` command run as root for an installer, fast and offline, see
   [Boot tests](README.md#boot-tests)), `description`, `replaces` (third-party images it stands in for, or `[]`) and
   `eggs` (the Octail eggs using it, or `[]`).
3. **`bases.txt`**: only when the image needs a base that isn't listed yet (see the ground rules).
4. **README**: a row in the right table under [Tags](README.md#tags), starting with
   `<a name="<tag>"></a>` and the tag (other repositories link to that anchor), and hook variables in
   [Hooks and their variables](README.md#hooks-and-their-variables) if you add a hook.
5. **Dependabot**: `scripts/dependabot.sh > .github/dependabot.yml`.
6. **Tests**: behaviour that runs without Docker (a hook, the entrypoint) gets a case in `test/run.sh`
   (entrypoint features that need neither jq nor python go in `test/entrypoint.sh`, which also runs on its own,
   e.g. in Git Bash on Windows).
7. **Build info** (optional): `ENV OCTAIL_IMAGE=<tag>-<yyyymmdd>` or a one-line `/etc/octail/image` shows in the
   entrypoint's banner; without it the banner says `(no build info)`.

## Changing the entrypoint

`common/entrypoint.sh` runs every live server of every runtime image, so a change must keep each egg's startup
working as before: `{{VAR}}`/`${VAR}`, one `eval`, values never parsed as shell, masking, the exit code, signals.
New behaviour is opt-in or prints only `octail: ...` lines before `container~`. Names starting with `OCTAIL_` are
the entrypoint's and Tentacle's; the server folder's `.octail/` is the place for per-server switches (pre-start
scripts, `.octail/debug`). Hooks are sourced at the top level, so a hook's `declare` stays global.

## Checks

Run these before opening a pull request (CI runs the same):

```bash
test/run.sh                                               # all tests, also runs check-images.sh and check-workflows.sh
test/check-images.sh                                      # images.json <-> folders, smoke, bases, README rows, dependabot.yml
test/check-workflows.sh                                   # actions pinned by SHA (# vX.Y.Z), downloads by sha256, .trivyignore
shellcheck -x common/*.sh common/hooks/*.sh scripts/*.sh test/*.sh
hadolint --config .hadolint.yaml images/*/Dockerfile
actionlint                                                # when you change a workflow
scripts/build.sh <tag>                                    # needs Docker Buildx
scripts/smoke.sh ghcr.io/sneakywrld/octail-yolks:<tag> <tag>   # the boot test CI runs before the push
```

A new action in a workflow is pinned to its full commit SHA with the version as a comment
(`uses: owner/action@<40 hex> # v1.2.3`), never a tag; a downloaded tool gets a pinned sha256. A fixable CRITICAL
vulnerability in what your image adds fails CI's scan (README: [Supply chain](README.md#supply-chain-scans-sboms-signatures)).

## CI changes

The build workflow is `.github/workflows/build.yml` (README: [How CI publishes](README.md#how-ci-publishes)). When you
change it or the scripts it runs:

- Keep the step order `test/check-workflows.sh` enforces: boot test, vulnerability scan, SARIF upload, content check,
  build and push, sign, build report, then the report job. Nothing is pushed, signed or reported for pull requests.
- Permissions stay least-privilege: top-level `contents: read`, each job widens only what it needs, and only the
  report job gets `contents: write` (it pushes the `stats` branch, never `main`).
- Logic goes into `scripts/*.sh` with a fake-tool test in `test/supply-chain.sh` (fake `docker`, `trivy`, `cosign`;
  `report.sh publish` is tested against a local bare repository), not into long `run:` blocks.
- `stats/images.json` is a public interface: add fields freely, but a renamed or removed field bumps `schema` and is
  documented in README ([Build report](README.md#build-report-statsimagesjson)).
- To rebuild by hand: Actions → build → Run workflow, with tags (`java_21,wine`, or `all`) and **force** when the tag
  should move even though its content is unchanged (for example after a label change you want published).

Then, better still, run a server of an egg that uses it on an Octail test node, and say in the pull request what you ran.

## Pull requests

- One image or one change per pull request; describe what changes for eggs already using the tag.
- Pull requests build every changed image without pushing it. Nothing is published until it lands on `main`.
- By contributing you agree that your contribution may be published under the licence the owner chooses for this
  repository (none is chosen yet).
