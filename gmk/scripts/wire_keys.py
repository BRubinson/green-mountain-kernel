#!/usr/bin/env python3
"""Static wire-key contract extractor for the GmKernelCoreShared tree.

Scans every Swift file under Sources/Core/GmKernelCoreShared (WireCodec.swift
excluded) and emits one sorted line per wire key:

    Type.property -> json_key    a key of a struct, class or keyed enum
    Type.case = raw_value        a case of a raw-value enum

Types are recorded when they declare Codable, Encodable or Decodable; under
Protocol/ every raw-value enum and the visible, uninitialised stored
properties of every top-level struct are recorded too. Nested types are
qualified (`Outer.Inner`).
The effective key is the explicit CodingKeys raw value when one exists, else
Foundation's .convertToSnakeCase of the name. A CodingKeys enum lists every
key the type encodes, so each of its cases is recorded; without one, every
stored property is. A Codable enum with no raw type, no CodingKeys and no
custom init(from:) records its case names as keys.

The frozen contract is gmk/scripts/wire_keys.golden: its first line is
`version <GmWireProtocol.version>`, the rest is this script's sorted output.
Diff a run against it to prove a change moved no wire key:

    python3 gmk/scripts/wire_keys.py | diff - <(tail -n +2 gmk/scripts/wire_keys.golden)

Pass --write-golden to rewrite the golden from the current tree (read the diff
before committing it: regenerating accepts every pending drift). Pass
--warn-unmapped to flag multi-word properties with no explicit mapping.

The tree read is the one this script sits in, so a copy checked out of the
index reads the index. Exits non-zero when the Protocol directory is missing or
no key is found, so a moved tree fails loudly instead of yielding an empty
contract.
"""

import re
import sys
from pathlib import Path

GMK_DIR = Path(__file__).resolve().parent.parent
SHARED_DIR = GMK_DIR / "Sources" / "Core" / "GmKernelCoreShared"
PROTOCOL_DIR = SHARED_DIR / "Protocol"
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


MODIFIERS = r"(?:(?:public|private|fileprivate|internal|package|open|final|indirect|nonisolated)(?:\(set\))?\s+)*"
ATTRIBUTES = r"(?:@\w+(?:\([^)]*\))?\s+)*"
DECL_RE = re.compile(
    rf"^\s*{ATTRIBUTES}{MODIFIERS}(struct|enum|class|actor|extension)\s+([A-Za-z_][\w.]*)"
    r"\s*(?:<[^{]*?>)?\s*(?::\s*([^{]*?))?\s*(?:\bwhere\b[^{]*)?(?:\{|$)"
)
PROPERTY_RE = re.compile(rf"^\s*{ATTRIBUTES}{MODIFIERS}(static\s+|class\s+|lazy\s+)?(?:let|var)\s+(\w+)\s*(.*)$")
CASE_RE = re.compile(r"^\s*(?:indirect\s+)?case\s+(.*)$")
CASE_ITEM_RE = re.compile(r"^(\w+)\s*(\(.*\))?\s*(?:=\s*(.+))?$", re.S)
CODABLE_RE = re.compile(r"\b(?:Codable|Encodable|Decodable)\b")
RAW_TYPES = {"String", "Character", "Int", "Int8", "Int16", "Int32", "Int64",
             "UInt", "UInt8", "UInt16", "UInt32", "UInt64", "Double", "Float"}


def scan(line, state):
    """Split one line into code with string contents blanked, and code with comments removed.

    `state` carries an open block comment or multi-line string across lines.
    """
    masked, kept = [], []
    i, n = 0, len(line)
    while i < n:
        if state.get("block"):
            end = line.find("*/", i)
            if end < 0:
                return "".join(masked), "".join(kept)
            state["block"] = False
            i = end + 2
            continue
        close = state.get("string")
        if close:
            end = line.find(close, i)
            if end < 0:
                kept.append(line[i:])
                return "".join(masked), "".join(kept)
            kept.append(line[i:end + len(close)])
            state["string"] = None
            i = end + len(close)
            continue
        if line.startswith("//", i):
            break
        if line.startswith("/*", i):
            state["block"] = True
            i += 2
            continue
        m = re.match(r'(#*)"""', line[i:])
        if m:
            state["string"] = '"""' + m.group(1)
            masked.append('""')
            kept.append(m.group(0))
            i += len(m.group(0))
            continue
        m = re.match(r'(#*)"', line[i:])
        if m:
            hashes = m.group(1)
            close = '"' + hashes
            j = i + len(m.group(0))
            while j < n:
                if not hashes and line[j] == "\\":
                    j += 2
                    continue
                if line.startswith(close, j):
                    break
                j += 1
            j = min(j + len(close), n)
            masked.append('""')
            kept.append(line[i:j])
            i = j
            continue
        masked.append(line[i])
        kept.append(line[i])
        i += 1
    return "".join(masked), "".join(kept)


