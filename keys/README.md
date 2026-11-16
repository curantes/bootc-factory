# Signing keys

`cosign.pub` is the public half of the cosign key that signs every published
image. It is baked into the base image (`/etc/pki/containers/bootc-factory/`)
and referenced by `/etc/containers/policy.json`, so hosts reject updates that
are not signed with it.

- Create it with `scripts/setup-wizard.sh` (private key + password go to the
  `release` environment secrets; keep an offline backup in your password
  manager).
- Local builds without the real key: `just dev-key` writes a throwaway
  `cosign-dev.pub` (git-ignored). Never publish images built with it.
- Rotation: add the new key as `cosign-YYYY.pub` next to the old one and ship
  one release (hosts then trust both), switch the secrets, then remove the old
  `.pub`. See docs/operations.md#key-rotation.
