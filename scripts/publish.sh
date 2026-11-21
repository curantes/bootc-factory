#!/usr/bin/env bash
# Assemble the multi-arch index for one image/version from per-arch digests,
# sign and attest it, and only then move the public tags.
#
#   scripts/publish.sh <image> <version> <digest-dir>
#
# <digest-dir> holds one file per arch, named <arch>, containing the digest
# of the per-arch image already pushed to $IMAGE_NAMESPACE/bootc-<image>.
# Env: IMAGE_NAMESPACE, BUILD_TAG (e.g. 20261115.42), LATEST (true|false),
#      COSIGN_PRIVATE_KEY, COSIGN_PASSWORD, SBOM_DIR (per-arch SBOMs: <arch>.spdx.json)
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

name=${1:?image}
ver=${2:?version}
digests=${3:?digest dir}
repo="$IMAGE_NAMESPACE/bootc-$name"
build_tag="$ver-${BUILD_TAG:?}"
day_tag="$ver-${BUILD_TAG%%.*}"

list="localhost/publish-$name-$ver"
podman manifest rm "$list" >/dev/null 2>&1 || true
podman manifest create "$list"
for f in "$digests"/*; do
	arch=$(basename "$f")
	log "Adding $arch $(<"$f")"
	podman manifest add "$list" "docker://$repo@$(<"$f")"
done
# --all=false: push only the index. The per-arch images are already in the
# registry and their digests are what the build job attested.
podman manifest push --all=false --digestfile "$RUNNER_TEMP/index-digest" "$list" "docker://$repo:$build_tag"
index=$(<"$RUNNER_TEMP/index-digest")

want=$(cat "$digests"/* | sort)
got=$(skopeo inspect --raw "docker://$repo@$index" | jq -r '.manifests[].digest' | sort)
[[ $want == "$got" ]] || die "index children differ from attested per-arch digests:\n$got\nvs\n$want"
log "Index $repo@$index"
echo "digest=$index" >>"${GITHUB_OUTPUT:-/dev/null}"

log "Signing (cosign key; verified by bootc/podman via policy.json)"
cosign sign --yes --recursive --key env://COSIGN_PRIVATE_KEY "$repo@$index"
log "Signing (keyless; GitHub OIDC identity for CI-side verification)"
cosign sign --yes --recursive "$repo@$index"

# bootc and podman only read signatures from the sha256-<digest>.sig tag.
# cosign verify also accepts newer storage formats (cosign 3.x defaults),
# so check the tag itself before any public tag points at this index.
mapfile -t children < <(cat "$digests"/*)
for digest in "$index" "${children[@]}"; do
	sig="$repo:${digest/:/-}.sig"
	skopeo inspect --raw "docker://$sig" >/dev/null ||
		die "no signature at $sig: bootc/podman clients would reject $repo@$digest"
done
log "Signatures stored where bootc/podman look for them"
# And they verify with our key, exactly as on a host, before any tag moves.
"$REPO_ROOT/scripts/verify-image.sh" "$repo@$index"

if [[ -n ${SBOM_DIR:-} ]]; then
	for f in "$digests"/*; do
		arch=$(basename "$f")
		sbom="$SBOM_DIR/$arch.spdx.json"
		[[ -s $sbom ]] || die "missing SBOM $sbom"
		log "Attesting SBOM for $arch"
		cosign attest --yes --key env://COSIGN_PRIVATE_KEY \
			--type spdxjson --predicate "$sbom" "$repo@$(<"$f")"
	done
fi

log "Promoting tags"
tags=("$day_tag" "$ver")
[[ ${LATEST:-false} == true ]] && tags+=(latest)
for t in "${tags[@]}"; do
	skopeo copy --all --preserve-digests "docker://$repo@$index" "docker://$repo:$t"
done
log "Published $repo:{$build_tag,${tags[*]}} -> $index"
