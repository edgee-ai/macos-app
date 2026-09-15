import AppKit
import SwiftUI

// Building blocks for the roomier (5b) menubar panel — cards, stat tiles, the
// token split, the launch grid, and the account pill. Kept together so the
// visual language (radii, borders, section labels) stays consistent.

// MARK: - Surfaces

extension View {
    /// A white card floating on the lilac panel: hairline border, soft shadow.
    func cardSurface(radius: CGFloat = 15) -> some View {
        background(Theme.cardFill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.cardBorder, lineWidth: 1))
            .shadow(color: Theme.ink.opacity(0.04), radius: 1.5, y: 1)
    }
}

/// Uppercase, letter-spaced muted caption that heads each section.
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(0.9)
            .foregroundStyle(Theme.labelMuted)
    }
}

/// A live status dot with a soft halo (green running, orange starting, red failed).
struct PulseDot: View {
    let color: Color
    var diameter: CGFloat = 7
    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.15)).frame(width: diameter + 9, height: diameter + 9)
            Circle().fill(color).frame(width: diameter, height: diameter)
        }
    }
}

// MARK: - Stat tiles

/// One KPI card: label over a large serif numeral, with an optional trailing dot.
struct StatTile: View {
    let label: String
    let value: String
    var dot: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(label)
            HStack(spacing: 10) {
                Text(value)
                    .font(Theme.serif(30))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                if let dot { PulseDot(color: dot) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 17)
        .cardSurface()
    }
}

/// Tokens in/out, split by a vanishing divider — up arrow (input, brand) and
/// down arrow (output, indigo), each with a small caption.
struct TokensCard: View {
    let inValue: String
    let inSub: String?
    let outValue: String
    let outSub: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Tokens")
            HStack(alignment: .center, spacing: 18) {
                half(
                    icon: "arrow.up", iconBg: Theme.tokenInBg, tint: Theme.tokenInTint,
                    value: inValue, sub: inSub, subColor: Theme.tokenInSub, subBold: true)
                Rectangle().fill(Theme.divider).frame(width: 1, height: 34)
                half(
                    icon: "arrow.down", iconBg: Theme.tokenOutBg, tint: Theme.tokenOutTint,
                    value: outValue, sub: outSub, subColor: Theme.secondaryText, subBold: false)
            }
            .padding(.top, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 18)
        .cardSurface()
    }

    private func half(
        icon: String, iconBg: Color, tint: Color, value: String, sub: String?,
        subColor: Color, subBold: Bool
    ) -> some View {
        HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(iconBg)
                .frame(width: 26, height: 26)
                .overlay(
                    Image(systemName: icon).font(.system(size: 12, weight: .bold))
                        .foregroundStyle(tint))
            VStack(alignment: .leading, spacing: 4) {
                Text(value).font(Theme.serif(22)).foregroundStyle(Theme.ink).lineLimit(1)
                if let sub {
                    Text(sub)
                        .font(.system(size: 10.5, weight: subBold ? .semibold : .regular))
                        .foregroundStyle(subColor)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Launch strip

/// The "Desktop apps" card: installed GUI apps only, in a 4-up grid.
struct LaunchStrip: View {
    @EnvironmentObject private var relays: RelayManager

    /// Chips before the rest collapse into `+N`.
    private static let inlineLimit = 6

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: ChipMetrics.spacing), count: 4)

    @State private var showingOverflow = false

    private var runningCount: Int {
        RelayTarget.installedDesktopApps.filter { relays.state($0.id) == .running }.count
    }

    private var unproxied: [RelayTarget] {
        RelayTarget.installedDesktopApps.filter(relays.isRunningWithoutProxy)
    }

    /// Installed desktop apps, running ones first — an active session is the thing you're
    /// most likely to want back, and it must never be the one hidden under `+N`.
    private var quickLinks: [RelayTarget] {
        let links = RelayTarget.installedDesktopApps
        let groups = Dictionary(grouping: links) { relays.state($0.id) != .stopped }
        return (groups[true] ?? []) + (groups[false] ?? [])
    }

    var body: some View {
        let links = quickLinks
        let inline = links.prefix(Self.inlineLimit)
        let overflow = Array(links.dropFirst(Self.inlineLimit))

        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel("Desktop apps")
                Spacer()
                Text(runningCount == 0 ? "none active" : "\(runningCount) active")
                    .font(.system(size: 11.5))
                    .foregroundStyle(unproxied.isEmpty ? Theme.secondaryText : .orange)
            }
            .padding(.bottom, 12)

            LazyVGrid(columns: columns, spacing: ChipMetrics.spacing) {
                ForEach(inline) { target in
                    AgentChip(
                        target: target, state: relays.state(target.id),
                        available: true, unproxied: relays.isRunningWithoutProxy(target)
                    ) {
                        relays.toggle(target)
                    }
                }

                if !overflow.isEmpty {
                    CountChip(label: "+\(overflow.count)") { showingOverflow = true }
                        .popover(isPresented: $showingOverflow, arrowEdge: .bottom) {
                            AgentList(title: "More agents") {
                                ForEach(overflow) { target in
                                    AgentRow(
                                        target: target, state: relays.state(target.id),
                                        available: true,
                                        unproxied: relays.isRunningWithoutProxy(target)
                                    ) {
                                        showingOverflow = false
                                        relays.toggle(target)
                                    }
                                }
                            }
                        }
                }

            }

            if !unproxied.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.orange)
                        .padding(.top, 1)
                    Text(unproxiedMessage)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.top, 10)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 16)
        .padding(.bottom, 16)
        .cardSurface()
    }

    private var unproxiedMessage: String {
        let names = unproxied.map(\.name).joined(separator: ", ")
        let verb = unproxied.count == 1 ? "is" : "are"
        return "\(names) \(verb) running without the Edgee proxy. Quit and relaunch here to route through Edgee."
    }
}

