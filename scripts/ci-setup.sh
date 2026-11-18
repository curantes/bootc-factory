#!/usr/bin/env bash
# Prepare a GitHub-hosted Ubuntu runner: KVM access and bcvk for boot tests,
# qemu-img for disk images.
#
#   scripts/ci-setup.sh [boot-test] [disk-image]
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

# Update the SHA256 together with the version (from the release's .sha256 asset).
# Held at v0.19.0, together with the AppArmor workaround below: v0.21.0+
# bind-mounts /run into /run/tmproot in its entrypoint (bcvk PR #395, tested
# rootless only), which failed with rootful podman on Ubuntu 26.04 runners
# ("mount: /run/tmproot/run: bind /run failed"). Retry v0.21.0+ once the
# workaround is proven, and lift the hold in .github/renovate.json5.
# renovate: datasource=github-releases depName=bootc-dev/bcvk
BCVK_VERSION=v0.19.0
BCVK_SHA256_X86_64=e6e3e2e8c13546d30481b035217442de78f2efe3e5a3bd3dbfb58d38345b4b98

pkgs=()
for want in "$@"; do
	case $want in
	boot-test) pkgs+=(qemu-system-x86 qemu-utils virtiofsd) ;;
	disk-image) pkgs+=(qemu-utils) ;;
	*) die "unknown feature $want" ;;
	esac
done
if ((${#pkgs[@]})); then
	sudo apt-get update -q
	sudo DEBIAN_FRONTEND=noninteractive apt-get install -yq --no-install-recommends "${pkgs[@]}"
fi

if [[ " $* " == *" boot-test "* ]]; then
	[[ $(uname -m) == x86_64 ]] || die "boot tests are only supported on x86_64 runners"
	echo 'KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"' |
		sudo tee /etc/udev/rules.d/99-kvm4all.rules >/dev/null
	sudo udevadm control --reload-rules
	sudo udevadm trigger --name-match=kvm

	# Ubuntu's AppArmor profile for bwrap also confines the bwrap inside
	# bcvk's container and denies its mounts ("bwrap: Failed to make /
	# slave: Permission denied"). Same workaround as bcvk's own CI
	# (bootc-dev/actions bootc-host-setup/ci/workarounds.sh). Runner only.
	if sudo test -r /etc/apparmor.d/bwrap-userns-restrict &&
		sudo grep -qx 'bwrap (enforce)' /sys/kernel/security/apparmor/profiles; then
		printf '%s\n' 'priority=100 allow file rwlkm /**,' 'priority=100 allow ix /**,' |
			sudo tee /etc/apparmor.d/local/bwrap-userns-restrict >/dev/null
		sudo apparmor_parser -Q /etc/apparmor.d/bwrap-userns-restrict
		sudo apparmor_parser -r /etc/apparmor.d/bwrap-userns-restrict
		echo "Relaxed AppArmor bwrap-userns-restrict for bcvk"
	fi

	tmp=$(mktemp -d)
	curl -fsSL -o "$tmp/bcvk.tar.gz" \
		"https://github.com/bootc-dev/bcvk/releases/download/$BCVK_VERSION/bcvk-x86_64-unknown-linux-gnu.tar.gz"
	echo "$BCVK_SHA256_X86_64  $tmp/bcvk.tar.gz" | sha256sum -c -
	tar -xzf "$tmp/bcvk.tar.gz" -C "$tmp"
	sudo install -m 0755 "$tmp/bcvk-x86_64-unknown-linux-gnu" /usr/local/bin/bcvk
	bcvk --version
fi
