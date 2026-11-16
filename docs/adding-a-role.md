# Adding a role

A role is a bootc image built `FROM` the hardened base. It inherits CIS
hardening, the signature policy, update timers and node_exporter, and gets
its own build matrix, gates, signatures, SBOM, provenance and disk images
automatically.

## 1. Scaffold

```sh
just new-role grafana
```

This copies `images/roles/_template` to `images/roles/grafana`:

| File | Purpose |
|---|---|
| `role.yaml` | name, description, optional `versions` subset, `boot_test` |
| `Containerfile` | `FROM ${BASE_IMAGE}`; **must end with** `RUN /usr/libexec/bootc-factory/finalize` |
| `rootfs/` | copied to `/` in the image (`usr/share/bootc-factory/role` records the role name) |
| `cis-exceptions.txt` | role-specific CIS exceptions (normally empty) |
| `tests/vm-test.sh` | assertions run as root inside the booted VM |

## 2. Add the application

Prefer **Quadlet + logically bound images** (see `images/roles/prometheus`):

1. `rootfs/usr/share/containers/systemd/<app>.container` with
   `Image=<registry>/<repo>:<tag>@sha256:<digest>` and
   `GlobalArgs=--storage-opt=additionalimagestore=/usr/lib/bootc/storage`.
2. Symlink it into `rootfs/usr/lib/bootc/bound-images.d/`.
3. Allow the repository in the signature policy:
   `rootfs/usr/share/bootc-factory/policy.d/30-<role>.json`
   (default is `reject`; a scope may be defined only once).
4. Open ports with a firewalld service file in `rootfs/usr/lib/firewalld/services/`
   and `firewall-offline-cmd --add-service=…` in the Containerfile.
5. Put secrets and per-host config in cloud-init, never in the image. Gate the
   unit with `ConditionPathExists=` on its config.

RPMs from the AlmaLinux repos are fine too: `RUN dnf -y install …`.

## 3. Test locally

```sh
just dev-key                 # once, if you don't have keys/cosign.pub locally
just build base 10
just build grafana 10
just check grafana 10        # SBOM, Trivy, OpenSCAP, boot test
```

## 4. Open a PR

CI builds only what changed. On merge to `main` the role is published as
`ghcr.io/curantes/bootc-grafana:<ver>`. After the first publish, make the
package public (see `scripts/setup-wizard.sh`, step 9). It is included in the
next weekly disk-image release.

## Rules

- Never weaken a base setting outside `finalize`: `finalize` re-applies CIS.
- Every CIS exception needs a reason and a CODEOWNERS security review.
- Keep `boot_test: true` unless the role truly cannot boot in a plain VM.
