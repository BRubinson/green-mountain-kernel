#!/usr/bin/env python3
"""gm_tree_check.py — stage 4 of the lint gate: the repo invariants no compiler or linter sees.

Usage:
  gm_tree_check.py [--repo DIR]           # every sub-check
  gm_tree_check.py [--repo DIR] NAME...   # only the named sub-checks
  gm_tree_check.py --list                 # name each sub-check and what it holds

Each finding prints as `[GMB] tree-check: <sub-check>: <message>`. The exit status is 1 when any
sub-check fails, 2 on a usage error. Paths come from `git ls-files` and bytes from the tree this
script sits in. --repo names the repository whose index and HEAD are compared when the script
runs from an index checkout (the pre-commit hook does), so the check judges the staged tree.

The wire gate is wire-shaped: a JSON key set or enum raw-value set recorded at HEAD must survive,
under its own type name or identically under another, unless the golden's version line moved.
"""
import fnmatch
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
# Where git runs; --repo moves it off ROOT when ROOT is an index checkout.
GIT_ROOT = ROOT
SCRIPTS = os.path.join(ROOT, "gmk", "scripts")
RELEASES = "gmk/scripts/gm_releases.sh"
RELEASES_PLUGIN = "plugins/gmcc/scripts/gm_releases.sh"
RELEASES_SWIFT = "gmk/Sources/AgenticsClaudeHarnessPluginBridge/GmBridgeScript+Bodies.swift"
PBXPROJ = "gmk/gmk.xcodeproj/project.pbxproj"
BASELINE = ".swiftlint-baseline.json"
GOLDEN = "gmk/scripts/wire_keys.golden"
WRITE_GOLDEN = "python3 gmk/scripts/wire_keys.py --write-golden"
# The roots swift_lint_format.sh lints by default.
LINT_ROOTS = ("gmk/Sources", "gmk/Tests")

CITATION_RE = re.compile(r"\b[A-Z][A-Za-z]+Tests\b")
TEST_CLASS_RE = re.compile(r"\bclass\s+([A-Z]\w*)")
# Names that are not test classes: the test target.
CITATION_ALLOW = {"GmKernelTests"}

UNBASELINABLE = {
    "historical_comment",
    "long_comment_run",
    "long_doc_comment_run",
    "block_comment",
    "comment_line_length",
    "no_record_bulk_write",
}

ENTITIES = "gmk/Sources/Core/Persistence/Entities"
# The same declaration SchemaEnrollmentTests counts against the roster.
TABLE_NAME_RE = re.compile(r"static let databaseTableName\b")

CORE = "gmk/Sources/Core"
TESTS = "gmk/Tests/GmKernelTests"
TESTS_MIRROR_EXEMPT = {"Harness"}

RESOURCE_ALLOW = (
    "gmk/Sources/UX/Apps/Vibes/Assets.xcassets/*",
    "gmk/Sources/UX/Apps/MachineHost/Legal/ThirdPartyNotices.txt",
    "gmk/Sources/UX/Apps/Vibes/Info.plist",
)


def git(*args):
    """Run git in the repo root and return its stdout, or None when git fails.

    Parameters:
      - args: The git arguments.
    Returns: The command's stdout as text, or None on a non-zero exit.
    """
    proc = subprocess.run(["git", "-C", GIT_ROOT, *args], capture_output=True, text=True)
    return proc.stdout if proc.returncode == 0 else None


def tracked(*pathspecs):
    """List tracked repo-relative paths under the given pathspecs.

    Parameters:
      - pathspecs: Git pathspecs; none means the whole tree.
    Returns: The tracked paths, in git's order.
    """
    out = git("ls-files", "-z", "--", *pathspecs) or ""
    return [p for p in out.split("\0") if p]


def read(rel):
    """Read a repo-relative text file, or None when it is absent or not UTF-8.

    Parameters:
      - rel: The repo-relative path.
    Returns: The file's text, or None.
    """
    try:
        with open(os.path.join(ROOT, rel), encoding="utf-8") as fh:
            return fh.read()
    except (OSError, UnicodeDecodeError):
        return None


