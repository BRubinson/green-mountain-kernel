#!/usr/bin/env python3
"""swift_doc_check.py — the third stage of the lint gate: every function, init and subscript
carries a doc comment with a one-line summary of at most 100 characters, a Parameters section
naming every parameter, a Returns section when it returns a value, and a Throws section when it
throws.

Usage:
  swift_doc_check.py [--baseline PATH] [--write-baseline] PATH...

Findings print as `path:line:col: error: [DocComment] message`, the same shape as swift-format,
and the exit status is 1 when any finding is not in the baseline. The baseline is keyed by file,
declaration and finding kind, not by line, so edits elsewhere in a file never churn it. It exists
to adopt the rule on a tree that predates it; a new declaration is never added to it.

Skipped on purpose: `override` members (their docs are inherited), local functions nested in a
body, and XCTest lifecycle and `test*` methods under gmk/Tests.
"""
import json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DEFAULT_BASELINE = os.path.join(ROOT, ".swift-doc-baseline.json")
SKIP_DIRS = ("/.build/", "/Generated/", "/DerivedData/", "/.swiftpm/", "/plugins/")

MODIFIER = r"(?:public|internal|private|fileprivate|open|package|static|class|final|override|mutating|nonmutating|convenience|required|dynamic|nonisolated|isolated|consuming|borrowing|indirect|optional|@\w+(?:\([^)]*\))?)"
DECL_RE = re.compile(r"^(\s*)((?:" + MODIFIER + r"\s+)*)(func\s+(`?[\w]+`?|[^\s(]+)|init[?!]?|subscript)\s*(<[^{]*?>)?\s*\(")
ATTR_LINE_RE = re.compile(r"^\s*@\w")
PARAM_NAME_RE = re.compile(r"^\s*(?:`?(\w+)`?\s+)?`?(\w+)`?\s*:")


def strip_code(line):
    """Blank string-literal contents and trailing comments, keeping columns, so brace and paren
    scanning is not fooled."""
    out = []
    i = 0
    n = len(line)
    in_str = False
    while i < n:
        c = line[i]
        if in_str:
            if c == "\\":
                out.append("  ")
                i += 2
                continue
            if c == '"':
                in_str = False
                out.append('"')
            else:
                out.append(" ")
            i += 1
            continue
        if c == '"':
            in_str = True
            out.append('"')
            i += 1
            continue
        if line.startswith("//", i):
            out.append(" " * (n - i))
            break
        out.append(c)
        i += 1
    return "".join(out)


def body_brace(lines, pj, pk):
    """The (line, col) of the `{` that opens the body after the parameter list closing at
    (pj, pk), or None for a bodiless declaration (protocol requirement)."""
    for j in range(pj, min(pj + 8, len(lines))):
        code = strip_code(lines[j])
        start = pk + 1 if j == pj else 0
        if j > pj and code.strip() == "":
            return None
        k = code.find("{", start)
        if k >= 0:
            return (j, k)
        if j > pj and re.match(r"^\s*(func|init|var|let|case|subscript|static|private|public|internal|final|override|@)", code):
            return None
    return None


def match_paren(lines, li, ci):
    """From lines[li][ci] == '(' return (line, col) of the matching ')' or None."""
    depth = 0
    for j in range(li, len(lines)):
        text = strip_code(lines[j])
        start = ci if j == li else 0
        for k in range(start, len(text)):
            ch = text[k]
            if ch in "([{":
                depth += 1
            elif ch in ")]}":
                depth -= 1
                if depth == 0:
                    return j, k
    return None


def split_top_level(text):
    depth = 0
    parts = []
    cur = []
    in_str = False
    i = 0
    while i < len(text):
        c = text[i]
        if in_str:
            cur.append(c)
            if c == "\\":
                cur.append(text[i + 1] if i + 1 < len(text) else "")
                i += 2
                continue
            if c == '"':
                in_str = False
            i += 1
            continue
        if c == '"':
            in_str = True
        elif c in "([{<":
            depth += 1
        elif c in ")]}>":
            depth -= 1
        elif c == "," and depth == 0:
            parts.append("".join(cur))
            cur = []
            i += 1
            continue
        cur.append(c)
        i += 1
    if "".join(cur).strip():
        parts.append("".join(cur))
    return parts