def split_items(text):
    """Split a case list on its top-level commas."""
    items, depth, cur, quote = [], 0, [], False
    for ch in text:
        if ch == '"':
            quote = not quote
        elif not quote and ch in "([":
            depth += 1
        elif not quote and ch in ")]":
            depth -= 1
        elif not quote and depth == 0 and ch == ",":
            items.append("".join(cur).strip())
            cur = []
            continue
        cur.append(ch)
    items.append("".join(cur).strip())
    return [item for item in items if item]


def new_type(types, name):
    return types.setdefault(name, {
        "kind": None, "codable": False, "protocol": False, "raw_type": None,
        "props": [], "keys": None, "cases": [], "custom_decode": False, "custom_encode": False,
    })


def member(types, frame, masked, kept):
    """Record one line that sits directly in a type body."""
    info = types[frame["type"]] if frame["type"] else None
    if frame["coding_keys"] is not None:
        owner = frame["coding_keys"]
        m = CASE_RE.match(kept)
        text = m.group(1) if m else (kept.strip() if frame["continues"] else None)
        if text is None:
            return
        frame["continues"] = text.rstrip().endswith(",")
        for item in split_items(text):
            im = CASE_ITEM_RE.match(item)
            if im:
                raw = im.group(3)
                key = raw.strip().strip('"') if raw else to_snake(im.group(1))
                types[owner]["keys"][im.group(1)] = key
        return
    if info is None:
        return
    if info["kind"] == "enum":
        m = CASE_RE.match(kept)
        text = m.group(1) if m else (kept.strip() if frame["continues"] else None)
        if text is not None:
            frame["continues"] = text.rstrip().endswith(",")
            for item in split_items(text):
                im = CASE_ITEM_RE.match(item)
                if im:
                    raw = im.group(3)
                    info["cases"].append((im.group(1), raw.strip() if raw else None))
            return
    if re.match(r"^\s*(?:(?:public|private|fileprivate|internal|package|required|convenience)\s+)*init\s*\(from\b", masked):
        info["custom_decode"] = True
        return
    if re.match(r"^\s*(?:(?:public|private|fileprivate|internal|package)\s+)*func\s+encode\s*\(to\b", masked):
        info["custom_encode"] = True
        return
    if info["kind"] == "enum":
        return
    m = PROPERTY_RE.match(masked)
    if not m or m.group(1):
        return
    rest = m.group(3)
    eq = rest.find("=")
    brace = rest.find("{")
    if brace >= 0 and (eq < 0 or brace < eq):
        return  # computed, or observed
    if not rest.startswith(":") and not rest.startswith("="):
        return
    hidden = eq >= 0 or re.match(r"^\s*(?:@\w+\s+)*(?:private|fileprivate)\b", masked) is not None
    info["props"].append((m.group(2), hidden))


