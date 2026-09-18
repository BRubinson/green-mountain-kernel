---
name: gm_swift_lint
description: Lint every authored Swift source under gmk/ with swift-format and the root .swift-format, or format it in place with --fix. Same gate rebuild_local.sh runs before it builds. Requires a checkout of green-mountain-kernel.
argument-hint: "[--fix] [path ...]"
allowed-tools: Bash, Read, Edit
---

# /gm_swift_lint

Run the repo's swift-format gate, and fix what it finds.

```bash
bash gmk/scripts/swift_lint_format.sh $ARGUMENTS
```

- No arguments: lint every authored package. Exit 1 on any finding.
- `--fix`: format in place under the root `.swift-format`, then lint.
- Paths after the flags restrict the run to those files or directories.

The script skips the vendored `gmk/gmClaudeForFoundationModels` package, generated protobuf sources under `Generated/`, and `.build` directories. Never format those by hand either.

## After a lint run

Findings print as `path:line:col: warning: [Rule] message`. Formatting rules (Indentation, LineLength, Spacing, AddLines, RemoveLine, TrailingComma, TrailingWhitespace, OrderedImports, DoNotUseSemicolons) are fixed by re-running with `--fix`. Anything left after `--fix` is a lint-only rule and needs a hand edit at the reported line.

Report the file count, the number of findings, and which files still need a hand edit. If `--fix` rewrote files, list them from `git status --short -- '*.swift'` so the reformat is visible before it is committed.

## Rules the config disables

`AlwaysUseLowerCamelCase` and `TypeNamesShouldBeCapitalized` are off: migration functions are `m00NN_name`, template constants are `GM_*`, and the tool registry's family enums are lowercase by design. Do not rename them to satisfy a linter.
