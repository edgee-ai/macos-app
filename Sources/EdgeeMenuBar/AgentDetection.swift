import Foundation

/// Which CLI coding agents are actually present on this machine.
///
/// GUI targets are detected from their app bundle (`RelayTarget.detectPaths`), but a
/// terminal agent is just a binary on the user's `PATH` — and a GUI app inherits
/// launchd's environment, not the shell's, so `ProcessInfo`'s `PATH` is the stub
/// `/usr/bin:/bin`. We therefore ask the user's login shell for its `PATH` the same
/// way `RelayManager` launches agents (including the `__…` guard-variable dance, see
/// `RelayManager.openInTerminal`), then scan it plus the usual install dirs.
///
/// Advisory only, and deliberately so: a version manager (mise, asdf, volta) can put
/// an agent behind a shim we never see, and the login shell can refuse to answer. A
/// target we fail to detect is sorted to the back of the launch grid but stays
/// clickable — the CLI is the one that decides whether an agent is installed, and it
/// says so on stderr, which the tile already surfaces.
enum AgentDetection {
    /// The subset of `commands` found as an executable in the user's search path.
    /// Blocking (it runs a login shell); call it off the main actor.
    static func detect(_ commands: [String]) -> Set<String> {
        let dirs = searchDirs()
        let fm = FileManager.default
        return Set(
            commands.filter { command in
                dirs.contains { fm.isExecutableFile(atPath: "\($0)/\(command)") }
            })
    }

    /// Login-shell `PATH` entries first, then the well-known install dirs — so a
    /// shell that won't answer degrades to a decent guess instead of "nothing found".
    private static func searchDirs() -> [String] {
        var seen = Set<String>()
        return (loginShellPath() + fallbackDirs).filter { seen.insert($0).inserted }
    }

    private static var fallbackDirs: [String] {
        let home = NSHomeDirectory()
        return [
            "\(home)/.local/bin",
            "\(home)/.bun/bin",
            "\(home)/.cargo/bin",
            "\(home)/.deno/bin",
            "\(home)/.volta/bin",
            "\(home)/.npm-global/bin",
            "\(home)/.nix-profile/bin",
            "\(home)/go/bin",
            "/run/current-system/sw/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
        ]
    }

    /// `PATH` as the user's login shell sees it, split into directories. Empty if the
    /// shell fails, times out, or prints nothing usable.
    private static func loginShellPath() -> [String] {
        let script = """
            for v in $(/usr/bin/env | /usr/bin/sed -n 's/^\\(__[A-Za-z0-9_]*\\)=.*/\\1/p'); do
                unset "$v"
            done
            exec \(shellQuoted(loginShell())) -lc 'printf %s "$PATH"'
            """
        guard let path = capture("/bin/sh", ["-c", script]) else { return [] }
        return path.split(separator: ":").map(String.init).filter { $0.hasPrefix("/") }
    }

    /// The user's `$SHELL` when it runs our command line as written, else macOS's
    /// default — same reasoning (and same list) as the launch path in `RelayManager`.
    static func loginShell() -> String {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? ""
        // Absolute only: a bare `SHELL=fish` would have to resolve against the stub
        // `PATH` the app runs under, which is the thing we're working around.
        guard shell.hasPrefix("/") else { return "/bin/zsh" }
        return posixLoginShells.contains(URL(fileURLWithPath: shell).lastPathComponent)
            ? shell : "/bin/zsh"
    }

    /// Login shells that run the command line as written. The exotic ones get this
    /// subtly wrong: nu treats `"$PATH"` as a literal, csh/tcsh honour `-l` only when
    /// it's the sole flag and so quietly drop the login shell the whole trick needs.
    private static let posixLoginShells: Set<String> = [
        "zsh", "bash", "sh", "dash", "ksh", "fish",
    ]

    /// Single-quote a string for POSIX `sh`.
    static func shellQuoted(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// How long the login shell gets to print its `PATH` before we give up. A slow
    /// `.zshrc` is common; a wedged one shouldn't cost more than this.
    private static let timeout: TimeInterval = 5

    /// Run a short-lived command and return its trimmed stdout, or nil on failure,
    /// timeout, or a non-zero exit.
    private static func capture(_ executable: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }

        // Read on this thread and bound the *wait*: a login shell that never exits
        // would otherwise park us for good. The read unblocks when the terminated
        // process closes its end of the pipe.
        let exited = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            guard exited.wait(timeout: .now() + timeout) != .success else { return }
            process.terminate()
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        exited.signal()

        guard process.terminationStatus == 0 else { return nil }
        let text = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
