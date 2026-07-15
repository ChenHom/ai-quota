import SwiftUI

struct QuotaPanel: View {
    @ObservedObject var store: QuotaStore

    private let providers = [("codex", "Codex"), ("claude", "Claude"), ("agy", "AGY")]

    var body: some View {
        Group {
            if #available(macOS 26.0, *) {
                panelContent
                    .padding(12)
                    .glassEffect(
                        .clear,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
            } else {
                ZStack {
                    GlassMaterialView(material: .popover, blendingMode: .behindWindow)
                    panelContent.padding(12)
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
        .frame(width: 300)
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let error = store.refreshError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            ForEach(providers, id: \.0) { key, name in
                ProviderCard(name: name, quota: store.quota?.providers[key])
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("AI USAGE")
                    .font(.caption2.weight(.bold))
                    .tracking(1)
                Text("最後同步：\(time(store.lastRefreshAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { Task { await store.refresh() } } label: {
                RefreshIcon(isRefreshing: store.isRefreshing)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(store.isRefreshing)
        }
    }

    private func time(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .omitted, time: .shortened)
    }
}

private struct RefreshIcon: View {
    let isRefreshing: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isRefreshing)) { timeline in
            let progress = timeline.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 0.3) / 0.3
            Image(systemName: "arrow.clockwise")
                .rotationEffect(.degrees(isRefreshing ? progress * 360 : 0))
        }
    }
}

private struct ProviderCard: View {
    let name: String
    let quota: ProviderQuota?

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(name).font(.headline)
                Spacer()
                Text("最後更新：\(shortTime(quota?.lastSuccessAt))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(statusLabel)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(statusColor.opacity(0.25), in: Capsule())
            }
            UsageRow(label: "5h", window: quota?.windows.fiveHour)
            UsageRow(label: "7d", window: quota?.windows.sevenDay)
        }
        .padding(12)
        .providerGlassBackground()
    }

    private var statusLabel: String {
        guard let quota else { return "暫無資料" }
        return quota.status == "ok" ? "正常" : "資料延遲"
    }

    private var statusColor: Color { quota?.status == "ok" ? .green : .orange }

    private func shortTime(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .omitted, time: .shortened)
    }
}

private extension View {
    func providerGlassBackground() -> some View {
        overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.24), lineWidth: 1)
        }
    }
}

private struct UsageRow: View {
    let label: String
    let window: UsageWindow?

    var body: some View {
        HStack(spacing: 8) {
            Text(label).frame(width: 24, alignment: .leading).font(.caption.weight(.semibold))
            ProgressView(value: window?.remainingPercent ?? 0, total: 100)
                .tint(.white.opacity(0.65))
                .frame(maxWidth: .infinity)
            Text(window.map { "\(Int($0.remainingPercent.rounded()))%" } ?? "—")
                .frame(width: 38, alignment: .trailing)
                .font(.caption.weight(.bold))
            Text(window.map { "重置 \($0.resetsAt.formatted(.dateTime.month().day().hour().minute()))" } ?? "")
                .frame(width: 116, alignment: .trailing)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
