# 7. Generic qcow2 disk images with image-builder

Date: 2026-11-15 · Status: accepted

## Decision

- Publish a **generic KVM/QEMU cloud image** (qcow2 with internal
  compression, cloud-init with datasource auto-detection) per image ×
  version × arch, weekly and on demand, as a GitHub Release with
  `SHA256SUMS`, a cosign blob bundle and a provenance attestation.
- Build with **image-builder** (`ghcr.io/osbuild/image-builder-cli`):
  `bootc-image-builder` is deprecated and merged into image-builder.
- Disk layout (`disk/qcow2.toml`): LVM with separate `/var`, `/var/log`,
  `/var/log/audit`, `/var/tmp`; free VG space for growth.
- Only images whose container signature verifies are converted.

## Consequences

image-builder doesn't work on hosts that load Ubuntu's AppArmor profile
`bwrap-userns-restrict`: it also confines the bwrap inside the privileged
container. `scripts/ci-setup.sh disk-image` unloads it on GitHub-hosted
runners only; elsewhere that is the host administrator's decision.

Releases are platform-neutral; any hypervisor/cloud that imports qcow2 over
HTTPS works. GitHub release assets are limited to 2 GiB each.
