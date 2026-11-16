#!/usr/bin/env bash
# Build planning for CI (needs yq + jq; both are on GitHub's Ubuntu runners).
#
#   scripts/plan.sh images                 JSON list of all roles
#   scripts/plan.sh changed <files...>     {"base":bool,"roles":[...]} for changed paths
#   scripts/plan.sh matrix <image>         GitHub matrix (version x arch) for one image
#   scripts/plan.sh versions <image>       JSON list of versions for one image
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

roles() {
	find images/roles -mindepth 2 -maxdepth 2 -name role.yaml -printf '%h\n' |
		xargs -rn1 basename | grep -v '^_' | sort | jq -Rnc '[inputs]'
}

versions() {
	local all
	all=$(yq -o=json -I=0 '.versions' factory.yaml)
	if [[ $1 == base ]]; then
		echo "$all"
		return
	fi
	# A role may narrow, never widen, the global version list.
	yq -o=json -I=0 '.versions // []' "images/roles/$1/role.yaml" |
		jq -c --argjson all "$all" 'if length == 0 then $all else map(select(. as $v | $all | index($v))) end'
}

matrix() {
	local name=$1 boot
	require_image "$name"
	boot=true
	[[ $name == base ]] || boot=$(yq '.boot_test // true' "images/roles/$name/role.yaml")
	jq -nc \
		--argjson versions "$(versions "$name")" \
		--argjson arches "$(yq -o=json -I=0 '.arches' factory.yaml)" \
		--argjson boot_arches "$(yq -o=json -I=0 '.boot_test_arches' factory.yaml)" \
		--argjson boot "$boot" '
		{include: [
			$versions[] as $v | $arches[] as $a | {
				version: $v,
				arch: $a,
				runner: (if $a == "arm64" then "ubuntu-24.04-arm" else "ubuntu-24.04" end),
				boot_test: ($boot and ($boot_arches | index($a) != null))
			}
		]}'
}

changed() {
	local base=false
	local -a touched=()
	for f in "$@"; do
		case $f in
		images/base/* | lib/* | keys/* | factory.yaml | scripts/* | disk/* | security/* | \
			.github/workflows/ci.yml | .github/workflows/_image.yml)
			base=true
			;;
		images/roles/_*) ;;
		images/roles/*/*)
			r=${f#images/roles/}
			touched+=("${r%%/*}")
			;;
		esac
	done
	if [[ $base == true ]]; then
		jq -nc --argjson roles "$(roles)" '{base: true, roles: $roles}'
	else
		printf '%s\n' "${touched[@]}" | sort -u | grep -v '^$' |
			while read -r r; do [[ -f images/roles/$r/role.yaml ]] && echo "$r"; done |
			jq -Rnc '{base: false, roles: [inputs]}'
	fi
}

cmd=${1:?usage: plan.sh images|changed|matrix|versions ...}
shift
case $cmd in
images) roles ;;
changed) changed "$@" ;;
matrix) matrix "${1:?image}" ;;
versions) versions "${1:?image}" ;;
*) die "unknown command $cmd" ;;
esac