def lint_skip_globs():
    """The canonical skip list, from gm_lint_skip in gm_build.sh.

    Returns: The case globs, one per entry, matched against repo-relative paths.
    """
    proc = subprocess.run(
        ["bash", "-c", '. "$1" && gm_lint_skip', "gm_lint_skip", os.path.join(SCRIPTS, "gm_build.sh")],
        capture_output=True,
        text=True,
    )
    return [line for line in proc.stdout.splitlines() if line.strip()]


def swift_raw_body(text, name):
    """The value of a `static let NAME` raw multi-line string literal, rendered as the bridge writes it.

    Parameters:
      - text: The Swift source.
      - name: The constant's name.
    Returns: (rendered text or None, problem or None).
    """
    lines = text.splitlines()
    opener = re.compile(rf'^\s*static let {re.escape(name)} = #"""\s*$')
    start = next((i for i, line in enumerate(lines) if opener.match(line)), None)
    if start is None:
        return None, f"no `static let {name} = #\"\"\"` found"
    end = next((i for i in range(start + 1, len(lines)) if re.match(r'^\s*"""#\s*$', lines[i])), None)
    if end is None:
        return None, f"{name} has no closing delimiter"
    indent = lines[end][: len(lines[end]) - len(lines[end].lstrip())]
    body = []
    for no in range(start + 1, end):
        line = lines[no]
        if "\\#(" in line:
            return None, f"line {no + 1}: {name} interpolates, so it cannot be compared statically"
        if line.strip() and not line.startswith(indent):
            return None, f"line {no + 1}: indented less than {name}'s closing delimiter"
        body.append(line[len(indent):] if line.strip() else "")
    rendered = "\n".join(body)
    return (rendered if rendered.endswith("\n") else rendered + "\n"), None


def check_releases_twin():
    """gm_releases.sh, GmBridgeScript.releaseStoreBody and the rendered plugin copy agree byte for byte.

    Returns: The findings.
    """
    script = read(RELEASES)
    if script is None:
        return [f"cannot read {RELEASES}"]
    findings = []
    plugin = read(RELEASES_PLUGIN)
    if plugin != script:
        findings.append(f"{RELEASES} and {RELEASES_PLUGIN} differ: regenerate the plugin over {RELEASES_SWIFT}")
    swift, problem = swift_raw_body(read(RELEASES_SWIFT) or "", "releaseStoreBody")
    if problem:
        findings.append(f"{RELEASES_SWIFT}: {problem}")
    elif swift != script:
        a, b = swift.splitlines(), script.splitlines()
        no = next((i for i, (x, y) in enumerate(zip(a, b)) if x != y), min(len(a), len(b)))
        findings.append(
            f"GmBridgeScript.releaseStoreBody and {RELEASES} differ first at body line {no + 1}: edit both, regenerate"
        )
    return findings


def check_test_citations():
    """Every *Tests name cited in sources, scripts and agent docs is a class under gmk/Tests.

    Returns: The findings.
    """
    classes = set()
    for rel in tracked("gmk/Tests"):
        if rel.endswith(".swift"):
            classes.update(TEST_CLASS_RE.findall(read(rel) or ""))
    findings = []
    for rel in tracked("gmk/Sources", "gmk/scripts", "CLAUDE.md", ".claude"):
        text = read(rel)
        if text is None:
            continue
        for no, line in enumerate(text.splitlines(), 1):
            for name in CITATION_RE.findall(line):
                if name not in classes and name not in CITATION_ALLOW:
                    findings.append(f"{rel}:{no}: cites {name}, which no class under gmk/Tests declares")
    return findings


def head_changes():
    """The paths this change set renames, adds or rewrites relative to HEAD, with rename detection.

    Returns: (renames as {old: new}, paths new in the change, paths it changed or removed).
    """
    cached = ["--cached"] if GIT_ROOT != ROOT else []
    out = git("diff", *cached, "-M", "--name-status", "-z", "HEAD") or ""
    fields = out.split("\0")
    renames, new, old = {}, set(), set()
    i = 0
    while i < len(fields) and fields[i]:
        status = fields[i]
        if status[0] in "RC":
            src, dst = fields[i + 1], fields[i + 2]
            if status[0] == "R":
                renames[src] = dst
            old.add(src)
            new.add(dst)
            i += 3
            continue
        if status[0] == "A":
            new.add(fields[i + 1])
        else:
            old.add(fields[i + 1])
        i += 2
    return renames, new, old


