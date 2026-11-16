#!/usr/bin/python3
"""Generate an XCCDF 1.2 tailoring file from cis-exceptions files.

Exceptions file format (see images/base/cis-exceptions.txt):

    <kind>  <rule>  <reason ...>

Also used in CI with --check to validate exception files without a datastream.
Standard library only: runs inside the image build and on CI runners.
"""

import argparse
import pathlib
import re
import sys
import xml.etree.ElementTree as ET

XCCDF = "http://checklists.nist.gov/xccdf/1.2"
RULE_PREFIX = "xccdf_org.ssgproject.content_rule_"
BASE_PROFILE = "xccdf_org.ssgproject.content_profile_cis"
KINDS = {"exception", "deploy-time"}
RULE_RE = re.compile(r"^[a-z0-9_.-]+$")


def parse_exceptions(paths):
    entries, errors = [], []
    for path in paths:
        for lineno, raw in enumerate(path.read_text().splitlines(), 1):
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split(None, 2)
            where = f"{path}:{lineno}"
            if len(parts) < 3:
                errors.append(f"{where}: expected '<kind> <rule> <reason>'")
                continue
            kind, rule, reason = parts
            if kind not in KINDS:
                errors.append(f"{where}: unknown kind {kind!r} (use {sorted(KINDS)})")
            if rule.startswith(RULE_PREFIX):
                rule = rule[len(RULE_PREFIX):]
            if not RULE_RE.match(rule):
                errors.append(f"{where}: invalid rule id {rule!r}")
            entries.append((kind, RULE_PREFIX + rule, reason, where))
    return entries, errors


def datastream_rules(path):
    ids = set()
    for _, elem in ET.iterparse(path):
        if elem.tag == f"{{{XCCDF}}}Rule":
            ids.add(elem.get("id"))
        elem.clear()
    return ids


def build_tailoring(name, rules, datastream):
    ET.register_namespace("xccdf", XCCDF)
    q = lambda tag: f"{{{XCCDF}}}{tag}"  # noqa: E731
    root = ET.Element(q("Tailoring"), {"id": f"xccdf_io.github.bootc-factory_tailoring_cis_{name}"})
    ET.SubElement(root, q("benchmark"), {"href": f"file://{datastream}"})
    ET.SubElement(root, q("version"), {"time": "1970-01-01T00:00:00"}).text = "1"
    profile = ET.SubElement(
        root,
        q("Profile"),
        {"id": f"xccdf_io.github.bootc-factory_profile_cis_{name}", "extends": BASE_PROFILE},
    )
    ET.SubElement(profile, q("title")).text = f"CIS Level 2 - Server (bootc-factory, {name})"
    ET.SubElement(profile, q("description")).text = (
        "Generated from cis-exceptions.d by bootc-factory gen-tailoring.py. Do not edit."
    )
    for rule in sorted(rules):
        ET.SubElement(profile, q("select"), {"idref": rule, "selected": "false"})
    ET.indent(root)
    return ET.tostring(root, encoding="unicode", xml_declaration=True) + "\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--exceptions-dir", type=pathlib.Path)
    ap.add_argument("--exceptions", type=pathlib.Path, nargs="*", default=[])
    ap.add_argument("--check", action="store_true", help="only validate the files")
    ap.add_argument("--datastream")
    ap.add_argument("--kinds", default="exception,deploy-time")
    ap.add_argument("--name", default="build")
    ap.add_argument("--out", type=pathlib.Path)
    args = ap.parse_args()

    files = list(args.exceptions)
    if args.exceptions_dir:
        files += sorted(args.exceptions_dir.glob("*.txt"))
    entries, errors = parse_exceptions(files)
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    if args.check:
        print(f"OK: {len(entries)} exception entries in {len(files)} file(s)")
        return 0
    if not (args.datastream and args.out):
        ap.error("--datastream and --out are required unless --check")

    kinds = set(args.kinds.split(","))
    known = datastream_rules(args.datastream)
    selected = set()
    for kind, rule, _reason, where in entries:
        if kind not in kinds:
            continue
        if rule not in known:
            print(f"WARNING: {where}: {rule} not in {args.datastream}; ignored", file=sys.stderr)
            continue
        selected.add(rule)
    args.out.write_text(build_tailoring(args.name, selected, args.datastream))
    print(f"wrote {args.out} ({len(selected)} rules deselected)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
