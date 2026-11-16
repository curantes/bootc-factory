#!/usr/bin/python3
"""Summarise XCCDF results; exit 1 if any rule failed or errored.

Usage: oscap-summary.py <xccdf-results.xml> [title]
Appends a Markdown summary to $GITHUB_STEP_SUMMARY when set.
"""

import collections
import os
import sys
import xml.etree.ElementTree as ET

NS = {"x": "http://checklists.nist.gov/xccdf/1.2"}
PREFIX = "xccdf_org.ssgproject.content_rule_"


def main(path, title="image"):
    root = ET.parse(path).getroot()
    results = root.findall(".//x:TestResult/x:rule-result", NS)
    counts = collections.Counter()
    bad = []
    for rr in results:
        res = rr.findtext("x:result", namespaces=NS)
        counts[res] += 1
        if res in ("fail", "error"):
            bad.append((res, rr.get("idref").removeprefix(PREFIX)))
    score = root.findtext(".//x:TestResult/x:score", namespaces=NS) or "?"

    lines = [f"### CIS L2 Server compliance: {title}", ""]
    lines.append("| result | rules |\n|---|---|")
    lines += [f"| {k} | {v} |" for k, v in sorted(counts.items())]
    lines.append(f"\nScore: {float(score):.1f}" if score != "?" else "")
    if bad:
        lines += ["", "**Failing rules** (fix, or add to cis-exceptions.txt with a reason):", ""]
        lines += [f"- `{rule}` ({res})" for res, rule in sorted(bad, key=lambda b: b[1])]
    text = "\n".join(lines) + "\n"
    print(text)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as fh:
            fh.write(text)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(*sys.argv[1:3]))
