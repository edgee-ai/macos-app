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
            .font(.system(size: 10, weight: .bold))
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

// MARK: - Launch grid

/// The "Launch & relay" card: a 4-up grid of app tiles.
struct LaunchGrid: View {
    @EnvironmentObject private var relays: RelayManager

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 9), count: 4)

    private var runningCount: Int {
        RelayTarget.all.filter { relays.state($0.id) == .running }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel("Launch & relay")
                Spacer()
                Text(runningCount == 0 ? "none active" : "\(runningCount) active")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.secondaryText)
            }
            .padding(.bottom, 14)

            LazyVGrid(columns: columns, spacing: 9) {
                ForEach(RelayTarget.all) { target in
                    AppTile(target: target, state: relays.state(target.id)) {
                        relays.toggle(target)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 16)
        .padding(.bottom, 18)
        .cardSurface()
    }
}

/// One app in the launch grid — real app icon when installed, SF Symbol otherwise,
/// with a running/failed status dot in the corner. Every tile is the same size
/// (`TileMetrics`) so single- and two-line names line up across the grid.
struct AppTile: View {
    let target: RelayTarget
    let state: RelayRunState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 9) {
                icon.frame(width: 23, height: 23)
                Text(target.name)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.bodyText)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: TileMetrics.labelHeight, alignment: .top)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 4)
            .padding(.top, 14)
            .padding(.bottom, 12)
            .frame(height: TileMetrics.height)
            .background(Theme.tileBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.tileBorder, lineWidth: 1))
            .overlay(alignment: .topTrailing) { statusDot.padding(8) }
            .opacity(target.installed ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!target.installed || state == .starting)
        .help(helpText)
    }

    @ViewBuilder
    private var icon: some View {
        if let path = target.appBundlePath {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable()
        } else {
            Image(systemName: target.symbol)
                .resizable().scaledToFit()
                .foregroundStyle(Theme.secondaryText)
                .padding(1)
        }
    }

    @ViewBuilder
    private var statusDot: some View {
        switch state {
        case .running: PulseDot(color: Theme.running, diameter: 6)
        case .starting: PulseDot(color: .orange, diameter: 6)
        case .failed: PulseDot(color: .red, diameter: 6)
        case .stopped: EmptyView()
        }
    }

    private var helpText: String {
        if !target.installed { return "\(target.name) is not installed" }
        switch state {
        case .running: return "Stop \(target.name)"
        case .starting: return "Starting…"
        case .failed(let message): return "Failed: \(message)"
        case .stopped:
            return target.proxyOnly ? "Start relay for \(target.name)" : "Launch \(target.name)"
        }
    }
}

/// Shared launch-grid tile geometry, so every tile is identical in size.
enum TileMetrics {
    /// Two lines of the 10pt label — reserved on every tile so icons align.
    static let labelHeight: CGFloat = 26
    static let height: CGFloat = 84
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
                pill {
                    label(
                        initial: initial(status.email),
                        text: status.email ?? "Logged in", chevron: true)
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
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
