import Foundation

/// Persists simple user settings in UserDefaults.
public struct SettingsStore {
    private let defaults: UserDefaults
    static let storageKey = "com.steipete.repobar.settings"
    public static let mainAppSuiteName = "com.steipete.repobar"
    private let key = Self.storageKey
    private static let currentVersion = 3

    public init(defaults: UserDefaults = Self.defaultDefaults()) {
        self.defaults = defaults
    }

    public static func defaultDefaults() -> UserDefaults {
        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            if let defaults = UserDefaults(suiteName: bundleIdentifier) {
                return defaults
            }
        }

        return .standard
    }

    public static func mainAppDefaults() -> UserDefaults {
        UserDefaults(suiteName: self.mainAppSuiteName) ?? .standard
    }

    public func load() -> UserSettings {
        guard let data = defaults.data(forKey: key) else {
            return UserSettings()
        }

        let decoder = JSONDecoder()
        if let envelope = try? decoder.decode(SettingsEnvelope.self, from: data) {
            var settings = envelope.settings
            if envelope.version < Self.currentVersion {
                Self.applyMigrations(to: &settings, fromVersion: envelope.version)
                self.save(settings)
            }
            return settings
        }
        return UserSettings()
    }

    public func save(_ settings: UserSettings) {
        let envelope = SettingsEnvelope(version: Self.currentVersion, settings: settings)
        if let data = try? JSONEncoder().encode(envelope) {
            self.defaults.set(data, forKey: self.key)
        }
    }

    private static func applyMigrations(to _: inout UserSettings, fromVersion: Int) {
        guard fromVersion < self.currentVersion else { return }
    }
}

private struct SettingsEnvelope: Codable {
    let version: Int
    let settings: UserSettings
}
