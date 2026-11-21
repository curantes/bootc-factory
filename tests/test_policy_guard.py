"""Unit tests for scripts/policy-guard.py (run by scripts/lint.sh)."""

import importlib.util
import pathlib
import unittest

_path = pathlib.Path(__file__).resolve().parent.parent / "scripts" / "policy-guard.py"
_spec = importlib.util.spec_from_file_location("policy_guard", _path)
pg = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(pg)

D1, D2 = "sha256:" + "1" * 64, "sha256:" + "2" * 64
HEAD = "a" * 40


def patch(*pairs, context="# context"):
    lines = ["@@ -1,3 +1,3 @@", context]
    for old, new in pairs:
        lines += [f"-{old}", f"+{new}"]
    return "\n".join(lines)


def file(path, *pairs, status="modified", **extra):
    return {"filename": path, "status": status, "patch": patch(*pairs), **extra}


def pr(author, head=HEAD):
    return {"user": {"login": author}, "head": {"sha": head}}


def review(login, state, commit=HEAD):
    return {"user": {"login": login}, "state": state, "commit_id": commit}


QUADLET = "images/roles/prometheus/rootfs/usr/share/containers/systemd/prometheus.container"


class Globs(unittest.TestCase):
    def test_globs(self):
        self.assertTrue(pg.glob_match("**/*.container", QUADLET))
        self.assertTrue(pg.glob_match("**/cis-exceptions.txt", "images/base/cis-exceptions.txt"))
        self.assertTrue(pg.glob_match(".github/**", ".github/workflows/ci.yml"))
        self.assertFalse(pg.glob_match("scripts/lib.sh", "scripts/lib.sh.bak"))
        self.assertFalse(pg.glob_match("flake.lock", "sub/flake.lock"))


class Pairs(unittest.TestCase):
    def test_digest_bump(self):
        self.assertIsNone(pg.check_pair(f"Image=quay.io/p/prometheus:v3.16.0@{D1}", f"Image=quay.io/p/prometheus:v3.16.0@{D2}"))

    def test_patch_bump(self):
        self.assertIsNone(pg.check_pair(f"Image=quay.io/p/prometheus:v3.16.0@{D1}", f"Image=quay.io/p/prometheus:v3.16.1@{D2}"))

    def test_minor_bump_needs_review(self):
        self.assertIn("more than a patch", pg.check_pair(f"Image=quay.io/p/prometheus:v3.16.0@{D1}", f"Image=quay.io/p/prometheus:v3.17.0@{D2}"))

    def test_image_swap_needs_review(self):
        self.assertIn("more than a version", pg.check_pair(f"Image=quay.io/p/prometheus:v3.16.0@{D1}", f"Image=evil.io/p/prometheus:v3.16.1@{D2}"))

    def test_upstream_env_digest(self):
        old = f"UPSTREAM_IMAGE_10=quay.io/almalinuxorg/almalinux-bootc:10@{D1}"
        self.assertIsNone(pg.check_pair(old, old.replace(D1, D2)))
        self.assertIn("not semver", pg.check_pair(old, old.replace(":10@", ":11@")))

    def test_gate_tools_always_reviewed(self):
        for key in ("TRIVY_IMAGE", "IMAGE_BUILDER_IMAGE"):
            old = f"{key}=ghcr.io/x/y:v1.0.0@{D1}"
            self.assertIn("gate tool", pg.check_pair(old, old.replace(D1, D2)))

    def test_tool_version(self):
        self.assertIsNone(pg.check_pair("ACTIONLINT_VERSION=v1.7.12", "ACTIONLINT_VERSION=v1.7.13"))
        self.assertIn("more than a patch", pg.check_pair("ACTIONLINT_VERSION=v1.7.12", "ACTIONLINT_VERSION=v1.8.0"))

    def test_flake_lock_pins(self):
        self.assertIsNone(pg.check_pair(f'      "rev": "{"a" * 40}",', f'      "rev": "{"b" * 40}",'))
        self.assertIsNone(pg.check_pair('      "lastModified": 1763000000,', '      "lastModified": 1763600000,'))
        nar = '      "narHash": "sha256-{}=",'
        self.assertIsNone(pg.check_pair(nar.format("A" * 43), nar.format("B" * 43)))
        self.assertIsNotNone(pg.check_pair('      "owner": "NixOS",', '      "owner": "evil",'))

    def test_other_lines_need_review(self):
        self.assertIn("not a version", pg.check_pair("PublishPort=9090:9090", "PublishPort=9091:9090"))
        self.assertIn("not a version", pg.check_pair("Exec=--web.enable-lifecycle", "Exec=--web.enable-admin-api"))


