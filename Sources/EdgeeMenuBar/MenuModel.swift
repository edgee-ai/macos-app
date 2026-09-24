import SwiftUI

/// Owns the panel's data and its CLI-backed actions. Held at the App level so
/// state is cached across popover opens — a reopen refreshes in the background
/// instead of blanking the UI.
@MainActor
final class MenuModel: ObservableObject {
    @Published private(set) var status: AuthStatus?
    @Published private(set) var stats: Stats?
    @Published private(set) var profiles: [Profile] = []
    @Published private(set) var orgs: [Org] = []
    @Published private(set) var loading = true
    @Published private(set) var statsLoading = true
    @Published private(set) var loggingIn = false
    @Published private(set) var switching = false
    /// Bumped after each explicit log out. `MenuContentView` watches it to
    /// dismiss the panel — swapping the dashboard for the much shorter login
    /// card in place leaves the panel's window at its old size.
    @Published private(set) var logoutCount = 0
    private var refreshTask: Task<Void, Never>?
    private var reloadGeneration = 0

    init() {
        // App-owned polling continues while the dropdown is closed.
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.reload()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    deinit { refreshTask?.cancel() }

    var lastRequestWasRerouted: Bool {
        status?.loggedIn == true && !switching && stats?.source == "api"
            && stats?.lastRequestChecked == true && stats?.lastRequest?.isReroute == true
    }

    var routingTooltip: String {
        guard status?.loggedIn == true, !switching,
              let request = stats?.lastRequest else { return "Edgee" }
        let time = request.date.map { " · \($0.formatted(date: .abbreviated, time: .standard))" } ?? ""
        return "Last recorded request: \(request.routingLabel) · \(request.modelLabel)\(time)"
    }

    func reload() async {
        guard !switching else { return }
        reloadGeneration += 1
        let generation = reloadGeneration
        // Only show the loading placeholders on a cold start; a refresh keeps the
        // cached values on screen until the new ones arrive.
        if status == nil { loading = true }
        if stats == nil { statsLoading = true }

        async let auth = EdgeeCLI.authStatus()
        async let summary = EdgeeCLI.stats()
        async let profs = EdgeeCLI.profiles()
        async let organizations = EdgeeCLI.orgs()

        let results = await (auth, summary, profs, organizations)
        guard generation == reloadGeneration, !switching else { return }
        status = results.0
        loading = false
        stats = results.1
        statsLoading = false
        profiles = results.2
        orgs = results.3
    }

    func login() async {
        loggingIn = true
        _ = await EdgeeCLI.login()
        loggingIn = false
        await reload()
    }

    func switchProfile(_ name: String) async {
        stats = nil
        reloadGeneration += 1
        switching = true
        await EdgeeCLI.switchProfile(name)
        switching = false
        await reload()
    }

    func switchOrg(_ idOrSlug: String) async {
        stats = nil
        reloadGeneration += 1
        switching = true
        await EdgeeCLI.switchOrg(idOrSlug)
        switching = false
        await reload()
    }

    func logout() async {
        stats = nil
        reloadGeneration += 1
        switching = true
        await EdgeeCLI.logout()
        switching = false
        await reload()
        logoutCount += 1
    }
}
