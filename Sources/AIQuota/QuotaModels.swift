import Foundation

/// 公開快照 `/quota.json` 的解碼型別，對應 schema v2（見 public-schema-v2.md）。
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

/// 攤平後的一列：provider 依 `ProviderKind` 固定順序，帳號依伺服器給的順序（`main` 在最前）
struct ProviderRow: Identifiable {
    let id: String
    let displayName: String
    let quota: ProviderQuota?

    /// 尚未取得快照時的佔位列，維持「三張卡片顯示暫無資料」的原本行為
    static let placeholders: [ProviderRow] = ProviderKind.allCases.map {
        ProviderRow(id: $0.rawValue, displayName: $0.displayName, quota: nil)
    }
}

extension QuotaResponse {
    var providerRows: [ProviderRow] {
        ProviderKind.allCases.flatMap { kind in
            providers[kind].map { quota in
                ProviderRow(
                    id: "\(kind.rawValue)/\(quota.account)",
                    displayName: quota.account == ProviderQuota.defaultAccount
                        ? kind.displayName
                        : "\(kind.displayName) (\(quota.account))",
                    quota: quota
                )
            }
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
