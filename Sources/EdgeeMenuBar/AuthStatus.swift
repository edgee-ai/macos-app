import Foundation

// These mirror the CLI's `--json` output. Decoding uses
// JSONDecoder.keyDecodingStrategy = .convertFromSnakeCase (see EdgeeCLI), so
// snake_case JSON fields map onto these camelCase properties automatically — no
// CodingKeys needed. The CLI's contract tests (crates/cli/src/commands/auth/*)
// guard the field names against drift.
//
// Caveat: `.convertFromSnakeCase` also transforms *dictionary* keys, so the keys
// of `AuthStatus.providers` (claude/codex/opencode/crush) must stay
// underscore-free.

/// Decoded from `edgee auth status --json`.
struct AuthStatus: Codable {
    let loggedIn: Bool
    let profile: String
    let configPath: String
    let email: String?
    let orgSlug: String?
    let providers: [String: ProviderStatus]
}

struct ProviderStatus: Codable {
    let configured: Bool
    let mode: String?
}

/// One entry from `edgee auth list --json` (`ProfileEntry` in the CLI).
struct Profile: Codable, Identifiable {
    let name: String
    let active: Bool
    let email: String?
    let orgSlug: String?

    var id: String { name }
}

/// One entry from `edgee auth orgs --json` (`OrgEntry` in the CLI).
struct Org: Codable, Identifiable {
    let id: String
    let slug: String
    let name: String
    let active: Bool
}

/// The Edgee web console.
enum Console {
    static let base = "https://www.edgee.ai"

    /// The console URL to open for an org. The console scopes everything under
    /// `/~/<org-slug>`; the bare host only redirects there once the *browser* has
    /// a session and a last-used org, so sending a signed-in user to the root can
    /// land them somewhere other than the org the tray is reporting on. Falls back
    /// to the root when we have no slug (logged out, or org not yet chosen) —
    /// there's nothing better to guess, and the console will sort them out.
    static func url(orgSlug: String?) -> URL? {
        guard let slug = orgSlug?.trimmingCharacters(in: .whitespacesAndNewlines),
            !slug.isEmpty,
            // Slugs are lowercase alphanumeric + hyphen, so this is belt-and-braces
            // against a surprising one silently producing a nil URL below.
            let encoded = slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return URL(string: base) }
        return URL(string: "\(base)/~/\(encoded)")
    }
}

/// Decoded from `edgee auth login --non-interactive --json` (`LoginOutcome`).
struct LoginOutcome: Codable {
    let loggedIn: Bool
    let email: String?
    let orgSlug: String?
    let needsOrgSelection: Bool
}