/// Shared chip geometry and surface, so the agent, overflow, and add chips are one
/// size and one shape.
enum ChipMetrics {
    /// Two lines of the 9.5pt label — reserved on every chip so icons align.
    static let labelHeight: CGFloat = 24
    static let height: CGFloat = 68
    static let radius: CGFloat = 10
    static let spacing: CGFloat = 8
    static let icon: CGFloat = 20
}

extension View {
    /// The chip's filled, hairline-bordered cell.
    func chipSurface(state: RelayRunState = .stopped) -> some View {
        frame(maxWidth: .infinity)
            .padding(.horizontal, 4)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .frame(height: ChipMetrics.height)
            .background(
                Theme.tileBg,
                in: RoundedRectangle(cornerRadius: ChipMetrics.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: ChipMetrics.radius, style: .continuous)
                    .strokeBorder(Theme.tileBorder, lineWidth: 1))
    }
}

/// One launchable agent: its real macOS icon when we have a bundle, else its SF
/// Symbol, over its name, with a running/failed dot in the corner. Every chip is the
/// same size (`ChipMetrics`), so one- and two-line names still line up across rows.
struct AgentChip: View {
    let target: RelayTarget
    let state: RelayRunState
    /// Detected on this machine. Only shades the chip back; it never disables it (see
    /// `RelayTarget.available`) — a hand-enrolled agent sits here undetected.
    let available: Bool
    var unproxied: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                AgentIcon(target: target, side: ChipMetrics.icon)
                Text(target.name)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(Theme.bodyText)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(
                        maxWidth: .infinity, minHeight: ChipMetrics.labelHeight, alignment: .top)
            }
            .chipSurface(state: state)
            .overlay(alignment: .topTrailing) { statusDot.padding(6) }
            .opacity(target.installed ? (available ? 1 : 0.72) : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!target.installed || state == .starting)
        .help(helpText)
    }

    @ViewBuilder
    private var statusDot: some View {
        if unproxied, state == .stopped {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.orange)
        } else {
            switch state {
            case .running: PulseDot(color: Theme.running, diameter: 6)
            case .starting: PulseDot(color: .orange, diameter: 6)
            case .failed: PulseDot(color: .red, diameter: 6)
            case .stopped: EmptyView()
            }
        }
    }

    private var helpText: String {
        if unproxied {
            return "\(target.name) is running without the Edgee proxy. Quit it and relaunch from here."
        }
        if !target.installed { return "\(target.name) is not installed" }
        if !available, state == .stopped {
            return "Launch \(target.name) — not detected on this machine"
        }
        switch state {
        case .running: return "Stop \(target.name)"
        case .starting: return "Starting \(target.name)…"
        case .failed(let message): return "\(target.name) failed: \(message)"
        case .stopped:
            return target.proxyOnly ? "Start relay for \(target.name)" : "Launch \(target.name)"
        }
    }
}

/// The `+N` overflow chip — same cell as an agent, so the grid stays even.
struct CountChip: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.bodyText)
                    .frame(height: ChipMetrics.icon)
                Text("more")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: ChipMetrics.labelHeight, alignment: .top)
            }
            .chipSurface()
        }
        .buttonStyle(.plain)
        .help("Show the rest of your agents")
    }
}

/// The dashed chip that opens the enroll list — dashed because, unlike its
/// neighbours, it isn't an agent.
struct AddChip: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(height: ChipMetrics.icon)
                Text("Enroll")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: ChipMetrics.labelHeight, alignment: .top)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 4)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .frame(height: ChipMetrics.height)
            .overlay(
                RoundedRectangle(cornerRadius: ChipMetrics.radius, style: .continuous)
                    .strokeBorder(
                        Theme.tileBorder, style: StrokeStyle(lineWidth: 1, dash: [3.5, 2.5])))
        }
        .buttonStyle(.plain)
        .help("Add or remove the coding agents Edgee routes for you")
    }
}

