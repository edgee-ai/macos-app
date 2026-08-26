import XCTest

@testable import EdgeeMenuBar

/// Unit tests for the app's pure logic — formatting, the appearance enum, the
/// launch-target table, and the `--json` model decoding that mirrors the CLI
/// contract. Anything that needs a subprocess or SwiftUI is out of scope here.
final class PureLogicTests: XCTestCase {

    // MARK: TokenFormat

    func testTokenFormatShort() {
        XCTAssertEqual(TokenFormat.short(0), "0")
        XCTAssertEqual(TokenFormat.short(42), "42")
        XCTAssertEqual(TokenFormat.short(999), "999")
        // Exact thousands render without a decimal.
        XCTAssertEqual(TokenFormat.short(1_000), "1k")
        XCTAssertEqual(TokenFormat.short(2_000), "2k")
        // Non-integer thousands under 100 keep one decimal.
        XCTAssertEqual(TokenFormat.short(1_500), "1.5k")
        XCTAssertEqual(TokenFormat.short(31_400), "31.4k")
        // >= 100 rounds to a whole number.
        XCTAssertEqual(TokenFormat.short(150_000), "150k")
        // Millions.
        XCTAssertEqual(TokenFormat.short(1_000_000), "1M")
        XCTAssertEqual(TokenFormat.short(2_500_000), "2.5M")
    }

    // MARK: Appearance

    func testAppearanceCycle() {
        XCTAssertEqual(Appearance.system.next, .light)
        XCTAssertEqual(Appearance.light.next, .dark)
        XCTAssertEqual(Appearance.dark.next, .system)
    }

    func testAppearanceColorScheme() {
        XCTAssertNil(Appearance.system.colorScheme)
        XCTAssertEqual(Appearance.light.colorScheme, .light)
        XCTAssertEqual(Appearance.dark.colorScheme, .dark)
    }

    func testAppearanceRawValueRoundTrip() {
        for appearance in Appearance.allCases {
            XCTAssertEqual(Appearance(rawValue: appearance.rawValue), appearance)
            XCTAssertFalse(appearance.symbol.isEmpty)
            XCTAssertFalse(appearance.label.isEmpty)
        }
        XCTAssertNil(Appearance(rawValue: "bogus"))
    }

    // MARK: RelayTarget table