def rename_symbols(text, renames):
    """Rewrite a line with every type rename the change's file renames imply (Old.swift -> New.swift).

    Parameters:
      - text: The baselined line text.
      - renames: The change's file renames, {old path: new path}.
    Returns: The rewritten text.
    """
    for src, dst in renames.items():
        a, b = os.path.splitext(os.path.basename(src))[0], os.path.splitext(os.path.basename(dst))[0]
        if a != b and src.endswith(".swift"):
            text = re.sub(rf"\b{re.escape(a)}\b", b, text)
    return text


def baseline_strays(entries, head_entries):
    """The entries no HEAD entry accounts for, matching each HEAD entry at most once.

    A HEAD entry accounts for an entry with the same rule and file and text; or one whose file is
    new in the change while the HEAD entry's file was renamed, rewritten or removed; or either of
    those with the text rewritten by a type rename the change's file renames record.

    Parameters:
      - entries: The baseline under check.
      - head_entries: HEAD's baseline.
    Returns: The unaccounted entries.
    """
    renames, new, old = head_changes()
    by_text = {}
    for index, entry in enumerate(head_entries):
        v = entry["violation"]
        for text in {entry["text"], rename_symbols(entry["text"], renames)}:
            by_text.setdefault((v["ruleIdentifier"], text), []).append(index)
    used, strays = set(), []
    for entry in entries:
        v = entry["violation"]
        file = v["location"]["file"]
        candidates = [
            i
            for i in by_text.get((v["ruleIdentifier"], entry["text"]), [])
            if i not in used
            and (
                head_entries[i]["violation"]["location"]["file"] == file
                or renames.get(head_entries[i]["violation"]["location"]["file"]) == file
                or (file in new and head_entries[i]["violation"]["location"]["file"] in old)
            )
        ]
        exact = [i for i in candidates if head_entries[i]["violation"]["location"]["file"] == file]
        if exact or candidates:
            used.add((exact or candidates)[0])
        else:
            strays.append(entry)
    return strays


def check_baseline():
    """The SwiftLint baseline never grows or gains an entry, never holds a comment rule, and names only real files.

    Returns: The findings.
    """
    text = read(BASELINE)
    if text is None:
        return [f"{BASELINE} is missing"]
    entries = json.loads(text)
    findings = []
    head = git("show", f"HEAD:{BASELINE}")
    if head is not None:
        head_entries = json.loads(head)
        before = len(head_entries)
        if len(entries) > before:
            findings.append(f"{BASELINE} grew from {before} to {len(entries)} entries; the baseline only shrinks")
        for entry in baseline_strays(entries, head_entries):
            v = entry["violation"]
            findings.append(
                f"{v['location']['file']}:{v['location']['line']}: {v['ruleIdentifier']} is new to the baseline "
                "(HEAD holds no entry it was moved or renamed from); fix the violation instead"
            )
    for entry in entries:
        violation = entry["violation"]
        rule = violation["ruleIdentifier"]
        where = f"{violation['location']['file']}:{violation['location']['line']}"
        if rule in UNBASELINABLE:
            findings.append(f"{where}: {rule} is never baselined; fix the comment or the write")
        if not os.path.exists(os.path.join(ROOT, violation["location"]["file"])):
            findings.append(f"{where}: baselined file does not exist; remap it with gmk/scripts/baseline_remap.py")
    return findings


def pbx_objects(text):
    """Split a project.pbxproj into its objects.

    Parameters:
      - text: The pbxproj contents.
    Returns: A dict of object id to (isa, body text).
    """
    objects = {}
    for match in re.finditer(r"^\t\t([0-9A-F]{24}) (?:/\*[^\n]*?\*/ )?= \{\n(.*?)^\t\t\};", text, re.M | re.S):
        isa = re.search(r"^\t\t\tisa = (\w+);", match.group(2), re.M)
        objects[match.group(1)] = (isa.group(1) if isa else "", match.group(2))
    return objects


def pbx_settings(body):
    """The scalar build settings of one XCBuildConfiguration body.

    Parameters:
      - body: The configuration object's body text.
    Returns: A dict of setting name to unquoted value.
    """
    block = re.search(r"buildSettings = \{\n(.*?)^\t\t\t\};", body, re.M | re.S)
    settings = {}
    for line in (block.group(1) if block else "").splitlines():
        m = re.match(r'^\t\t\t\t"?([^"=]+?)"? = "?(.*?)"?;$', line)
        if m:
            settings[m.group(1)] = m.group(2)
    return settings