class LinePairs(unittest.TestCase):
    def test_one_for_one(self):
        pairs, problem = pg.line_pairs(patch(("a", "b"), ("c", "d")))
        self.assertIsNone(problem)
        self.assertEqual(pairs, [("a", "b"), ("c", "d")])

    def test_added_line(self):
        _, problem = pg.line_pairs("@@ -1 +1,2 @@\n ctx\n+Volume=/:/host")
        self.assertIn("0 line(s) removed, 1 added", problem)

    def test_removed_line(self):
        _, problem = pg.line_pairs("@@ -1,2 +1 @@\n ctx\n-ReadOnly=true")
        self.assertIn("1 line(s) removed, 0 added", problem)

    def test_no_newline_marker(self):
        pairs, problem = pg.line_pairs("@@ -1 +1 @@\n-a\n\\ No newline at end of file\n+b\n\\ No newline at end of file")
        self.assertIsNone(problem)
        self.assertEqual(pairs, [("a", "b")])


class Files(unittest.TestCase):
    def test_allowed_bump(self):
        f = file(QUADLET, (f"Image=quay.io/p/prometheus:v3.16.0@{D1}", f"Image=quay.io/p/prometheus:v3.16.1@{D2}"))
        self.assertEqual(pg.check_files([f]), [])

    def test_protected_and_unlisted(self):
        reasons = pg.check_files([
            file(".github/workflows/ci.yml", ("uses: a@x", "uses: a@y")),
            file("scripts/build.sh", ("a", "b")),
        ])
        self.assertIn("protected path", reasons[0])
        self.assertIn("not in the Renovate allowlist", reasons[1])

    def test_new_or_renamed_file(self):
        self.assertIn("added", pg.check_files([file("x/new.container", status="added")])[0])
        renamed = file(QUADLET, status="renamed", previous_filename="old.container")
        self.assertIn("renamed", pg.check_files([renamed])[0])

    def test_missing_patch(self):
        self.assertIn("no diff", pg.check_files([{"filename": "flake.lock", "status": "modified"}])[0])


class Decide(unittest.TestCase):
    OWNER = {"curantes"}
    BUMP = [file(QUADLET, (f"Image=quay.io/p/prometheus:v3.16.0@{D1}", f"Image=quay.io/p/prometheus:v3.16.0@{D2}"))]
    MINOR = [file(QUADLET, (f"Image=quay.io/p/prometheus:v3.16.0@{D1}", f"Image=quay.io/p/prometheus:v3.17.0@{D2}"))]

    def test_owner_passes(self):
        self.assertTrue(pg.decide(pr("curantes"), self.MINOR, [], self.OWNER)[0])

    def test_renovate_bump_passes(self):
        self.assertTrue(pg.decide(pr(pg.RENOVATE), self.BUMP, [], self.OWNER)[0])

    def test_renovate_minor_needs_approval(self):
        self.assertFalse(pg.decide(pr(pg.RENOVATE), self.MINOR, [], self.OWNER)[0])
        self.assertTrue(pg.decide(pr(pg.RENOVATE), self.MINOR, [review("curantes", "APPROVED")], self.OWNER)[0])

    def test_stranger_needs_approval_even_for_a_bump(self):
        self.assertFalse(pg.decide(pr("someone"), self.BUMP, [], self.OWNER)[0])

    def test_approval_must_be_for_head(self):
        old = [review("curantes", "APPROVED", commit="b" * 40)]
        self.assertFalse(pg.decide(pr("someone"), self.BUMP, old, self.OWNER)[0])

    def test_only_approvers_count(self):
        self.assertFalse(pg.decide(pr("someone"), self.BUMP, [review("friend", "APPROVED")], self.OWNER)[0])

    def test_latest_verdict_wins(self):
        later_dismissed = [review("curantes", "APPROVED"), review("curantes", "DISMISSED")]
        self.assertFalse(pg.decide(pr("someone"), self.BUMP, later_dismissed, self.OWNER)[0])
        comment_after = [review("curantes", "APPROVED"), review("curantes", "COMMENTED")]
        self.assertTrue(pg.decide(pr("someone"), self.BUMP, comment_after, self.OWNER)[0])


if __name__ == "__main__":
    unittest.main()
