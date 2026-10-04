#!/usr/bin/env python3
"""baseline_remap.py — carry .swiftlint-baseline.json across a move, a split or a rename.

Usage:
  baseline_remap.py [--baseline PATH] --map OLD_PREFIX NEW_PREFIX [OLD_PREFIX NEW_PREFIX ...]
  baseline_remap.py [--baseline PATH] --split OLD_FILE NEW_FILE [NEW_FILE ...]
  baseline_remap.py [--baseline PATH] --rename-symbol OLD=NEW [OLD=NEW ...]

--map rewrites location.file wherever it equals OLD_PREFIX or lies under it.
--split re-points each OLD_FILE entry to the one NEW_FILE that holds its exact line text, and
fails, writing nothing, when a text is found nowhere or in more than one new file.
--rename-symbol rewrites each entry's line text on identifier boundaries.

It never regenerates the baseline: entries keep their order and the file keeps SwiftLint's own
single-line spelling, so the diff shows only what moved. Run it after the move, from anywhere.
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def load(path):
    """Read a baseline.

    Parameters:
      - path: The baseline file.
    Returns: The decoded entry list.
    """
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def dump(path, entries):
    """Write a baseline in SwiftLint's spelling: one line, compact separators, escaped slashes.

    Parameters:
      - path: The baseline file.
      - entries: The entry list.
    """
    text = json.dumps(entries, separators=(",", ":"), ensure_ascii=False).replace("/", "\\/")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)


def under(path, prefix):
    """Whether a repo-relative path equals a prefix or lies beneath it.

    Parameters:
      - path: The repo-relative path.
      - prefix: The file or directory prefix.
    Returns: True when the prefix names the path or an ancestor.
    """
    prefix = prefix.rstrip("/")
    return path == prefix or path.startswith(prefix + "/")


def remap(entries, pairs):
    """Rewrite location.file for every (old, new) prefix pair.

    Parameters:
      - entries: The baseline entries, rewritten in place.
      - pairs: (old prefix, new prefix) tuples, applied first match wins.
    Returns: The number of entries rewritten per pair.
    """
    counts = [0] * len(pairs)
    for entry in entries:
        location = entry["violation"]["location"]
        for i, (old, new) in enumerate(pairs):
            if under(location["file"], old):
                location["file"] = new.rstrip("/") + location["file"][len(old.rstrip("/")):]
                counts[i] += 1
                break
    return counts


def split(entries, old, news):
    """Re-point OLD's entries to the new file holding each entry's line text.

    Parameters:
      - entries: The baseline entries, rewritten in place.
      - old: The repo-relative file that was split.
      - news: The repo-relative files it was split into.
    Returns: The list of problems; entries are rewritten only when it is empty.
    """
    lines = {}
    for new in news:
        with open(os.path.join(ROOT, new), encoding="utf-8") as fh:
            lines[new] = fh.read().splitlines()
    moves, problems = [], []
    for entry in entries:
        location = entry["violation"]["location"]
        if location["file"] != old:
            continue
        hits = {new: [n for n, line in enumerate(body, 1) if line == entry["text"]] for new, body in lines.items()}
        homes = [new for new, found in hits.items() if found]
        if len(homes) != 1:
            where = "no new file" if not homes else f"{len(homes)} files ({', '.join(homes)})"
            problems.append(f"{old}:{location['line']}: line text found in {where}: {entry['text'].strip()[:80]}")
            continue
        moves.append((entry, homes[0], hits[homes[0]]))
    # Entries on one old line share one new line; distinct old lines need distinct occurrences.
    old_lines = {}
    for entry, new, found in moves:
        old_lines.setdefault((new, entry["text"]), set()).add(entry["violation"]["location"]["line"])
    for (new, text), wanted in old_lines.items():
        found = sum(1 for line in lines[new] if line == text)
        if len(wanted) > found:
            problems.append(f"{new}: {len(wanted)} old lines share a text found {found} time(s): {text.strip()[:80]}")
    if problems:
        return problems
    for entry, new, found in moves:
        location = entry["violation"]["location"]
        rank = sorted(old_lines[(new, entry["text"])]).index(location["line"])
        location["file"] = new
        location["line"] = found[rank]
    return []


def rename_symbol(entries, renames):
    """Rewrite each entry's line text for every OLD=NEW rename, on identifier boundaries.

    Parameters:
      - entries: The baseline entries, rewritten in place.
      - renames: (old, new) symbol tuples.
    Returns: The number of entries rewritten per rename.
    """
    counts = []
    for old, new in renames:
        pattern = re.compile(rf"(?<![A-Za-z0-9_]){re.escape(old)}(?![A-Za-z0-9_])")
        count = 0
        for entry in entries:
            text = pattern.sub(new, entry["text"])
            if text != entry["text"]:
                entry["text"] = text
                count += 1
        counts.append(count)
    return counts


def main(argv):
    """Parse the mode, rewrite the baseline and report.

    Parameters:
      - argv: The command-line arguments.
    Returns: The exit status.
    """
    path = os.path.join(ROOT, ".swiftlint-baseline.json")
    if argv[:1] == ["--baseline"] and len(argv) > 1:
        path, argv = argv[1], argv[2:]
    if len(argv) < 2 or argv[0] not in ("--map", "--split", "--rename-symbol"):
        print(__doc__.split("\n\n")[1], file=sys.stderr)
        return 2
    mode, args = argv[0], argv[1:]
    entries = load(path)

    if mode == "--map":
        if len(args) % 2:
            print("[GMB] baseline_remap: --map takes OLD_PREFIX NEW_PREFIX pairs", file=sys.stderr)
            return 2
        pairs = list(zip(args[0::2], args[1::2]))
        for (old, new), count in zip(pairs, remap(entries, pairs)):
            print(f"[GMB] baseline_remap: {count} entr{'y' if count == 1 else 'ies'} {old} -> {new}")
    elif mode == "--split":
        problems = split(entries, args[0], args[1:])
        if problems:
            for problem in problems:
                print(f"[GMB] baseline_remap: {problem}", file=sys.stderr)
            print("[GMB] baseline_remap: split is ambiguous; nothing written", file=sys.stderr)
            return 1
        print(f"[GMB] baseline_remap: split {args[0]} into {', '.join(args[1:])}")
    else:
        renames = [tuple(a.split("=", 1)) for a in args]
        if any(len(r) != 2 or not r[0] or not r[1] for r in renames):
            print("[GMB] baseline_remap: --rename-symbol takes OLD=NEW", file=sys.stderr)
            return 2
        for (old, new), count in zip(renames, rename_symbol(entries, renames)):
            print(f"[GMB] baseline_remap: {count} entr{'y' if count == 1 else 'ies'} {old} -> {new}")

    dump(path, entries)
    files = {e["violation"]["location"]["file"] for e in entries}
    for rel in sorted(f for f in files if not os.path.exists(os.path.join(ROOT, f))):
        print(f"[GMB] baseline_remap: warning: {rel} does not exist", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
