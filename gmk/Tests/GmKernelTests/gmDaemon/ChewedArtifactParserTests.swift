import XCTest

/// The chewed-artifact parser had no coverage at all, and two gaps in it
/// silently produced kbites whose file rows all carried NULL content: the
/// Contents Overview `File` cell was resolved as a path WITHOUT stripping the
/// backticks chew agents habitually wrap it in, and the inline allowlist
/// carried `.h` but not `.m`, so every Objective-C body digested empty while
/// its own header digested fine. Both failures are invisible at digest time —
/// the row still inserts, the digest still reports success — so they are only
/// catchable here.
final class ChewedArtifactParserTests: XCTestCase {

    // MARK: - File cell is a real path

    func testBacktickQuotedFileCellYieldsBarePath() {
        let artifact = ChewedArtifactParser.parse(
            text: """
                # Chewed: demo

                ## 1. Contents Overview

                | File | Type | Description |
                |------|------|-------------|
                | `sources/VT100/VT100Parser.m` | m | byte-stream parser |
                | sources/VT100/VT100Token.h | h | token IR |
                """,
            fallbackName: "fallback"
        )

        XCTAssertEqual(
            artifact.files.map(\.name),
            [
                "sources/VT100/VT100Parser.m",
                "sources/VT100/VT100Token.h",
            ],
            "a code-quoted File cell must resolve to the same path as a bare one"
        )
    }

    func testBacktickedCellStillClassifiesAsTextType() {
        // The end-to-end symptom: backticks made pathExtension come back as
        // "m`", which matched no allowlist entry, so content inlined as nil.
        let artifact = ChewedArtifactParser.parse(
            text: """
                ## Contents Overview

                | File | Type | Description |
                |------|------|-------------|
                | `Trigger.m` | m | base trigger |
                """,
            fallbackName: "demo"
        )

        let name = try! XCTUnwrap(artifact.files.first).name
        XCTAssertTrue(
            ChewedArtifactParser.isTextType(fileName: name),
            "backticked cell must survive as an inlinable text type"
        )
    }

    func testHeaderAndSeparatorRowsAreNotIngestedAsFiles() {
        let artifact = ChewedArtifactParser.parse(
            text: """
                ## 1. Contents Overview

                | File | Type | Description |
                |------|------|-------------|
                | real.swift | swift | the only file |
                """,
            fallbackName: "demo"
        )

        XCTAssertEqual(artifact.files.map(\.name), ["real.swift"])
    }

    // MARK: - Inline allowlist

    func testObjectiveCImplementationFilesAreTextTypes() {
        // The gap that made ~1000 iTerm2 .m files invisible to search.
        for name in ["VT100Terminal.m", "iTermAPIHelper.m", "Bridge.mm"] {
            XCTAssertTrue(
                ChewedArtifactParser.isTextType(fileName: name),
                "\(name) must inline — its .h counterpart already did"
            )
        }
    }

    func testImplementationAndHeaderAgreeForEveryCLikeLanguage() {
        // The original bug was an asymmetry, not a missing entry: whenever a
        // header extension inlines, its implementation must too.
        let pairs = [("c", "h"), ("cc", "hh"), ("cpp", "hpp"), ("cxx", "hxx"), ("m", "h"), ("mm", "hh")]
        for (impl, header) in pairs {
            XCTAssertEqual(
                ChewedArtifactParser.isTextType(fileName: "x.\(impl)"),
                ChewedArtifactParser.isTextType(fileName: "x.\(header)"),
                ".\(impl) and .\(header) must inline alike"
            )
        }
    }

    func testSchemaAndAppleTextFormatsAreTextTypes() {
        for name in ["api.proto", "Info.plist", "iTerm2.sdef", "iTerm2.entitlements"] {
            XCTAssertTrue(ChewedArtifactParser.isTextType(fileName: name), "\(name) is text")
        }
    }

    func testBinaryAndUnknownExtensionsStayFilesystemOnly() {
        for name in ["icon.png", "clip.mov", "bundle.zip", "Makefile", "a.out"] {
            XCTAssertFalse(ChewedArtifactParser.isTextType(fileName: name), "\(name) must not inline")
        }
    }

    func testExtensionMatchIsCaseInsensitive() {
        XCTAssertTrue(ChewedArtifactParser.isTextType(fileName: "README.MD"))
        XCTAssertTrue(ChewedArtifactParser.isTextType(fileName: "Legacy.M"))
    }

    // MARK: - Section + header handling

    func testResourceNameComesFromChewedHeader() {
        // resourceName picks the directory relative entries resolve against, so
        // a drifting header silently points every path at a missing folder.
        let artifact = ChewedArtifactParser.parse(
            text: "# Chewed: iTerm2_vt100_engine\n",
            fallbackName: "wrong"
        )
        XCTAssertEqual(artifact.resourceName, "iTerm2_vt100_engine")
    }

    func testFallbackNameUsedWhenHeaderAbsent() {
        let artifact = ChewedArtifactParser.parse(text: "no header here\n", fallbackName: "fallback")
        XCTAssertEqual(artifact.resourceName, "fallback")
    }

    func testContentsSectionClosesAtNextHeading() {
        let artifact = ChewedArtifactParser.parse(
            text: """
                ## 1. Contents Overview

                | File | Type | Description |
                |------|------|-------------|
                | real.swift | swift | counted |

                ## 3. Detailed Analysis

                | Location | Importance | Confidence |
                |----------|------------|------------|
                | not-a-file | 90 | 80 |
                """,
            fallbackName: "demo"
        )

        XCTAssertEqual(
            artifact.files.map(\.name),
            ["real.swift"],
            "a later table must not contribute file rows"
        )
    }

    func testFullPathsBackfillMatchesByBasename() {
        let artifact = ChewedArtifactParser.parse(
            text: """
                ## 1. Contents Overview

                | File | Type | Description |
                |------|------|-------------|
                | VT100Parser.m | m | parser |

                **Full Paths**:
                - `/tmp/iterm/VT100Parser.m`
                """,
            fallbackName: "demo"
        )

        XCTAssertEqual(artifact.files.count, 1, "back-fill must not duplicate the row")
        XCTAssertEqual(artifact.files.first?.fullPath, "/tmp/iterm/VT100Parser.m")
    }

    func testBodySurvivesVerbatim() {
        let text = "# Chewed: demo\n\nprose\n\n## 4. Keywords\n\nalpha, beta\n"
        XCTAssertEqual(ChewedArtifactParser.parse(text: text, fallbackName: "x").body, text)
    }

    func testKeywordsAreNormalizedAndDeduped() {
        let artifact = ChewedArtifactParser.parse(
            text: """
                ## 4. Keywords

                VT100 Parser, escape-codes, VT100 Parser, OSC 133
                """,
            fallbackName: "demo"
        )

        XCTAssertEqual(artifact.keywords, ["vt100_parser", "escape_codes", "osc_133"])
    }
}
