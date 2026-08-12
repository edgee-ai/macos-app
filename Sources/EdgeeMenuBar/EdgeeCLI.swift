import Foundation

/// Thin wrapper for shelling out to the `edgee` binary.
///
/// GUI apps don't inherit the user's shell `PATH`, so we resolve the binary from
/// a set of well-known locations and also augment `PATH` for any tools `edgee`
/// itself spawns. Override with the `EDGEE_BIN` environment variable.
enum EdgeeCLI {
    /// Absolute path to the edgee binary. Preference order:
    /// 1. `EDGEE_BIN` override, 2. the copy bundled inside Edgee.app (so the app
    /// always runs a CLI that matches its own version), 3. well-known install dirs.
    private static let resolvedBinary: String? = {
        let env = ProcessInfo.processInfo.environment
        if let override = env["EDGEE_BIN"], !override.isEmpty {
            return override
        }
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("edgee").path,
            FileManager.default.isExecutableFile(atPath: bundled)
        {
            return bundled
        }
        return searchDirs
            .map { "\($0)/edgee" }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }()

    /// Absolute path to the resolved edgee binary, if any — for building the
    /// AppleScript/shell command used to launch interactive agents in Terminal.
    static var binaryPath: String? { resolvedBinary }

    /// Fire-and-forget launch: spawn `edgee <args>` detached, no pipes, no wait.
    /// Used for one-shot launch targets (e.g. `launch codex-desktop`) where we
    /// don't supervise a long-running process. Returns false on launch failure.
    @discardableResult
    static func launchDetached(_ args: [String]) -> Bool {
        let process = makeProcess(args)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        return runReaped(process)
    }

    /// Spawn an arbitrary executable detached (augmented PATH, no pipes, no wait) —
    /// used to open a terminal emulator on the agent command. Returns false on
    /// launch failure so the caller can fall back.
    @discardableResult
    static func spawnDetached(executable: String, arguments: [String]) -> Bool {
        let process = Process()
        process.environment = childEnvironment()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        return runReaped(process)
    }

    /// Retains a fire-and-forget process until it exits, then releases it, so the
    /// child is reaped instead of left a zombie when the `Process` object would
    /// otherwise deallocate right after `run()`.
    private static let reaper = ProcessReaper()
    @discardableResult
    private static func runReaped(_ process: Process) -> Bool {
        reaper.retain(process)
        process.terminationHandler = { reaper.release($0) }
        do {
            try process.run()
        } catch {
            reaper.release(process)
            return false
        }
        return true
    }

    /// Directories prepended to `PATH` (and scanned for the binary).
    private static let searchDirs = [
        "\(NSHomeDirectory())/.local/bin",
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
    ]