def param_names(param_text):
    names = []
    for part in split_top_level(param_text):
        m = PARAM_NAME_RE.match(part.replace("\n", " "))
        if not m:
            continue
        internal = m.group(2)
        if internal == "_":
            continue
        names.append(internal)
    return names


def doc_block(lines, decl_idx):
    """The `///` block above the declaration, skipping attribute-only lines. Returns list of bodies."""
    i = decl_idx - 1
    while i >= 0 and ATTR_LINE_RE.match(lines[i]) and not lines[i].lstrip().startswith("///"):
        i -= 1
    if i < 0 or not lines[i].lstrip().startswith("///"):
        return None
    block = []
    while i >= 0 and lines[i].lstrip().startswith("///"):
        block.append(lines[i].lstrip()[3:].strip())
        i -= 1
    block.reverse()
    return block


def documented_params(block):
    names = set()
    in_plural = False
    for body in block:
        m = re.match(r"^-\s*[Pp]arameter\s+`?(\w+)`?\s*:", body)
        if m:
            names.add(m.group(1))
            in_plural = False
            continue
        if re.match(r"^-\s*[Pp]arameters\s*:", body):
            in_plural = True
            continue
        if in_plural:
            m = re.match(r"^-\s*`?(\w+)`?\s*:", body)
            if m:
                names.add(m.group(1))
                continue
            if body.startswith("-") or body == "":
                in_plural = body == "" and in_plural
    return names


def has_section(block, name):
    rx = re.compile(r"^-\s*" + name + r"\s*:", re.I)
    return any(rx.match(b) for b in block)


def has_summary(block):
    for body in block:
        if body == "":
            continue
        return not body.startswith("-")
    return False


SUMMARY_MAX_CHARS = 100


def summary_paragraph(block):
    """The lines of the first paragraph: up to the first blank line or section bullet."""
    para = []
    for body in block:
        if body == "" or body.startswith("-"):
            if para:
                break
            continue
        para.append(body)
    return para


def check_file(path, rel, findings):
    try:
        text = open(path, encoding="utf-8").read()
    except OSError:
        return
    lines = text.split("\n")
    is_test = rel.startswith("gmk/Tests/")
    brace_stack = []  # entries: True when the brace opened a callable body
    callable_braces = set()  # (line, col) of every `{` that opens a function, init or subscript body
    for idx, raw in enumerate(lines):
        code = strip_code(raw)
        m = DECL_RE.match(raw)
        if m:
            local = any(brace_stack)
            modifiers = m.group(2)
            kind = m.group(3)
            name = m.group(4) or kind
            skip = local or "override" in modifiers.split()
            if is_test and (name.startswith("test") or name in ("setUp", "tearDown", "setUpWithError", "tearDownWithError")):
                skip = True
            paren = match_paren(lines, idx, raw.index("(", m.end() - 1))
            if paren:
                bb = body_brace(lines, paren[0], paren[1])
                if bb:
                    callable_braces.add(bb)
            if not skip:
                if paren:
                    pj, pk = paren
                    if pj == idx:
                        params_text = raw[raw.index("(", m.end() - 1) + 1:pk]
                    else:
                        params_text = raw[raw.index("(", m.end() - 1) + 1:] + "\n" + "\n".join(lines[idx + 1:pj]) + "\n" + lines[pj][:pk]
                    bb = body_brace(lines, pj, pk)
                    if bb is None:
                        tail = strip_code(lines[pj])[pk + 1:]
                    elif bb[0] == pj:
                        tail = strip_code(lines[pj])[pk + 1:bb[1]]
                    else:
                        tail = strip_code(lines[pj])[pk + 1:] + " " + " ".join(strip_code(l) for l in lines[pj + 1:bb[0]]) + " " + strip_code(lines[bb[0]])[:bb[1]]
                    throws = re.search(r"\b(re)?throws\b", tail) is not None
                    returns = None
                    rm = re.search(r"->\s*(.+?)\s*(?:\bwhere\b|$)", tail)
                    if rm:
                        returns = rm.group(1).strip()
                        if returns in ("Void", "()", "Never"):
                            returns = None
                    if kind.startswith("init") or kind == "subscript":
                        returns = None
                    names = param_names(params_text)
                    block = doc_block(lines, idx)
                    col = len(m.group(1)) + 1
                    decl_key = f"{rel}|{kind if not m.group(4) else 'func ' + name}({','.join(names)})"

                    def add(kind_key, msg):
                        findings.append((rel, idx + 1, col, f"{decl_key}|{kind_key}", msg))

                    label = name if m.group(4) else kind
                    if block is None:
                        add("missing", f"add a doc comment to '{label}': a summary line, then Parameters, Returns and Throws as they apply")
                    else:
                        if not has_summary(block):
                            add("summary", f"begin the doc comment on '{label}' with a one-sentence summary before any section")
                        else:
                            para = summary_paragraph(block)
                            chars = len(" ".join(para))
                            if len(para) > 1 or chars > SUMMARY_MAX_CHARS:
                                add("summary_long", f"keep the summary of '{label}' to one line of at most {SUMMARY_MAX_CHARS} characters (now {chars} characters over {len(para)} line(s)); move the rest below a blank /// line")
                        if names:
                            documented = documented_params(block)
                            missing = [n for n in names if n not in documented]
                            if missing:
                                add("parameters", f"document parameter(s) {', '.join(missing)} of '{label}' in a Parameters section")
                        if returns and not has_section(block, "returns"):
                            add("returns", f"add a Returns section to '{label}' (it returns {returns})")
                        if throws and not has_section(block, "throws"):
                            add("throws", f"add a Throws section to '{label}'")
        for k, ch in enumerate(code):
            if ch == "{":
                brace_stack.append((idx, k) in callable_braces)
            elif ch == "}" and brace_stack:
                brace_stack.pop()


