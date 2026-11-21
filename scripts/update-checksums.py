#!/usr/bin/env python3
"""Refresh product.json checksums for bundle files modified by a patch.

VS Code-style builds ship a `checksums` map in product.json keyed by paths
relative to `out/`. Cursor only lists a few entries there; files without an
entry are left alone, matching what the patcher changed.
"""

import base64
import hashlib
import json
import os
import sys


def main(argv):
    if len(argv) < 3:
        print("usage: update-checksums.py <app-root> <rel-file>...", file=sys.stderr)
        return 2

    app_root, files = argv[1], argv[2:]
    product_path = os.path.join(app_root, "product.json")
    with open(product_path, encoding="utf-8") as handle:
        product = json.load(handle)

    checksums = product.get("checksums")
    if not checksums:
        print("  product.json has no checksums, skipped")
        return 0

    updated = 0
    for rel in files:
        key = rel[len("out/"):] if rel.startswith("out/") else rel
        if key not in checksums:
            print(f"  {key}: no checksum entry, skipped")
            continue
        path = os.path.join(app_root, rel)
        with open(path, "rb") as handle:
            digest = hashlib.sha256(handle.read()).digest()
        checksums[key] = base64.b64encode(digest).decode("ascii").rstrip("=")
        print(f"  {key}: updated")
        updated += 1

    if updated:
        with open(product_path, "w", encoding="utf-8") as handle:
            json.dump(product, handle, indent=2)
            handle.write("\n")

    print(f"  {updated} checksum(s) updated")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
