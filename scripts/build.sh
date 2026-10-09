#!/bin/bash
# Builds one image locally with Docker Buildx (for your own platform unless PLATFORMS is set):
#   scripts/build.sh java_21                      -> ghcr.io/sneakywrld/octail-yolks:java_21 (loaded locally)
#   PLATFORMS=linux/amd64,linux/arm64 PUSH=1 scripts/build.sh java_21
# Run from the repository root; the build context is the repository root (images use common/).
set -euo pipefail

tag=${1:?usage: scripts/build.sh <tag>}
entry=$(jq -c --arg t "${tag}" '.images[] | select(.tag == $t)' images.json)
if [ -z "${entry}" ]; then
	echo "unknown image tag: ${tag} (see images.json)" >&2
	exit 1
fi
registry=$(jq -r '.registry' images.json)
folder=$(jq -r '.folder' <<<"${entry}")

args=(--file "${folder}/Dockerfile" --tag "${registry}:${tag}")
if [ -n "${PLATFORMS:-}" ]; then
	args+=(--platform "${PLATFORMS}")
fi
if [ "${PUSH:-0}" = 1 ]; then
	args+=(--push)
elif [ -z "${PLATFORMS:-}" ] || [[ ${PLATFORMS} != *,* ]]; then
	args+=(--load)
fi
exec docker buildx build "${args[@]}" .
