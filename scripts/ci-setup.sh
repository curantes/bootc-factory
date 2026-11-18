#!/usr/bin/env bash
# Prepare a GitHub-hosted Ubuntu runner: KVM access and bcvk for boot tests,
# qemu-img for disk images.
#
#   scripts/ci-setup.sh [boot-test] [disk-image]
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

# Update the SHA256 together with the version (from the release's .sha256 asset).
# Held at v0.19.0: v0.21.0+ bind-mounts /run into /run/tmproot in its
# entrypoint (bcvk PR #395, tested rootless only), which fails with rootful
# podman on Ubuntu 26.04 runners ("mount: /run/tmproot/run: bind /run failed").
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

	tmp=$(mktemp -d)
	curl -fsSL -o "$tmp/bcvk.tar.gz" \
		"https://github.com/bootc-dev/bcvk/releases/download/$BCVK_VERSION/bcvk-x86_64-unknown-linux-gnu.tar.gz"
	echo "$BCVK_SHA256_X86_64  $tmp/bcvk.tar.gz" | sha256sum -c -
	tar -xzf "$tmp/bcvk.tar.gz" -C "$tmp"
	sudo install -m 0755 "$tmp/bcvk-x86_64-unknown-linux-gnu" /usr/local/bin/bcvk
	bcvk --version
fi
