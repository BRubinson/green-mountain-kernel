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

## Why a local copy and not a remote package reference

GRDB and swift-protobuf are `XCRemoteSwiftPackageReference`s in
`gmk/gmk.xcodeproj/project.pbxproj`, resolved into the workspace's one lockfile
(`gmk/gmk.xcworkspace/xcshareddata/swiftpm/Package.resolved`), and each is
imported only by files under its one folder (`Sources/GmDaemon/`,
`Sources/GmITerm2Client/`). That is the convention this package would otherwise
follow, and nothing structural prevents it any more: it is consumed as an
`XCLocalSwiftPackageReference` at `gmClaudeForFoundationModels`, and only files
under `Sources/GmAgententicsSdk/` import it.

It stays vendored on the merits of the trade rather than by necessity: no
automatic upgrades, and the re-sync below is a manual step; in exchange the
build is hermetic and the exact bytes are in-tree and reviewable, which matters
for a pre-1.0 upstream that this repo's agent surface sits directly on.

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

## Platform floor — 27, matched by the project

Upstream declares:

```swift
platforms: [.iOS("27.0"), .macOS("27.0"), .visionOS("27.0"), .watchOS("27.0")]
```

because the server-side `LanguageModel` API it implements ships in the OS 27
SDK. The `gm_kernel` project sets `MACOSX_DEPLOYMENT_TARGET = 27.0` at project
level, so the consumer's floor matches and the product is a dependency of the
one `gm_kernel` target.

**A dependency may not have a floor above its consumer's.** Lowering the
project's deployment target below 27 fails at package resolution, before a
single file compiles:

```
error: The package product 'ClaudeForFoundationModels-product' requires minimum
platform version 27.0 for the macOS platform, but this target supports 26.0
```

Lowering *this* package's floor is not a fix either — the bridge target then
fails to compile with availability errors across `ClaudeExecutor`,
`ClaudeLanguageModel`, `EventTranslator` and `RequestBuilder`
(`LanguageModelExecutorGenerationRequest`, `LanguageModelExecutorGenerationChannel`,
`LanguageModelCapabilities`, `ContextOptions`, `ToolCallingMode` are all
macOS-27-only). An `@available` gate on the consumer side cannot help: the
floor is checked when the package graph resolves, which is strictly before any
availability scope exists.

`ClaudeAPI` alone *does* build clean at a macOS 26 floor, since it never imports
FoundationModels. Exposing it would mean adding a `.library` product upstream
does not declare, and it delivers the raw Messages API client rather than the
FoundationModels bridge — a different thing from what this package was vendored
for.

The floor is a decision about the repo's deployment target, not about this
directory.
