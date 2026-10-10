# Security

Please report security problems privately, not in a public issue or pull request.

## Reporting

Use GitHub's private vulnerability reporting: the **Security** tab of this repository →
**Report a vulnerability** ([direct link](https://github.com/sneakywrld/octail-yolks/security/advisories/new)).
Include the tag (and the dated tag or image digest if you have it), what an attacker can do, and how to reproduce it.

> **For the owner:** private vulnerability reporting is off by default and must be switched on once: repository
> **Settings** → **Code security** → **Private vulnerability reporting** → **Enable**. Until then the link above
> shows nothing and reporters have no private channel.

## What is in scope

- The entrypoint and hooks (`common/`): for example a server variable's value being run as shell, a secret printed
  unmasked in the startup line, or a hook that lets a server owner escape the server folder.
- How the images are built: a Dockerfile pulling something from an unofficial source or without a checksum.

Vulnerabilities in upstream software inside the images (Debian or Ubuntu packages, the JDK, Wine, Proton, SteamCMD)
belong to their publishers. The weekly rebuild picks up their fixes; if a fix is out and an image still lacks it,
an ordinary issue is fine.

## Supported versions

Only the newest build of each tag is maintained. Dated tags (`<tag>-<yyyymmdd>`) are kept for pinning and rollback,
but they are not patched; move to a newer build to get fixes.
