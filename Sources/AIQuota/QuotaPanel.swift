import SwiftUI

struct QuotaPanel: View {
    @ObservedObject var store: QuotaStore

    /// 每個 provider 一落牌；還沒有快照時退回三張佔位卡片
    private var stacks: [ProviderStack] {
        store.quota?.providerStacks ?? ProviderStack.placeholders
    }

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
            ForEach(stacks) { stack in
                ProviderStackCard(stack: stack)
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

/// 多帳號 provider 疊成一落牌：點擊把最前面那張壓下去，彈回來時已經換成下一個帳號。
/// 單帳號時退化成一張普通卡片，外觀與行為都跟以前一樣
private struct ProviderStackCard: View {
    let stack: ProviderStack

    /// 記帳號名稱而非索引：快照刷新後伺服器可能重排陣列，使用者看的要還是同一個帳號
    @State private var frontAccount: String?
    /// 整落牌正在被壓住
    @State private var isPressing = false
    /// 按下去的時刻，用來算還要不要補足 pressDuration
    @State private var pressStartedAt: Date?

    /// 後面那張往下露出的高度
    private static let peek: CGFloat = 9
    /// 每往後一層縮小的比例
    private static let shrink: CGFloat = 0.045
    /// 疊超過兩層就不再往下推，避免越堆越糊
    private static let maxVisibleDepth = 2
    /// 壓下去的時間。放開得太快時會補足剩下的，確保交換仍然被壓到底那一刻蓋住
    private static let pressDuration: TimeInterval = 0.13
    /// 按下去時整落牌往中間收斂的位置（0 = 最前面，1 = 牌底那張）。
    /// 所有卡片收到同一個位置、大小與明度，誰在前誰在後完全看不出來——
    /// 交換就藏在這一刻，這是整個做法的關鍵
    private static let pressLevel: CGFloat = 0.5

    var body: some View {
        Button {
            // 切換走 isPressed 轉 false，這裡不做事：Button 的 action 比
            // isPressed 轉 false 更早觸發，放在這裡會比回彈早一步（實測）
        } label: {
            cardStack
        }
        .buttonStyle(CardPressStyle { pressed in
            if pressed { press() } else { release() }
        })
        .accessibilityElement(children: .combine)
        .accessibilityAction {
            guard let next = stack.account(after: frontAccount) else { return }
            withAnimation(.spring(response: 0.40, dampingFraction: 0.60)) { frontAccount = next }
        }
        .accessibilityAddTraits(stack.isMultiAccount ? AccessibilityTraits.isButton : [])
        .accessibilityHint(stack.isMultiAccount ? "切換下一個帳號" : "")
    }

    private var cardStack: some View {
        let ordered = stack.ordered(from: frontAccount)

        return ZStack {
            if ordered.isEmpty {
                ProviderCard(displayName: stack.displayName, quota: nil,
                             accountCount: 0, accountIndex: 0, activeIndex: 0)
            } else {
                ForEach(Array(ordered.enumerated()), id: \.element.account) { depth, quota in
                    let level = isPressing
                        ? Self.pressLevel
                        : CGFloat(min(depth, Self.maxVisibleDepth))
                    ProviderCard(
                        displayName: stack.displayName,
                        quota: quota,
                        accountCount: stack.accounts.count,
                        accountIndex: stack.index(of: quota.account),
                        activeIndex: stack.index(of: frontAccount)
                    )
                    // 不要加 .shadow：套在 glassEffect 上會先把玻璃光柵化到離屏圖層，
                    // 影子就按外框矩形畫，變成一個黑方塊而不是跟著圓角（實測）。
                    // 深度靠位移、縮放與明度表示就夠了
                    .offset(y: level * Self.peek)
                    .scaleEffect(1 - level * Self.shrink)
                    .opacity(isPressing ? 0.8 : (depth == 0 ? 1 : 0.5))
                    .zIndex(Double(ordered.count - depth))
                }
            }
        }
        // 露出的那一角要留空間，否則會被下一張卡蓋掉
        .padding(.bottom, stack.isMultiAccount ? Self.peek : 0)
        .contentShape(Rectangle())
    }

    /// 按下：整落牌沉下去
    private func press() {
        // DragGesture 的 onChanged 會連續觸發，只認第一次
        guard !isPressing else { return }
        pressStartedAt = .now
        // 加速壓下去，像被指頭按住
        withAnimation(.easeIn(duration: Self.pressDuration)) { isPressing = true }
    }

    /// 放開：彈回來，順便換帳號
    private func release() {
        guard isPressing else { return }
        let next = stack.account(after: frontAccount)

        // 點得太快時沉下去還沒走完，先補足剩下的時間。
        // 沒補的話兩張卡還沒收斂到同一個位置就交換，會被看見
        let elapsed = pressStartedAt.map { Date.now.timeIntervalSince($0) } ?? Self.pressDuration
        let remaining = Self.pressDuration - elapsed
        guard remaining > 0 else { return settle(next: next) }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(remaining))
            settle(next: next)
        }
    }

