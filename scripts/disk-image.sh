#!/usr/bin/env bash
# Build a compressed qcow2 disk image from a (signed) container image with
# image-builder, using the CIS disk layout in disk/qcow2.toml.
#
#   scripts/disk-image.sh <image-ref> <output.qcow2>
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

ref=${1:?usage: disk-image.sh <image-ref> <output.qcow2>}
dest=${2:?usage: disk-image.sh <image-ref> <output.qcow2>}
mkdir -p "$REPO_ROOT/out" # git-ignored, so absent on a fresh checkout
work=$(mktemp -d "$REPO_ROOT/out/disk.XXXXXX")
trap 'sudo rm -rf "$work"' EXIT

# image-builder resolves an index to its per-arch manifest and then looks
# that digest up in local storage, where podman doesn't record it when it
# pulled by index digest. So resolve the per-arch manifest here and use it
# for both.
raw=$(skopeo inspect --raw "docker://$ref")
if jq -e '.manifests' <<<"$raw" >/dev/null; then
	digest=$(jq -r --arg arch "$ARCH" \
		'[.manifests[] | select(.platform.os == "linux" and .platform.architecture == $arch)][0].digest // empty' <<<"$raw")
	[[ -n $digest ]] || die "$ref has no linux/$ARCH image"
	ref="$(ref_repo "$ref")@$digest"
	log "Using the $ARCH image $ref"
fi

"${PODMAN[@]}" pull -q "$ref" >/dev/null
mkdir -p "$work/output"
"${PODMAN[@]}" run --rm --privileged --pull=missing \
	--security-opt label=type:unconfined_t \
	-v "$REPO_ROOT/disk/qcow2.toml:/blueprint.toml:ro" \
	-v "$work/output:/output" \
	-v /var/lib/containers/storage:/var/lib/containers/storage \
	"$IMAGE_BUILDER_IMAGE" \
	build --blueprint /blueprint.toml --output-dir /output \
	--bootc-ref "$ref" --bootc-default-fs xfs qcow2

src=$(sudo find "$work/output" -name '*.qcow2' -print -quit)
[[ -n $src ]] || die "image-builder produced no qcow2"
log "Compressing $src -> $dest"
sudo qemu-img convert -c -O qcow2 "$src" "$dest"
sudo chown "$(id -u):$(id -g)" "$dest"
log "Wrote $dest ($(du -h "$dest" | cut -f1))"
