import Foundation

/// Decoded from `edgee stats --json` (`StatsJson` in crates/cli/src/commands/stats.rs).
/// Field names come across via `.convertFromSnakeCase` (see EdgeeCLI) — no CodingKeys.
struct Stats: Codable {
    let sessions: Int
    let totals: Totals
    let recent: [SessionBrief]
    /// "api" (this account's usage in its org, windowed) or "local" (this
    /// machine's logs). Absent on older CLIs → treated as local.
    let source: String?
    /// The API time window (e.g. "1h") when `source == "api"`.
    let window: String?
    /// Live online-session count for this account from the API when logged in.
    let activeSessions: UInt64?

    struct Totals: Codable {
        let requests: UInt64
        let errors: UInt64
        let inputTokens: UInt64
        let outputTokens: UInt64
        // Optional so `stats --json` from an older edgee (pre-`cached_input_tokens`)
        // still decodes instead of nil-ing the whole struct — the UI just hides
        // the "cached" sub-line when it's absent.
        let cachedInputTokens: UInt64?
        /// Estimated model spend in US dollars. Optional so an older external CLI
        /// can still populate the rest of the dashboard.
        let costUsd: Double?
        let tokenCostSavings: UInt64
        let uncompressedToolsTokens: UInt64
        let compressedToolsTokens: UInt64
        let compressionPct: UInt64?
    }

    struct SessionBrief: Codable, Identifiable {
        let sessionId: String
        let toolName: String
        let endedAt: String
        let endedAtUnix: Int64
        let requests: UInt64
        let inputTokens: UInt64
        let outputTokens: UInt64
        let errors: UInt64
        let costUsd: Double?
        let compressionPct: UInt64?
        let logsUrl: String

        var id: String { sessionId }
    }
}

enum CostFormat {
    /// Compact USD amount for a KPI tile. A precise sub-cent value does not fit
    /// in the three-column layout, so distinguish it from a true zero with a bound.
    static func usd(_ value: Double) -> String {
        if value > 0 && value < 0.01 { return "<$0.01" }
        return String(format: "$%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}

enum TokenFormat {
    /// Compact token count: 61410 → "61k", 1681 → "1.7k", 2_500_000 → "2.5M".
    static func short(_ value: UInt64) -> String {
        let v = Double(value)
        switch value {
        case 1_000_000...:
            return trim(v / 1_000_000, suffix: "M")
        case 1_000...:
            return trim(v / 1_000, suffix: "k")
        default:
            return "\(value)"
        }
    }

    private static func trim(_ value: Double, suffix: String) -> String {
        if value >= 100 || value == value.rounded() {
            return "\(Int(value.rounded()))\(suffix)"
        }
        return String(format: "%.1f%@", value, suffix)
    }
}
