#!/bin/bash
# Build-time: GE-Proton (GloriousEggroll's Proton build, which runs outside Steam) in /opt/proton, checked
# against its published SHA-512, and a `proton` command that calls it by its real path (Proton finds its
# files next to the script, so a symlink would not do).
#   install-proton.sh <release tag, e.g. GE-Proton11-7>
set -euo pipefail

tag=${1:?GE-Proton release tag}
base="https://github.com/GloriousEggroll/proton-ge-custom/releases/download/${tag}"
work=$(mktemp -d)
cd "${work}"

# Releases name the archive <tag>.tar.gz (older) or <tag>-x86_64.tar.gz (newer); try both.
for name in "${tag}-x86_64" "${tag}"; do
	if curl -fsSL -o "${name}.tar.gz" "${base}/${name}.tar.gz"; then
		curl -fsSL -o "${name}.sha512sum" "${base}/${name}.sha512sum"
		sha512sum -c "${name}.sha512sum"
		mkdir -p /opt/proton
		tar -xzf "${name}.tar.gz" -C /opt/proton --strip-components=1
		break
	fi
done
[ -x /opt/proton/proton ] || {
	echo "GE-Proton ${tag} was not installed" >&2
	exit 1
}
cd /
rm -rf "${work}"

cat >/usr/local/bin/proton <<'EOF'
#!/bin/sh
exec /opt/proton/proton "$@"
EOF
chmod 0755 /usr/local/bin/proton
echo "${tag}" >/opt/proton/OCTAIL_VERSION
