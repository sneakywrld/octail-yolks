## What and why

<!-- What changes, which tags it affects, and what changes for eggs already using them. -->

## Checklist

- [ ] Bases only from `bases.txt`; nothing from Pterodactyl, Pelican or parkervcp images or scripts
- [ ] New or removed image: `images/<tag>/`, `images.json`, a README tag-table row with its anchor, and
      `scripts/dependabot.sh > .github/dependabot.yml`
- [ ] `test/run.sh` passes (it runs `test/check-images.sh`)
- [ ] `shellcheck -x common/*.sh common/hooks/*.sh scripts/*.sh test/*.sh` and
      `hadolint --config .hadolint.yaml images/*/Dockerfile` pass
- [ ] Built with `scripts/build.sh <tag>` and a server of an egg using it started (say which below)

## How it was tested

<!-- The egg(s), node OS and container runtime, and what you checked. -->
