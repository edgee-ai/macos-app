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
    /// Executable name marking a CLI agent as installed, looked up in the user's
    /// search path by `AgentDetection`. nil for GUI targets (they use `detectPaths`).
    let detectCommand: String?
    /// How tapping the tile drives this target.
    let mode: LaunchMode

    var installed: Bool {
        if detectPaths.isEmpty { return true }
        return detectPaths.contains { FileManager.default.fileExists(atPath: $0) }
    }

    /// Whether we can see this target on the machine — a GUI bundle that exists, or a
    /// CLI whose binary turned up in `detected`. Drives ordering only: unlike
    /// `installed`, a false here never disables the tile, because CLI detection can't
    /// see behind a version-manager shim (see `AgentDetection`).
    func available(detected: Set<String>) -> Bool {
        if let detectCommand { return detected.contains(detectCommand) }
        return installed
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

    /// The targets offered in the UI, in the order they appear when nothing is
    /// detected — the terminal coding agents first (that's what most of this is for),
    /// then the GUI apps. `ordered(detected:)` promotes what the user actually has.
    ///
    /// Ids are the CLI's own `edgee launch <id>` subcommands, and every terminal agent
    /// happens to ship a binary named after its id.
    static let all: [RelayTarget] = [
        RelayTarget(
            id: "claude", name: "Claude Code", symbol: "asterisk.circle",
            proxyOnly: false, detectPaths: [], detectCommand: "claude", mode: .terminalAgent),
        RelayTarget(
            id: "codex", name: "Codex", symbol: "terminal",
            proxyOnly: false, detectPaths: [], detectCommand: "codex", mode: .terminalAgent),
        RelayTarget(
            id: "opencode", name: "OpenCode", symbol: "curlybraces",
            proxyOnly: false, detectPaths: [], detectCommand: "opencode", mode: .terminalAgent),
        RelayTarget(
            id: "crush", name: "Crush", symbol: "wand.and.stars",
            proxyOnly: false, detectPaths: [], detectCommand: "crush", mode: .terminalAgent),
        RelayTarget(
            id: "codebuddy", name: "CodeBuddy", symbol: "cube",
            proxyOnly: false, detectPaths: [], detectCommand: "codebuddy", mode: .terminalAgent),
        RelayTarget(
            id: "pi", name: "Pi", symbol: "function",
            proxyOnly: false, detectPaths: [], detectCommand: "pi", mode: .terminalAgent),
        RelayTarget(
            id: "kimi", name: "Kimi Code", symbol: "moon.stars",
            proxyOnly: false, detectPaths: [], detectCommand: "kimi", mode: .terminalAgent),
        RelayTarget(
            id: "kilo", name: "Kilo Code", symbol: "scalemass",
            proxyOnly: false, detectPaths: [], detectCommand: "kilo", mode: .terminalAgent),
        RelayTarget(
            id: "cursor", name: "Cursor", symbol: "cursorarrow.rays",
            proxyOnly: false, detectPaths: appPaths("Cursor.app"), detectCommand: nil,
            mode: .relay),
        RelayTarget(
            id: "copilot-vscode", name: "VS Code (Copilot)",
            symbol: "chevron.left.forwardslash.chevron.right",
            proxyOnly: false, detectPaths: appPaths("Visual Studio Code.app"),
            detectCommand: nil, mode: .relay),
        RelayTarget(
            id: "claude-desktop", name: "Claude Desktop", symbol: "network",
            proxyOnly: false, detectPaths: appPaths("Claude.app"), detectCommand: nil,
            mode: .relay),
        RelayTarget(
            id: "codex-desktop", name: "Codex Desktop", symbol: "sparkles",
            proxyOnly: false, detectPaths: appPaths("ChatGPT.app"), detectCommand: nil,
            mode: .launch),
    ]

    /// The launch card's two halves: the quick links — what we can see on this
    /// machine, plus anything the user enrolled by hand — and the rest, offered under
    /// "enroll" instead of spending a tile on an agent they don't have. Each half
    /// keeps its declared order.
    ///
    /// All-or-nothing fallback: if nothing is detected and nothing is enrolled
    /// (detection hasn't landed yet, or the login shell wouldn't answer) every target
    /// is a quick link — an empty grid reads as broken, and an enroll menu holding the
    /// entire roster isn't a shortlist.
    static func split(
        _ targets: [RelayTarget] = all, detected: Set<String>, enrolled: Set<String>
    ) -> (quickLinks: [RelayTarget], enrollable: [RelayTarget]) {
        let groups = Dictionary(grouping: targets) {
            $0.available(detected: detected) || enrolled.contains($0.id)
        }
        guard let quickLinks = groups[true], !quickLinks.isEmpty else { return (targets, []) }
        return (quickLinks, groups[false] ?? [])
    }
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
    /// Executable names of the CLI agents found on this machine, so the launch grid
    /// can show the ones the user actually has. Empty until detection lands.
    @Published private(set) var detectedAgents: Set<String> = []
    /// Ids the user pinned via "enroll an agent" — quick links even when detection
    /// can't see them, which covers both an agent behind a version-manager shim and
    /// one they're about to install. Persisted, since enrolling reads as a choice that
    /// should stick.
    @Published private(set) var enrolled: Set<String> = RelayManager.loadEnrolled()
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
        refreshDetection()
    }

    private func applyDetection(_ found: Set<String>) { detectedAgents = found }

    private static let enrolledKey = "enrolledTargets"

    private static func loadEnrolled() -> Set<String> {
        let stored = UserDefaults.standard.stringArray(forKey: enrolledKey) ?? []
        // Drop ids we no longer ship, so a target renamed or removed between versions
        // can't keep a phantom tile in the grid.
        let known = Set(RelayTarget.all.map(\.id))
        return Set(stored).intersection(known)
    }

    /// Pin a target as a quick link and run it straight away — enrolling is what the
    /// user does *in order to* launch something, so it shouldn't take two clicks. It
    /// also has to become a tile first: the run's status dot and failure tooltip live
    /// there, and the CLI's "not installed, install it with…" is exactly what someone
    /// enrolling an agent they don't have yet needs to see.
    func enroll(_ target: RelayTarget) {
        enrolled.insert(target.id)
        UserDefaults.standard.set(Array(enrolled), forKey: Self.enrolledKey)
        toggle(target)
    }

    /// Drop a hand-enrolled quick link. A detected agent stays in the grid regardless
    /// — detection, not this set, is what put it there.
    func unenroll(_ id: String) {
        guard enrolled.remove(id) != nil else { return }
        UserDefaults.standard.set(Array(enrolled), forKey: Self.enrolledKey)
    }

    /// Look up which CLI agents are installed. Runs a login shell, so it's kept off
    /// the main actor; the grid re-sorts when the result arrives. Cheap enough to
    /// repeat when the panel opens — an agent installed mid-session should show up.
    func refreshDetection() {
        let commands = RelayTarget.all.compactMap(\.detectCommand)
        Task.detached(priority: .utility) { [weak self] in
            let found = AgentDetection.detect(commands)
            await self?.applyDetection(found)
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
            launchOneShot(target)
        case .terminalAgent:
            openInTerminal(target.id)
        }
    }

    /// One-shot `edgee launch <id>` for a GUI app target. It exits in well under a
    /// second, so there is nothing to supervise — but it very much can *fail*, and
    /// the common case is not an edge case: `edgee launch codex-desktop` writes its
    /// managed block into the agent's config and then `open`s the app, so if that
    /// app is already running the open just hands off to the existing instance,
    /// which isn't routed through Edgee. The CLI detects that, explains it on
    /// stderr, and exits non-zero.
    ///
    /// So this is spawned with pipes and its exit status checked, rather than
    /// fire-and-forget: swallowing stderr and ignoring the status left the tile
    /// showing nothing at all on the click that fails most often — the button
    /// looked broken. On a clean exit we drop straight back to `.stopped` (there's
    /// no lasting process to represent); otherwise the CLI's own last stderr line
    /// becomes the tile's failure reason.
    private func launchOneShot(_ target: RelayTarget) {
        guard processes[target.id] == nil else { return }
        let id = target.id
        states[id] = .starting
        stopping.remove(id)

        guard let spawned = EdgeeCLI.spawn(["launch", id]) else {
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
                // A quit-time `stopAll` may have interrupted it mid-launch; that's
                // a shutdown, not a failure the user needs to see.
                if self.stopping.remove(id) != nil || status == 0 {
                    self.states[id] = .stopped
                } else {
                    // Read the tail after the actor hop, as in `start`, so the
                    // stderr handler has had a chance to append the final chunk.
                    self.states[id] =
                        .failed(
                            tail.text.split(whereSeparator: \.isNewline).last.map(String.init)
                                ?? "launch exited (code \(status))")
                }
            }
        }
    }

    /// Run `edgee launch <id>` in the user's terminal — interactive coding agents
    /// need a TTY, so they can't run headless like the relay targets do.
    ///
    /// We write the command to a `.command` script, then place it in a terminal —
    /// first reachable option wins:
    ///
    /// 1. A running kitty with remote control enabled → a new OS window inside the
    ///    user's own instance (`kitten @ launch`). Nothing new is started.
    /// 2. kitty installed but not reachable → an instance of our own, isolated in
    ///    `--instance-group edgee` and told to quit with its last window.
    /// 3. Otherwise → **LaunchServices**, which routes the `.command` to whatever app
    ///    handles shell scripts (Terminal.app unless the user changed it).
    ///
    /// Except for kitty's remote-control client — which only talks to a socket and
    /// exits, leaving the agent parented to the user's kitty — nothing here is spawned
    /// as a child of Edgee.app. A child would make Edgee.app the TCC "responsible
    /// process" for anything the terminal/shell/tools touch (e.g. the Media Library),
    /// so permission prompts would be attributed to Edgee.app. Reparenting to launchd
    /// lets the terminal own its own permissions.
    ///
    /// Getting `PATH` right takes two steps, both load-bearing — without them `edgee`
    /// reports the agent as "not installed" whenever it lives somewhere the system
    /// doesn't know about (nix, homebrew, npm):
    ///
    /// 1. Re-exec through `$SHELL -lc`. Terminal runs a `.command` directly, with a
    ///    near-empty `PATH` (`/usr/bin:/bin` + `/etc/paths.d`) and no login shell,
    ///    despite the prompt it echoes into the window.
    /// 2. First drop the exported `__…` guard variables. launchd's environment keeps
    ///    them (`__NIX_DARWIN_SET_ENVIRONMENT_DONE`, `__HM_SESS_VARS_SOURCED`,
    ///    `__ETC_ZSHENV_SOURCED`, …) while *not* keeping the `PATH` they went with, so
    ///    a login shell sees "already sourced", skips the setup, and step 1 alone
    ///    yields the same stub `PATH`.
    ///
    /// Step 2 replaces an older scheme that detected emulators (Ghostty, kitty, …) and
    /// drove each by argv in a plain new application instance. Don't go back to that:
    /// kitty is one macOS app instance per bundle, so the instance *we* start ends up
    /// owning the OS windows the user opens later — with our environment and our
    /// lifetime. The instance group plus `macos_quit_when_last_window_closed` is what
    /// keeps our instance out of their session.
    private func openInTerminal(_ id: String) {
        guard let edgee = EdgeeCLI.binaryPath,
            let script = Self.writeLaunchScript(edgee: edgee, id: id)
        else { return }
        let kitty = Self.kittyApp
        // Probing kitty's socket means spawning its client and waiting on it, so this
        // runs on a GCD thread — off the main actor (it's a menubar click) and off the
        // cooperative pool, which a blocking wait would starve.
        DispatchQueue.global(qos: .userInitiated).async {
            let handedOff = kitty.map { Self.launchInRunningKitty($0, script: script) } ?? false
            Task { @MainActor in
                if handedOff {
                    Self.activateKitty()
                } else if let kitty {
                    Self.launchNewKitty(kitty, script: script)
                } else {
                    NSWorkspace.shared.open(script)
                }
            }
        }
    }

    /// The `.command` script both kitty and the default handler run. Returns nil if it
    /// can't be written.
    private static func writeLaunchScript(edgee: String, id: String) -> URL? {
        let shell = AgentDetection.loginShell()
        // `cd "$HOME"` because a GUI-launched terminal can start us in `/`.
        let command = "cd \"$HOME\" && exec \(AgentDetection.shellQuoted(edgee)) launch \(id)"
        let script = """
            #!/bin/sh
            # Shell-startup guards without the PATH they belong to — see above.
            for v in $(/usr/bin/env | /usr/bin/sed -n 's/^\\(__[A-Za-z0-9_]*\\)=.*/\\1/p'); do
                unset "$v"
            done
            exec \(AgentDetection.shellQuoted(shell)) -lc \(AgentDetection.shellQuoted(command))

            """

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("edgee-launch-\(id).command")
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: url.path)
        } catch {
            return nil
        }
        return url
    }

    private static let kittyBundleID = "net.kovidgoyal.kitty"

    /// The instance `launchNewKitty` started, so `activateKitty` can tell the user's
    /// kitty from ours when both are running. The app object rather than its pid: ours
    /// quits with its last window, and a bare pid would go on matching whatever the
    /// system recycled it for.
    private static var edgeeKitty: NSRunningApplication?

    /// Where kitty is installed, if it is. LaunchServices knows about non-standard
    /// locations (nix, home-manager) that a path scan would miss.
    private static var kittyApp: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: kittyBundleID)
    }

    /// Open the script in a new OS window of a *running* kitty via remote control,
    /// which the user has to opt into (`allow_remote_control` + `listen_on` in
    /// `kitty.conf`). False if there's no reachable socket — the common case.
    ///
    /// Not to be confused with `--single-instance`: that only hands off to an instance
    /// which was *itself* started with the flag, so for a kitty the user launched
    /// normally it silently starts a second instance instead of reusing theirs.
    private nonisolated static func launchInRunningKitty(_ app: URL, script: URL) -> Bool {
        let kitten = app.appendingPathComponent("Contents/MacOS/kitten")
        guard FileManager.default.isExecutableFile(atPath: kitten.path) else { return false }
        for socket in kittySockets() {
            let address = "unix:\(socket.path)"
            guard run(kitten, ["@", "--to", address, "ls"]) else { continue }
            if run(
                kitten,
                [
                    "@", "--to", address, "launch", "--type=os-window",
                    "--cwd=\(NSHomeDirectory())", "/bin/sh", script.path,
                ])
            {
                return true
            }
        }
        return false
    }

    /// Sockets kitty may be listening on. `listen_on` points wherever the user says,
    /// with a `{kitty_pid}` placeholder in the conventional spelling, so we collect
    /// `kitty*` sockets from the two usual directories and let the caller probe them.
    ///
    /// Ours only: `/tmp` is world-writable, and handing the agent to a socket another
    /// account is listening on would hand them the session with it.
    private nonisolated static func kittySockets() -> [URL] {
        let fm = FileManager.default
        return [fm.temporaryDirectory, URL(fileURLWithPath: "/tmp")]
            .flatMap { (try? fm.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)) ?? [] }
            .filter { url in
                guard url.lastPathComponent.hasPrefix("kitty") else { return false }
                var info = stat()
                // `lstat`: a symlink planted in /tmp would otherwise pass the ownership
                // check on whatever it points at.
                guard lstat(url.path, &info) == 0 else { return false }
                return (info.st_mode & S_IFMT) == S_IFSOCK && info.st_uid == getuid()
            }
    }

    /// Start our own kitty instance, kept out of the user's way: its own instance
    /// group (so it never merges with or hands off to theirs) and quitting with its
    /// last window (so it isn't left around to adopt windows they open later).
    /// Repeated launches land in this same instance as extra OS windows.
    ///
    /// The isolation is not total, and can't be: while our instance is alive, it is a
    /// running kitty, so LaunchServices may route the user's own Dock/Spotlight open to
    /// it and their window lands here. Quitting with the last agent window is what keeps
    /// that to the length of a session instead of indefinitely.
    @MainActor
    private static func launchNewKitty(_ app: URL, script: URL) {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        config.activates = true
        config.arguments = [
            "-o", "macos_quit_when_last_window_closed=yes",
            // No socket of our own: the user's `listen_on` applies to this instance too,
            // so it would race theirs for the same path — and then our own socket could
            // be the one the next launch finds and hands the agent to.
            "-o", "allow_remote_control=no",
            "--single-instance", "--instance-group", "edgee",
            "/bin/sh", script.path,
        ]
        NSWorkspace.shared.openApplication(at: app, configuration: config) { running, error in
            Task { @MainActor in
                guard error == nil else {
                    // kitty refused to launch → default shell-script handler.
                    NSWorkspace.shared.open(script)
                    return
                }
                // On a repeat launch this is the `--single-instance` forwarder, already
                // gone by the time we're called (LaunchServices reports it with a dead
                // or `-1` pid). Keeping the instance we recorded is the point.
                guard let running, running.processIdentifier > 0, !running.isTerminated
                else { return }
                edgeeKitty = running
            }
        }
    }

    /// Bring kitty forward after handing it a window over the socket, which doesn't
    /// raise the app on its own. Prefers an instance that isn't the one we started:
    /// the window went to the user's, and `runningApplications` is unordered, so with
    /// one of ours still open it would otherwise be a coin flip which one comes up.
    @MainActor
    private static func activateKitty() {
        let instances = NSRunningApplication.runningApplications(withBundleIdentifier: kittyBundleID)
        var candidates = instances
        if let ours = edgeeKitty, !ours.isTerminated {
            candidates.removeAll { $0.processIdentifier == ours.processIdentifier }
        }
        (candidates.first ?? instances.first)?.activate()
    }

    /// How long a remote-control client gets before we give up on it.
    private static let kittenTimeout: TimeInterval = 5

    /// Run a short-lived command to completion, true on a clean exit. For kitty's
    /// remote-control client only: it round-trips a socket, so the wait is brief, and
    /// the timeout is there for a socket that accepts but never answers.
    private nonisolated static func run(_ executable: URL, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do {
            try process.run()
        } catch {
            return false
        }
        guard exited.wait(timeout: .now() + kittenTimeout) == .success else {
            // Wedged on a socket that accepts but never answers. Ask it to go, then
            // insist — waiting on `SIGTERM` alone would park this thread for good.
            process.terminate()
            if exited.wait(timeout: .now() + 1) != .success {
                kill(process.processIdentifier, SIGKILL)
            }
            return false
        }
        return process.terminationStatus == 0
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
