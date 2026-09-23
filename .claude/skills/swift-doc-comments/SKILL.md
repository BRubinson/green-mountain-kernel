---
name: swift-doc-comments
description: How to write the `///` documentation comment on a Swift function, init, subscript, type or property in this repo, in Xcode Quick Help markup (summary, discussion, Parameters, Returns, Throws, callouts). Use whenever you add or change a Swift declaration, or when the lint gate reports a [DocComment], BeginDocumentationCommentWithOneLineSummary, ValidateDocumentationComments or long_doc_comment_run finding.
---

# swift-doc-comments

Every function, initializer and subscript in `gmk/` carries a doc comment that says what it does,
names every parameter, states what it returns and what it throws. The lint gate enforces it
(`gmk/scripts/swift_doc_check.py`, stage 3 of `swift_lint_format.sh`), swift-format validates the
sections against the signature, and the PostToolUse hook shows the findings after every edit.
Write the comment when you write the declaration; do not leave it for the gate.

## The shape

```swift
/// Inserts `row` into `table` and stamps the identity block.
///
/// The write goes through the store's version gate, so a stale `expectedVersion`
/// is refused before any SQL runs. Never call from an event subscriber.
///
/// - Parameters:
///   - table: The domain table, by its SQL name.
///   - row: Column values keyed by column name; identity columns are ignored.
///   - expectedVersion: The version the caller last read, or nil to skip the gate.
/// - Returns: The uuid of the inserted row.
/// - Throws: `StoreError.versionConflict` when `expectedVersion` is stale.
func insert(into table: String, row: [String: Any], expectedVersion: Int? = nil) throws -> String
```

In order, separated by blank `///` lines:

1. **Summary.** One sentence fragment, ending with a period, alone in its paragraph, on **one
   line of at most 100 characters**. The gate (`summary_long`) fails a summary that wraps or runs
   long; swift-format (`BeginDocumentationCommentWithOneLineSummary`) rejects a second sentence in
   the same paragraph and a summary with no period. It is rendered as the Description in Quick
   Help, where a long one is truncated. Anything the sentence cannot hold goes in the discussion.
2. **Discussion** (optional). Complete sentences. What the code cannot say: invariants, the
   thread or queue it must run on, why a caller would pick this over a sibling. Not history and not
   the implementation.
3. **Sections.** `- Parameters:`, `- Returns:`, `- Throws:`, in that order. Callouts go after the
   discussion and before the sections, or after the sections.

## Summary by kind

- **Function or method**: what it does and what it returns, as a verb phrase for a side effect
  (`Inserts …`, `Stops the daemon …`) or a noun phrase for a pure read (`The prompt row for …`).
  Omit `Void` returns and null effects.
- **Initializer**: what it creates. `Creates a client bound to the socket at `path`.`
- **Subscript**: what it accesses. `Accesses the element at `index`.`
- **Type, property, case, protocol**: what it is. `A collection that …`, `The root the kernel
  serves, resolved once per process.`
- **Boolean**: an assertion about the receiver. `True when the holder is a headless daemon.`

## Parameters

- One parameter: the inline singular form.
  `/// - Parameter path: The socket path; must be under 104 bytes.`
- Two or more: the plural form with one nested bullet per parameter, indented two spaces, in
  declaration order. swift-format rejects a singular entry when there are several parameters.
- Name the parameter by its internal name, exactly as declared. `_`-labelled parameters use the
  internal name too. Every parameter is listed; swift-format fails the comment when one is missing
  or misspelt, and the gate fails a Parameters section that is absent.
- Describe the role and the constraint, not the type. `The run id; keep it short, sun_path is 104
  bytes.` beats `A string.`
- Defaulted parameters: say what the default means. `… or nil to use the ambient handle.`
- Closure parameters: name what it receives and when it is called.

## Returns and Throws

- `- Returns:` on every function whose return type is not `Void`. Say what the value is, including
  the nil case: `The row, or nil when no prompt carries `code`.`
- `- Throws:` on every `throws`/`rethrows` function. Name the error cases a caller can act on:
  `` `StoreError.versionConflict` on a stale version; `DaemonError.unreachable` when the socket is gone. ``
  Something like `Any error the daemon returns.` is acceptable only for pure pass-throughs.
