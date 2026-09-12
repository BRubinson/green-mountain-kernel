#!/usr/bin/env python3
"""Static wire-key contract extractor for GMCCDaemonKit/Protocol/*.swift.

Emits one line per stored Codable property: `Type.property -> json_key`.
The effective key is the explicit CodingKeys mapping when one exists, else
Foundation's .convertToSnakeCase of the property name. Run before the
snake-case refactor to freeze the v6 contract (Fixtures/wire_keys.golden);
run after — the diff must be empty for every unintentionally changed key.

Key rule (matches WireCodec's strategies): an explicit CodingKeys raw value is
used verbatim; a bare CodingKeys case and a property with no CodingKeys enum
both encode through .convertToSnakeCase of the name. Pass --warn-unmapped to
flag multi-word properties with no explicit mapping (the pre-refactor
freeze-time check for camelCase leaking onto the wire; always clean since).
"""

import re
import sys
from pathlib import Path

PROTOCOL_DIR = Path(__file__).resolve().parent.parent / "Sources" / "GMCCDaemonKit" / "Protocol"

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


PROPERTY_RE = re.compile(r"^\s{4}public\s+(?:let|var)\s+(\w+)\s*:\s*([^={]+?)\s*$")
STRUCT_RE = re.compile(r"^public struct (\w+)")
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


def main():
    lines = []
    warnings = []
    for path in sorted(PROTOCOL_DIR.glob("*.swift")):
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
    for line in lines:
        print(line)
    if warnings:
        print("\n".join(warnings), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
