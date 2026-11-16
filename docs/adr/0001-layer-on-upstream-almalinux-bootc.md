# 1. Layer on the upstream AlmaLinux bootc image

Date: 2026-11-15 · Status: accepted

## Context

We need an AlmaLinux 9/10 bootc base we control. Two options: rebuild from
scratch like `AlmaLinux/bootc-images` (rpm-ostree compose via
`bootc-base-imagectl`, privileged builds, tooling borrowed from a moving
`fedora-bootc:latest`), or `FROM` the published
`quay.io/almalinuxorg/almalinux-bootc` image.

## Decision

Layer on the upstream image, **pinned by digest** in `images/base/upstream.env`
and bumped by Renovate (digest updates only; majors are separate images).
The base build also runs `dnf upgrade` so errata land before upstream rebuilds.

## Consequences

- Fast, simple builds that reuse AlmaLinux's tested compose.
- We trust AlmaLinux's build. Upstream is signed with their KMS cosign key
  (`cosign.pub` in their repo) but ships no SBOM/provenance; our SBOM covers
  the full final image.
- Switching to a from-scratch build later only changes the base
  `Containerfile`; roles are unaffected.
