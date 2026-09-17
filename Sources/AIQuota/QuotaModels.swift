import Foundation

/// 公開快照 `/quota.json` 的解碼型別，對應 schema v2（見 docs/public-schema-v2.md）。
/// v2 起每個 provider 是「一帳號一元素」的陣列，元素多了 `account`。
struct QuotaResponse: Decodable {
    /// 伺服器只輸出 v2；版本不符一律視為不可用
    static let supportedSchemaVersion = 2

    let schemaVersion: Int
    let generatedAt: Date
    let providers: Providers
}

enum ProviderKind: String, CaseIterable {
    case codex
    case claude
    case agy

    var displayName: String {
        switch self {
        case .codex: return "Codex"
        case .claude: return "Claude"
        case .agy: return "AGY"
        }
    }
}

struct Providers: Decodable {
    let codex: [ProviderQuota]
    let claude: [ProviderQuota]
    /// agy 在 v2 仍可能整個缺席
    let agy: [ProviderQuota]?

    subscript(kind: ProviderKind) -> [ProviderQuota] {
        switch kind {
        case .codex: return codex
        case .claude: return claude
        case .agy: return agy ?? []
        }
    }
}

struct ProviderQuota: Decodable {
    /// 預設帳號的固定標籤；顯示時沿用 provider 原名，不加後綴
    static let defaultAccount = "main"

    let provider: String
    /// v2 新增。同 provider 內唯一
    let account: String
    let status: String
    let lastSuccessAt: Date?
    let windows: QuotaWindows
    let resetCredits: ResetCredits?
}

/// 一個 provider 一落牌。面板固定三張卡片，多帳號時疊在同一個位置、點擊切換
struct ProviderStack: Identifiable {
    let id: String
    let displayName: String
    let accounts: [ProviderQuota]

    var isMultiAccount: Bool { accounts.count > 1 }

    /// 尚未取得快照時的佔位，維持「三張卡片顯示暫無資料」的原本行為。
    /// id 與真實資料相同，快照到達時 SwiftUI 才不會把卡片視為新元素而重置切換狀態
    static let placeholders: [ProviderStack] = ProviderKind.allCases.map {
        ProviderStack(id: $0.rawValue, displayName: $0.displayName, accounts: [])
    }

    /// 以 `frontAccount` 為首的循環排列。帳號不存在（快照換過、該帳號已移除）時退回原順序，
    /// 也就是 `main` 在最前
    func ordered(from frontAccount: String?) -> [ProviderQuota] {
        guard isMultiAccount,
              let frontAccount,
              let start = accounts.firstIndex(where: { $0.account == frontAccount })
        else { return accounts }
        return Array(accounts[start...]) + Array(accounts[..<start])
    }

    /// 點擊後要切到的下一個帳號
    func account(after frontAccount: String?) -> String? {
        let order = ordered(from: frontAccount)
        guard order.count > 1 else { return nil }
        return order[1].account
    }

    /// `frontAccount` 在 `accounts` 裡的位置，供指示圓點標示第幾張
    func index(of frontAccount: String?) -> Int {
        guard let frontAccount,
              let index = accounts.firstIndex(where: { $0.account == frontAccount })
        else { return 0 }
        return index
    }
}

extension QuotaResponse {
    var providerStacks: [ProviderStack] {
        ProviderKind.allCases.map { kind in
            ProviderStack(id: kind.rawValue, displayName: kind.displayName, accounts: providers[kind])
        }
    }
}

struct ResetCredits: Decodable {
    let availableCount: Int
    let applicableAvailableCount: Int
    let credits: [ResetCredit]
}

struct ResetCredit: Decodable {
    let status: String
    let grantedAt: Date
    let expiresAt: Date?
}

struct QuotaWindows: Decodable {
    let fiveHour: UsageWindow?
    let sevenDay: UsageWindow?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}

struct UsageWindow: Decodable {
    let remainingPercent: Double
    let resetsAt: Date?
}
