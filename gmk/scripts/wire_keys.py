#!/usr/bin/env python3
"""Static wire-key contract extractor for the GmKernelCoreShared Protocol tree.

Emits one line per stored Codable property of every top-level struct under
Sources/API/Shared/GmKernelCoreShared/Protocol (recursively, WireCodec.swift
excluded): `Type.property -> json_key`. The effective key is the explicit
CodingKeys mapping when one exists, else Foundation's .convertToSnakeCase of
the property name.

The frozen contract is gmk/scripts/wire_keys.golden: its first line is
`version <GmWireProtocol.version>`, the rest is this script's sorted output.
Diff a run against it to prove a change moved no wire key:

    python3 gmk/scripts/wire_keys.py | diff - <(tail -n +2 gmk/scripts/wire_keys.golden)

Pass --write-golden to rewrite the golden from the current tree (read the diff
before committing it: regenerating accepts every pending drift).

Key rule (matches WireCodec's strategies): an explicit CodingKeys raw value is
used verbatim; a bare CodingKeys case and a property with no CodingKeys enum
both encode through .convertToSnakeCase of the name. Pass --warn-unmapped to
flag multi-word properties with no explicit mapping.

Exits non-zero when the Protocol directory is missing or no key is found, so a
moved tree fails loudly instead of yielding an empty contract.
"""

import re
import sys
from pathlib import Path

GMK_DIR = Path(__file__).resolve().parent.parent
PROTOCOL_DIR = GMK_DIR / "Sources" / "API" / "Shared" / "GmKernelCoreShared" / "Protocol"
ENVELOPE = PROTOCOL_DIR / "Envelope.swift"
GOLDEN = Path(__file__).resolve().parent / "wire_keys.golden"
VERSION_RE = re.compile(r"^\s*static let version = (\d+)\s*$", re.MULTILINE)

# Foundation's JSONEncoder.KeyEncodingStrategy.convertToSnakeCase.
def to_snake(name: str) -> str:
    if not name:
        return name
    out = []
    chars = list(name)
    i = 0
    n = len(chars)
    while i < n:
        c = chars[i]
        if c.isupper():
            # find the run of uppercase
            j = i
            while j < n and chars[j].isupper():
                j += 1
            run = "".join(chars[i:j]).lower()
            if j < n and j - i > 1:
                # last upper of the run starts the next word
                out.append("_" + run[:-1])
                out.append("_" + run[-1])
            else:
                out.append("_" + run)
            i = j
        else:
            out.append(c)
            i += 1
    s = "".join(out)
    return s.lstrip("_")


PROPERTY_RE = re.compile(r"^\s{4}(?:public\s+)?(?:let|var)\s+(\w+)\s*:\s*([^={]+?)\s*$")
STRUCT_RE = re.compile(r"^(?:public\s+)?struct (\w+)")
CODING_KEYS_RE = re.compile(r"^\s{4}(?:private|public)?\s*enum CodingKeys")
CASE_MAPPED_RE = re.compile(r"^\s{8}case\s+(\w+)\s*=\s*\"([^\"]+)\"")
CASE_BARE_RE = re.compile(r"^\s{8}case\s+(\w+)\s*$")


def parse_file(path: Path):
    structs = {}  # name -> {"props": [name...], "keys": {prop: key} or None}
    current = None
    in_coding_keys = False
    depth = 0
    for raw in path.read_text().splitlines():
        line = raw.rstrip("\n")
        m = STRUCT_RE.match(line)
        if m and depth == 0:
            current = m.group(1)
            structs[current] = {"props": [], "keys": None}
        if current is not None:
            depth += line.count("{") - line.count("}")
            if depth <= 0 and "}" in line:
                current = None
                in_coding_keys = False
                depth = 0
                continue
            if CODING_KEYS_RE.match(line):
                in_coding_keys = True
                structs[current]["keys"] = {}
                continue
            if in_coding_keys:
                m = CASE_MAPPED_RE.match(line)
                if m:
                    structs[current]["keys"][m.group(1)] = m.group(2)
                    continue
                m = CASE_BARE_RE.match(line)
                if m:
                    # A bare case's stringValue still passes through the coder
                    # key strategy, so its effective wire key is the conversion.
                    structs[current]["keys"][m.group(1)] = to_snake(m.group(1))
                    continue
                if line.strip() == "}":
                    in_coding_keys = False
                continue
            m = PROPERTY_RE.match(line)
            if m and "{" not in line:
                structs[current]["props"].append(m.group(1))
    return structs


def wire_version() -> int:
    """Read GmWireProtocol.version from Envelope.swift; exit 1 when absent."""
    match = VERSION_RE.search(ENVELOPE.read_text()) if ENVELOPE.is_file() else None
    if match is None:
        sys.exit(f"wire_keys: no `static let version` in {ENVELOPE}")
    return int(match.group(1))


def main():
    if not PROTOCOL_DIR.is_dir():
        sys.exit(f"wire_keys: protocol directory not found: {PROTOCOL_DIR}")
    lines = []
    warnings = []
    for path in sorted(PROTOCOL_DIR.rglob("*.swift")):
        if path.name == "WireCodec.swift":
            continue
        for name, info in sorted(parse_file(path).items()):
            keys = info["keys"]
            for prop in info["props"]:
                if keys is not None and prop in keys:
                    key = keys[prop]
                elif keys is not None:
                    # property omitted from an explicit CodingKeys enum: not encoded
                    continue
                else:
                    key = to_snake(prop)
                    if key != prop and "--warn-unmapped" in sys.argv:
                        warnings.append(
                            f"WARNING: {name}.{prop} has no explicit mapping "
                            f"(wire key '{key}' comes from the strategy alone)"
                        )
                lines.append(f"{name}.{prop} -> {key}")
    if not lines:
        sys.exit(f"wire_keys: no wire keys found under {PROTOCOL_DIR}")
    lines.sort()
    if "--write-golden" in sys.argv:
        GOLDEN.write_text(f"version {wire_version()}\n" + "\n".join(lines) + "\n")
        print(f"wrote {len(lines)} keys to {GOLDEN}", file=sys.stderr)
        return
    for line in lines:
        print(line)
    if warnings:
        print("\n".join(warnings), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
