#!/usr/bin/env bash
# Build one image for one major version on the host architecture, then
# rechunk it for efficient client updates.
#
#   scripts/build.sh <base|role> <version>
#
# Env: IMAGE_NAMESPACE  registry namespace for the signature policy (base)
#      BASE_IMAGE       base image for roles (default: local base build)
#      PODMAN           podman command (default: root podman via sudo)
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

name=${1:?usage: build.sh <image> <version>}
ver=${2:?usage: build.sh <image> <version>}
require_image "$name"
ref=$(local_ref "$name" "$ver")
raw="$ref-raw"

# Local builds may happen before the first commit or with uncommitted changes.
revision=$(git rev-parse --verify -q HEAD || echo uncommitted)
[[ -z $(git status --porcelain 2>/dev/null) ]] || revision+="-dirty"

labels=(
	--label "org.opencontainers.image.version=$ver"
	--label "org.opencontainers.image.revision=$revision"
	--label "org.opencontainers.image.created=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
)
if [[ -n ${GITHUB_SERVER_URL:-} ]]; then
	labels+=(--label "org.opencontainers.image.source=$GITHUB_SERVER_URL/$GITHUB_REPOSITORY")
fi

if [[ $name == base ]]; then
	args=(
		--build-arg "UPSTREAM_IMAGE=$(upstream_image "$ver")"
		--build-arg "IMAGE_NAMESPACE=$IMAGE_NAMESPACE"
		-f images/base/Containerfile .
	)
else
	base=${BASE_IMAGE:-$(local_ref base "$ver")}
	labels+=(--label "io.github.bootc-factory.base=$base")
	args=(--build-arg "BASE_IMAGE=$base" -f "images/roles/$name/Containerfile" "images/roles/$name")
fi

log "Building $raw"
"${PODMAN[@]}" build --pull=missing "${labels[@]}" -t "$raw" "${args[@]}"

chunked="$ref-chunked"
log "Rechunking into $chunked"
# rpm-ostree from the image itself splits content into stable layers, so
# clients only download what changed.
"${PODMAN[@]}" run --rm --privileged \
	-v /var/lib/containers:/var/lib/containers \
	--entrypoint /usr/bin/rpm-ostree "$raw" \
	compose build-chunked-oci --bootc --format-version=1 \
	--from "$raw" --output "containers-storage:$chunked"

# Rechunking re-creates directories that span several chunks with default
# metadata, undoing CIS permission fixes (e.g. /etc/cron.d 0700 -> 0755).
# Compare ownership/modes before and after, restore any difference in one
# small final layer, and (re)apply our labels there.
snapshot() {
	"${PODMAN[@]}" run --rm --network=none --entrypoint /usr/bin/find "$1" / -xdev \
		\( -path /proc -o -path /sys -o -path /dev -o -path /run -o -path /tmp \) -prune -o \
		\( -type d -o -type f \) -printf '%m %U %G %p\n'
}
fixdir=$(mktemp -d)
trap 'rm -rf "$fixdir"' EXIT
snapshot "$raw" >"$fixdir/before"
snapshot "$chunked" >"$fixdir/after"
python3 -I "$REPO_ROOT/scripts/metadata-fix.py" "$fixdir/before" "$fixdir/after" >"$fixdir/fix.sh"
log "Restoring $(grep -c '^ch' "$fixdir/fix.sh" || true) metadata changes made by rechunking"
printf '%s\n' \
	"FROM $chunked" \
	"RUN --network=none --mount=type=bind,source=fix.sh,target=/run/fix.sh sh -eu /run/fix.sh" \
	>"$fixdir/Containerfile"
"${PODMAN[@]}" build --pull=never "${labels[@]}" -t "$ref" "$fixdir"
"${PODMAN[@]}" rmi "$raw" "$chunked" >/dev/null

log "Linting $ref"
"${PODMAN[@]}" run --rm "$ref" bootc container lint
log "Built $ref"
