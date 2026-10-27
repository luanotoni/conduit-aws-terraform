#!/usr/bin/env bash
# Install a pinned Trivy release in CI, verified against its published SHA-256.
# Pinned on purpose: floating tags of the Trivy GitHub Actions were hijacked in
# March 2026, so CI never pulls "latest" scanner code. Bump both values together
# from https://github.com/aquasecurity/trivy/releases.
set -euo pipefail

TRIVY_VERSION="0.73.0"
TRIVY_SHA256="2edd39da482bb4e9831962487b68f68e3928ec3137794757f54d00383d79547b"
INSTALL_DIR="${1:-/usr/local/bin}"

tarball="trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

curl -fsSL -o "$tmp/$tarball" \
  "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/${tarball}"
echo "${TRIVY_SHA256}  $tmp/$tarball" | sha256sum --check --quiet
tar -xzf "$tmp/$tarball" -C "$tmp" trivy
sudo install -m 0755 "$tmp/trivy" "$INSTALL_DIR/trivy"
trivy --version
