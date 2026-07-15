import Foundation

struct QuotaResponse: Decodable {
    let schemaVersion: Int
    let generatedAt: Date
    let providers: [String: ProviderQuota]
}

struct ProviderQuota: Decodable {
    let provider: String
    let status: String
    let lastSuccessAt: Date
    let windows: QuotaWindows
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
    let resetsAt: Date
}
