---
name: gm_swift_lint
description: Lint every authored Swift source under gmk/ with swift-format and SwiftLint (root .swift-format and .swiftlint.yml), or format and autocorrect in place with --fix. Same gate rebuild_local.sh, the pre-commit hook and the PostToolUse hook run. Requires a checkout of green-mountain-kernel.
argument-hint: "[--fix] [path ...]"
allowed-tools: Bash, Read, Edit
---

# /gm_swift_lint

Run the repo's lint gate, and fix what it finds.

```bash
bash gmk/scripts/swift_lint_format.sh $ARGUMENTS
```

- No arguments: lint every authored package. Exit 1 on any swift-format finding or any SwiftLint error.
- `--fix`: swift-format in place, then lint. SwiftLint never rewrites code: its autocorrect has
  changed semantics here (double-optional flattening, closure parameters, test base classes).
- Paths after the flags restrict the run to those files or directories.

Three stages, one gate, in this order:

1. **swift-format** owns layout. Config discovered by walking up: root `.swift-format`, and
   `gmk/Tests/.swift-format` for the test package (force-try and IUOs allowed there).
   `.swift-format-ignore` at the root declares vendored, generated and build output.
2. **SwiftLint 0.65.1** owns semantics and comments. Config is the root `.swiftlint.yml`.
   Not installed → the stage is skipped with a warning; install with
   `bash gmk/scripts/install_swiftlint.sh` (pinned binary under `$GM_FS_ROOT/tools/swiftlint/`).
3. **swift_doc_check.py** owns doc-comment completeness: every function, init and subscript has
   a one-line summary of at most 100 characters, a Parameters section naming each parameter,
   Returns when it returns, Throws when it throws. Findings print as `[DocComment]` and every one
   fails the gate; the tree carries no baseline. Style: `.claude/skills/swift-doc-comments/SKILL.md`.

The script skips `gmk/gmClaudeForFoundationModels`, `Generated/`, `.build`, `Package.swift` and
`plugins/`. Never format those by hand either.

## After a lint run

swift-format findings print as `path:line:col: error: [Rule] message`. Formatting rules
(Indentation, LineLength, Spacing, AddLines, RemoveLine, TrailingComma, TrailingWhitespace,
OrderedImports, DoNotUseSemicolons) are fixed by `--fix`. Anything left is a lint-only rule
(ValidateDocumentationComments, NeverUseForceTry, NeverUseImplicitlyUnwrappedOptionals,
AlwaysUseLowerCamelCase exemptions) and needs a hand edit at the reported line.

SwiftLint findings print as `path:line:col: error|warning: Message (rule_id)`. Errors fail the
gate; warnings do not. The error-severity rules are the comment rules
(`historical_comment`, `long_comment_run`, `long_doc_comment_run`, `block_comment`,
`comment_line_length`), `no_print`,
`no_unchecked_sendable`, `no_file_literal`, and the error tier of `function_body_length`,
`cyclomatic_complexity` and `identifier_name`.

`.swiftlint-baseline.json` exempts the warnings that pre-dated the gate. Comment-rule errors are
never baselined. Regenerate it only on purpose:

```bash
~/gmfs/bin/swiftlint lint --write-baseline .swiftlint-baseline.json
```

Report the file count, the number of findings, and which files still need a hand edit. If
`--fix` rewrote files, list them from `git status --short -- '*.swift'` so the reformat is
visible before it is committed.

## Rules the configs disable, and why

- swift-format `AlwaysUseLowerCamelCase` (off under `gmk/Sources`, on under `gmk/Tests`):
  migration functions are `m00NN_name`, template constants are `GM_*`, and `@Generable` tool
  argument properties are snake_case because they ARE the wire names. SwiftLint admits the same
  names through `identifier_name.excluded`. Do not rename them to satisfy a linter. Type names ARE
  checked (`TypeNamesShouldBeCapitalized` is on).
- swift-format `UseSynthesizedInitializer`, `UseLetInEveryBoundCaseVariable`: hand-written inits and
  `case let .x(a, b)` are the house style.
- SwiftLint layout rules (whitespace, braces, colons, commas, multiline_*, line_length ...): swift-format
  owns layout; running both on the same concern makes them fight.
- SwiftLint `multiple_closures_with_trailing_closure`, `type_contents_order`, `file_types_order`,
  `no_magic_numbers`, `redundant_discardable_let`: they misfire on SwiftUI label+content closures,
  init-before-properties views, padding literals and `@ViewBuilder` bodies.
- SwiftLint `redundant_nil_coalescing` and `final_test_case`: their fixers broke the build (a stripped
  double-optional flatten; a shared test base class marked final).

## Where else the gate runs

- `rebuild_local.sh` runs it before building (`--no-lint` skips) and sets `core.hooksPath` to
  `gmk/scripts/githooks` when unset, which activates the committed pre-commit hook.
- The pre-commit hook lints staged `.swift` files; `git commit --no-verify` bypasses it once.
- `.claude/settings.json` registers `gmk/scripts/swift_lint_hook.sh` as a PostToolUse hook: it lints
  the one file an agent just edited and returns findings as context. It never formats.