def parse_file(path, types, in_protocol):
    """Fold one file's type declarations into `types`, keyed by qualified name."""
    stack = []  # frames: {"type", "body", "coding_keys", "continues"}
    depth = 0
    state = {}
    for raw in path.read_text().splitlines():
        masked, kept = scan(raw, state)
        top_body = stack[-1]["body"] if stack else 0
        m = DECL_RE.match(masked) if depth == top_body else None
        if m and m.group(2) not in ("func", "var", "let", "subscript", "init"):
            kind, name, clause = m.group(1), m.group(2), m.group(3) or ""
            parent = stack[-1] if stack else None
            parent_type = parent["type"] if parent else None
            inherits = [part.strip() for part in clause.split(",") if part.strip()]
            frame = {"type": None, "body": depth + 1, "coding_keys": None, "continues": False}
            if kind == "extension":
                frame["type"] = name
                new_type(types, name)
                if CODABLE_RE.search(clause):
                    types[name]["codable"] = True
            elif kind == "enum" and name == "CodingKeys" and parent_type:
                frame["coding_keys"] = parent_type
                types[parent_type]["keys"] = types[parent_type]["keys"] or {}
            else:
                qualified = f"{parent_type}.{name}" if parent_type else name
                info = new_type(types, qualified)
                info["kind"] = "enum" if kind == "enum" else "struct"
                info["codable"] = info["codable"] or bool(CODABLE_RE.search(clause))
                info["protocol"] = info["protocol"] or in_protocol
                if kind == "enum" and inherits and inherits[0] in RAW_TYPES:
                    info["raw_type"] = inherits[0]
                frame["type"] = qualified
            stack.append(frame)
            open_at = masked.find("{")
            if open_at >= 0:
                close_at = masked.rfind("}")
                inner_masked = masked[open_at + 1:close_at if close_at > open_at else len(masked)]
                kept_open = kept.find("{")
                kept_close = kept.rfind("}")
                inner_kept = kept[kept_open + 1:kept_close if kept_close > kept_open else len(kept)]
                if inner_kept.strip():
                    member(types, frame, inner_masked, inner_kept)
        elif stack and depth == stack[-1]["body"]:
            member(types, stack[-1], masked, kept)
        depth += masked.count("{") - masked.count("}")
        while stack and stack[-1]["body"] > depth:
            stack.pop()


def raw_values(info):
    """The raw value of every case of a raw-value enum, implicit ones resolved."""
    out, nxt = [], 0
    for case, raw in info["cases"]:
        if info["raw_type"] in ("String", "Character"):
            value = raw.strip('"') if raw else case
        elif raw is not None:
            value = raw
            if re.fullmatch(r"-?\d+", raw):
                nxt = int(raw) + 1
        else:
            value = str(nxt)
            nxt += 1
        out.append((case, value))
    return out


def wire_lines(types, warnings):
    lines = []
    for name, info in types.items():
        if info["kind"] is None:
            continue
        if not info["codable"] and not info["protocol"]:
            continue
        if info["kind"] == "enum" and info["raw_type"]:
            lines.extend(f"{name}.{case} = {value}" for case, value in raw_values(info))
            continue
        if info["keys"] is not None:
            lines.extend(f"{name}.{case} -> {key}" for case, key in info["keys"].items())
            continue
        if info["kind"] == "enum":
            if info["codable"] and not info["custom_decode"]:
                lines.extend(f"{name}.{case} -> {to_snake(case)}" for case, _ in info["cases"])
            continue
        if info["codable"] and info["custom_encode"]:
            continue  # a hand-written encode(to:) with no CodingKeys names no stored key
        for prop, hidden in info["props"]:
            if not info["codable"] and (hidden or "." in name):
                continue  # a plain Protocol struct records only its visible, uninitialised stored state
            key = to_snake(prop)
            if key != prop:
                warnings.append(
                    f"WARNING: {name}.{prop} has no explicit mapping "
                    f"(wire key '{key}' comes from the strategy alone)"
                )
            lines.append(f"{name}.{prop} -> {key}")
    return sorted(set(lines))


def wire_version() -> int:
    """Read GmWireProtocol.version from Envelope.swift; exit 1 when absent."""
    match = VERSION_RE.search(ENVELOPE.read_text()) if ENVELOPE.is_file() else None
    if match is None:
        sys.exit(f"wire_keys: no `static let version` in {ENVELOPE}")
    return int(match.group(1))


def main():
    if not PROTOCOL_DIR.is_dir():
        sys.exit(f"wire_keys: protocol directory not found: {PROTOCOL_DIR}")
    types = {}
    for path in sorted(SHARED_DIR.rglob("*.swift")):
        if path.name == "WireCodec.swift":
            continue
        parse_file(path, types, PROTOCOL_DIR in path.parents)
    warnings = []
    lines = wire_lines(types, warnings)
    if not lines:
        sys.exit(f"wire_keys: no wire keys found under {SHARED_DIR}")
    if "--write-golden" in sys.argv:
        GOLDEN.write_text(f"version {wire_version()}\n" + "\n".join(lines) + "\n")
        print(f"wrote {len(lines)} keys to {GOLDEN}", file=sys.stderr)
        return
    for line in lines:
        print(line)
    if warnings and "--warn-unmapped" in sys.argv:
        print("\n".join(warnings), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
