#!/usr/bin/env bash
# CIS compliance gate: evaluate the built image against its gate tailoring
# (CIS L2 Server minus `exception` and `deploy-time` rules) with the SCE
# engine, the same way oscap-im does during the build. Any failing rule
# fails the gate.
#
#   scripts/oscap-gate.sh <image> <version>
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

name=${1:?usage: oscap-gate.sh <image> <version>}
ver=${2:?usage: oscap-gate.sh <image> <version>}
ref=$(local_ref "$name" "$ver")
out=$(outdir "$name" "$ver")

log "OpenSCAP evaluation of $ref"
# Results are written inside the container and streamed out as a tar: a
# bind-mounted output directory owned by a host user would itself fail
# no_files_or_dirs_unowned_by_user / _ungroupowned.
# shellcheck disable=SC2016 # expanded inside the container
"${PODMAN[@]}" run --rm -e OSCAP_PREFERRED_ENGINE=SCE \
	--entrypoint /usr/bin/bash "$ref" -c '
	mkdir -p /out
	. /etc/os-release
	ds=/usr/share/xml/scap/ssg/content/ssg-almalinux${VERSION_ID%%.*}-ds.xml
	oscap xccdf eval \
		--profile xccdf_io.github.bootc-factory_profile_cis_gate \
		--tailoring-file /usr/share/bootc-factory/cis-gate-tailoring.xml \
		--results /out/oscap-results.xml \
		--results-arf /out/oscap-arf.xml \
		--report /out/oscap-report.html \
		"$ds" >/out/oscap.log 2>&1
	rc=$?
	# 0 = all pass, 2 = some rule failed (judged below), else = tool error
	if [ "$rc" -ne 0 ] && [ "$rc" -ne 2 ]; then tail -50 /out/oscap.log >&2; exit "$rc"; fi
	# Archive the files, not ".": extracting a "." entry over an existing
	# directory fails with newer GNU tar ("Cannot unlink: Invalid argument").
	cd /out && tar -cf - -- *' | tar -xf - -C "$out"

python3 -I "$REPO_ROOT/scripts/oscap-summary.py" "$out/oscap-results.xml" "$name $ver $ARCH"
