#!/usr/bin/env bash
# Verify a published image the way bootc and podman do: the containers/image
# signature policy with our cosign key, reading the sha256-<digest>.sig tag.
#
#   scripts/verify-image.sh <registry/repo>{:tag|@digest} [public-key]
#
# containers/image checks the signature of every per-arch image it copies,
# never the index itself (hosts pull one per-arch image), so this copies all
# of them into a temporary OCI layout: it downloads their layers.
#
# Why not `cosign verify --key`: cosign 2.x switches to the Sigstore bundle
# format whenever the registry holds any bundle (actions/attest provenance
# is one), even with --new-bundle-format=false, and then fails with
# "expected key signature, not certificate".
key=${2:-}
[[ -z $key ]] || key=$(realpath "$key") # before lib.sh changes directory
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

ref=${1:?usage: verify-image.sh <image-ref> [public-key]}
key=${key:-$REPO_ROOT/keys/cosign.pub}
repo=$(ref_repo "$ref")
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT

sigstore_policy "$repo" "$key" "$dir"
log "Verifying $ref with $key"
# --remove-signatures: an OCI layout can't store them; the policy check
# reads them from the registry regardless.
skopeo copy --quiet --multi-arch all --preserve-digests --remove-signatures \
	--policy "$dir/policy.json" --registries.d "$dir/registries.d" \
	"docker://$ref" "oci:$dir/layout" ||
	die "$ref: not every image carries a valid signature from $key"
log "Verified: every image in $ref is signed with $key"
