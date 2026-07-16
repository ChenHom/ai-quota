import SwiftUI

struct QuotaPanel: View {
    @ObservedObject var store: QuotaStore

    private let providers = [("codex", "Codex"), ("claude", "Claude"), ("agy", "AGY")]

    var body: some View {
        Group {
            if #available(macOS 26.0, *) {
                panelContent
                .padding(12)
                // 玻璃島必須直接面對視窗背後的螢幕內容才會自動深淺適應——
                // 任何墊在下面的圖層（玻璃底、半透明填色）都會被當成取樣對象，破壞適應。
                // 因此底層完全留空，透感與暗化交給每座島自己的玻璃
            } else {
                ZStack {
                    GlassMaterialView(material: .menu, blendingMode: .behindWindow)
                    panelContent.padding(12)
                }
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            }
        }
        .frame(width: 300)
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .glassIsland(cornerRadius: 14)
            if let error = store.refreshError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .glassIsland(cornerRadius: 10)
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
        .glassIsland(cornerRadius: 14)
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
    @ViewBuilder
    func glassIsland(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.quaternary, in: shape)
        }
    }
}

private struct UsageBar: View {
    let percent: Double?

    var body: some View {
        let fraction = min(max((percent ?? 0) / 100, 0), 1)
        Color.clear
            .frame(height: 6)
            .frame(maxWidth: .infinity)
            // 進度列統一用 .background(_, in:) 畫形狀：Shape.fill 作為獨立 view
            // 會讓玻璃島的自動深淺適應失效（實測），background(in:) 不會
            .background(Color(white: 0.5).opacity(0.55), in: Capsule())
            .overlay(alignment: .leading) {
                if fraction > 0 {
                    Color.clear
                        .background(.white, in: Capsule())
                        .shadow(color: .black.opacity(0.15), radius: 0.5, y: 0.5)
                        .mask(alignment: .leading) {
                            Rectangle().scaleEffect(x: fraction, anchor: .leading)
                        }
                }
            }
    }
}

private struct UsageRow: View {
    let label: String
    let window: UsageWindow?

    private static let resetDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter
    }()

    var body: some View {
        HStack(spacing: 8) {
            Text(label).frame(width: 24, alignment: .leading).font(.caption.weight(.semibold))
            UsageBar(percent: window?.remainingPercent)
                .frame(maxWidth: .infinity)
            Text(window.map { "\(Int($0.remainingPercent.rounded()))%" } ?? "—")
                .frame(width: 38, alignment: .trailing)
                .font(.caption.weight(.bold))
            // 空字串的 Text 會變成零尺寸 view，讓玻璃島的深淺適應失效（實測）；
            // 沒有重置時間就以單一空白佔位
            Text(resetText.isEmpty ? " " : resetText)
                .frame(width: 116, alignment: .trailing)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var resetText: String {
        guard let resetsAt = window?.resetsAt else { return "" }
        return "重置 \(Self.resetDateFormatter.string(from: resetsAt))"
    }
}