- Neither section on `init` or `subscript` unless it throws.
- swift-format removes a `Returns:` from a `Void` function and requires one otherwise, so keep them
  in step with the signature when you change it.

## Callouts

Xcode renders these bullets as titled callouts inside the Description. Use them for facts a reader
must not miss; they are not a place for prose that belongs in the discussion.

| Callout | Use it for |
|---|---|
| `- Important:` | A rule that breaks the system when ignored (second writer, wrong queue). |
| `- Precondition:` / `- Requires:` | What must be true on entry; the function traps or misbehaves otherwise. |
| `- Postcondition:` / `- Invariant:` | What holds afterwards or always. |
| `- Warning:` | A footgun the signature hides. |
| `- Note:` | A clarification that is not a rule. |
| `- Complexity:` | Required on any computed property or method that is not O(1). |
| `- SeeAlso:` | The sibling a reader will want next, as a backticked symbol. |
| `- Attention:`, `- Experiment:`, `- Remark:`, `- ToDo:` | Available; rarely right here. `ToDo` needs a ticket. |

Not used here: `- Author:`, `- Authors:`, `- Copyright:`, `- Date:`, `- Version:`, `- Since:`,
`- Bug:`. Git carries authorship and history.

## Inline markup

Swift's Markdown dialect, rendered by Quick Help:

- Backticks around every symbol, parameter name, literal and path: `` `expectedVersion` ``,
  `` `nil` ``, `` `~/gmfs` ``.
- `*emphasis*` and `**strong**` sparingly; never for a symbol.
- Fenced code blocks (```` ``` ````) for a multi-line example; indented code is not recognised.
- Links: `[text](https://…)` and bare `<https://…>`. Escape a literal `*`, `_`, `` ` ``, `[`, `#` with a backslash.
- Headings (`#`) are legal in a discussion but almost never earn their place in a doc comment
  here; a callout does the same job at lower cost.

## Length and the comment rules

SwiftLint's comment rules are errors and are never baselined:

- A `///` block may run to **30 lines** (`long_doc_comment_run`), which is what a wire init with
  twenty parameters needs. Plain `//` comments still stop at 8 (`long_comment_run`). A discussion
  should never be what pushes a block near the cap; if it is, the prose is a design document and
  belongs in the architecture record.
- 120 columns per line (`comment_line_length`).
- No `/* */` blocks (`block_comment`). Triple-slash only; swift-format converts `/** */`.
- No history (`historical_comment`): no "previously", "used to", "no longer", "replaced by",
  "originally". Describe what IS.
- `TODO`/`FIXME` carry a ticket: `TODO(GMK-123)`.

## What the gate checks, and what it does not

`swift_doc_check.py` reports, per declaration, one of: `missing` (no doc comment), `summary`
(the block opens with a section instead of a sentence), `summary_long` (the summary wraps or
exceeds 100 characters), `parameters` (names it lists that the Parameters section lacks),
`returns`, `throws`. It skips `override` members, local functions
inside a body, and `test*`/`setUp`/`tearDown` under `gmk/Tests`. It does not judge prose, and it
does not check types or properties; the guideline still applies to them.

The tree is fully documented, so there is no baseline: every finding fails the gate. The checker
still supports one for adopting the rule on another tree (`--write-baseline` writes
`.swift-doc-baseline.json`, keyed by file, signature and finding kind, and suppressed findings are
reported as such). Do not create one here to get past a finding; write the comment.

## Working on findings

1. Read the declaration and its call sites before writing. A summary that could describe three
   other functions is not a summary.
2. Write the summary first, then the sections, then decide whether a discussion is needed at all.
   Most methods need none.
3. Run `bash gmk/scripts/swift_lint_format.sh <file>`; it must print `swift-format: clean`,
   `swiftlint: no errors` and `doc-check: clean`.
4. When a comment cannot be written plainly, the API is the problem. Say so instead of padding.

Reference for the guideline text: `Reference_Swift_Code_styling.md` (Swift API Design Guidelines)
and Apple's Markup Formatting Reference for Quick Help.
