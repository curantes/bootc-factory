# Operations

## Images

| Image | Tags |
|---|---|
| `ghcr.io/curantes/bootc-base` | `9`, `10`, `latest` (= 10), `<ver>-<yyyymmdd>`, `<ver>-<yyyymmdd>.<run>` |
| `ghcr.io/curantes/bootc-<role>` | same scheme |

Verify before use:

```sh
cosign verify --new-bundle-format=false --key keys/cosign.pub ghcr.io/curantes/bootc-base:10
gh attestation verify oci://ghcr.io/curantes/bootc-base:10 --repo curantes/bootc-factory
```

## Creating a VM from the qcow2 release

Download from the latest `disk-*` release and verify:

```sh
sha256sum -c SHA256SUMS --ignore-missing
cosign verify-blob --key cosign.pub \
  --bundle bootc-prometheus-10-x86_64.qcow2.sigstore.json bootc-prometheus-10-x86_64.qcow2
```

Any KVM/QEMU platform or cloud that imports qcow2 works; the image uses
cloud-init with datasource auto-detection (NoCloud, ConfigDrive, OpenStack,
…). Boot with **UEFI and Secure Boot**. Example with libvirt and a NoCloud
seed:

```sh
cloud-localds seed.iso docs/examples/base-user-data.yaml
qemu-img create -f qcow2 -F qcow2 -b bootc-base-10-x86_64.qcow2 vm1.qcow2 40G
virt-install --name vm1 --memory 4096 --vcpus 2 --import \
  --disk vm1.qcow2 --disk seed.iso,device=cdrom \
  --boot uefi,firmware.feature0.name=secure-boot,firmware.feature0.enabled=yes \
  --os-variant almalinux10 --network default --noautoconsole
```

For the `prometheus` role, attach a second disk for data and use
`docs/examples/prometheus-user-data.yaml` (it formats the disk with the label
`prometheus-data` on first boot).

### Console access

Root login is disabled for SSH, and the bootloader has no password (CIS
exception, ADR 0005). **Restrict access to the VM console in your
hypervisor/cloud platform.**

## Updates and reboots

- Nightly: `bootc upgrade` downloads and stages (signature-verified).
- Sunday 03:00: reboot into the staged deployment (`REBOOT=auto`).
- Change the window per host:

  ```ini
  # /etc/systemd/system/bootc-factory-reboot-window.timer.d/window.conf
  [Timer]
  OnCalendar=
  OnCalendar=Wed *-*-* 04:00:00
  ```

- Stage only, reboot manually: `REBOOT=never` in `/etc/bootc-factory/updates.conf`.
- Status: `bootc status`. Apply now: `systemctl start bootc-factory-reboot-window.service`.

## Rollback

```sh
bootc rollback && systemctl reboot          # previous deployment
bootc switch ghcr.io/curantes/bootc-base:10-20261115   # pin a dated build (kept 90 days)
bootc switch ghcr.io/curantes/bootc-base:10            # back to the moving tag
```

## Signature enforcement

On first boot `bootc-factory-enforce-sigpolicy.service` re-targets the host
with `bootc switch --enforce-container-sigpolicy` (effective after the next
reboot window). Check with `bootc status --json | jq .status.booted.image.image.signature`
→ `"containerPolicy"`.

## Compliance scan on a host

```sh
oscap xccdf eval \
  --profile xccdf_io.github.bootc-factory_profile_cis_host \
  --tailoring-file /usr/share/bootc-factory/cis-host-tailoring.xml \
  --report /root/cis-report.html \
  /usr/share/xml/scap/ssg/content/ssg-almalinux10-ds.xml
```

The host tailoring excludes only accepted-risk `exception` rules, so this
also checks the `deploy-time` rules (partitions, mount options, kargs).

## Key rotation

Yearly, or immediately if the key may be exposed:

1. `cosign generate-key-pair` locally; save the new key + password in your
   password manager.
2. Commit the new public key as `keys/cosign-<yyyy>.pub` **next to** the old
   one; merge. Every image now trusts both keys (`keyPaths`).
3. Wait until hosts have updated (one reboot window), then replace the
   `COSIGN_PRIVATE_KEY` / `COSIGN_PASSWORD` secrets of the `release`
   environment and rename the new key to `keys/cosign.pub` (CI verifies with
   that file), removing the old one; merge.
4. On compromise: do steps 1–3 without waiting, and rebuild everything
   (`workflow_dispatch` with `force`).

## Retention

- Dated image tags: 90 days. Moving tags: never deleted.
- Disk-image releases: 8 weeks.
- `cleanup.yml` is dry-run until `gh variable set CLEANUP_DRY_RUN --body false`.
