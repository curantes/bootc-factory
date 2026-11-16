#!/usr/bin/env bash
# Vulnerability gate with Trivy.
#
# Fails on CRITICAL/HIGH vulnerabilities that have a fixed version:
#   - OS image: distribution packages (RPM advisories). Go/Python libraries
#     vendored inside AlmaLinux RPMs are reported to code scanning but do not
#     gate: their fixes ship as RPM errata, which the OS scan already covers.
#   - Logically bound images: everything (they are upstream builds).
# Exceptions live in security/trivyignore.yaml (statement + expiry each).
#
#   scripts/scan.sh <image> <version>
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

name=${1:?usage: scan.sh <image> <version>}
ver=${2:?usage: scan.sh <image> <version>}
ref=$(local_ref "$name" "$ver")
out=$(outdir "$name" "$ver")
cache="$REPO_ROOT/out/.trivy-cache"
mkdir -p "$cache"

rootfs=$(mount_image "$ref")
trap 'unmount_image "$ref"' EXIT

trivy() {
	"${PODMAN[@]}" run --rm --security-opt label=disable \
		-v "$rootfs:/rootfs:ro" -v "$out:/work" -v "$cache:/cache" \
		-v "$REPO_ROOT/security:/security:ro" \
		"$TRIVY_IMAGE" --cache-dir /cache "$@"
}
os_scan=(rootfs --scanners vuln --skip-dirs /rootfs/sysroot)

rc=0
# Full report (all severities, all package types) for GitHub code scanning.
trivy "${os_scan[@]}" --format sarif --output /work/trivy.sarif /rootfs
# Gate.
log "Trivy gate: $ref (OS packages)"
trivy "${os_scan[@]}" --pkg-types os \
	--severity CRITICAL,HIGH --ignore-unfixed \
	--ignorefile /security/trivyignore.yaml \
	--exit-code 1 --format table --output /work/trivy-gate.txt /rootfs || rc=1
cat "$out/trivy-gate.txt"

while read -r bound; do
	[[ -n $bound ]] || continue
	safe=$(basename "${bound%%@*}" | tr ':/' '__')
	log "Trivy gate: bound image $bound"
	trivy image --scanners vuln \
		--severity CRITICAL,HIGH --ignore-unfixed \
		--ignorefile /security/trivyignore.yaml \
		--exit-code 1 --format table --output "/work/trivy-gate-$safe.txt" "$bound" || rc=1
	cat "$out/trivy-gate-$safe.txt"
done < <("$REPO_ROOT/scripts/bound-images.sh" "$name" "$ver")

if ((rc == 0)); then log "Vulnerability gate passed"; else log "Vulnerability gate FAILED"; fi
exit "$rc"
