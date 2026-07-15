import Foundation

enum AppConfiguration {
    private static let endpointKey = "quotaEndpoint"

    static var quotaEndpoint: URL? {
        let rawValue = ProcessInfo.processInfo.environment["AIQUOTA_ENDPOINT"]
            ?? UserDefaults.standard.string(forKey: endpointKey)

        guard let rawValue,
              let endpoint = URL(string: rawValue),
              endpoint.scheme == "https",
              endpoint.host != nil else {
            return nil
        }

        return endpoint
    }
}
