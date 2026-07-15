import Foundation

@MainActor
final class QuotaStore: ObservableObject {
    @Published private(set) var quota: QuotaResponse?
    @Published private(set) var isRefreshing = false
    @Published private(set) var refreshError: String?
    @Published private(set) var lastRefreshAt: Date?

    private let endpoint = AppConfiguration.quotaEndpoint
    private var refreshTask: Task<Void, Never>?

    init() {
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                await self?.refresh()
            }
        }
    }

    deinit { refreshTask?.cancel() }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        refreshError = nil
        defer { isRefreshing = false }
        let startedAt = Date()

        do {
            guard let endpoint else {
                throw QuotaConfigurationError.missingEndpoint
            }
            let (data, response) = try await URLSession.shared.data(from: endpoint)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { decoder in
                let value = try decoder.singleValueContainer().decode(String.self)
                let fractional = ISO8601DateFormatter()
                fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let standard = ISO8601DateFormatter()
                guard let date = fractional.date(from: value) ?? standard.date(from: value) else {
                    throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(), debugDescription: "Invalid ISO 8601 date: \(value)")
                }
                return date
            }
            let decodedQuota = try decoder.decode(QuotaResponse.self, from: data)
            await waitForMinimumRefreshDuration(since: startedAt)
            quota = decodedQuota
            lastRefreshAt = .now
        } catch {
            await waitForMinimumRefreshDuration(since: startedAt)
            refreshError = "更新失敗：\(error.localizedDescription)"
        }
    }

    private func waitForMinimumRefreshDuration(since startedAt: Date) async {
        let remaining = 0.3 - Date().timeIntervalSince(startedAt)
        guard remaining > 0 else { return }
        try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
    }
}

private enum QuotaConfigurationError: LocalizedError {
    case missingEndpoint

    var errorDescription: String? {
        "尚未設定額度資料網址"
    }
}
