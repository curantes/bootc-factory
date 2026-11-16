#!/usr/bin/env bash
# Exit 0 (and print "true") if any published base image has RPM updates
# available, "false" otherwise. Used by the nightly CI schedule.
#
#   scripts/check-updates.sh ghcr.io/curantes
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

ns=${1:?usage: check-updates.sh <namespace>}
for ver in $(yq '.versions[]' factory.yaml); do
	ref="$ns/bootc-base:$ver"
	if ! "${PODMAN[@]}" pull -q "$ref" >/dev/null 2>&1; then
		log "$ref not published yet: rebuild needed"
		echo true
		exit 0
	fi
	rc=0
	"${PODMAN[@]}" run --rm --entrypoint /usr/bin/dnf "$ref" -q check-update >/dev/null || rc=$?
	if ((rc == 100)); then
		log "$ref has RPM updates"
		echo true
		exit 0
	elif ((rc != 0)); then
		die "dnf check-update failed for $ref (exit $rc)"
	fi
done
log "No RPM updates"
echo false
