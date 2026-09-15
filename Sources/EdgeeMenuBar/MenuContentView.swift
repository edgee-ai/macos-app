import AppKit
import SwiftUI

/// Usage dashboard and agent launcher backed by live CLI data.
struct MenuContentView: View {
    @EnvironmentObject private var model: MenuModel
    @EnvironmentObject private var relays: RelayManager

    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue
    @Environment(\.colorScheme) private var systemScheme

    /// The panel's own window, so a log out can dismiss the panel (see
    /// `PanelWindowReader`).
    @State private var panelWindow: NSWindow?
    @State private var selectedTab = "Overview"

    private var appearance: Appearance { Appearance(rawValue: appearanceRaw) ?? .system }
    /// The scheme the panel actually renders in (explicit choice, else the OS's).
    private var resolvedScheme: ColorScheme { appearance.colorScheme ?? systemScheme }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header.padding(.bottom, 6)
            if model.status == nil && model.loading {
                loadingView
            } else if !isLoggedIn {
                loggedOutView
            } else if needsOrg {
                orgPickerView
            } else {
                navigation
                if selectedTab == "Overview" {
                    lastHour
                    spendCard
                    tokenBreakdown
                } else {
                    if RelayTarget.installedDesktopApps.isEmpty {
                        Text("No supported desktop agents installed.")
                            .font(Theme.font(size: 13))
                            .foregroundStyle(Theme.secondaryText)
                            .frame(maxWidth: .infinity, minHeight: 160)
                    } else {
                        LaunchStrip()
                    }
                }
            }
            footer.padding(.top, 2)
        }
        .padding(20)
        .frame(width: 420)
        // Let MenuBarExtra resize its window to the current tab and async data,
        // rather than centering a shorter card inside the previous window size.
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.panelTop)
        .environment(\.colorScheme, resolvedScheme)
        .preferredColorScheme(appearance.colorScheme)
        .background(PanelWindowReader { panelWindow = $0 })
        // Dismiss the panel after logging out of the current account.
        .onChange(of: model.logoutCount) { panelWindow?.close() }
        .task { await model.reload() }
    }

    private var isLoggedIn: Bool { model.status?.loggedIn == true }

    /// Logged in but no org chosen yet (multi-org accounts land here after login,
    /// since the CLI doesn't auto-pick). The dashboard needs an org, so gate it.
    private var needsOrg: Bool { isLoggedIn && (model.status?.orgSlug?.isEmpty ?? true) }

    // MARK: Logged-out / loading

    /// Cold-start placeholder while the first `auth status` is in flight.
    private var loadingView: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Checking…").font(Theme.font(size: 12)).foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    /// Stripped state when logged out: nothing but a login call-to-action. Stats
    /// and the launch grid need an account, so we don't tease them here.
    private var loggedOutView: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(Theme.font(size: 34))
                .foregroundStyle(Theme.secondaryText)
            VStack(spacing: 4) {
                Text("Log in to Edgee")
                    .font(Theme.serif(17))
                    .foregroundStyle(Theme.ink)
                Text("See your usage and launch agents through the gateway.")
                    .font(Theme.font(size: 12))
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
                .font(Theme.font(size: 13, weight: .semibold))
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

    // MARK: Org selection

    /// Initial org picker for multi-org accounts (post-login, before an org is
    /// set). Switching between orgs later happens in the account pill.
    private var orgPickerView: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Choose an organization")
            if model.orgs.isEmpty {
                Text("No organizations found. Create one in the console to continue.")
                    .font(Theme.font(size: 12))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                openConsole
            } else {
                ForEach(model.orgs) { org in
                    Button { Task { await model.switchOrg(org.slug) } } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(org.name)
                                    .font(Theme.font(size: 13, weight: .semibold))
                                    .foregroundStyle(Theme.ink)
                                Text(org.slug)
                                    .font(Theme.font(size: 11))
                                    .foregroundStyle(Theme.secondaryText)
                            }
                            Spacer()
                            if model.switching {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(Theme.font(size: 11, weight: .bold))
                                    .foregroundStyle(Theme.secondaryText)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .cardSurface(radius: 12)
                    }
                    .buttonStyle(.plain)
                    .disabled(model.switching)
                }
            }
        }
        .padding(.top, 2)
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
            Text("edgee")
                .font(Theme.font(size: 24, weight: .bold))
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
                .font(Theme.font(size: 12, weight: .semibold))
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
                .font(Theme.font(size: 11.5))
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.horizontal, 4)
    }

    private var navigation: some View {
        HStack(spacing: 0) {
            ForEach(["Overview", "Agents"], id: \.self) { tab in
                Button { selectedTab = tab } label: {
                    Text(tab)
                        .font(Theme.font(size: 13, weight: .semibold))
                        .foregroundStyle(selectedTab == tab ? Theme.ink : Theme.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(selectedTab == tab ? Theme.accent : .clear)
                                .frame(height: 2)
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 1) }
        .padding(.bottom, 6)
    }

    private var spendCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                SectionLabel("Total spend")
                Spacer()
                Text("USD").font(Theme.font(size: 11))
                    .foregroundStyle(Theme.secondaryText)
            }
            Text(costValue)
                .font(Theme.font(size: 44, weight: .medium)).monospacedDigit()
                .foregroundStyle(Theme.ink)
            Rectangle().fill(Theme.divider).frame(height: 1)
            HStack {
                metric("Requests", value: requestsValue)
                Spacer()
                metric("Active", value: activeTile.value)
                Spacer()
                metric("Cache share", value: cacheShare)
            }
        }
        .padding(18)
        .cardSurface()
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(title)
            Text(value).font(Theme.font(size: 22, weight: .medium)).monospacedDigit()
                .foregroundStyle(Theme.ink)
        }
    }

    private var cacheShare: String {
        guard let totals = model.stats?.totals,
            let share = CacheShare.fraction(input: totals.inputTokens, cached: totals.cachedInputTokens, cacheWrite: totals.cacheCreationInputTokens ?? 0)
        else { return "—" }
        return share.formatted(.percent.precision(.fractionLength(0)))
    }

    private var tokenBreakdown: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionLabel("Token breakdown")
                Spacer()
                Text("VOLUME").font(Theme.font(size: 10))
                    .foregroundStyle(Theme.secondaryText)
            }
            if let totals = model.stats?.totals {
                let segments: [(String, Double, Color)] = [
                    ("Input", Double(totals.inputTokens), Theme.input),
                    ("Cache write", Double(totals.cacheCreationInputTokens ?? 0), Theme.cacheWrite),
                    ("Cached input", Double(totals.cachedInputTokens ?? 0), Theme.cached),
                    ("Output", Double(totals.outputTokens - min(totals.outputTokens, totals.reasoningOutputTokens ?? 0)), Theme.output),
                    ("Reasoning", Double(min(totals.outputTokens, totals.reasoningOutputTokens ?? 0)), Theme.reasoning),
                ]
                let visibleSegments = segments.filter { $0.1 > 0 }
                let total = visibleSegments.reduce(0) { $0 + $1.1 }
                if total > 0 {
                    GeometryReader { geometry in
                        let minimum = min(3, geometry.size.width / Double(visibleSegments.count))
                        let remaining = max(0, geometry.size.width - minimum * Double(visibleSegments.count))
                        HStack(spacing: 0) {
                            ForEach(visibleSegments, id: \.0) { segment in
                                Rectangle().fill(segment.2)
                                    .frame(width: minimum + remaining * segment.1 / total)
                                    .help("\(segment.0): \(segment.1.formatted(.number.precision(.fractionLength(0)))) tokens")
                            }
                        }
                        .clipShape(Capsule())
                    }
                    .frame(height: 6)
                    .help("Small segments have a minimum display width. Token counts are exact.")
                    .accessibilityLabel("Input, cache write, cached input, output, and reasoning token distribution")
                }
            }
            tokenRow("Input", value: tokenValue(\.inputTokens), color: Theme.input)
            if let written = model.stats?.totals.cacheCreationInputTokens {
                tokenRow("Cache write", value: TokenFormat.short(written), color: Theme.cacheWrite)
            }
            if let cached = model.stats?.totals.cachedInputTokens {
                tokenRow("Cached input", value: TokenFormat.short(cached), color: Theme.cached)
            }
            tokenRow("Output", value: tokenValue(\.outputTokens), color: Theme.output)
            if let reasoning = model.stats?.totals.reasoningOutputTokens {
                tokenRow("Reasoning (included in output)", value: TokenFormat.short(reasoning), color: Theme.reasoning)
            }
        }
        .padding(18)
        .cardSurface()
    }

    private func tokenRow(_ label: String, value: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(label).font(Theme.font(size: 13))
            Spacer()
            Text(value).font(Theme.font(size: 13))
                .foregroundStyle(Theme.secondaryText)
        }
        .foregroundStyle(Theme.bodyText)
    }

    // MARK: Actions

    private var openConsole: some View {
        Button {
            if let url = Console.url(orgSlug: model.status?.orgSlug) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            Label("Console", systemImage: "arrow.up.right")
                .font(Theme.font(size: 12))
                .foregroundStyle(Theme.secondaryText)
        }
        .buttonStyle(.plain)
        .keyboardShortcut("o", modifiers: .command)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Button { Task { await model.reload() } } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh usage")
            .disabled(model.loading || model.statsLoading)
            openConsole
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
        .font(Theme.font(size: 12))
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

    /// The active KPI: real online-session count from the API when available,
    /// otherwise the local count of running relays.
    private var activeTile: (value: String, on: Bool) {
        if let active = model.stats?.activeSessions {
            return ("\(active)", active > 0)
        }
        let n = runningCount
        return ("\(n)", n > 0)
    }

    private var sessionsLabel: String {
        guard let n = model.stats?.sessions else { return "—" }
        return "\(n) session\(n == 1 ? "" : "s")"
    }

    private var requestsValue: String {
        guard let r = model.stats?.totals.requests else { return "—" }
        return r.formatted()
    }

    private var costValue: String {
        guard let cost = model.stats?.totals.costUsd else { return "—" }
        return CostFormat.usd(cost)
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

/// Hands back the window hosting the panel. `MenuBarExtra(.window)` exposes no
/// way to dismiss its panel — `@Environment(\.dismiss)` is a no-op inside it —
/// so we reach the window through a zero-sized AppKit view in the background.
private struct PanelWindowReader: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        // The view has no window until it's in the hierarchy, so read it after
        // this layout pass.
        DispatchQueue.main.async { onWindow(view.window) }
        return view
    }

    /// The panel gets a fresh window on each open, so re-read on every update.
    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { onWindow(view.window) }
    }
}
