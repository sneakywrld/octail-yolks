#!/bin/bash
# Build-time: GE-Proton (GloriousEggroll's Proton build, which runs outside Steam) in /opt/proton, checked
# against its published SHA-512, and a `proton` command that calls it by its real path (Proton finds its
# files next to the script, so a symlink would not do).
#   install-proton.sh <release tag, e.g. GE-Proton10-34>
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

# GE-Proton runs on the image's own glibc (no Steam Runtime): a release built against a newer one fails at every
# start with "wine: could not load ntdll.so" (GE-Proton 11 needs 2.38, Debian 12 has 2.36). Refuse it here instead.
need=$(grep -aohE 'GLIBC_[0-9]+\.[0-9]+' /opt/proton/files/bin/wineserver \
	/opt/proton/files/lib/wine/x86_64-unix/ntdll.so | sed 's/^GLIBC_//' | sort -uV | tail -n1)
have=$(getconf GNU_LIBC_VERSION | awk '{print $2}')
if [ -z "${need}" ] || [ -z "${have}" ] || [ "$(printf '%s\n%s\n' "${need}" "${have}" | sort -V | tail -n1)" != "${have}" ]; then
	echo "GE-Proton ${tag} needs glibc ${need:-?}, this base image has ${have:-?}: use an older GE-Proton or a newer base" >&2
	exit 1
fi
/opt/proton/files/bin/wineserver --version

cat >/usr/local/bin/proton <<'EOF'
#!/bin/sh
exec /opt/proton/proton "$@"
EOF
chmod 0755 /usr/local/bin/proton
echo "${tag}" >/opt/proton/OCTAIL_VERSION
