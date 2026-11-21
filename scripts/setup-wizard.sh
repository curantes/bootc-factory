#!/usr/bin/env bash
# One-time setup of the GitHub side of bootc-factory. Run it yourself:
#
#   scripts/setup-wizard.sh
#
# Every step asks before acting and can be skipped/re-run. Needs: gh (logged
# in with repo + admin rights), cosign 2.x, git, jq.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

bold=$'\e[1m' dim=$'\e[2m' reset=$'\e[0m'
step() { printf '\n%s== %s ==%s\n' "$bold" "$*" "$reset"; }
info() { printf '%s%s%s\n' "$dim" "$*" "$reset"; }
ask() {
	local reply
	read -r -p "$1 [y/N] " reply
	[[ $reply =~ ^[Yy] ]]
}
pause() { read -r -p "Press Enter when done… " _; }

step "Preflight"
for t in gh cosign git jq; do command -v "$t" >/dev/null || { echo "missing: $t"; exit 1; }; done
cosign version 2>/dev/null | grep -q 'GitVersion:\s*v2\.' ||
	echo "WARNING: cosign 2.x recommended (3.x stores signatures where podman/bootc don't look)."
gh auth status >/dev/null || { echo "Run: gh auth login"; exit 1; }
login=$(gh api user --jq .login)
info "GitHub user: $login"

repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)
if [[ -z $repo ]]; then
	step "1. Create the public GitHub repository"
	if ask "Create $login/bootc-factory (public) and add it as 'origin'?"; then
		gh repo create "$login/bootc-factory" --public --source . --remote origin \
			--description "CIS-hardened AlmaLinux bootc images: signed, attested, SBOM'd"
		repo="$login/bootc-factory"
	else
		echo "Create the repo and re-run."; exit 1
	fi
fi
info "Repository: $repo"

step "2. CODEOWNERS"
if grep -q '@OWNER' .github/CODEOWNERS && ask "Set CODEOWNERS owner to @$login?"; then
	sed -i "s/@OWNER/@$login/g" .github/CODEOWNERS
	info "Updated .github/CODEOWNERS (commit it)."
fi

step "3. 'release' environment (main branch only)"
if ask "Create/update the 'release' environment?"; then
	jq -n '{deployment_branch_policy: {protected_branches: false, custom_branch_policies: true}}' |
		gh api -X PUT "repos/$repo/environments/release" --input - >/dev/null
	gh api -X POST "repos/$repo/environments/release/deployment-branch-policies" \
		-f name=main -f type=branch >/dev/null 2>&1 || true
	info "Environment 'release' deployable from main only."
fi

step "4. Cosign signing key"
if [[ -s keys/cosign.pub ]]; then
	info "keys/cosign.pub already exists; skip unless you are rotating (see docs/operations.md)."
fi
if ask "Generate a NEW cosign key pair and store it in the 'release' environment?"; then
	tmp=$(mktemp -d)
	trap 'rm -rf "$tmp"' EXIT
	(umask 077 && cd "$tmp" && cosign generate-key-pair)
	gh secret set COSIGN_PRIVATE_KEY --env release --repo "$repo" <"$tmp/cosign.key"
	echo "Enter the SAME key password again to store it as COSIGN_PASSWORD:"
	gh secret set COSIGN_PASSWORD --env release --repo "$repo"
	cp "$tmp/cosign.pub" keys/cosign.pub
	echo
	echo "${bold}Back up the private key and password in your password manager NOW.${reset}"
	echo "Private key file: $tmp/cosign.key (deleted when this wizard exits)"
	pause
fi

step "5. Repository security settings"
if ask "Apply: Dependabot alerts on, Dependabot updates off, private vuln reporting, read-only default token, auto-merge?"; then
	gh api -X PUT "repos/$repo/vulnerability-alerts" >/dev/null
	gh api -X DELETE "repos/$repo/automated-security-fixes" >/dev/null || true
	gh api -X PUT "repos/$repo/private-vulnerability-reporting" >/dev/null || true
	gh api -X PUT "repos/$repo/actions/permissions/workflow" \
		-f default_workflow_permissions=read -F can_approve_pull_request_reviews=false >/dev/null
	gh repo edit "$repo" --enable-auto-merge --delete-branch-on-merge >/dev/null
	info "Done."
fi

step "6. Commit and push"
info "Commit keys/cosign.pub and CODEOWNERS, then push main (the ruleset comes after the first push)."
if ask "Run 'git add -A && git commit && git push -u origin main' now?"; then
	git add -A
	git commit -m "chore: initialise signing key and code owners" || true
	git push -u origin main
fi

step "7. Branch ruleset for main"
if ask "Create ruleset: PR required, 'ci-ok' must pass, squash-only, no force-push/deletion?"; then
	# Commits are not signed locally. PR-only + squash-only + no bypass
	# means GitHub creates (and signs) every commit that lands on main.
	# No required_signatures rule: it also checks the PR's own commits, so
	# it blocks squash merges of unsigned PRs even though the squash commit
	# is signed (GitHub docs, "Require signed commits").
	gh repo edit "$repo" --enable-squash-merge --enable-merge-commit=false \
		--enable-rebase-merge=false >/dev/null
	jq -n '{
		name: "main", target: "branch", enforcement: "active",
		conditions: {ref_name: {include: ["~DEFAULT_BRANCH"], exclude: []}},
		rules: [
			{type: "deletion"}, {type: "non_fast_forward"},
			{type: "pull_request", parameters: {
				required_approving_review_count: 0, dismiss_stale_reviews_on_push: true,
				require_code_owner_review: false, require_last_push_approval: false,
				required_review_thread_resolution: true,
				allowed_merge_methods: ["squash"]}},
			{type: "required_status_checks", parameters: {
				strict_required_status_checks_policy: false,
				required_status_checks: [{context: "ci-ok"}]}}
		]}' | gh api -X POST "repos/$repo/rulesets" --input - >/dev/null
	info "Ruleset created. Raise required_approving_review_count when you have co-maintainers."
fi

step "8. Install Renovate (Mend-hosted app)"
info "Open https://github.com/apps/renovate , install it for $repo only, then merge its onboarding PR."
pause

step "9. Make the GHCR packages public (after the first successful CI run on main)"
info "For each package (bootc-base, bootc-prometheus, …) open:"
info "  https://github.com/users/$login/packages/container/<package>/settings"
info "  → Danger Zone → Change visibility → Public"
info "Repeat for every new role after its first publish."
pause

step "10. Retention"
info "cleanup.yml runs in dry-run mode. After checking its logs, enable it with:"
info "  gh variable set CLEANUP_DRY_RUN --body false --repo $repo"

echo
echo "${bold}Setup complete.${reset}"
