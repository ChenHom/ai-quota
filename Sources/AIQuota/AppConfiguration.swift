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
