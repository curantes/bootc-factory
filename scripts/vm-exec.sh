#!/usr/bin/env bash
# Run one shell command as root inside an ephemeral VM of a local build and
# keep the output in out/vm-exec.log. Root has no password and no SSH (CIS),
# so this is how to look inside an image. The command runs in a directory
# holding the boot-test scripts, so `bash base.sh` and `bash role.sh` work.
#
#   scripts/vm-exec.sh <image> <version> <command>
#   e.g. scripts/vm-exec.sh prometheus 10 'bash role.sh; journalctl -b -p warning'
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

name=${1:?usage: vm-exec.sh <image> <version> <command>}
ver=${2:?usage: vm-exec.sh <image> <version> <command>}
cmd=${3:?usage: vm-exec.sh <image> <version> <command>}
ref=$(local_ref "$name" "$ver")

dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
cp scripts/vm-checks/base.sh "$dir/base.sh"
role_test="$(image_dir "$name")/tests/vm-test.sh"
[[ -f $role_test ]] && cp "$role_test" "$dir/role.sh"
printf '#!/usr/bin/bash\ncd /run/virtiofs-mnt-tests || exit 1\n%s\n' "$cmd" >"$dir/cmd.sh"

mkdir -p out
log "Running in $ref: $cmd"
bcvk_execute "$ref" "$dir" "/usr/bin/bash /run/virtiofs-mnt-tests/cmd.sh" out/vm-exec.log
log "Output in out/vm-exec.log"