def pbx_config_lists(objects):
    """Each target's and the project's configurations, by configuration name.

    Parameters:
      - objects: The pbxproj objects from pbx_objects.
    Returns: A dict of target name (the project is "<project>") to {config name: settings}.
    """
    def configs(list_id):
        body = objects.get(list_id, ("", ""))[1]
        out = {}
        for config_id in re.findall(r"([0-9A-F]{24})", body.split("buildConfigurations = (", 1)[-1].split(");", 1)[0]):
            config_body = objects.get(config_id, ("", ""))[1]
            name = re.search(r"^\t\t\tname = (\w+);", config_body, re.M)
            out[name.group(1) if name else config_id] = pbx_settings(config_body)
        return out

    lists = {}
    for isa, body in objects.values():
        list_id = re.search(r"buildConfigurationList = ([0-9A-F]{24})", body)
        if not list_id:
            continue
        if isa == "PBXProject":
            lists["<project>"] = configs(list_id.group(1))
        elif isa in ("PBXNativeTarget", "PBXAggregateTarget"):
            name = re.search(r"^\t\t\tname = \"?([^\";]+)\"?;", body, re.M)
            lists[name.group(1) if name else list_id.group(1)] = configs(list_id.group(1))
    return lists


def check_build_settings():
    """The build settings CLAUDE.md pins still hold, and the deployment floor has one spelling.

    Returns: The findings.
    """
    text = read(PBXPROJ)
    if text is None:
        return [f"{PBXPROJ} is missing"]
    findings = []
    floors = sorted(set(re.findall(r"MACOSX_DEPLOYMENT_TARGET = \"?([^\";]+)\"?;", text)))
    if len(floors) != 1:
        findings.append(f"MACOSX_DEPLOYMENT_TARGET has {len(floors)} distinct values {floors}; the floor is one value")
    binaries = read("gmk/scripts/build_plugin_binaries.sh") or ""
    if re.search(r"-apple-macosx[0-9]", binaries):
        findings.append("build_plugin_binaries.sh spells the deployment floor; read it from project.pbxproj")
    if re.search(r"ENABLE_APP_SANDBOX = \"?YES", text):
        findings.append("ENABLE_APP_SANDBOX = YES appears; the app is never sandboxed")
    if "INFOPLIST_KEY_GMFSRoot" in text:
        findings.append("INFOPLIST_KEY_GMFSRoot appears; Xcode drops it, GMFSRoot lives in Vibes/Info.plist")

    lists = pbx_config_lists(pbx_objects(text))
    project = lists.get("<project>", {})

    def effective(target, config, key):
        own = lists.get(target, {}).get(config, {})
        return own.get(key, project.get(config, {}).get(key))

    if "gm_kernel" not in lists:
        findings.append("no gm_kernel target in project.pbxproj")
    else:
        if effective("gm_kernel", "Debug", "ENABLE_DEBUG_DYLIB") != "NO":
            findings.append("gm_kernel Debug: ENABLE_DEBUG_DYLIB must be NO (the debug stub ignores argv)")
        for config in lists["gm_kernel"]:
            if effective("gm_kernel", config, "ENABLE_USER_SCRIPT_SANDBOXING") != "YES":
                findings.append(f"gm_kernel {config}: ENABLE_USER_SCRIPT_SANDBOXING must be YES")
    for aggregate in ("PluginBridge", "TestEnvSeed"):
        if aggregate not in lists:
            findings.append(f"no {aggregate} aggregate target in project.pbxproj")
            continue
        for config in lists[aggregate]:
            if effective(aggregate, config, "ENABLE_USER_SCRIPT_SANDBOXING") != "NO":
                findings.append(f"{aggregate} {config}: ENABLE_USER_SCRIPT_SANDBOXING must be NO")

    for rel in tracked("*.xcscheme"):
        if "<EnvironmentVariables" in (read(rel) or ""):
            findings.append(f"{rel}: carries an <EnvironmentVariables> block; a root is baked, never injected")
    for rel in ("gmk/scripts/rebuild_local.sh", "gmk/scripts/build-dmg.sh"):
        script = read(rel) or ""
        if not re.search(r'^\s*VERSION="[^\n]*\$GMK/VERSION', script, re.M):
            findings.append(f"{rel}: VERSION is no longer read from gmk/VERSION")
        if 'MARKETING_VERSION="$VERSION"' not in script:
            findings.append(f'{rel}: no longer passes MARKETING_VERSION="$VERSION" to xcodebuild')
    return findings


