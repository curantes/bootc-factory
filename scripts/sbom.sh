#!/usr/bin/env bash
# Generate SPDX JSON SBOMs with Syft for a locally built image (its mounted
# root filesystem, minus the duplicate /sysroot object store) and for each
# logically bound image.
#
#   scripts/sbom.sh <image> <version>
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

name=${1:?usage: sbom.sh <image> <version>}
ver=${2:?usage: sbom.sh <image> <version>}
ref=$(local_ref "$name" "$ver")
out=$(outdir "$name" "$ver")

rootfs=$(mount_image "$ref")
trap 'unmount_image "$ref"' EXIT

log "SBOM for $ref"
"${PODMAN[@]}" run --rm --security-opt label=disable \
	-v "$rootfs:/rootfs:ro" -v "$out:/work" "$SYFT_IMAGE" \
	scan dir:/rootfs --exclude './sysroot/**' \
	--source-name "bootc-$name" --source-version "$ver" \
	-o "spdx-json=/work/sbom-full.spdx.json"
# The attested SBOM is package-level: ~34k per-file entries of a bootc OS
# would exceed the 16 MB attestation limit. The full one is kept as a report.
rm -f "$out/sbom.spdx.json"  # may be owned by the container user from an earlier run
python3 -I "$REPO_ROOT/scripts/sbom-trim.py" "$out/sbom-full.spdx.json" "$out/sbom.spdx.json"

# GitHub attestations accept predicates up to 16 MB.
size=$(stat -c %s "$out/sbom.spdx.json")
((size < 16 * 1024 * 1024)) || die "SBOM is $((size / 1024 / 1024)) MB; GitHub attestations allow 16 MB"

while read -r bound; do
	[[ -n $bound ]] || continue
	safe=$(basename "${bound%%@*}" | tr ':/' '__')
	log "SBOM for bound image $bound"
	"${PODMAN[@]}" run --rm --security-opt label=disable -v "$out:/work" "$SYFT_IMAGE" \
		scan "registry:$bound" -o "spdx-json=/work/sbom-bound-$safe.spdx.json"
done < <("$REPO_ROOT/scripts/bound-images.sh" "$name" "$ver")
log "SBOMs in $out"
