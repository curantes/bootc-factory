# 2. Keyed cosign signatures, plus keyless for CI verification

Date: 2026-11-15 · Status: accepted

## Context

Hosts must refuse unsigned or foreign updates. `bootc` verifies via
`containers-policy.json` (`sigstoreSigned`). As of late 2026 that policy can
not verify GitHub Actions keyless (Fulcio) certificates: it matches only an
e-mail SAN, while Actions certificates carry a URI SAN
(containers/container-libs#625 is open). We have no cloud KMS.

## Decision

- Sign every published image (index and per-arch, `--recursive`) with a
  **password-protected cosign key pair**. The private key and password are
  secrets of the `release` GitHub environment (deployable from `main` only);
  an offline backup lives in a password manager.
- `keys/*.pub` is baked into the base image and referenced by
  `/etc/containers/policy.json` (default `reject`) with `keyPaths`, so a key
  rotation ships the new key one release ahead. Local-only transports
  (`containers-storage`, `oci`, `oci-archive`) are accepted: they hold content
  already on the machine and are needed by rpm-ostree rechunking and osbuild.
- **Also** sign keylessly and publish GitHub attestations, for CI/policy
  tooling that can verify workflow identity.
- Pin cosign to **2.x**: cosign 3 stores signatures where podman/bootc do not
  look yet.
- Hosts installed from a disk image re-target themselves once with
  `bootc switch --enforce-container-sigpolicy` (unit
  `bootc-factory-enforce-sigpolicy.service`).

## Consequences

- A leaked key + password allows signing; mitigated by environment
  protection, yearly rotation, and keyless signatures/provenance as a second
  check. Revisit KMS or keyless-only once the policy supports URI SANs.
