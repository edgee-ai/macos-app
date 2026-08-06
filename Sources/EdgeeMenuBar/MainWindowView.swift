import SwiftUI

/// Root of the full-app window: a sidebar (Dashboard / Relays) over the shared
/// `MenuModel` and `RelayManager`, so it stays live-linked with the menubar.
struct MainWindowView: View {
    @EnvironmentObject private var model: MenuModel
    @EnvironmentObject private var relays: RelayManager

    @State private var panel: Panel = .dashboard

    enum Panel: String, CaseIterable, Identifiable {
        case dashboard = "Dashboard"
        case relays = "Relays"

        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .dashboard: return "chart.bar.xaxis"
            case .relays: return "play.circle"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Panel.allCases, selection: $panel) { item in
                Label(item.rawValue, systemImage: item.symbol).tag(item)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            .safeAreaInset(edge: .bottom) { accountFooter }
        } detail: {
            Group {
                switch panel {
                case .dashboard:
                    DashboardView(stats: model.stats, loading: model.statsLoading)
                case .relays:
                    RelaysView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await model.reload() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh")
                }
            }
        }
        .frame(minWidth: 720, minHeight: 460)
        .task { await model.reload() }
    }

    private var accountFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            if let status = model.status, status.loggedIn {
                HStack(spacing: 8) {
                    Circle().fill(.green).frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(status.email ?? "Logged in")
                            .font(.caption).fontWeight(.semibold).lineLimit(1)
                        Text([status.orgSlug.map { "org · \($0)" }, "profile · \(status.profile)"]
                            .compactMap { $0 }.joined(separator: "   "))
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    Circle().fill(.red).frame(width: 8, height: 8)
                    Button("Log in…") { Task { await model.login() } }
                        .buttonStyle(.borderless)
                        .disabled(model.loggingIn)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }
}