    private func settle(next: String?) {
        // 阻尼壓低才彈得出來
        withAnimation(.spring(response: 0.40, dampingFraction: 0.60)) {
            if let next { frontAccount = next }
            isPressing = false
        }
        pressStartedAt = nil
    }
}

/// 卡片的按壓狀態，用 ButtonStyle 的 `configuration.isPressed` 取得。
///
/// 前提是 `FirstMouseHostingView` 的 acceptsFirstMouse——少了它，這裡
/// 收不到 isPressed（實測，而且換成 DragGesture 或 LongPressGesture 也一樣
/// 收不到，因為卡住的是視窗層級而不是手勢寫法）。
///
/// 注意順序：Button 的 action 比 isPressed 轉 false 更早觸發（實測），
/// 所以切換要走 isPressed，不能放進 action
private struct CardPressStyle: ButtonStyle {
    let onPressChange: (Bool) -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, pressed in
                onPressChange(pressed)
            }
    }
}

private struct ProviderCard: View {
    /// 多帳號時用底色區分是哪一個帳號。第一個帳號（一般是 main）不上色，
    /// 維持與單帳號卡片相同的外觀；色相避開狀態膠囊的綠／橘與重置券的藍
    private static let accountTints: [Color] = [
        Color(red: 0.58, green: 0.47, blue: 1.00),   // 紫
        Color(red: 0.27, green: 0.78, blue: 0.78),   // 青
        Color(red: 1.00, green: 0.47, blue: 0.74)    // 粉
    ]

    let displayName: String
    let quota: ProviderQuota?
    let accountCount: Int
    /// 這張卡是 provider 的第幾個帳號，決定底色
    let accountIndex: Int
    let activeIndex: Int

    private var tint: Color? {
        guard accountCount > 1, accountIndex > 0 else { return nil }
        return Self.accountTints[(accountIndex - 1) % Self.accountTints.count]
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(displayName).font(.headline)
                if accountCount > 1 {
                    AccountDots(count: accountCount, activeIndex: activeIndex)
                }
                ResetCreditsBadge(resetCredits: quota?.resetCredits)
                Spacer()
                // 「最後更新：」前綴拿掉只留時間——面板頂端的「最後同步」已經交代時間的意思
                Text(shortTime(quota?.lastSuccessAt ?? nil))
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
        .glassIsland(cornerRadius: 14, tint: tint)
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

/// 目前看的是第幾個帳號
private struct AccountDots: View {
    let count: Int
    let activeIndex: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<count, id: \.self) { index in
                // 只靠明暗差在 4pt 的小圓點上看不出來（實測），目前這顆改成拉長的膠囊：
                // 形狀差在任何尺寸都讀得到。寬度會跟著切換的 spring 一起變形
                let isActive = index == activeIndex
                let style: HierarchicalShapeStyle = isActive ? .primary : .quaternary
                // 形狀比照 UsageBar 用 .background(_, in:)：獨立的 Shape view
                // 會讓玻璃島的自動深淺適應失效（實測）
                Color.clear
                    .frame(width: isActive ? 10 : 4, height: 4)
                    .background(style, in: Capsule())
            }
        }
    }
}

private struct ResetCreditsBadge: View {
    let resetCredits: ResetCredits?
    @State private var showPopover = false

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "Asia/Taipei")
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter
    }()

    private static let hintDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "Asia/Taipei")
        formatter.dateFormat = "MM/dd"
        return formatter
    }()

    var body: some View {
        if let resetCredits, resetCredits.availableCount > 0 {
            Button {
                showPopover = true
            } label: {
                Text("+\(resetCredits.availableCount)")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.25), in: Capsule())
            }
            .buttonStyle(.plain)
            .help(nearestExpiryHint)
            .popover(isPresented: $showPopover) {
                creditsList(resetCredits)
            }
        }
    }

    private var nearestExpiryHint: String {
        guard let nearest = resetCredits?.credits.compactMap(\.expiresAt).min() else {
            return "重置券"
        }
        return "到期：\(Self.hintDateFormatter.string(from: nearest))"
    }

    private func creditsList(_ resetCredits: ResetCredits) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("重置券到期時間").font(.caption.weight(.semibold))
            ForEach(Array(resetCredits.credits.enumerated()), id: \.offset) { _, credit in
                Text(credit.expiresAt.map { Self.dateFormatter.string(from: $0) } ?? "—")
                    .font(.caption2)
            }
        }
        .padding(10)
        .frame(minWidth: 140, alignment: .leading)
    }
}

private extension View {
    /// `tint` 是多帳號卡片的底色。兩條路徑的濃度分開給：玻璃會自己再做一次處理，
    /// 直接沿用 fallback 的值會太淡（數值待實機微調）
    @ViewBuilder
    func glassIsland(cornerRadius: CGFloat, tint: Color? = nil) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            if let tint {
                glassEffect(.regular.tint(tint.opacity(0.5)), in: shape)
            } else {
                glassEffect(.regular, in: shape)
            }
        } else if let tint {
            background(tint.opacity(0.22), in: shape)
                .background(.quaternary, in: shape)
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
