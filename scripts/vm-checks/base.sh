#!/usr/bin/bash
# Base checks: run as root INSIDE an ephemeral VM for every image.
set -euo pipefail

fail() { echo "FAIL: $*"; exit 1; }
check() { echo "--- $*"; }

# Wait until boot has settled (only this test job left in the queue).
for _ in $(seq 60); do
	(($(systemctl list-jobs --no-legend | wc -l) <= 1)) && break
	sleep 5
done

check "no failed units"
failed=$(systemctl --failed --no-legend --plain | awk '{print $1}')
if [[ -n $failed ]]; then
	for u in $failed; do journalctl -u "$u" --no-pager -n 30; done
	fail "failed units: $failed"
fi

check "SELinux enforcing"
[[ $(getenforce) == Enforcing ]] || fail "SELinux is $(getenforce)"

check "core services active"
for u in sshd firewalld auditd; do
	systemctl is-active --quiet "$u" || fail "$u not active"
done

check "update policy"
[[ $(systemctl is-enabled bootc-fetch-apply-updates.timer 2>/dev/null) == masked ]] ||
	fail "bootc-fetch-apply-updates.timer is not masked"
for u in bootc-factory-stage-update.timer bootc-factory-reboot-window.timer; do
	systemctl is-enabled --quiet "$u" || fail "$u not enabled"
done

check "/tmp is tmpfs with nodev,nosuid,noexec"
opts=$(findmnt -no FSTYPE,OPTIONS /tmp) || fail "/tmp not mounted"
for o in tmpfs nodev nosuid noexec; do [[ $opts == *"$o"* ]] || fail "/tmp: missing $o ($opts)"; done

check "container signature policy defaults to reject"
python3 -I -c 'import json,sys; p=json.load(open("/etc/containers/policy.json")); sys.exit(p["default"]!=[{"type":"reject"}])' ||
	fail "policy.json default is not reject"

check "crypto policy is not LEGACY"
[[ $(update-crypto-policies --show) != LEGACY* ]] || fail "crypto policy is LEGACY"

check "sshd: no root login"
sshd -T 2>/dev/null | grep -qx 'permitrootlogin no' || fail "PermitRootLogin is not 'no'"

check "CIS tailoring present"
test -s /usr/share/bootc-factory/cis-host-tailoring.xml || fail "host tailoring missing"

echo "base checks passed"
