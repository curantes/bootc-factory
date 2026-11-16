#!/usr/bin/env bash
# Build a compressed qcow2 disk image from a (signed) container image with
# image-builder, using the CIS disk layout in disk/qcow2.toml.
#
#   scripts/disk-image.sh <image-ref> <output.qcow2>
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

ref=${1:?usage: disk-image.sh <image-ref> <output.qcow2>}
dest=${2:?usage: disk-image.sh <image-ref> <output.qcow2>}
work=$(mktemp -d "$REPO_ROOT/out/disk.XXXXXX")
trap 'sudo rm -rf "$work"' EXIT

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
