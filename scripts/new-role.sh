#!/usr/bin/env bash
# Scaffold a new role from images/roles/_template.
#
#   scripts/new-role.sh <name>
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

name=${1:?usage: new-role.sh <name>}
[[ $name =~ ^[a-z][a-z0-9-]{1,30}$ ]] || die "role names are lowercase [a-z0-9-], 2-31 chars"
[[ $name != base ]] || die "'base' is reserved"
dest=images/roles/$name
[[ ! -e $dest ]] || die "$dest already exists"

cp -a images/roles/_template "$dest"
grep -rl __ROLE__ "$dest" | xargs sed -i "s/__ROLE__/$name/g"
log "Created $dest. Next:"
cat <<MSG
  1. Describe the role in $dest/role.yaml and $dest/Containerfile
  2. Add files under $dest/rootfs/ (copied to / in the image)
  3. Write VM assertions in $dest/tests/vm-test.sh
  4. just build base 10 && just build $name 10 && just check $name 10
  5. Add the role to .github/CODEOWNERS if someone else owns it
MSG
