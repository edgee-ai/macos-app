import AppKit
import SwiftUI

/// The window's Relays panel: every launch/relay target with start/stop controls,
/// plus a live log console for the selected target — the depth the menubar row
/// can't show.
struct RelaysView: View {
    @EnvironmentObject private var model: MenuModel
    @EnvironmentObject private var relays: RelayManager

    @State private var selected: String = RelayTarget.all.first?.id ?? ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.status?.loggedIn == true {
                targetList
                Divider()
                console
            } else {
                ContentUnavailableCompat(
                    title: "Log in to use the relay",
                    message: "Sign in from the sidebar to launch apps and start the relay.",
                    symbol: "person.crop.circle.badge.questionmark")
            }
        }
        .navigationTitle("Relays")
    }

    // MARK: Targets

    private var targetList: some View {
        VStack(spacing: 0) {
            ForEach(RelayTarget.all) { target in
                row(target)
                if target.id != RelayTarget.all.last?.id { Divider() }
            }
        }
        .padding(.vertical, 4)
    }

    private func row(_ target: RelayTarget) -> some View {
        let state = relays.state(target.id)
        return HStack(spacing: 12) {
            icon(for: target).frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(target.name)
                Text(subtitle(target, state))
                    .font(.caption).foregroundStyle(state.isFailed ? .red : .secondary)
                    .lineLimit(1)
            }
            Spacer()
            dot(state)
            Button(buttonTitle(state)) { relays.toggle(target) }
                .disabled(!target.installed || state == .starting)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(selected == target.id ? Color.accentColor.opacity(0.12) : .clear)
        .contentShape(Rectangle())
        .onTapGesture { selected = target.id }
    }

    private func subtitle(_ target: RelayTarget, _ state: RelayRunState) -> String {
        if case let .failed(message) = state { return message }
        if !target.installed { return "Not installed" }
        switch state {
        case .running: return target.proxyOnly ? "Proxy running" : "Running"
        case .starting: return "Starting…"
        default: return target.proxyOnly ? "Point this app at the relay" : "Ready to launch"
        }
    }

    // MARK: Console

    private var console: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Logs · \(selectedName)", systemImage: "terminal")
                    .font(.headline)
                Spacer()
                Button {
                    relays.clearLog(selected)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Clear log")
                .disabled(relays.log(selected).isEmpty)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)

            LogConsole(lines: relays.log(selected))
        }
    }

    private var selectedName: String {
        RelayTarget.all.first { $0.id == selected }?.name ?? "—"
    }

    // MARK: Bits

    @ViewBuilder
    private func icon(for target: RelayTarget) -> some View {
        if let path = target.appBundlePath {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable()
        } else {
            Image(systemName: target.symbol).foregroundStyle(.secondary)
        }
    }

    private func buttonTitle(_ state: RelayRunState) -> String {
        switch state {
        case .running: return "Stop"
        case .starting: return "…"
        case .stopped, .failed: return "Start"
        }
    }

    @ViewBuilder
    private func dot(_ state: RelayRunState) -> some View {
        let color: Color =
            switch state {
            case .running: .green
            case .starting: .orange
            case .failed: .red
            case .stopped: .secondary
            }
        Circle().fill(color).frame(width: 8, height: 8)
    }
}

private extension RelayRunState {
    var isFailed: Bool { if case .failed = self { return true }; return false }
}

/// A monospaced, auto-scrolling log view that pins to the newest line as output
/// streams in.
struct LogConsole: View {
    let lines: [String]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if lines.isEmpty {
                    Text("No output yet. Start this target to see its live log.")
                        .font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                } else {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            Text(line.isEmpty ? " " : line)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(12)
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: lines.count) { _, _ in
                withAnimation(.linear(duration: 0.1)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }
}

/// Minimal stand-in for `ContentUnavailableView` (macOS 15+) so the empty state
/// works on our macOS 14 baseline.
struct ContentUnavailableCompat: View {
    let title: String
    let message: String
    let symbol: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.largeTitle).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}
