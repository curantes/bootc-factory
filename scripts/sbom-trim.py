#!/usr/bin/python3
"""Reduce an SPDX 2.3 JSON SBOM to package level.

Removes `files` and every relationship that references a file, and marks
packages as not file-analyzed, so the document stays valid SPDX while fitting
the 16 MB limit of GitHub attestations.

Usage: sbom-trim.py <in.spdx.json> <out.spdx.json>
"""

import json
import sys


def main(src, dst):
    with open(src) as fh:
        doc = json.load(fh)
    file_ids = {f["SPDXID"] for f in doc.pop("files", [])}
    doc["relationships"] = [
        r for r in doc.get("relationships", [])
        if r.get("spdxElementId") not in file_ids and r.get("relatedSpdxElement") not in file_ids
    ]
    for pkg in doc.get("packages", []):
        pkg["filesAnalyzed"] = False
        pkg.pop("packageVerificationCode", None)
        pkg.pop("hasFiles", None)
    with open(dst, "w") as fh:
        json.dump(doc, fh, separators=(",", ":"))
    print(f"{dst}: {len(doc['packages'])} packages, {len(doc['relationships'])} relationships, "
          f"{len(file_ids)} file entries removed")


if __name__ == "__main__":
    sys.exit(main(*sys.argv[1:3]))
