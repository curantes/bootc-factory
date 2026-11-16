#!/usr/bin/env bash
# Print the logically bound images (one per line) declared in a built image.
#
#   scripts/bound-images.sh <image> <version>
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

ref=$(local_ref "${1:?image}" "${2:?version}")
# shellcheck disable=SC2016 # expanded inside the container
"${PODMAN[@]}" run --rm --entrypoint /usr/bin/bash "$ref" -c '
	shopt -s nullglob
	for f in /usr/lib/bootc/bound-images.d/*.container /usr/lib/bootc/bound-images.d/*.image; do
		sed -n "s/^Image=//p" "$f"
	done' | sort -u
