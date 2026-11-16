# 4. Applications as Quadlet + logically bound images

Date: 2026-11-15 · Status: accepted

## Context

Roles need applications (Prometheus, Alertmanager, node_exporter). EPEL RPMs
lag and add a third-party repo; raw binaries need their own update plumbing.

## Decision

Run applications as Podman **Quadlet** units from upstream images pinned by
digest, declared as bootc **logically bound images**
(`/usr/lib/bootc/bound-images.d/` symlinks). `bootc upgrade` pulls them
before switching, so OS + app versions move and roll back together.
Renovate bumps the digests; the Trivy gate and SBOM step cover them.

Because they are digest-pinned inside the signed OS image, the signature
policy allows those exact repositories without a signature
(`policy.d/*.json`); everything else stays `reject`.

## Consequences

- If a disk-image build does not pre-pull bound images, the first service
  start pulls them (same pinned digest).
- Containers run read-only, `NoNewPrivileges`, all capabilities dropped;
  node_exporter needs `SecurityLabelDisable` to read the host filesystem.
