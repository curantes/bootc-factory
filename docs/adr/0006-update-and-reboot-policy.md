# 6. Staged updates with a reboot window

Date: 2026-11-15 · Status: accepted

## Decision

`bootc-fetch-apply-updates.timer` (download + immediate reboot) is masked.
Instead:

- `bootc-factory-stage-update.timer`: nightly `bootc upgrade` (download and
  stage only; signatures verified).
- `bootc-factory-reboot-window.timer`: Sunday 03:00 reboots into a staged
  update if `/etc/bootc-factory/updates.conf` has `REBOOT=auto`.
  `REBOOT=never` leaves the reboot to an operator.
- Hosts/roles change the window with a timer drop-in.
- `bootc-factory-aide-reinit.service` re-baselines AIDE once per booted image
  digest, since every update legitimately changes `/usr`.

Rollback: `bootc rollback` and reboot, or pin a dated tag with `bootc switch`.
