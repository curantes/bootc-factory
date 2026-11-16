# shellcheck shell=bash
# Shared helpers for bootc-factory scripts. Source, don't execute.
set -euo pipefail

REPO_ROOT=$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)
cd "$REPO_ROOT"

# Builds, rechunking and boot tests need rootful podman (as upstream does).
read -r -a PODMAN <<<"${PODMAN:-sudo podman}"
# Registry namespace baked into the signature policy, e.g. ghcr.io/owner.
IMAGE_NAMESPACE=${IMAGE_NAMESPACE:-localhost}
ARCH=${ARCH:-$(uname -m | sed 's/x86_64/amd64/; s/aarch64/arm64/')}

# Tool images, pinned by digest (Renovate keeps them current). Used by the
# scripts that source this file.
# shellcheck disable=SC2034
TRIVY_IMAGE=ghcr.io/aquasecurity/trivy:0.76.2@sha256:8f6bb947dbc528902e11f2f5be52f7b519f6a39d5d148f41166f2040499768fb
# shellcheck disable=SC2034
SYFT_IMAGE=docker.io/anchore/syft:v1.57.1@sha256:03215d0e98b661d0ecbc8575dbc14d65be1743b5de5df6410aecb7e80f95b060
# shellcheck disable=SC2034
IMAGE_BUILDER_IMAGE=ghcr.io/osbuild/image-builder-cli:v90.0.0@sha256:8e255e3ddd056fd23255afa4ff4f7e01663b7326e0d811ce708369ff91a9df9f

die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo "==> $*" >&2; }

# Local image reference produced by build.sh.
local_ref() { echo "localhost/bootc-$1:$2"; }

# Per-image/version/arch output directory for reports.
outdir() {
	local d="$REPO_ROOT/out/$1-$2-$ARCH"
	mkdir -p "$d"
	echo "$d"
}

# Mount a local image's root filesystem (rootful podman) and print the path.
# Scanners read the mounted tree: after rechunking, files are hardlinks into
# /sysroot/ostree, which layer-based scanners skip. Callers unmount with
# unmount_image and exclude /sysroot (a duplicate object store).
mount_image() {
	"${PODMAN[@]}" image mount "$1"
}
unmount_image() {
	"${PODMAN[@]}" image unmount "$1" >/dev/null || true
}

upstream_image() {
	local v
	v=$(sed -n "s/^UPSTREAM_IMAGE_$1=//p" images/base/upstream.env)
	[[ -n $v ]] || die "no UPSTREAM_IMAGE_$1 in images/base/upstream.env"
	echo "$v"
}

image_dir() {
	if [[ $1 == base ]]; then echo images/base; else echo "images/roles/$1"; fi
}

require_image() {
	[[ $1 == base || -f images/roles/$1/role.yaml ]] || die "unknown image '$1'"
	[[ $1 != _* ]] || die "'$1' is a template, not an image"
}
