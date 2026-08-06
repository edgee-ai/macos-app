import Foundation

/// A relay/launch target the menubar can drive via `edgee relay <id>`.
struct RelayTarget: Identifiable {
    /// The `edgee relay` argument (also the id).
    let id: String
    let name: String
    /// SF Symbol shown next to the row.
    let symbol: String
    /// Proxy-only (`--no-launch`) — for external clients like Claude Desktop.
    /// When false, the relay also launches the app.
    let proxyOnly: Bool
    /// App bundle paths used to detect installation. Empty = always available.
    let detectPaths: [String]

    var installed: Bool {
        if detectPaths.isEmpty { return true }
        return detectPaths.contains { FileManager.default.fileExists(atPath: $0) }
    }

    /// The installed app bundle path (first existing detectPath), used to render
    /// the app's real macOS icon. `nil` → fall back to the SF Symbol.
    var appBundlePath: String? {
        detectPaths.first { FileManager.default.fileExists(atPath: $0) }
    }

    private static func appPaths(_ name: String) -> [String] {
        [
            "/Applications/\(name)",
            "\(NSHomeDirectory())/Applications/\(name)",
        ]
    }

    /// The targets offered in the UI. Editors launch behind the relay; the
    /// proxy-only entry is for pointing an external app (Claude Desktop) at it.
    static let all: [RelayTarget] = [
        RelayTarget(
            id: "cursor", name: "Cursor", symbol: "cursorarrow.rays",
            proxyOnly: false, detectPaths: appPaths("Cursor.app")),
        RelayTarget(
            id: "copilot-vscode", name: "VS Code (Copilot)", symbol: "chevron.left.forwardslash.chevron.right",
            proxyOnly: false, detectPaths: appPaths("Visual Studio Code.app")),
        RelayTarget(
            id: "claude-desktop", name: "Claude Desktop", symbol: "network",
            proxyOnly: false, detectPaths: appPaths("Claude.app")),
    ]
}

enum RelayRunState: Equatable {
    case stopped
    case starting
    case running
    case failed(String)
}

/// Supervises `edgee relay` subprocesses — one per target — as headless
/// background processes (no shell/terminal). Owned at the App level so relays
/// survive the popover opening and closing.
@MainActor
final class RelayManager: ObservableObject {
    /// How long a relay must survive without exiting before we call it running.
    /// Fast failures (not logged in, port in use, bad provider) exit well within
    /// this window and flip straight to `.failed` instead.
    private static let readyGrace: Duration = .milliseconds(1200)

    /// Cap on retained log lines per target — enough to scroll back through a
    /// session without growing unbounded over a long-lived relay.
    private static let maxLogLines = 1000

    @Published private(set) var states: [String: RelayRunState] = [:]
    /// Per-target live log lines (merged stdout+stderr), for the window's console.
    @Published private(set) var logs: [String: [String]] = [:]
    private var processes: [String: Process] = [:]
    /// Ids we've asked to stop, so the termination handler can tell a
    /// user-requested shutdown from an unexpected exit/crash.
    private var stopping: Set<String> = []

    func state(_ id: String) -> RelayRunState { states[id] ?? .stopped }

    func log(_ id: String) -> [String] { logs[id] ?? [] }

    func clearLog(_ id: String) { logs[id] = [] }

    private func appendLog(_ id: String, _ line: String) {
        var lines = logs[id] ?? []
        lines.append(line)
        if lines.count > Self.maxLogLines {
            lines.removeFirst(lines.count - Self.maxLogLines)
        }
        logs[id] = lines
    }

    /// Strip ANSI SGR color escapes so the relay's colored log output renders as
    /// plain text in the console view.
    nonisolated static func stripANSI(_ line: String) -> String {
        guard line.contains("\u{1B}") else { return line }
        let scalars = Array(line.unicodeScalars)
        var result = String.UnicodeScalarView()
        var i = 0
        while i < scalars.count {
            if scalars[i] == "\u{1B}", i + 1 < scalars.count, scalars[i + 1] == "[" {
                i += 2
                while i < scalars.count, scalars[i] != "m" { i += 1 }
                i += 1  // consume the terminating 'm'
            } else {
                result.append(scalars[i])
                i += 1
            }
        }
        return String(result)
    }

    func toggle(_ target: RelayTarget) {
        switch state(target.id) {
        case .running, .starting:
            stop(target.id)
        case .stopped, .failed:
            start(target)
        }
    }

    func start(_ target: RelayTarget) {
        guard processes[target.id] == nil else { return }
        states[target.id] = .starting
        stopping.remove(target.id)
        logs[target.id] = []  // fresh log for this session

        var args = ["relay", target.id, "--non-interactive"]
        if target.proxyOnly { args.append("--no-launch") }

        let id = target.id
        guard let spawned = EdgeeCLI.spawn(args, onLine: { [weak self] line in
            let clean = RelayManager.stripANSI(line)
            Task { @MainActor in self?.appendLog(id, clean) }
        }) else {
            states[target.id] = .failed("could not start edgee")
            return
        }
        processes[target.id] = spawned.process

        spawned.process.terminationHandler = { [weak self] proc in
            let errText = spawned.stderr.text
            let status = proc.terminationStatus
            Task { @MainActor in
                guard let self else { return }
                self.processes[target.id] = nil
                if self.stopping.remove(target.id) != nil {
                    self.states[target.id] = .stopped
                } else {
                    // Exited on its own — surface the last stderr line as the cause.
                    let lastLine =
                        errText.split(whereSeparator: \.isNewline).last.map(String.init)
                        ?? "relay exited (code \(status))"
                    self.states[target.id] = .failed(lastLine)
                }
            }
        }

        // Promote to `.running` only after it survives the grace period; a fast
        // exit will already have flipped it to `.failed` via the handler.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.readyGrace)
            guard let self else { return }
            if self.processes[target.id] != nil, self.state(target.id) == .starting {
                self.states[target.id] = .running
            }
        }
    }

    func stop(_ id: String) {
        guard let process = processes[id] else { return }
        // SIGINT triggers the relay's graceful shutdown; the handler flips to
        // `.stopped` because we recorded the intent here.
        stopping.insert(id)
        process.interrupt()
    }

    func stopAll() {
        for (id, process) in processes {
            stopping.insert(id)
            process.interrupt()
        }
    }
}