def collect(paths):
    files = []
    for p in paths:
        if os.path.isdir(p):
            for dp, dns, fns in os.walk(p):
                dns[:] = [d for d in dns if d not in (".build", "Generated", "DerivedData", ".swiftpm")]
                for fn in fns:
                    if fn.endswith(".swift"):
                        files.append(os.path.join(dp, fn))
        elif p.endswith(".swift"):
            files.append(p)
    out = []
    for f in files:
        a = os.path.abspath(f)
        if any(s in a for s in SKIP_DIRS) or a.endswith("Package.swift"):
            continue
        out.append(a)
    return sorted(set(out))


def main(argv):
    baseline_path = DEFAULT_BASELINE
    write = False
    paths = []
    it = iter(argv)
    for a in it:
        if a == "--baseline":
            baseline_path = next(it)
        elif a == "--write-baseline":
            write = True
        else:
            paths.append(a)
    if not paths:
        paths = [os.path.join(ROOT, "gmk", d) for d in ("Sources", "Tests", "Plugins") if os.path.isdir(os.path.join(ROOT, "gmk", d))]
    findings = []
    for f in collect(paths):
        check_file(f, os.path.relpath(f, ROOT), findings)
    if write:
        keys = sorted({k for _, _, _, k, _ in findings})
        with open(baseline_path, "w") as fh:
            json.dump({"version": 1, "findings": keys}, fh, indent=1)
        print(f"[GMB] doc-check: baseline written with {len(keys)} entries to {os.path.relpath(baseline_path, ROOT)}")
        return 0
    baseline = set()
    if os.path.exists(baseline_path):
        try:
            baseline = set(json.load(open(baseline_path)).get("findings", []))
        except (OSError, ValueError):
            baseline = set()
    fresh = [f for f in findings if f[3] not in baseline]
    suppressed = len(findings) - len(fresh)
    for rel, line, col, _, msg in fresh:
        print(f"{os.path.join(ROOT, rel)}:{line}:{col}: error: [DocComment] {msg}")
    if fresh:
        print(f"[GMB] doc-check: {len(fresh)} finding(s) ({suppressed} baselined). See .claude/skills/swift-doc-comments/SKILL.md", file=sys.stderr)
        return 1
    print(f"[GMB] doc-check: clean ({suppressed} baselined)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
