# bootc-factory developer commands. CI runs the same scripts/ these call.
# Tools: `nix develop` (or direnv) provides everything except podman (host,
# rootful via sudo) and bcvk (needed for `vm`/`boot-test`).

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

# Interactive ephemeral VM of a local build (bcvk). Root SSH is disabled by
# CIS, so this drops you on the console.
vm image version=default_version:
    sudo bcvk ephemeral run --rm -it --console localhost/bootc-{{image}}:{{version}}

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
