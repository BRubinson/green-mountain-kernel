# gmClaudeForFoundationModels — vendored third-party package

Anthropic's **ClaudeForFoundationModels**, copied into this repo in source form.
It conforms Claude to Apple's FoundationModels `LanguageModel` protocol, so a
`LanguageModelSession` can be driven by a server-side Claude model with the same
API used for the on-device one.

| | |
|---|---|
| upstream | <https://github.com/anthropics/ClaudeForFoundationModels> |
| commit | `5a0fde3ae4275c3ae7ebf840bea840af268138c2` |
| version | `0.2.0`, tagged 2026-09-09 (`chore(main): release 0.2.0 (#27)`) |
| license | Apache-2.0 — the upstream `LICENSE` is retained verbatim beside this file |

## What it contains

Two targets and one product:

- **`ClaudeAPI`** — a self-contained Messages API client (request/response
  models, SSE parsing, transport, telemetry). Imports Foundation only; **no
  FoundationModels dependency**. Upstream keeps it internal — it is not a
  product.
- **`ClaudeForFoundationModels`** — the FoundationModels ↔ Messages API bridge
  (`ClaudeLanguageModel`, `ClaudeExecutor`, `EventTranslator`, App Attest
  auth). This is the sole exported library.
- `ClaudeExample` is a runnable `executableTarget`, deliberately not a product.

It has **zero external package dependencies**, which is what makes vendoring it
a self-contained copy rather than the head of a dependency tree.

## Why a local copy and not a `.package(url:)` pin

GRDB — pinned in `gmk/Package.swift` and consumed only by the GmDaemon target — is fetched by URL, and
that is the convention this package would otherwise follow. It cannot, for a
structural reason specific to the intended consumer:

the `GmAgententicsSdk` target in `gmk/Package.swift` applies `SwiftSetting.unsafeFlags` to define its
`GmAgentOs` availability macro, and **SwiftPM refuses to resolve a package that
uses `unsafeFlags` as a versioned remote dependency**. The `gmk` package
is therefore consumed by local `path:`, and anything entering that graph has to
be reachable the same way. Vendoring is what makes this package reachable by
path.

The trade is the usual one: no automatic upgrades, and the re-sync below is a
manual step. In exchange the build is hermetic and the exact bytes are in-tree
and reviewable.

## What was left behind

Upstream's release automation is not vendored, because it automates *their*
repo and would be inert-to-confusing in this one:

```
.github/                      release-please + PR-title workflows
.pre-commit-config.yaml
release-please-config.json
.release-please-manifest.json
.gitignore
```

Everything else is copied verbatim: `Sources/`, `Tests/`, `Examples/`,
`Package.swift`, `LICENSE`, `README.md`, `CHANGELOG.md`, `version.txt`,
`.swift-format`.

## Re-syncing

The **only** local modification is the provenance header at the top of
`Package.swift`. Every other vendored file is byte-identical to the commit
above, so a re-sync is a copy plus one small conflict you are meant to resolve
by updating the commit SHA:

```bash
git clone --depth 1 https://github.com/anthropics/ClaudeForFoundationModels /tmp/cffm
cd /tmp/cffm && git rev-parse HEAD          # the SHA to record

D=gmk/gmClaudeForFoundationModels
rm -rf $D/Sources $D/Tests $D/Examples
cp -R /tmp/cffm/{Sources,Tests,Examples} $D/
cp /tmp/cffm/{LICENSE,README.md,CHANGELOG.md,version.txt,.swift-format} $D/
# Package.swift: re-apply the provenance header, then update commit/version.
```

Then re-read **Platform floor**, below — it is the thing most likely to have
changed, and the thing that decides whether the package can be consumed at all.

## Platform floor — the open blocker

Upstream declares:

```swift
platforms: [.iOS("27.0"), .macOS("27.0"), .visionOS("27.0"), .watchOS("27.0")]
```

because the server-side `LanguageModel` API it implements ships in the OS 27
SDK. The `GmAgententicsSdk` target used to declare `platforms: [.macOS("26.0")]`, and CI pins
`macos-26` on every job.

**A dependency may not have a floor above its consumer's**, so this package is
*not* wired into `gmAgententicsSdk`. Adding the edge as-is fails at planning
time, before a single file compiles:

```
error: The package product 'ClaudeForFoundationModels-product' requires minimum
platform version 27.0 for the macOS platform, but this target supports 26.0
```

Lowering *this* package's floor to 26 is not a fix either — the bridge target
then fails to compile with 26 availability errors across `ClaudeExecutor`,
`ClaudeLanguageModel`, `EventTranslator` and `RequestBuilder`
(`LanguageModelExecutorGenerationRequest`, `LanguageModelExecutorGenerationChannel`,
`LanguageModelCapabilities`, `ContextOptions`, `ToolCallingMode` are all
macOS-27-only). Note that the repo's usual escape hatch — floor 26 with 27-only
symbols gated behind `@available(GmAgentOs, *)` — does **not** apply: SwiftPM
checks platform floors when it resolves the package graph, which is strictly
before any availability scope exists.

`ClaudeAPI` alone *does* build clean at a macOS 26 floor, since it never imports
FoundationModels. Exposing it would mean adding a `.library` product upstream
does not declare, and it delivers the raw Messages API client rather than the
FoundationModels bridge — a different thing from what this package was vendored
for.

Resolving this is a decision about the repo's platform floor and its CI runner,
not about this directory.
