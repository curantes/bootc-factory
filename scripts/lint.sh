#!/usr/bin/env bash
# Static checks (CI "lint" job). Tools that are missing locally are skipped
# with a warning; CI installs all of them.
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

rc=0
have() { command -v "$1" >/dev/null || { echo "WARN: $1 not installed; skipping" >&2; return 1; }; }
run() { echo "--- $*"; "$@" || rc=1; }

mapfile -t shell_files < <(
	{ git ls-files -co --exclude-standard 'scripts/*.sh' 'scripts/**/*.sh' 'images/**/*.sh'
	  git ls-files -co --exclude-standard lib/factory | while read -r f; do head -1 "$f" | grep -q bash && echo "$f"; done
	} | sort -u)
have shellcheck && run shellcheck -x "${shell_files[@]}"
have actionlint && run actionlint
have zizmor && run zizmor --min-severity medium .github/workflows

echo "--- python syntax"
run python3 -m py_compile lib/factory/*.py lib/factory/bootc-state scripts/*.py

echo "--- unit tests"
run python3 -I -m unittest discover -s tests

echo "--- CIS exception files"
run python3 -I lib/factory/gen-tailoring.py --check \
	--exceptions images/base/cis-exceptions.txt images/roles/*/cis-exceptions.txt

echo "--- role metadata"
for r in images/roles/*/; do
	n=$(basename "$r")
	[[ $n == _* ]] && continue
	[[ -f $r/.containerignore ]] || { echo "$r: missing .containerignore"; rc=1; }
	[[ $(yq '.name' "$r/role.yaml") == "$n" ]] || { echo "$r/role.yaml: name must be '$n'"; rc=1; }
	grep -q 'bootc-factory/finalize' "$r/Containerfile" || { echo "$r/Containerfile: must end with finalize"; rc=1; }
	[[ $(grep -v '^\s*$' "$r/Containerfile" | tail -1) == *finalize* ]] ||
		{ echo "$r/Containerfile: finalize must be the LAST instruction"; rc=1; }
done

echo "--- no dev keys committed"
if git ls-files -c keys | grep -q 'cosign-dev'; then echo "keys/: development key is tracked"; rc=1; fi

echo "--- JSON policy fragments"
for f in $(git ls-files -co --exclude-standard '*.json'); do run python3 -I -m json.tool "$f" >/dev/null; done

exit "$rc"
