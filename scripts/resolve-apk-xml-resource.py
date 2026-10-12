#!/usr/bin/env python3
"""Resolve a compiled AAPT2 XML entry by logical resource name.

Android resource packaging may rename res/xml/foo.xml to res/A1.xml; the
resource table, not the original on-disk filename, is the authority.
"""
import re
import sys

RESOURCE_LINE = re.compile(
    r"^\s*resource\s+0x[0-9a-fA-F]{8}\s+"
    r"(?:(?:[A-Za-z0-9_.]+):)?([a-z][a-z0-9_]*/[A-Za-z0-9_.]+)"
    r"(?::|\s|$)"
)
FILE = re.compile(r"\(file\)\s+(res/[A-Za-z0-9_./-]+\.xml)(?:\s|$)")


def resolve(dump: str, logical_name: str) -> str:
    if not re.fullmatch(r"[a-z][a-z0-9_]*/[A-Za-z0-9_]+", logical_name):
        raise ValueError("invalid logical resource name")
    matched = False
    found: set[str] = set()
    active = False
    for line in dump.splitlines():
        header = RESOURCE_LINE.match(line)
        if header:
            active = header.group(1) == logical_name
            matched = matched or active
        if active:
            for filename in FILE.findall(line):
                if ".." in filename.split("/") or not filename.startswith("res/"):
                    raise ValueError("invalid resource table XML path")
                found.add(filename)
    if not matched:
        raise ValueError(f"AAPT2 table does not contain {logical_name}")
    if len(found) != 1:
        raise ValueError(f"expected one packaged XML path for {logical_name}, found {sorted(found)!r}")
    return next(iter(found))


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: resolve-apk-xml-resource.py type/name < aapt2-dump-resources", file=sys.stderr)
        return 2
    try:
        print(resolve(sys.stdin.read(), sys.argv[1]))
    except ValueError as exc:
        print(f"APK compiled-resource check failed: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
