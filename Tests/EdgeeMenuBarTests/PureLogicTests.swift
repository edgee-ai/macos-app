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
}