    func testRelayTargetIdsAreUnique() {
        let ids = RelayTarget.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "duplicate relay target id")
    }

    func testRelayTargetRoster() {
        let byId = Dictionary(uniqueKeysWithValues: RelayTarget.all.map { ($0.id, $0) })
        // The expected roster and how each is driven.
        let expected: [String: LaunchMode] = [
            "claude": .terminalAgent,
            "codex": .terminalAgent,
            "opencode": .terminalAgent,
            "crush": .terminalAgent,
            "codebuddy": .terminalAgent,
            "pi": .terminalAgent,
            "kimi": .terminalAgent,
            "kilo": .terminalAgent,
            "codex-desktop": .launch,
            "claude-desktop": .relay,
            "cursor": .relay,
            "copilot-vscode": .relay,
        ]
        XCTAssertEqual(Set(byId.keys), Set(expected.keys))
        for (id, mode) in expected {
            XCTAssertEqual(byId[id]?.mode, mode, "wrong launch mode for \(id)")
            XCTAssertFalse(byId[id]?.name.isEmpty ?? true, "empty name for \(id)")
        }
    }

    /// Every terminal agent is detected by a binary named after its `edgee launch`
    /// subcommand; GUI targets are detected by bundle path instead.
    func testTerminalAgentsDetectByCommandNamedAfterTheirId() {
        for target in RelayTarget.all {
            switch target.mode {
            case .terminalAgent:
                XCTAssertEqual(target.detectCommand, target.id, "detectCommand for \(target.id)")
                XCTAssertTrue(target.detectPaths.isEmpty, "\(target.id) is a CLI, not a bundle")
            case .relay, .launch:
                XCTAssertNil(target.detectCommand, "GUI target \(target.id) has a command")
                XCTAssertFalse(target.detectPaths.isEmpty, "no detectPaths for \(target.id)")
            }
        }
    }

    // MARK: Launch-grid split (quick links vs "enroll an agent")

    func testSplitKeepsDetectedAgentsAsQuickLinks() {
        let (quick, enrollable) = RelayTarget.split(detected: ["kilo", "crush"], enrolled: [])
        XCTAssertEqual(quick.prefix(2).map(\.id), ["crush", "kilo"], "declared order kept")
        XCTAssertFalse(quick.contains { $0.id == "claude" }, "undetected CLI is not a quick link")
        XCTAssertTrue(enrollable.contains { $0.id == "claude" })
        // The two halves are the whole roster, once each.
        XCTAssertEqual(
            Set(quick.map(\.id)).union(enrollable.map(\.id)), Set(RelayTarget.all.map(\.id)))
        XCTAssertEqual(quick.count + enrollable.count, RelayTarget.all.count)
    }

    func testSplitTreatsEnrolledAsQuickLinksEvenWhenUndetected() {
        let (quick, enrollable) = RelayTarget.split(detected: ["crush"], enrolled: ["kimi"])
        XCTAssertEqual(quick.map(\.id).filter { $0 == "kimi" }, ["kimi"])
        XCTAssertFalse(enrollable.contains { $0.id == "kimi" })
    }

    /// Detection hasn't landed (or the login shell wouldn't answer): show everything
    /// rather than an empty grid with the whole roster hidden behind "enroll".
    func testSplitWithNothingDetectedShowsTheWholeRoster() {
        // A GUI target whose bundle happens to exist on the test machine would count
        // as detected, so exercise the fallback on the CLI agents alone.
        let cliOnly = RelayTarget.all.filter { $0.mode == .terminalAgent }
        let (quick, enrollable) = RelayTarget.split(cliOnly, detected: [], enrolled: [])
        XCTAssertEqual(quick.map(\.id), cliOnly.map(\.id))
        XCTAssertTrue(enrollable.isEmpty)
    }

    /// Detection must never gate the tile: an undetected CLI agent is only sorted
    /// last, because a version-manager shim can hide a binary we can't see.
    func testUndetectedCLIAgentsStayInstalled() {
        for target in RelayTarget.all where target.mode == .terminalAgent {
            XCTAssertTrue(target.installed, "\(target.id) must stay clickable")
            XCTAssertFalse(target.available(detected: []), "\(target.id) can't be available")
        }
    }

    // MARK: RelayRunState equality

    func testRelayRunStateEquatable() {
        XCTAssertEqual(RelayRunState.running, .running)
        XCTAssertNotEqual(RelayRunState.stopped, .starting)
        XCTAssertEqual(RelayRunState.failed("x"), .failed("x"))
        XCTAssertNotEqual(RelayRunState.failed("x"), .failed("y"))
    }

    // MARK: --json model decoding (Swift side of the CLI contract)

    /// Decoder matching `EdgeeCLI`'s: snake_case → camelCase.
    private func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    func testStatsDecoding() throws {
        let json = """
            {
              "sessions": 4,
              "totals": {
                "requests": 38,
                "errors": 1,
                "input_tokens": 31400,
                "output_tokens": 2900,
                "cached_input_tokens": 24000,
                "token_cost_savings": 12,
                "uncompressed_tools_tokens": 100,
                "compressed_tools_tokens": 60,
                "compression_pct": 40
              },
              "recent": [
                {
                  "session_id": "s1",
                  "tool_name": "Claude Code",
                  "ended_at": "2026-08-12T00:00:00Z",
                  "ended_at_unix": 1786000000,
                  "requests": 10,
                  "input_tokens": 5000,
                  "output_tokens": 400,
                  "errors": 0,
                  "compression_pct": 42,
                  "logs_url": "https://example.com/s1"
                }
              ]
            }
            """
        let stats = try decoder().decode(Stats.self, from: Data(json.utf8))
        XCTAssertEqual(stats.sessions, 4)
        XCTAssertEqual(stats.totals.requests, 38)
        XCTAssertEqual(stats.totals.cachedInputTokens, 24_000)
        XCTAssertEqual(stats.totals.compressionPct, 40)
        XCTAssertEqual(stats.recent.count, 1)
        XCTAssertEqual(stats.recent.first?.toolName, "Claude Code")
        XCTAssertEqual(stats.recent.first?.logsUrl, "https://example.com/s1")
    }

    func testStatsDecodingWithoutOptionalFields() throws {
        // `compression_pct` is omitted when there's nothing to report, and an
        // older edgee (pre-#182) omits `cached_input_tokens` entirely — both must
        // still decode rather than nil-ing the whole struct.
        let json = """
            {"sessions":0,"totals":{"requests":0,"errors":0,"input_tokens":0,
            "output_tokens":0,"token_cost_savings":0,
            "uncompressed_tools_tokens":0,"compressed_tools_tokens":0},"recent":[]}
            """
        let stats = try decoder().decode(Stats.self, from: Data(json.utf8))
        XCTAssertEqual(stats.sessions, 0)
        XCTAssertNil(stats.totals.compressionPct)
        XCTAssertNil(stats.totals.cachedInputTokens)
        XCTAssertTrue(stats.recent.isEmpty)
    }

    func testStatsDecodingApiSource() throws {
        // The API-sourced shape carries source/window/active_sessions.
        let json = """
            {"source":"api","window":"1h","sessions":12,"active_sessions":2,
            "totals":{"requests":241,"errors":3,"input_tokens":189000,
            "output_tokens":34000,"cached_input_tokens":3300000,"token_cost_savings":42,
            "uncompressed_tools_tokens":100,"compressed_tools_tokens":60,"compression_pct":40},
            "recent":[]}
            """
        let stats = try decoder().decode(Stats.self, from: Data(json.utf8))
        XCTAssertEqual(stats.source, "api")
        XCTAssertEqual(stats.window, "1h")
        XCTAssertEqual(stats.activeSessions, 2)
        XCTAssertEqual(stats.totals.cachedInputTokens, 3_300_000)
        // Local-shaped JSON (no source/window/active_sessions) leaves them nil.
        let local = try decoder().decode(
            Stats.self,
            from: Data(#"{"sessions":1,"recent":[],"totals":{"requests":1,"errors":0,"input_tokens":0,"output_tokens":0,"token_cost_savings":0,"uncompressed_tools_tokens":0,"compressed_tools_tokens":0}}"#.utf8))
        XCTAssertNil(local.source)
        XCTAssertNil(local.activeSessions)
    }

    func testAuthStatusDecoding() throws {
        let json = """
            {
              "logged_in": true,
              "profile": "default",
              "config_path": "/Users/x/.config/edgee/credentials.toml",
              "email": "clement@edgee.ai",
              "org_slug": "edgee",
              "providers": { "claude": { "configured": true, "mode": "plan" } }
            }
            """
        let status = try decoder().decode(AuthStatus.self, from: Data(json.utf8))
        XCTAssertTrue(status.loggedIn)
        XCTAssertEqual(status.email, "clement@edgee.ai")
        XCTAssertEqual(status.orgSlug, "edgee")
        XCTAssertEqual(status.providers["claude"]?.configured, true)
    }

    func testAuthStatusDecodingLoggedOut() throws {
        let json = """
            {"logged_in":false,"profile":"default","config_path":"/x","providers":{}}
            """
        let status = try decoder().decode(AuthStatus.self, from: Data(json.utf8))
        XCTAssertFalse(status.loggedIn)
        XCTAssertNil(status.email)
        XCTAssertNil(status.orgSlug)
    }

    func testProfileAndOrgDecoding() throws {
        let profiles = try decoder().decode(
            [Profile].self,
            from: Data(#"[{"name":"default","active":true,"email":"a@b.c","org_slug":"acme"}]"#.utf8))
        XCTAssertEqual(profiles.first?.name, "default")
        XCTAssertEqual(profiles.first?.active, true)

        let orgs = try decoder().decode(
            [Org].self,
            from: Data(#"[{"id":"o1","slug":"acme","name":"Acme","active":true}]"#.utf8))
        XCTAssertEqual(orgs.first?.slug, "acme")
    }

    func testConsoleURLIsOrgScoped() {
        XCTAssertEqual(
            Console.url(orgSlug: "edgee")?.absoluteString, "https://www.edgee.ai/~/edgee")
        XCTAssertEqual(
            Console.url(orgSlug: "acme-corp")?.absoluteString, "https://www.edgee.ai/~/acme-corp")
    }

    func testConsoleURLFallsBackToRootWithoutOrg() {
        for slug in [nil, "", "   "] as [String?] {
            XCTAssertEqual(
                Console.url(orgSlug: slug)?.absoluteString, "https://www.edgee.ai",
                "slug \(String(describing: slug)) should fall back to the root")
        }
    }

    func testConsoleURLEncodesAnUnexpectedSlug() {
        // Not a slug the API produces — asserts we percent-encode rather than
        // return nil (which would make the button do nothing).
        XCTAssertEqual(
            Console.url(orgSlug: "a b")?.absoluteString, "https://www.edgee.ai/~/a%20b")
    }
}