/// An agent's icon at a given size: the app's real macOS icon when it's installed,
/// else its SF Symbol.
struct AgentIcon: View {
    let target: RelayTarget
    let side: CGFloat

    var body: some View {
        if let path = target.appBundlePath {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .frame(width: side, height: side)
        } else {
            Image(systemName: target.symbol)
                .resizable().scaledToFit()
                .foregroundStyle(Theme.secondaryText)
                .frame(width: side - 2, height: side - 2)
        }
    }
}

/// The popover behind the `+N` and `+` chips: a titled list of agent rows.
struct AgentList<Rows: View>: View {
    let title: String
    @ViewBuilder let rows: Rows

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionLabel(title)
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
            rows
        }
        .padding(8)
        .frame(width: 218)
    }
}

/// One row in an agent popover: icon, name, and either a status dot or a checkmark
/// (the latter marks an agent the user enrolled, so clicking removes it).
struct AgentRow: View {
    let target: RelayTarget
    let state: RelayRunState
    let available: Bool
    var unproxied: Bool = false
    var checked: Bool = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                AgentIcon(target: target, side: 17)
                    .frame(width: 26, height: 26)
                    .background(
                        Theme.tileBg, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text(target.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.bodyText)
                    .lineLimit(1)
                Spacer(minLength: 6)
                trailing
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                hovering ? Theme.tileBg : .clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(target.installed ? (available || checked ? 1 : 0.7) : 0.45)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!target.installed || state == .starting)
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var trailing: some View {
        if unproxied, state == .stopped {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.orange)
        } else if checked {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.brand)
        } else {
            switch state {
            case .running: PulseDot(color: Theme.running, diameter: 6)
            case .starting: PulseDot(color: .orange, diameter: 6)
            case .failed: PulseDot(color: .red, diameter: 6)
            case .stopped: EmptyView()
            }
        }
    }
}

// MARK: - Account pill

/// The rounded account chip in the header: switches org/profile when logged in,
/// offers a login when not.
struct AccountPill: View {
    @EnvironmentObject private var model: MenuModel

    var body: some View {
        if model.loading && model.status == nil {
            pill { label(initial: "…", text: "Checking…") }
                .allowsHitTesting(false)
        } else if let status = model.status, status.loggedIn {
            Menu {
                if model.orgs.count > 1 {
                    Section("Organization") {
                        ForEach(model.orgs) { org in
                            switchButton(org.name, active: org.active) {
                                Task { await model.switchOrg(org.slug) }
                            }
                        }
                    }
                }
                if model.profiles.count > 1 {
                    Section("Profile") {
                        ForEach(model.profiles) { profile in
                            switchButton(profile.name, active: profile.active) {
                                Task { await model.switchProfile(profile.name) }
                            }
                        }
                    }
                }
                Divider()
                Button("Refresh") { Task { await model.reload() } }
                Button("Log out", role: .destructive) { Task { await model.logout() } }
            } label: {
                Text(initial(status.email))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 30, height: 30)
                    .background(Theme.pillBg, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.pillBorder, lineWidth: 1))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 34)
            .help(status.email ?? "Account")
            .accessibilityLabel("Account")
            .disabled(model.switching)
        } else {
            Button { Task { await model.login() } } label: {
                pill {
                    if model.loggingIn {
                        HStack(spacing: 7) {
                            ProgressView().controlSize(.small)
                            Text("Opening…").font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.bodyText)
                        }
                    } else {
                        label(initial: "?", text: "Log in", chevron: false)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(model.loggingIn)
        }
    }

    private func switchButton(_ name: String, active: Bool, _ act: @escaping () -> Void)
        -> some View
    {
        Button {
            guard !active else { return }
            act()
        } label: {
            if active { Label(name, systemImage: "checkmark") } else { Text(name) }
        }
    }

    private func pill<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.leading, 5)
            .padding(.trailing, 10)
            .padding(.vertical, 4)
            .background(Theme.pillBg, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.pillBorder, lineWidth: 1))
            .frame(maxWidth: 215)
    }

    private func label(initial: String, text: String, chevron: Bool = false) -> some View {
        HStack(spacing: 8) {
            Text(initial)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 21, height: 21)
                .background(Theme.brandGradient, in: Circle())
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.bodyText)
                .lineLimit(1)
                .truncationMode(.middle)
            if chevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private func initial(_ email: String?) -> String {
        guard let c = email?.first else { return "?" }
        return String(c).uppercased()
    }
}
