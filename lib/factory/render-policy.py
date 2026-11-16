#!/usr/bin/python3
"""Render /etc/containers/policy.json from policy.d fragments.

Default is `reject`: only scopes listed in a fragment may be pulled.
Each fragment is JSON of the form  {"<transport>": {"<scope>": [requirements]}}.
Fragments are merged in file-name order; a later fragment may not redefine a
scope (that would silently weaken an earlier, stricter rule).
"""

import json
import pathlib
import sys

BASE = {
    "default": [{"type": "reject"}],
    "transports": {
        # Local-only transports: content already on this machine (podman
        # build, bootc bound-image store, rpm-ostree rechunking, osbuild).
        # Reaching them requires local root; registries stay `reject`.
        "containers-storage": {"": [{"type": "insecureAcceptAnything"}]},
        "oci": {"": [{"type": "insecureAcceptAnything"}]},
        "oci-archive": {"": [{"type": "insecureAcceptAnything"}]},
        "docker-daemon": {"": [{"type": "reject"}]},
    },
}


def main(fragment_dir, out):
    policy = json.loads(json.dumps(BASE))
    for path in sorted(pathlib.Path(fragment_dir).glob("*.json")):
        for transport, scopes in json.loads(path.read_text()).items():
            target = policy["transports"].setdefault(transport, {})
            for scope, reqs in scopes.items():
                if scope in target:
                    sys.exit(f"ERROR: {path}: scope {transport}:{scope} already defined")
                target[scope] = reqs
    pathlib.Path(out).write_text(json.dumps(policy, indent=2, sort_keys=True) + "\n")
    print(f"wrote {out}")


if __name__ == "__main__":
    main(*sys.argv[1:3])
