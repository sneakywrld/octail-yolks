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
2. **`images.json`**: an entry with `tag`, `folder`, `platforms` (`linux/amd64` and, when everything inside runs on
   it, `linux/arm64`), `kind` (`runtime` or `installer`), `description`, `replaces` (third-party images it stands in
   for, or `[]`) and `eggs` (the Octail eggs using it, or `[]`).
3. **`bases.txt`**: only when the image needs a base that isn't listed yet (see the ground rules).
4. **README**: a row in the right table under [Tags](README.md#tags), starting with
   `<a name="<tag>"></a>` and the tag (other repositories link to that anchor), and hook variables in
   [Hooks and their variables](README.md#hooks-and-their-variables) if you add a hook.
5. **Dependabot**: `scripts/dependabot.sh > .github/dependabot.yml`.
6. **Tests**: behaviour that runs without Docker (a hook, the entrypoint) gets a case in `test/run.sh`.

## Checks

Run these before opening a pull request (CI runs the same):

```bash
test/run.sh                                               # entrypoint and hook tests, also runs check-images.sh
test/check-images.sh                                      # images.json <-> folders, bases, README rows, dependabot.yml
shellcheck -x common/*.sh common/hooks/*.sh scripts/*.sh test/*.sh
hadolint --config .hadolint.yaml images/*/Dockerfile
actionlint                                                # when you change a workflow
scripts/build.sh <tag>                                    # needs Docker Buildx
```

Then start the image the way a node would (`docker run --rm -e STARTUP='...' ghcr.io/sneakywrld/octail-yolks:<tag>`)
or, better, run a server of an egg that uses it on an Octail test node, and say in the pull request what you ran.

## Pull requests

- One image or one change per pull request; describe what changes for eggs already using the tag.
- Pull requests build every changed image without pushing it. Nothing is published until it lands on `main`.
- By contributing you agree that your contribution may be published under the licence the owner chooses for this
  repository (none is chosen yet).