    /// Environment for spawned processes: the app's env with an augmented `PATH`
    /// and the parent's Claude Code session markers stripped. An agent launched
    /// from the tray is a fresh top-level session, so it must not inherit
    /// `CLAUDE_CODE_CHILD_SESSION` (which silences the agent's own transcript
    /// saving) or the other `CLAUDE_CODE_*` markers of whatever launched the app.
    private static func childEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let existingPath = environment["PATH"] ?? ""
        environment["PATH"] = (searchDirs + [existingPath]).joined(separator: ":")
        for key in Array(environment.keys)
        where key == "CLAUDECODE" || key.hasPrefix("CLAUDE_CODE_") {
            environment.removeValue(forKey: key)
        }
        return environment
    }

    /// Decoder for every `--json` command. `.convertFromSnakeCase` maps the CLI's
    /// snake_case fields onto our camelCase models, so the model structs need no
    /// `CodingKeys`. (Note: this strategy also converts dictionary keys — see
    /// AuthStatus.providers.)
    private static let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    /// Run an edgee `--json` command off the main actor and decode its stdout.
    /// Returns nil if the command failed to run/exited non-zero or didn't decode.
    private static func runJSON<T: Decodable>(_ args: [String]) async -> T? {
        await Task.detached(priority: .userInitiated) {
            capture(args).flatMap { try? jsonDecoder.decode(T.self, from: $0) }
        }.value
    }

    /// Auth status via `edgee auth status --json`.
    static func authStatus() async -> AuthStatus? { await runJSON(["auth", "status", "--json"]) }

    /// Aggregated stats via `edgee stats --json`.
    static func stats(period: String = "1h", limit: Int = 20) async -> Stats? {
        // `--period` drives the API window when logged in; ignored (all-time local
        // logs) when logged out. The panel labels itself from the response's source.
        if let stats: Stats = await runJSON([
            "stats", "--json", "--period", period, "--limit", "\(limit)",
        ]) {
            return stats
        }
        // Older edgee (no `--period`) rejects the flag — fall back to a plain call.
        return await runJSON(["stats", "--json", "--limit", "\(limit)"])
    }

    /// Configured profiles via `edgee auth list --json`.
    static func profiles() async -> [Profile] { await runJSON(["auth", "list", "--json"]) ?? [] }

    /// The account's organizations via `edgee auth orgs --json` (network).
    static func orgs() async -> [Org] { await runJSON(["auth", "orgs", "--json"]) ?? [] }

    /// Headless browser login via `edgee auth login --non-interactive --json`.
    /// The subprocess opens the browser and blocks until the callback arrives.
    static func login() async -> LoginOutcome? {
        // Login blocks until the browser callback — or forever if the user abandons
        // it — so use a cancellable, time-bounded capture that terminates the
        // subprocess on timeout instead of pinning a concurrency-pool thread.
        let data = await captureAsync(
            ["auth", "login", "--non-interactive", "--json"], timeout: 300)
        return data.flatMap { try? jsonDecoder.decode(LoginOutcome.self, from: $0) }
    }

    /// Switch the active profile via `edgee auth switch <name>`. Returns success.
    @discardableResult
    static func switchProfile(_ name: String) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            capture(["auth", "switch", name]) != nil
        }.value
    }

    /// Switch the active profile's org via `edgee auth orgs --set <id|slug>`.
    @discardableResult
    static func switchOrg(_ idOrSlug: String) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            capture(["auth", "orgs", "--set", idOrSlug]) != nil
        }.value
    }

    /// Clear the active profile's credentials via `edgee auth logout`.
    @discardableResult
    static func logout() async -> Bool {
        await Task.detached(priority: .userInitiated) {
            capture(["auth", "logout"]) != nil
        }.value
    }

    /// Configure a `Process` to invoke edgee with an augmented PATH (so edgee and
    /// any editors it launches resolve), without running it.
    private static func makeProcess(_ args: [String]) -> Process {
        let process = Process()
        process.environment = childEnvironment()

        if let bin = resolvedBinary {
            process.executableURL = URL(fileURLWithPath: bin)
            process.arguments = args
        } else {
            // Last resort: let `env` resolve `edgee` off the augmented PATH.
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["edgee"] + args
        }
        return process
    }

    /// Run edgee and capture stdout. Returns nil on launch failure or non-zero exit.
    private static func capture(_ args: [String]) -> Data? {
        let process = makeProcess(args)
        let stdout = Pipe()
        process.standardOutput = stdout
        // We never read stderr here; discard it so a chatty command can't fill an
        // undrained pipe and deadlock while we block reading stdout.
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return data
    }

    /// Run edgee capturing stdout, cancellable and time-bounded. Used for `login`,
    /// which blocks until the browser callback (or never, if abandoned); on timeout
    /// or task cancellation the subprocess is terminated so it can't pin a thread.
    /// Returns nil on failure, timeout, or non-zero exit.
    private static func captureAsync(_ args: [String], timeout seconds: Double) async -> Data? {
        await withTaskGroup(of: Data?.self) { group in
            group.addTask { await runCapturing(args) }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil  // timeout sentinel
            }
            let result = await group.next() ?? nil
            group.cancelAll()  // cancels the loser → terminates the subprocess if it's still the capture
            return result
        }
    }

    /// One capture run: launch, then read stdout to EOF on a background queue (a
    /// single reader, so there's no race between a readability handler and a final
    /// read). Task cancellation terminates the process, which closes stdout and
    /// unblocks the read. `ProcessBox` covers the cancel-before-`run()` window.
    private static func runCapturing(_ args: [String]) async -> Data? {
        let process = makeProcess(args)
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = FileHandle.nullDevice
        let box = ProcessBox()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<Data?, Never>) in
                do {
                    try process.run()
                } catch {
                    cont.resume(returning: nil)
                    return
                }
                // If cancellation already arrived, tear it down now.
                if box.started(process) { process.terminate() }
                DispatchQueue.global(qos: .userInitiated).async {
                    let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    cont.resume(returning: process.terminationStatus == 0 ? data : nil)
                }
            }
        } onCancel: {
            box.cancel()
        }
    }

    /// Spawn a long-running edgee subprocess (e.g. a relay) in the background — no
    /// shell, no window. Both pipes are drained continuously so the child can't
    /// wedge on a full pipe; stdout is discarded and stderr feeds a bounded tail so
    /// the last error line is available as the failure cause. Returns the process
    /// and its stderr tail, or nil if it couldn't be launched.
    static func spawn(_ args: [String]) -> (process: Process, stderr: StderrTail)? {
        let process = makeProcess(args)

        let outPipe = Pipe()
        process.standardOutput = outPipe
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            if handle.availableData.isEmpty { handle.readabilityHandler = nil }  // drain & discard
        }

        let tail = StderrTail()
        let errPipe = Pipe()
        process.standardError = errPipe
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty { handle.readabilityHandler = nil } else { tail.append(chunk) }
        }

        do {
            try process.run()
        } catch {
            return nil
        }
        return (process, tail)
    }
}

/// A thread-safe, size-bounded accumulator for a subprocess's stderr — enough to
/// surface the last error line without letting the buffer grow unbounded over a
/// long-lived relay session.
final class StderrTail: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock()
        defer { lock.unlock() }
        data.append(chunk)
        if data.count > 8192 { data = data.suffix(4096) }
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        // Lossy decode: `suffix` may have truncated `data` mid-UTF-8, which would
        // make `String(data:encoding:)` return nil and drop the whole message.
        return String(decoding: data, as: UTF8.self)
    }
}

/// Coordinates cancel-vs-launch for a one-shot capture: if task cancellation
/// arrives before the process starts, the launch path terminates it immediately
/// so it can't outlive its awaiter.
final class ProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    /// Record the launched process; returns true if cancellation already arrived
    /// (so the caller should terminate it right away).
    func started(_ process: Process) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        self.process = process
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let process = self.process
        lock.unlock()
        process?.terminate()
    }
}

/// Retains fire-and-forget `Process` objects until they exit, so the child is
/// reaped rather than left a zombie when the object would deallocate after `run()`.
final class ProcessReaper: @unchecked Sendable {
    private let lock = NSLock()
    private var live = Set<Process>()
    func retain(_ process: Process) {
        lock.lock()
        defer { lock.unlock() }
        live.insert(process)
    }
    func release(_ process: Process) {
        lock.lock()
        defer { lock.unlock() }
        live.remove(process)
    }
}
