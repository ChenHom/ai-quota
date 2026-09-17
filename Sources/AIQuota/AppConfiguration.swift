import Foundation

enum AppConfiguration {
    private static let endpointKey = "quotaEndpoint"
    private static let releaseBundleID = "com.example.aiquota"

    /// `swift run`/`swift build` 的裸執行檔沒有 bundle ID，`UserDefaults.standard`
    /// 落在別的網域，讀不到打包版寫入的 `quotaEndpoint`；開發時退回讀打包版的網域
    private static var packagedAppDefaults: UserDefaults? {
        guard Bundle.main.bundleIdentifier != releaseBundleID else { return nil }
        return UserDefaults(suiteName: releaseBundleID)
    }

    /// 面板上顯示的建置標示，例如 `0.1.0 (74b90e9)`。後綴的 `+` 表示打包時
    /// 工作區還有未提交的改動。打包版才有值——裸執行檔沒有 bundle，讀不到
    static var buildLabel: String {
        guard let revision = infoValue("AIQuotaGitRevision") else { return "開發版" }
        return "\(shortVersion) (\(revision))"
    }

    /// 滑鼠停留時顯示的完整資訊
    static var buildDetail: String {
        guard let revision = infoValue("AIQuotaGitRevision") else {
            return "開發版：未經打包，無法判斷來源 commit"
        }
        let builtAt = infoValue("AIQuotaBuiltAt").map { "，建置於 \($0)" } ?? ""
        return "版本 \(shortVersion)（\(revision)）\(builtAt)"
    }

    private static var shortVersion: String {
        infoValue("CFBundleShortVersionString") ?? "0.0.0"
    }

    private static func infoValue(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty else { return nil }
        return value
    }

    static var quotaEndpoint: URL? {
        let rawValue = ProcessInfo.processInfo.environment["AIQUOTA_ENDPOINT"]
            ?? UserDefaults.standard.string(forKey: endpointKey)
            ?? packagedAppDefaults?.string(forKey: endpointKey)

        guard let rawValue,
              let endpoint = URL(string: rawValue),
              endpoint.scheme == "https",
              endpoint.host != nil else {
            return nil
        }

        return endpoint
    }
}
