import AppKit
import Charts
import SwiftUI

/// The window's Dashboard: headline KPI tiles plus Swift Charts over recent
/// sessions (tokens in/out and compression), and a fuller recent-sessions list.
/// Fed by `edgee stats --json` (same data as the menubar, more room to show it).
struct DashboardView: View {
    let stats: Stats?
    let loading: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if stats == nil && loading {
                    loadingState
                } else if let stats, stats.sessions > 0 {
                    kpis(stats)
                    charts(stats)
                    recentList(stats)
                } else {
                    emptyState
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Dashboard")
    }

    // MARK: KPIs

    private func kpis(_ stats: Stats) -> some View {
        let totals = stats.totals
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
            kpi("Sessions", "\(stats.sessions)", "rectangle.stack")
            kpi("Requests", "\(totals.requests)", "arrow.left.arrow.right")
            kpi("Tokens saved", TokenFormat.short(totals.tokenCostSavings), "leaf.fill", tint: .green)
            kpi("Tokens in", TokenFormat.short(totals.inputTokens), "arrow.down")
            kpi("Tokens out", TokenFormat.short(totals.outputTokens), "arrow.up")
            kpi("Compression", totals.compressionPct.map { "\($0)%" } ?? "—", "arrow.down.right.and.arrow.up.left", tint: Theme.brand)
        }
    }

    private func kpi(_ label: String, _ value: String, _ symbol: String, tint: Color = .secondary) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Charts

    @ViewBuilder
    private func charts(_ stats: Stats) -> some View {
        let sessions = chartSessions(stats)
        if sessions.count >= 2 {
            VStack(alignment: .leading, spacing: 24) {
                tokensChart(sessions)
                agentChart(stats)
            }
        }
    }

    private func tokensChart(_ sessions: [Stats.SessionBrief]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tokens per session").font(.headline)
            Chart {
                ForEach(sessions) { session in
                    BarMark(
                        x: .value("Session", session.endedAtUnix),
                        y: .value("Tokens", session.inputTokens)
                    )
                    .foregroundStyle(by: .value("Kind", "In"))
                    .position(by: .value("Kind", "In"))
                    BarMark(
                        x: .value("Session", session.endedAtUnix),
                        y: .value("Tokens", session.outputTokens)
                    )
                    .foregroundStyle(by: .value("Kind", "Out"))
                    .position(by: .value("Kind", "Out"))
                }
            }
            .chartForegroundStyleScale(["In": Theme.brand, "Out": Color.teal])
            .chartXAxis {
                AxisMarks(values: sessions.map(\.endedAtUnix)) { value in
                    if let unix = value.as(Int64.self) {
                        AxisValueLabel { Text(timeLabel(unix)) }
                        AxisTick()
                    }
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    if let count = value.as(Int.self) {
                        AxisValueLabel { Text(TokenFormat.short(UInt64(max(0, count)))) }
                    }
                }
            }
            .frame(height: 200)
        }
    }

    /// Total tokens (in + out) per agent across recent sessions — where usage
    /// concentrates. Horizontal bars so agent names stay readable.
    private func agentChart(_ stats: Stats) -> some View {
        let usage = agentUsage(stats)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Usage by agent").font(.headline)
            Chart(usage) { agent in
                BarMark(
                    x: .value("Tokens", agent.tokens),
                    y: .value("Agent", agent.tool)
                )
                .foregroundStyle(Theme.brand.gradient)
                .cornerRadius(4)
                .annotation(position: .trailing, alignment: .leading) {
                    Text("\(TokenFormat.short(UInt64(agent.tokens)))  ·  \(agent.requests) req")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisGridLine()
                    if let count = value.as(Int.self) {
                        AxisValueLabel { Text(TokenFormat.short(UInt64(max(0, count)))) }
                    }
                }
            }
            .frame(height: CGFloat(usage.count) * 42 + 24)
        }
    }

    // MARK: Recent list

    private func recentList(_ stats: Stats) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent sessions").font(.headline)
            VStack(spacing: 0) {
                ForEach(stats.recent) { session in
                    sessionRow(session)
                    if session.id != stats.recent.last?.id { Divider() }
                }
            }
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func sessionRow(_ session: Stats.SessionBrief) -> some View {
        Button {
            if let url = URL(string: session.logsUrl) { NSWorkspace.shared.open(url) }
        } label: {
            HStack(spacing: 12) {
                Text(session.toolName)
                    .frame(width: 120, alignment: .leading).lineLimit(1)
                Text(relative(session.endedAtUnix))
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(width: 90, alignment: .leading)
                Spacer()
                Text("\(session.requests) req")
                    .font(.caption).foregroundStyle(.secondary)
                Text("\(TokenFormat.short(session.inputTokens)) → \(TokenFormat.short(session.outputTokens))")
                    .font(.system(.caption, design: .rounded))
                    .frame(width: 110, alignment: .trailing)
                Text(session.compressionPct.map { "\($0)%" } ?? "—")
                    .font(.caption).foregroundStyle(.green)
                    .frame(width: 44, alignment: .trailing)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open session on the Edgee console")
    }

    // MARK: States

    private var loadingState: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Loading…").foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "chart.bar.xaxis").font(.largeTitle).foregroundStyle(.secondary)
            Text("No sessions yet").font(.headline)
            Text("Launch an agent through Edgee to start seeing stats here.")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Helpers

    /// Recent sessions oldest-first, capped so the charts stay readable.
    private func chartSessions(_ stats: Stats) -> [Stats.SessionBrief] {
        stats.recent.sorted { $0.endedAtUnix < $1.endedAtUnix }.suffix(15).map { $0 }
    }

    /// Total tokens and requests per agent across recent sessions, biggest first.
    private func agentUsage(_ stats: Stats) -> [AgentUsage] {
        var totals: [String: (tokens: Int, requests: UInt64)] = [:]
        for session in stats.recent {
            let existing = totals[session.toolName] ?? (0, 0)
            totals[session.toolName] = (
                existing.tokens + Int(session.inputTokens) + Int(session.outputTokens),
                existing.requests + session.requests
            )
        }
        return totals
            .map { AgentUsage(tool: $0.key, tokens: $0.value.tokens, requests: $0.value.requests) }
            .sorted { $0.tokens > $1.tokens }
    }

    private func timeLabel(_ unix: Int64) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(unix)))
    }

    private struct AgentUsage: Identifiable {
        let tool: String
        let tokens: Int
        let requests: UInt64
        var id: String { tool }
    }

    private func relative(_ unix: Int64) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(
            for: Date(timeIntervalSince1970: TimeInterval(unix)), relativeTo: Date())
    }
}
