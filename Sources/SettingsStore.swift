import Foundation
import Security

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var lookbackHours: Double
    @Published var maxPerDesk: Int
    @Published var weatherCity: String
    @Published var hermesAPIURL: String
    @Published var hermesUseCLI: Bool
    @Published var openClawURL: String
    @Published var bridgePort: Int
    @Published var enabledDesks: Set<Desk>
    @Published var marketSymbols: String

    private let defaults = UserDefaults.standard

    private init() {
        lookbackHours = defaults.object(forKey: "lookbackHours") as? Double ?? 12
        maxPerDesk = defaults.object(forKey: "maxPerDesk") as? Int ?? 20
        weatherCity = defaults.string(forKey: "weatherCity") ?? "New York"
        hermesAPIURL = defaults.string(forKey: "hermesAPIURL") ?? "http://127.0.0.1:8642"
        hermesUseCLI = defaults.object(forKey: "hermesUseCLI") as? Bool ?? true
        openClawURL = defaults.string(forKey: "openClawURL") ?? "ws://127.0.0.1:18789"
        bridgePort = defaults.object(forKey: "bridgePort") as? Int ?? 18765
        marketSymbols = defaults.string(forKey: "marketSymbols")
            ?? "^GSPC,^DJI,^IXIC,SPY,QQQ,AAPL,MSFT,NVDA,GOOGL,AMZN,META,TSLA,BTC-USD,ETH-USD"
        if let raw = defaults.array(forKey: "enabledDesks") as? [String] {
            enabledDesks = Set(raw.compactMap(Desk.init(rawValue:)))
        } else {
            enabledDesks = Set(Desk.allCases)
        }
    }

    func save() {
        defaults.set(lookbackHours, forKey: "lookbackHours")
        defaults.set(maxPerDesk, forKey: "maxPerDesk")
        defaults.set(weatherCity, forKey: "weatherCity")
        defaults.set(hermesAPIURL, forKey: "hermesAPIURL")
        defaults.set(hermesUseCLI, forKey: "hermesUseCLI")
        defaults.set(openClawURL, forKey: "openClawURL")
        defaults.set(bridgePort, forKey: "bridgePort")
        defaults.set(marketSymbols, forKey: "marketSymbols")
        defaults.set(enabledDesks.map(\.rawValue), forKey: "enabledDesks")
    }

    var hermesToken: String {
        get { Keychain.get("hermes-api") ?? "" }
        set { Keychain.set(newValue, account: "hermes-api") }
    }

    var openClawToken: String {
        get { Keychain.get("openclaw") ?? "" }
        set { Keychain.set(newValue, account: "openclaw") }
    }
}

enum Keychain {
    static func set(_ value: String, account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AppPaths.bundleId,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AppPaths.bundleId,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var out: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
