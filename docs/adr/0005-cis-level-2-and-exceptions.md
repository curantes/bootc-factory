# 5. CIS Level 2 Server via oscap-im, with typed exceptions

Date: 2026-11-15 · Status: accepted

## Decision

- Every image's last build step (`/usr/libexec/bootc-factory/finalize`) runs
  `oscap-im` with the SSG `cis` profile (CIS AlmaLinux 9/10 Level 2 – Server)
  through a generated tailoring. Roles re-run it, so packages they add are
  hardened too.
- Exceptions live in `cis-exceptions.txt` (base) and per role, as
  `<kind> <rule> <reason>`:
  - `deploy-time`: remediated at build time where possible, but only
    verifiable on a booted host (LVM layout, tmpfs mounts, `kargs.d`, running
    services, live sysctl values). Skipped by the CI gate
    (`cis-gate-tailoring.xml`); checked by on-host scans
    (`cis-host-tailoring.xml`, which is also what `oscap-im` remediates with).
  - `exception`: accepted risk, excluded everywhere.
- Current accepted risks:
  - `grub2_password`: bootc manages the bootloader via bootupd. **Assumption:**
    access to VM consoles is restricted by the hypervisor/cloud platform.
  - `ensure_root_password_configured`: root stays locked; administrators are
    cloud-init users in `wheel` (sudo with password). SSH is limited to
    `wheel` (`AllowGroups wheel`).
  - `partition_for_home`: `/home` → `/var/home`, covered by the `/var` LV.
  - `kernel_module_overlayfs_disabled` (EL10): composefs and podman need it.
- CODEOWNERS requires security review of every exceptions file.

## Consequences

The crypto policy is set by the CIS profile (DEFAULT plus CIS sub-policies,
no SHA-1); FIPS is out of scope. The first CI runs will reveal further rules
that cannot be evaluated in a container; classify each as `deploy-time` or
fix it, never silence it without a reason.