def yaml_list(text, key):
    """The `- item` entries of one top-level list in a simple YAML file.

    Parameters:
      - text: The YAML text.
      - key: The top-level key.
    Returns: The list's entries, unquoted.
    """
    block = re.search(rf"^{re.escape(key)}:\n((?:[ \t]+-[^\n]*\n|[ \t]*#[^\n]*\n)*)", text, re.M)
    if not block:
        return []
    items = re.findall(r"^[ \t]+-[ \t]*(.+?)[ \t]*$", block.group(1), re.M)
    return [item.strip("'\"") for item in items]


def swiftlint_covers(entry, path):
    """Whether a SwiftLint excluded entry covers a repo-relative path.

    Parameters:
      - entry: The excluded entry; `*` matches within one path component.
      - path: The repo-relative path.
    Returns: True when the entry names the path or one of its ancestors.
    """
    pattern = "".join("[^/]*" if c == "*" else re.escape(c) for c in entry.rstrip("/"))
    return re.match(rf"{pattern}(?:/|$)", path) is not None


def gitignore_line(glob):
    """Render one skip glob as its .swift-format-ignore (gitignore) line.

    Parameters:
      - glob: The skip glob.
    Returns: The gitignore spelling of the same set of paths.
    """
    if glob.startswith("*/") and glob.endswith("/*"):
        return glob[2:-1]
    if glob.startswith("*/"):
        return glob[2:]
    if glob.endswith("/*"):
        return "/" + glob[:-1]
    return "/" + glob


def skip_hit(globs, rel):
    """The shallowest prefix of a path that the skip list names.

    Parameters:
      - globs: The skip globs.
      - rel: A repo-relative file path.
    Returns: The skipped directory or file, or None.
    """
    parts = rel.split("/")
    for k in range(1, len(parts) + 1):
        candidate = "/".join(parts[:k])
        probe = candidate if k == len(parts) else candidate + "/"
        if any(fnmatch.fnmatchcase(probe, g) for g in globs):
            return candidate
    return None


def check_lint_skip():
    """.swiftlint.yml excluded and .swift-format-ignore skip what gm_lint_skip skips.

    Returns: The findings.
    """
    globs = lint_skip_globs()
    if not globs:
        return ["gm_lint_skip in gmk/scripts/gm_build.sh printed nothing"]
    findings = []

    ignore = read(".swift-format-ignore") or ""
    have = {line.strip() for line in ignore.splitlines() if line.strip() and not line.startswith("#")}
    want = {gitignore_line(g) for g in globs}
    for line in sorted(want - have):
        findings.append(f".swift-format-ignore lacks {line} (gm_lint_skip names it)")
    for line in sorted(have - want):
        findings.append(f".swift-format-ignore has {line}, which gm_lint_skip does not name")

    config = read(".swiftlint.yml") or ""
    included = yaml_list(config, "included")
    excluded = yaml_list(config, "excluded")
    hits = {skip_hit(globs, rel) for rel in tracked(*LINT_ROOTS)} - {None}
    for hit in sorted(hits):
        if not any(swiftlint_covers(e, hit) for e in excluded):
            findings.append(f".swiftlint.yml excluded does not cover {hit} (gm_lint_skip names it)")
    for entry in excluded:
        if "**" in entry:
            findings.append(f".swiftlint.yml excluded {entry}: a ** globstar crashes SwiftLint 0.65.1")
        if not any(entry == inc or entry.startswith(inc.rstrip("/") + "/") for inc in included):
            findings.append(f".swiftlint.yml excluded {entry} lies outside included {included}; it is inert")
        in_roots = any(entry == r or entry.startswith(r + "/") for r in LINT_ROOTS)
        if in_roots and not any(swiftlint_covers(entry, hit) or entry.startswith(hit + "/") for hit in hits):
            findings.append(f".swiftlint.yml excluded {entry} skips lint-root sources gm_lint_skip does not name")
    return findings


