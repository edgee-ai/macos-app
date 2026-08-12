import AppKit
import SwiftUI

/// The dropdown panel shown when the menubar icon is clicked — the roomier (5b)
/// "Edgee Menubar" design: a lilac card with an account pill, last-hour stats,
/// a token split, and the launch/relay grid. Data + actions live in `MenuModel`
/// and `RelayManager`.
struct MenuContentView: View {
    @EnvironmentObject private var model: MenuModel
    @EnvironmentObject private var relays: RelayManager

    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue
    @Environment(\.colorScheme) private var systemScheme

    private var appearance: Appearance { Appearance(rawValue: appearanceRaw) ?? .system }
    /// The scheme the panel actually renders in (explicit choice, else the OS's).
    private var resolvedScheme: ColorScheme { appearance.colorScheme ?? systemScheme }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header.padding(.bottom, 6)
            if isLoggedIn {
                lastHour
                statTiles
                tokens
                LaunchGrid()
                openConsole
            } else if model.status == nil && model.loading {
                loadingView
            } else {
                loggedOutView
            }
            footer.padding(.top, 2)
        }
        .padding(14)
        .frame(width: 380)
        .background {
            ZStack {
                LinearGradient(
                    colors: [Theme.panelTop, Theme.panelBottom],
                    startPoint: .top, endPoint: .bottom)
                RadialGradient(
                    colors: [Theme.brand.opacity(resolvedScheme == .dark ? 0.45 : 0.22), .clear],
                    center: .topLeading, startRadius: 0, endRadius: 190)
                RadialGradient(
                    colors: [Theme.indigo.opacity(resolvedScheme == .dark ? 0.40 : 0.18), .clear],
                    center: .topTrailing, startRadius: 0, endRadius: 190)
            }
            .ignoresSafeArea()
        }
        .environment(\.colorScheme, resolvedScheme)
        .preferredColorScheme(appearance.colorScheme)
        .task { await model.reload() }
    }

    private var isLoggedIn: Bool { model.status?.loggedIn == true }

    // MARK: Logged-out / loading

    /// Cold-start placeholder while the first `auth status` is in flight.
    private var loadingView: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Checking…").font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    /// Stripped state when logged out: nothing but a login call-to-action. Stats
    /// and the launch grid need an account, so we don't tease them here.
    private var loggedOutView: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 34))
                .foregroundStyle(Theme.secondaryText)
            VStack(spacing: 4) {
                Text("Log in to Edgee")
                    .font(Theme.serif(17))
                    .foregroundStyle(Theme.ink)
                Text("See your usage and launch agents through the gateway.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button { Task { await model.login() } } label: {
                HStack(spacing: 8) {
                    if model.loggingIn {
                        ProgressView().controlSize(.small)
                        Text("Opening browser…")
                    } else {
                        Text("Log in")
                    }
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity)
                .background(
                    Theme.brandGradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(model.loggingIn)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
        .padding(.bottom, 18)
        .padding(.horizontal, 10)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Theme.brandGradient)
                .frame(width: 30, height: 30)
                .overlay(
                    Image(nsImage: AppIcons.menuBar)
                        .renderingMode(.template).resizable().scaledToFit()
                        .frame(width: 15, height: 17)
                        .foregroundStyle(.white))
                .shadow(color: Theme.brand.opacity(0.4), radius: 6, y: 3)
            Text("Edgee")
                .font(Theme.serif(19))
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 8)
            AccountPill()
            appearanceButton
        }
    }

    /// Cycles the panel appearance: system → light → dark. The icon reflects the
    /// current choice.
    private var appearanceButton: some View {
        Button {
            appearanceRaw = appearance.next.rawValue
        } label: {
            Image(systemName: appearance.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 26, height: 26)
                .background(Theme.pillBg, in: Circle())
                .overlay(Circle().strokeBorder(Theme.pillBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("Appearance: \(appearance.label) — click to change")
    }

    // MARK: Stats

    private var lastHour: some View {
        HStack(alignment: .firstTextBaseline) {
            SectionLabel(windowLabel)
            Spacer()
            Text(sessionsLabel)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.horizontal, 4)
    }

    private var statTiles: some View {
        let active = activeTile
        return HStack(spacing: 12) {
            StatTile(label: "Requests", value: requestsValue)
            StatTile(label: active.label, value: active.value, dot: active.on ? Theme.running : nil)
        }
    }

    private var tokens: some View {
        TokensCard(
            inValue: tokenValue(\.inputTokens),
            inSub: cachedSub,
            outValue: tokenValue(\.outputTokens),
            outSub: "generated")
    }

    // MARK: Actions

    private var openConsole: some View {
        Button {
            if let url = URL(string: "https://www.edgee.ai") { NSWorkspace.shared.open(url) }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "macwindow").font(.system(size: 13, weight: .semibold))
                Text("Open Edgee Console").font(.system(size: 13, weight: .semibold))
                Text("⌘O").font(.system(size: 11)).opacity(0.75)
            }
            .foregroundStyle(.white)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity)
            .background(
                Theme.brandGradient, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .shadow(color: Theme.brand.opacity(0.5), radius: 9, y: 3)
        }
        .buttonStyle(.plain)
        .keyboardShortcut("o", modifiers: .command)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button {
                relays.stopAll()
                NSApplication.shared.terminate(nil)
            } label: {
                HStack(spacing: 3) {
                    Text("Quit")
                    Text("⌘Q").opacity(0.7)
                }
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .font(.system(size: 12))
        .buttonStyle(.plain)
        .foregroundStyle(Theme.secondaryText)
        .padding(.horizontal, 6)
    }

    // MARK: Derived values

    private var runningCount: Int {
        RelayTarget.all.filter { relays.state($0.id) == .running }.count
    }

    /// Section label reflecting where the stats came from: the API's time window
    /// when logged in, or all-time local logs otherwise (so "Last hour" is never
    /// a lie).
    private var windowLabel: String {
        guard model.stats?.source == "api", let window = model.stats?.window else {
            return "All sessions"
        }
        switch window {
        case "1h": return "Last hour"
        case "3h": return "Last 3 hours"
        case "6h": return "Last 6 hours"
        case "24h": return "Last 24 hours"
        case "7d": return "Last 7 days"
        case "30d": return "Last 30 days"
        default: return "Last \(window)"
        }
    }

    /// The second KPI tile: real online-session count from the API when available,
    /// otherwise the local count of running relays.
    private var activeTile: (label: String, value: String, on: Bool) {
        if let active = model.stats?.activeSessions {
            return ("Active sessions", "\(active)", active > 0)
        }
        let n = runningCount
        return ("Active relays", "\(n)", n > 0)
    }

    private var sessionsLabel: String {
        guard let n = model.stats?.sessions else { return "—" }
        return "\(n) session\(n == 1 ? "" : "s")"
    }

    private var requestsValue: String {
        guard let r = model.stats?.totals.requests else { return "—" }
        return r.formatted()
    }

    private func tokenValue(_ key: KeyPath<Stats.Totals, UInt64>) -> String {
        guard let totals = model.stats?.totals else { return "—" }
        return TokenFormat.short(totals[keyPath: key])
    }

    private var cachedSub: String? {
        guard let cached = model.stats?.totals.cachedInputTokens, cached > 0 else { return nil }
        return "\(TokenFormat.short(cached)) cached"
    }
}
