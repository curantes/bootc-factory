# 3. Supply chain: gates before promotion, SBOM, SLSA Build L3

Date: 2026-11-15 · Status: accepted

## Decision

Per image × version × arch, in the reusable workflow `_image.yml`:

1. build + rechunk (`rpm-ostree compose build-chunked-oci`)
2. `bootc container lint`
3. SBOM (Syft, SPDX JSON) for the image and each logically bound image
4. **Vulnerability gate** (Trivy): fail on CRITICAL/HIGH with a fix available.
   For the OS image the gate covers distribution packages (RPM advisories);
   Go/Python libraries vendored inside AlmaLinux RPMs are reported but do not
   gate, since their fixes arrive as RPM errata. Bound images (upstream
   builds) are gated on everything. Exceptions in `security/trivyignore.yaml`
   require a statement and an expiry. Full results go to GitHub code scanning.
   Scanners read the mounted image root filesystem: after rechunking, files
   are hardlinks into `/sysroot/ostree`, which layer-based scanning skips.
5. **Compliance gate** (OpenSCAP, CIS L2 Server minus documented exceptions)
6. **Boot test** in an ephemeral KVM VM (bcvk) on x86_64

Only on `main`, after all gates pass: push per-arch images (dated tags),
attest provenance + SBOM per arch, then in the `release` environment create
the index, sign with the key, attest SBOMs with the key, attest index
provenance, verify everything, and **only then** move `<ver>`,
`<ver>-<date>` and `latest`.

## Scanner choice: Trivy, not Grype

Evaluated 2026-11-15 on `bootc-base:10` (AlmaLinux 10.2, fully updated).
Trivy: 0 fixable CRITICAL/HIGH, matching `dnf upgrade` ("nothing to do").
Grype on the Syft SBOM: 4,408 findings, mostly noise for a gate:
~3,900 kernel matches from Syft's binary classifier compared against
kernel.org versions (ignores RHEL backports), and 351 RPM matches whose
fixes exist only in the next minor release (`el10_3`), not yet installable
on AlmaLinux. Trivy's AlmaLinux errata data matches the gate's definition
("fix available to us"), so Trivy stays the single gating scanner.

## SLSA

Build and provenance generation happen inside a reusable workflow on
GitHub-hosted runners via `actions/attest`, which GitHub documents as meeting
SLSA v1.0 **Build L3**. Verify with
`gh attestation verify oci://… --signer-workflow curantes/bootc-factory/.github/workflows/_image.yml`.
`slsa-github-generator` is unmaintained and not used.

## Hygiene

Actions pinned by SHA, tool images pinned by digest (Renovate),
`permissions: {}` by default, harden-runner (audit), zizmor, actionlint,
shellcheck, OpenSSF Scorecard, branch ruleset with a single `ci-ok` check.
