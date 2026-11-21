# bootc-factory developer commands. CI runs the same scripts/ these call.
# Tools: `nix develop` (or direnv) provides everything, including bcvk,
# except podman (host, rootful via sudo) and, for VMs, QEMU and virtiofsd
# (host: bcvk mounts the host's /usr; apt install qemu-system-x86 qemu-utils
# virtiofsd). VMs also need /dev/kvm access (the kvm group).

set shell := ["bash", "-euo", "pipefail", "-c"]

default_version := "10"

# List recipes
default:
    @just --list

# Build an image (base or role) for one version: just build prometheus 10
build image version=default_version:
    scripts/build.sh {{image}} {{version}}

# Run every CI gate locally: SBOM, vulnerability, CIS compliance, boot test
check image version=default_version: (sbom image version) (scan image version) (oscap image version) (boot-test image version)

# Generate SPDX SBOMs (image + bound images)
sbom image version=default_version:
    scripts/sbom.sh {{image}} {{version}}

# Trivy vulnerability gate
scan image version=default_version:
    scripts/scan.sh {{image}} {{version}}

# OpenSCAP CIS L2 Server gate
oscap image version=default_version:
    scripts/oscap-gate.sh {{image}} {{version}}

# Boot test in an ephemeral VM (needs KVM + bcvk)
boot-test image version=default_version:
    scripts/boot-test.sh {{image}} {{version}}

# Logged to out/smoke-<image>-<version>.log.
[doc("Fast local loop: build + boot test only (no SBOM/Trivy/OpenSCAP)")]
smoke image version=default_version:
    mkdir -p out
    { scripts/build.sh {{image}} {{version}} && scripts/boot-test.sh {{image}} {{version}}; } 2>&1 | tee out/smoke-{{image}}-{{version}}.log

# Root can't log in (CIS), so this replaces a console. Output in out/vm-exec.log:
#   just vm-exec prometheus 'bash role.sh; journalctl -b -u prometheus'
[doc("Run a command as root in an ephemeral VM of a local build")]
vm-exec image cmd version=default_version:
    scripts/vm-exec.sh {{image}} {{version}} {{quote(cmd)}}

# Build a compressed qcow2 from a local or remote image
disk image version=default_version:
    scripts/disk-image.sh localhost/bootc-{{image}}:{{version}} out/bootc-{{image}}-{{version}}.qcow2

# Scaffold a new role from images/roles/_template
new-role name:
    scripts/new-role.sh {{name}}

# Throwaway signing key for local builds (never publish with it)
dev-key:
    mkdir -p out/dev
    COSIGN_PASSWORD= cosign generate-key-pair --output-key-prefix out/dev/cosign-dev
    cp out/dev/cosign-dev.pub keys/cosign-dev.pub

# Lint everything CI lints
lint:
    scripts/lint.sh

# Remove local build outputs
clean:
    sudo rm -rf out
