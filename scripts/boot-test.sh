#!/usr/bin/env bash
# Boot the image in an ephemeral KVM VM with bcvk and run
# scripts/vm-checks/base.sh plus the role's tests/vm-test.sh inside it.
#
#   scripts/boot-test.sh <image> <version>
#
# Uses `bcvk ephemeral run --execute` (a systemd unit inside the VM) rather
# than SSH, because the CIS profile disables root SSH login.
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

name=${1:?usage: boot-test.sh <image> <version>}
ver=${2:?usage: boot-test.sh <image> <version>}
ref=$(local_ref "$name" "$ver")
out=$(outdir "$name" "$ver")

tests=$(mktemp -d)
trap 'rm -rf "$tests"' EXIT
cp scripts/vm-checks/base.sh "$tests/base.sh"
role_test="$(image_dir "$name")/tests/vm-test.sh"
[[ -f $role_test ]] && cp "$role_test" "$tests/role.sh"
cat >"$tests/run.sh" <<'RUN'
#!/usr/bin/bash
cd /run/virtiofs-mnt-tests || exit 1
if bash ./base.sh && { [ ! -f role.sh ] || bash ./role.sh; }; then
	echo "BOOT-TEST-RESULT: PASS"
else
	echo "--- failed units"
	systemctl --failed --no-pager
	echo "--- errors in this boot's journal"
	journalctl -b -p err --no-pager | tail -60
	echo "BOOT-TEST-RESULT: FAIL"
fi
RUN

log "Booting $ref"
bcvk_execute "$ref" "$tests" "/usr/bin/bash /run/virtiofs-mnt-tests/run.sh" "$out/boot-test.log"

grep -q 'BOOT-TEST-RESULT: PASS' "$out/boot-test.log" || die "boot test failed (see $out/boot-test.log)"
log "Boot test passed"
