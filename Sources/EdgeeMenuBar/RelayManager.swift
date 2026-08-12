import AppKit
import Foundation

/// How a target is driven from the tray.
enum LaunchMode {
    /// Supervised, headless `edgee relay <id>` — GUI apps that talk to the relay.
    case relay
    /// One-shot `edgee launch <id>` — a GUI app launcher (e.g. codex-desktop).
    case launch
    /// Interactive `edgee launch <id>` opened in Terminal — TUI coding agents.
    case terminalAgent
}

/// A relay/launch target the menubar can drive via the `edgee` CLI.
struct RelayTarget: Identifiable {
    /// The `edgee relay`/`edgee launch` argument (also the id).
    let id: String
    let name: String
    /// SF Symbol shown next to the row.
    let symbol: String
    /// Proxy-only (`--no-launch`) — for external clients like Claude Desktop.
    /// When false, the relay also launches the app. (relay mode only.)
    let proxyOnly: Bool
    /// App bundle paths used to detect installation. Empty = always available.
    let detectPaths: [String]
    /// How tapping the tile drives this target.
    let mode: LaunchMode

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
            id: "claude", name: "Claude Code", symbol: "asterisk.circle",
            proxyOnly: false, detectPaths: [], mode: .terminalAgent),
        RelayTarget(
            id: "claude-desktop", name: "Claude Desktop", symbol: "network",
            proxyOnly: false, detectPaths: appPaths("Claude.app"), mode: .relay),
        RelayTarget(
            id: "codex", name: "Codex", symbol: "terminal",
            proxyOnly: false, detectPaths: [], mode: .terminalAgent),
        RelayTarget(
            id: "codex-desktop", name: "Codex Desktop", symbol: "sparkles",
            proxyOnly: false, detectPaths: appPaths("ChatGPT.app"), mode: .launch),
        RelayTarget(
            id: "cursor", name: "Cursor", symbol: "cursorarrow.rays",
            proxyOnly: false, detectPaths: appPaths("Cursor.app"), mode: .relay),
        RelayTarget(
            id: "copilot-vscode", name: "VS Code (Copilot)", symbol: "chevron.left.forwardslash.chevron.right",
            proxyOnly: false, detectPaths: appPaths("Visual Studio Code.app"), mode: .relay),
        RelayTarget(
            id: "opencode", name: "OpenCode", symbol: "curlybraces",
            proxyOnly: false, detectPaths: [], mode: .terminalAgent),
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

    @Published private(set) var states: [String: RelayRunState] = [:]
    private var processes: [String: Process] = [:]
    /// Ids we've asked to stop, so the termination handler can tell a
    /// user-requested shutdown from an unexpected exit/crash.
    private var stopping: Set<String> = []

    private var terminationObserver: (any NSObjectProtocol)?

    init() {
        // Relays are detached background processes, so tear them down on the
        // normal quit paths (⌘Q, logout, shutdown) via AppKit's terminate
        // notification — not just the panel's Quit button. (A hard `kill`/SIGKILL
        // can't be intercepted; those relays are reaped by launchd at exit.)
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopAll() }
        }
    }

    deinit {
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
    }

    func state(_ id: String) -> RelayRunState { states[id] ?? .stopped }

    func toggle(_ target: RelayTarget) {
        switch target.mode {
        case .relay:
            switch state(target.id) {
            case .running, .starting: stop(target.id)
            case .stopped, .failed: start(target)
            }
        case .launch:
            EdgeeCLI.launchDetached(["launch", target.id])
        case .terminalAgent:
            openInTerminal(target.id)
        }
    }

    /// Run `edgee launch <id>` in the user's terminal — interactive coding agents
    /// need a TTY, so they can't run headless like the relay targets do.
    ///
    /// We first look for an installed terminal emulator we know how to drive from
    /// the CLI (kitty, Ghostty, WezTerm, Alacritty) and launch it directly on the
    /// agent command. If none is found we fall back to opening a `.command` script
    /// via LaunchServices — i.e. whatever app is the default handler for shell
    /// scripts (typically Terminal.app). Either way the command runs through a
    /// login shell so the user's real `PATH` (nix, homebrew, …) applies.
    private func openInTerminal(_ id: String) {
        guard let edgee = EdgeeCLI.binaryPath else { return }
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        // One argv element for the shell. `cd "$HOME"` first because a GUI-launched
        // app inherits CWD `/`, so the agent would otherwise start at the root.
        let command = "cd \"$HOME\" && exec '\(edgee)' launch \(id)"
        let runInShell = [shell, "-lc", command]

        if let term = Self.resolveTerminal(),
            EdgeeCLI.spawnDetached(executable: term.bin, arguments: term.prefix + runInShell)
        {
            return
        }
        openViaCommandFile(edgee: edgee, id: id)
    }

    /// A terminal emulator binary plus the argv prefix that makes it run a program.
    private struct TerminalSpec {
        let bin: String
        let prefix: [String]
    }

    /// First installed terminal we know how to launch a command in. `nil` → none,
    /// so the caller falls back to the LaunchServices `.command` handler.
    private static func resolveTerminal() -> TerminalSpec? {
        let home = NSHomeDirectory()
        let dirs = [
            "\(home)/.nix-profile/bin",
            "/run/current-system/sw/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(home)/.local/bin",
            "/usr/bin",
        ]
        // (cli name, .app name, argv prefix before the program to run)
        let candidates: [(name: String, app: String, prefix: [String])] = [
            ("ghostty", "Ghostty", ["-e"]),
            ("kitty", "kitty", ["--detach"]),
            ("wezterm", "WezTerm", ["start", "--"]),
            ("alacritty", "Alacritty", ["-e"]),
        ]
        let fm = FileManager.default
        for c in candidates {
            let paths =
                dirs.map { "\($0)/\(c.name)" } + [
                    "/Applications/\(c.app).app/Contents/MacOS/\(c.name)",
                    "\(home)/Applications/\(c.app).app/Contents/MacOS/\(c.name)",
                    "\(home)/Applications/Home Manager Apps/\(c.app).app/Contents/MacOS/\(c.name)",
                ]
            if let bin = paths.first(where: { fm.isExecutableFile(atPath: $0) }) {
                return TerminalSpec(bin: bin, prefix: c.prefix)
            }
        }
        return nil
    }

    /// Fallback: write a `.command` script and open it via LaunchServices (routes
    /// to the default shell-script handler, usually Terminal.app).
    private func openViaCommandFile(edgee: String, id: String) {
        let script = "#!/bin/sh\ncd \"$HOME\"\nexec '\(edgee)' launch \(id)\n"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("edgee-launch-\(id).command")
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: url.path)
        } catch {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func start(_ target: RelayTarget) {
        guard processes[target.id] == nil else { return }
        states[target.id] = .starting
        stopping.remove(target.id)

        var args = ["relay", target.id, "--non-interactive"]
        if target.proxyOnly { args.append("--no-launch") }

        let id = target.id
        guard let spawned = EdgeeCLI.spawn(args) else {
            states[id] = .failed("could not start edgee")
            return
        }
        processes[id] = spawned.process

        spawned.process.terminationHandler = { [weak self] proc in
            let status = proc.terminationStatus
            let tail = spawned.stderr
            Task { @MainActor in
                guard let self else { return }
                self.processes[id] = nil
                if self.stopping.remove(id) != nil {
                    self.states[id] = .stopped
                } else {
                    // Read the tail after the actor hop so the stderr readability
                    // handler has had a chance to append the final chunk first
                    // (best-effort — a race here only yields a less specific line).
                    let lastLine =
                        tail.text.split(whereSeparator: \.isNewline).last.map(String.init)
                        ?? "relay exited (code \(status))"
                    self.states[id] = .failed(lastLine)
                }
            }
        }

        // Promote to `.running` only after it survives the grace period; a fast
        // exit will already have flipped it to `.failed` via the handler.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.readyGrace)
            guard let self else { return }
            if self.processes[id] != nil, self.state(id) == .starting {
                self.states[id] = .running
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
