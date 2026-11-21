# bootc-factory

A factory for CIS Level 2 hardened [bootc](https://bootc.dev) images based on
[AlmaLinux bootc](https://github.com/AlmaLinux/bootc-images), with a hardened
**base** and **roles** that build on it.

- **Base**: AlmaLinux 10 (x86_64), CIS Level 2 Server via
  `oscap-im`, signature-enforcing `policy.json`, cloud-init, staged updates
  with a reboot window, and node_exporter (off until it's configured).
- **Roles**: `images/roles/<name>/`, built `FROM` the exact base digest and
  re-hardened at the end of every build. The first role is
  [`prometheus`](images/roles/prometheus) (Prometheus + Alertmanager).
- **Supply chain**: images are pinned by digest and kept current by Renovate;
  the upstream AlmaLinux image must also carry a valid AlmaLinux signature.
  CI runs Trivy and OpenSCAP gates and a boot test in a VM, then publishes a
  Syft SBOM, a keyed and keyless cosign signature, and GitHub build
  provenance (SLSA Build L3).
- **Disk images**: weekly signed qcow2 images (generic KVM/QEMU cloud images)
  built with image-builder, using the CIS LVM layout.

```text
images/base/            base Containerfile, upstream digests, CIS exceptions, rootfs
images/roles/<role>/    role.yaml, Containerfile, rootfs/, cis-exceptions.txt, tests/
images/roles/_template/ scaffold for `just new-role`
lib/factory/            build-time tooling installed into every image (finalize, tailoring, policy)
scripts/                build/scan/gate/test/publish scripts (shared by CI and `just`)
disk/                   image-builder blueprint (CIS disk layout)
security/               Trivy exceptions
keys/                   cosign public key(s)
docs/                   ADRs, operations, adding a role, cloud-init examples
```

## Quick start

```sh
nix develop                 # or `direnv allow`: just, cosign, yq, linters, gh
scripts/setup-wizard.sh     # once: repo, signing key, environment, ruleset, Renovate
just build base 10
just build prometheus 10
just check prometheus 10    # SBOM, Trivy, OpenSCAP, boot test
just new-role grafana       # scaffold the next role
```

## Use

```sh
scripts/verify-image.sh ghcr.io/curantes/bootc-prometheus:10   # needs skopeo
bootc switch --enforce-container-sigpolicy ghcr.io/curantes/bootc-prometheus:10
```

You can also create a VM from a `disk-*` release (see
[docs/operations.md](docs/operations.md)).

## Docs

- [Operations](docs/operations.md): VMs, updates, rollback, key rotation,
  compliance scans
- [Adding a role](docs/adding-a-role.md)
- [Decisions](docs/adr/)
- [Security policy](SECURITY.md)

## License

[Apache-2.0](LICENSE)
