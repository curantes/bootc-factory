#!/usr/bin/env bash
# Prepare a GitHub-hosted Ubuntu runner: KVM access and bcvk for boot tests,
# qemu-img and a working osbuild sandbox for disk images.
#
#   scripts/ci-setup.sh [boot-test] [disk-image]
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

# Update the SHA256 together with the version (from the release's .sha256 asset).
# renovate: datasource=github-releases depName=bootc-dev/bcvk
BCVK_VERSION=v0.22.0
BCVK_SHA256_X86_64=eb72198c0d36fab75bfcadbb6794a87afa6f496a4da6b1b34d27728243fa6474

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

if [[ " $* " == *" disk-image "* ]]; then
	# AppArmor attaches profiles by path, also inside privileged containers.
	# Ubuntu's bwrap-userns-restrict thus catches image-builder's /usr/bin/bwrap
	# and takes every capability from its children, so osbuild can't chown or
	# mount. Unload that one profile, and only on a throwaway runner: it
	# guards the host's user namespace restriction.
	profile=/etc/apparmor.d/bwrap-userns-restrict
	if [[ ${RUNNER_ENVIRONMENT:-} != github-hosted ]]; then
		log "Not a GitHub-hosted runner: leaving AppArmor alone"
	# unpriv_bwrap is only defined in that file (other profiles are named bwrap).
	elif sudo grep -qs '^unpriv_bwrap ' /sys/kernel/security/apparmor/profiles; then
		log "Unloading AppArmor profile $profile"
		sudo apparmor_parser --remove "$profile"
	else
		log "AppArmor profile bwrap-userns-restrict is not loaded"
	fi
fi
