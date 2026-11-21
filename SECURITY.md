# Security policy

## Reporting a vulnerability

Please report vulnerabilities privately via GitHub's
[private vulnerability reporting](https://github.com/curantes/bootc-factory/security/advisories/new). Do not open
a public issue. You can expect an acknowledgement within 5 working days.

## Supported images

Only the moving tags (`ghcr.io/curantes/bootc-*:<major>` and `:latest`) receive
updates. Dated tags are immutable snapshots kept for 90 days for rollback.

## Verifying images

Every published image is signed with the repository's cosign key
([`keys/cosign.pub`](keys/cosign.pub)), signed keylessly by this repository's
CI, and carries SLSA build provenance and an SPDX SBOM:

```sh
scripts/verify-image.sh ghcr.io/curantes/bootc-base:10   # cosign key, checked as bootc does
gh attestation verify oci://ghcr.io/curantes/bootc-base:10 --repo curantes/bootc-factory
```

Hosts built from these images enforce the signature on every `bootc upgrade`
(`/etc/containers/policy.json`).
