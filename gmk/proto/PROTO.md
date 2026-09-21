# `proto/api.proto` — provenance and regeneration

`proto/api.proto` is a **byte-identical** copy of iTerm2's own API schema. It
carries no provenance header, deliberately: a header inside the file would make
every future re-sync diff start with a conflict on a line upstream does not
have. Provenance lives here instead, following the `gmClaudeForFoundationModels`
precedent, where the only local modification is on `Package.swift` and every
other byte is upstream's.

## Provenance

| | |
|---|---|
| Upstream | https://github.com/gnachman/iTerm2 — `proto/api.proto` |
| iTerm2 version | **3.6.11** (`/Applications/iTerm.app`, `CFBundleShortVersionString`) |
| Local source of the copy | `~/gmfs/kbites/digested/_retired_iterm_fork_20260913/primary/example_project/iTerm2-master/proto/api.proto` |
| `sha256(api.proto)` | `c55506a085fdce33d750456e059348331a958dc6e894984766146ddf54700afe` |
| Lines | 1663 |
| Schema | `syntax = "proto2"`, `package iterm2`, `option objc_class_prefix = "ITM"` |

The `objc_class_prefix` is upstream's and is inert for us — `protoc-gen-swift`
derives its prefix from the `package`, which is why every generated type is
`Iterm2_*` and not `ITM*`.

## Regeneration

```bash
brew install protobuf swift-protobuf
cd gmk
protoc --swift_out=Sources/API/Clients/ITerm2Client/Generated \
       --swift_opt=Visibility=Internal --proto_path=proto proto/api.proto
```

Versions that produced the committed `Sources/API/Clients/ITerm2Client/Generated/api.pb.swift`:

| | |
|---|---|
| `protoc` | **libprotoc 36.1** |
| `protoc-gen-swift` | **1.38.1** |
| SwiftProtobuf runtime | **1.38.1** (`gmk/gmk.xcworkspace/xcshareddata/swiftpm/Package.resolved`, revision `55d7a1cc`) |

**`protoc-gen-swift` must match the pinned SwiftProtobuf runtime's minor
version.** The generated file opens with a `ProtobufAPIVersionCheck` conformance
whose whole job is to fail to compile when it does not. The
`XCRemoteSwiftPackageReference` for `swift-protobuf` in
`gmk/gmk.xcodeproj/project.pbxproj` declares a minimum of `1.28.0`, which is a
floor, not a pin; the workspace's `xcshareddata/swiftpm/Package.resolved` is the
ONE lockfile and the record of what actually resolved, and it is committed for
exactly this reason. If you upgrade one side, regenerate against the other.

`--swift_opt=Visibility=Internal` is not optional. Without it the ~16,500
generated lines become exported API of the kernel module. Everything under
`gmk/Sources` is one module, so `Internal` does not hide the types from the
Vibes layer; what keeps the Vibes layer off protobuf types is the convention
that only files under `Sources/API/Clients/ITerm2Client/` write `import SwiftProtobuf`,
which `MEMBER_IMPORT_VISIBILITY` makes visible per file. The hand-written
façade (`ITerm2Launcher.swift`) and its value types are the surface the rest of
the tree is meant to use.

## **READ THE DIFF BEFORE COMMITTING IT**

**Regenerating ACCEPTS ALL PENDING DRIFT AS INTENTIONAL.** This repository
already has one generator whose output nothing checks — `wire_keys.golden`,
which carried a stale `TxBatchResponse.failedIndex` for several releases because
nobody diffed a regeneration. That is the cautionary precedent, and it applies
here with 16,500 lines instead of a few hundred.

A re-sync that changes 40,000 lines is a re-sync that was not reviewed. Diff it,
read it, and know what moved before it lands.

## Why the proto is NOT trimmed

Trimming `api.proto` down to the two or three messages we actually send was
considered and **declined**.

The decision names `proto/api.proto`. A hand-trimmed wire vocabulary is a second
source of truth that drifts from upstream silently, and whose drift nothing can
see — you would not discover a field had changed meaning, you would discover a
launch stopped working. This is the same argument that put `gmAgententicsSdk` on
`gmDaemonSdk` rather than on a hand-maintained copy of a dozen enums whose raw
values are load-bearing.

The cost of not trimming is compile time and file size. The cost of trimming is
a schema that lies. We pay the first one.

## What this package actually sends

Exactly one request type: `CreateTabRequest` (submessage tag 108 on
`ClientOriginatedMessage`), carrying its command through
`custom_profile_properties` — **never** the `command` field 4, which upstream
marks `[deprecated=true]` with the note "Use custom_profile_properties instead".