def wire_protocol_version():
    """GmWireProtocol.version as compiled.

    Returns: The version, or None when it cannot be found.
    """
    for rel in tracked("gmk/Sources"):
        if not rel.endswith(".swift"):
            continue
        text = read(rel) or ""
        m = re.search(r"enum GmWireProtocol\b.*?static let version = (\d+)", text, re.S)
        if m:
            return int(m.group(1))
    return None


def golden_parts(text):
    """Split a wire_keys golden into its version and its keys.

    Parameters:
      - text: The golden's contents.
    Returns: (version or None, set of key lines).
    """
    lines = text.splitlines()
    m = re.fullmatch(r"version (\d+)", lines[0].strip()) if lines else None
    return (int(m.group(1)) if m else None, {line for line in lines[1:] if line.strip()})


def wire_shapes(lines):
    """Group golden lines into wire shapes: each type's JSON key set and its enum raw-value set.

    Parameters:
      - lines: Golden lines, `Type.member -> key` or `Type.case = raw`.
    Returns: A dict of (type, "->" or "=") to the set of keys or raw values.
    """
    shapes = {}
    for line in lines:
        m = re.fullmatch(r"(.+)\.(\w+) (->|=) (.*)", line)
        if m:
            shapes.setdefault((m.group(1), m.group(3)), set()).add(m.group(4))
    return shapes


def wire_losses(before, after):
    """The wire shapes of `before` that `after` no longer carries.

    A shape survives when its type still carries every key or raw value, or when some type carries
    exactly the same set: a pure type rename moves nothing on the wire.

    Parameters:
      - before: The earlier golden lines.
      - after: The later golden lines.
    Returns: One message per lost shape.
    """
    old, new = wire_shapes(before), wire_shapes(after)
    losses = []
    for (name, op), values in sorted(old.items()):
        if (name, op) in new:
            missing = values - new[(name, op)]
            if missing:
                losses.append(f"{name} loses {', '.join(sorted(missing)[:5])}")
        elif not any(o == op and v == values for (_, o), v in new.items()):
            losses.append(f"{name} ({len(values)} {'keys' if op == '->' else 'raw values'}) survives under no type name")
    return losses


def check_wire_keys():
    """The extracted wire keys equal the golden; a wire-shaped removal rides a GmWireProtocol.version bump.

    Returns: The findings.
    """
    proc = subprocess.run(
        [sys.executable, os.path.join(SCRIPTS, "wire_keys.py")], capture_output=True, text=True, cwd=ROOT
    )
    if proc.returncode != 0:
        return [f"wire_keys.py exited {proc.returncode}: {proc.stderr.strip()[:300]}"]
    keys = {line for line in proc.stdout.splitlines() if line.strip()}
    if not keys:
        return ["wire_keys.py found no keys; its SHARED_DIR names no shared sources"]
    text = read(GOLDEN)
    if text is None:
        return [f"{GOLDEN} is missing; re-record: {WRITE_GOLDEN}"]
    version, golden = golden_parts(text)
    if version is None:
        return [f"{GOLDEN}: the first line must be `version N`"]
    protocol = wire_protocol_version()
    if protocol is None:
        return ["GmWireProtocol.version not found under gmk/Sources"]

    findings = []
    losses = wire_losses(golden, keys)
    if losses and protocol == version:
        findings.append(
            f"{len(losses)} wire shape(s) removed or renamed without a GmWireProtocol.version bump "
            f"(still {protocol}): {'; '.join(losses[:5])}"
        )
    removed, added = sorted(golden - keys), sorted(keys - golden)
    if removed or added:
        sample = ", ".join((["-" + line for line in removed] + ["+" + line for line in added])[:5])
        findings.append(f"{GOLDEN} is stale (-{len(removed)} +{len(added)}: {sample}); re-record: {WRITE_GOLDEN}")
    if version != protocol:
        findings.append(f"{GOLDEN} records version {version}, GmWireProtocol.version is {protocol}; re-record: {WRITE_GOLDEN}")

    head = git("show", f"HEAD:{GOLDEN}")
    if head is not None:
        head_version, head_keys = golden_parts(head)
        dropped = wire_losses(head_keys, golden)
        if dropped and head_version == version:
            findings.append(
                f"{GOLDEN} drops {len(dropped)} wire shape(s) HEAD recorded at the same version {version}: "
                f"{'; '.join(dropped[:5])}; a removal needs a GmWireProtocol.version bump"
            )
    return findings


