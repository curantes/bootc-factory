# shellcheck shell=bash
# Shared helpers for bootc-factory scripts. Source, don't execute.
set -euo pipefail

REPO_ROOT=$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)
cd "$REPO_ROOT"

# Builds, rechunking and boot tests need rootful podman (as upstream does).
# sudo-rs (Ubuntu 26.04) keeps the caller's XDG_RUNTIME_DIR, so root podman
# would use the caller's /run/user/<uid>/containers/auth.json and leave it
# root-owned. Drop it so root uses /run/containers/0/auth.json.
read -r -a PODMAN <<<"${PODMAN:-sudo env -u XDG_RUNTIME_DIR podman}"
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

# Repository part of an image reference: strip @digest, then a :tag (but not
# a registry :port).
ref_repo() {
	local repo=${1%%@*}
	[[ ${repo##*/} == *:* ]] && repo=${repo%:*}
	echo "$repo"
}

# Write a containers/image policy.json and registries.d into directory $3
# that accept only repository $1 signed with cosign public key $2 (absolute
# path), read from the sha256-<digest>.sig tag. This is how bootc and podman
# verify, so it never mistakes another signature format for ours.
sigstore_policy() {
	local repo=$1 key=$2 dir=$3
	cat >"$dir/policy.json" <<-EOF
		{
		  "default": [{"type": "reject"}],
		  "transports": {"docker": {"$repo": [{
		    "type": "sigstoreSigned",
		    "keyPath": "$key",
		    "signedIdentity": {"type": "matchRepository"}
		  }]}}
		}
	EOF
	mkdir -p "$dir/registries.d"
	printf 'docker:\n  %s:\n    use-sigstore-attachments: true\n' "$repo" >"$dir/registries.d/sigstore.yaml"
}

# Copy an upstream base image into root's container storage, but only if
# AlmaLinux's cosign signature verifies. This uses the same containers/image
# policy code as bootc and podman, so it also catches signatures stored where
# they don't look. Key: images/base/almalinux-bootc.pub, published in
# github.com/AlmaLinux/bootc-images (cosign.pub) and AlmaLinux/atomic-desktop.
pull_verified_upstream() {
	local ref=$1 repo dir
	repo=$(ref_repo "$ref")
	dir=$(mktemp -d)
	sigstore_policy "$repo" "$REPO_ROOT/images/base/almalinux-bootc.pub" "$dir"
	log "Pulling $ref (signature verified with images/base/almalinux-bootc.pub)"
	# Same privileges as PODMAN (sudo for root storage), with skopeo instead.
	# Absolute path: sudo's secure_path misses e.g. a Nix-provided skopeo.
	"${PODMAN[@]:0:${#PODMAN[@]}-1}" "$(command -v skopeo)" copy --quiet \
		--policy "$dir/policy.json" --registries.d "$dir/registries.d" \
		"docker://$repo@${ref#*@}" "containers-storage:$repo@${ref#*@}" ||
		die "upstream image $ref is missing a valid AlmaLinux signature"
	rm -rf "$dir"
}

image_dir() {
	if [[ $1 == base ]]; then echo images/base; else echo "images/roles/$1"; fi
}

require_image() {
	[[ $1 == base || -f images/roles/$1/role.yaml ]] || die "unknown image '$1'"
	[[ $1 != _* ]] || die "'$1' is a template, not an image"
}