def check_resources():
    """Tracked non-Swift files under gmk/Sources are only the resources the app ships.

    Returns: The findings.
    """
    findings = []
    for rel in tracked("gmk/Sources"):
        if rel.endswith(".swift"):
            continue
        if not any(fnmatch.fnmatchcase(rel, allowed) for allowed in RESOURCE_ALLOW):
            findings.append(f"{rel}: a synchronized root copies every non-Swift file into the app; move it out")
    return findings


def pbx_list(body, key):
    """The entries of one `key = ( ... );` list in a pbxproj object body.

    Parameters:
      - body: The object's body text.
      - key: The list's key.
    Returns: The entries, comments stripped and unquoted.
    """
    block = re.search(rf"^\t\t\t{re.escape(key)} = \(\n(.*?)^\t\t\t\);", body, re.M | re.S)
    if not block:
        return []
    entries = []
    for line in block.group(1).splitlines():
        entry = re.sub(r"\s*/\*.*?\*/", "", line.strip()).rstrip(",").strip('"')
        if entry:
            entries.append(entry)
    return entries


def check_sources_roots():
    """gmk/Sources is a plain group of the roots gm_kernel builds; tests build Core; only Info.plist is excepted.

    Returns: The findings.
    """
    text = read(PBXPROJ)
    if text is None:
        return [f"{PBXPROJ} is missing"]
    objects = pbx_objects(text)

    def field(body, key):
        m = re.search(rf"^\t\t\t{key} = \"?([^\";]+?)\"?(?: /\*.*?\*/)?;", body, re.M)
        return m.group(1) if m else None

    groups = [b for isa, b in objects.values() if isa == "PBXGroup" and field(b, "path") == "Sources"]
    if len(groups) != 1:
        return [f"expected one PBXGroup with path Sources, found {len(groups)}; Sources is a plain group of roots"]
    roots = {}
    findings = []
    for child in pbx_list(groups[0], "children"):
        isa, body = objects.get(child, ("", ""))
        if isa != "PBXFileSystemSynchronizedRootGroup":
            findings.append(f"Sources group child {child} is a {isa or 'missing object'}, not a synchronized root")
            continue
        roots[field(body, "path")] = body

    dirs = {rel.split("/")[2] for rel in tracked("gmk/Sources") if rel.count("/") >= 3}
    for name in sorted(dirs - set(roots)):
        findings.append(f"gmk/Sources/{name} is not a synchronized root of the Sources group; it builds into nothing")
    for name in sorted(set(roots) - dirs):
        findings.append(f"Sources group root {name} names no tracked folder under gmk/Sources")

    targets = {
        tid: field(body, "name")
        for tid, (isa, body) in objects.items()
        if isa in ("PBXNativeTarget", "PBXAggregateTarget")
    }
    kernel_exceptions = set()
    for root_isa, root_body in objects.values():
        if root_isa != "PBXFileSystemSynchronizedRootGroup":
            continue
        root_path = field(root_body, "path")
        for set_id in pbx_list(root_body, "exceptions"):
            set_body = objects.get(set_id, ("", ""))[1]
            target = targets.get(field(set_body, "target") or "")
            entries = [f"{root_path}/{e}" for e in pbx_list(set_body, "membershipExceptions")]
            if target == "GmKernelTests":
                findings.append(f"exception set {set_id} on {root_path} targets GmKernelTests; Core is shared by root")
            elif target == "gm_kernel":
                kernel_exceptions.update(entries)
    if kernel_exceptions != {"UX/Apps/Vibes/Info.plist"}:
        findings.append(f"gm_kernel exceptions are {sorted(kernel_exceptions)}; the only one is UX/Apps/Vibes/Info.plist")

    by_name = {name: tid for tid, name in targets.items()}

    def synchronized(target):
        body = objects.get(by_name.get(target, ""), ("", ""))[1]
        return {field(objects.get(g, ("", ""))[1], "path") or g for g in pbx_list(body, "fileSystemSynchronizedGroups")}

    kernel = synchronized("gm_kernel")
    for name in sorted(set(roots) - kernel):
        findings.append(f"Sources root {name} is not among gm_kernel's synchronized groups; it builds into nothing")
    for name in sorted(kernel - set(roots)):
        findings.append(f"gm_kernel synchronizes {name}, which is not a root of the Sources group")
    tests = synchronized("GmKernelTests")
    if tests != {"Core", "Tests/GmKernelTests"}:
        findings.append(f"GmKernelTests synchronizes {sorted(tests)}; it compiles exactly Core and Tests/GmKernelTests")
    for rel in tracked("gmk/Sources"):
        if rel.count("/") == 2:
            findings.append(f"{rel}: lies loose in gmk/Sources, outside every synchronized root")
    return findings


def check_entities_one_table():
    """Every file in Persistence/Entities declares exactly one table.

    Returns: The findings.
    """
    findings = []
    for rel in tracked(ENTITIES):
        if not rel.endswith(".swift"):
            continue
        count = len(TABLE_NAME_RE.findall(read(rel) or ""))
        if count != 1:
            findings.append(
                f"{rel}: declares {count} `static let databaseTableName`; Entities holds one TableRecord per file, "
                "record-family protocols live in Persistence/Records"
            )
    return findings


def check_tests_mirror():
    """Every top-level test folder but Harness names a top-level folder of Sources/Core.

    Returns: The findings.
    """
    core = {rel[len(CORE) + 1 :].split("/")[0] for rel in tracked(CORE) if rel.count("/") > CORE.count("/") + 1}
    tests = {rel[len(TESTS) + 1 :].split("/")[0] for rel in tracked(TESTS) if rel.count("/") > TESTS.count("/") + 1}
    return [
        f"{TESTS}/{folder}: names no folder of {CORE}; a test lives in the folder of the Core subtree it exercises"
        for folder in sorted(tests - core - TESTS_MIRROR_EXEMPT)
    ]


CHECKS = {
    "releases_twin": (check_releases_twin, "gm_releases.sh, releaseStoreBody and the plugin copy are identical"),
    "test_citations": (check_test_citations, "every cited *Tests name is a class under gmk/Tests"),
    "baseline": (check_baseline, "the SwiftLint baseline only shrinks or moves, holds no comment rule, names real files"),
    "build_settings": (check_build_settings, "pinned build settings, one deployment floor, version wiring"),
    "lint_skip": (check_lint_skip, ".swiftlint.yml and .swift-format-ignore agree with gm_lint_skip"),
    "wire_keys": (check_wire_keys, "wire keys equal wire_keys.golden; wire-shaped removals bump GmWireProtocol.version"),
    "resources": (check_resources, "gmk/Sources holds no non-Swift file but the shipped resources"),
    "sources_roots": (check_sources_roots, "gmk/Sources roots are gm_kernel's; tests build Core; only Info.plist is excepted"),
    "entities_one_table": (check_entities_one_table, "each Persistence/Entities file declares exactly one table"),
    "tests_mirror": (check_tests_mirror, "each GmKernelTests folder but Harness mirrors a Sources/Core folder"),
}


def main(argv):
    """Run the requested sub-checks and report.

    Parameters:
      - argv: `--repo DIR` and sub-check names, or `--list`; no name runs every sub-check.
    Returns: The exit status.
    """
    global GIT_ROOT
    if argv[:1] == ["--repo"]:
        if len(argv) < 2:
            print("[GMB] tree-check: --repo needs a directory", file=sys.stderr)
            return 2
        GIT_ROOT, argv = os.path.abspath(argv[1]), argv[2:]
    if argv == ["--list"]:
        for name, (_, about) in CHECKS.items():
            print(f"{name}: {about}")
        return 0
    unknown = [a for a in argv if a not in CHECKS]
    if unknown:
        print(f"[GMB] tree-check: unknown sub-check(s) {unknown}; see --list", file=sys.stderr)
        return 2
    failed = []
    for name in argv or list(CHECKS):
        findings = CHECKS[name][0]()
        for finding in findings:
            print(f"[GMB] tree-check: {name}: {finding}", file=sys.stderr)
        if findings:
            failed.append(name)
    if failed:
        print(f"[GMB] tree-check: FAILED {', '.join(failed)}", file=sys.stderr)
        return 1
    print(f"[GMB] tree-check: clean ({len(argv or CHECKS)} sub-checks)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
