import Foundation

struct AppLocalizer: Sendable {
    private let bundle: Bundle

    init(preferredLanguages: [String] = Locale.preferredLanguages, bundle: Bundle? = nil) {
        // Packaged apps use sealed main-bundle resources; SwiftPM runs use the module bundle.
        let bundle = bundle ?? (Bundle.main.bundleURL.pathExtension == "app" ? .main : .module)
        // Language preferences (including macOS per-app settings) are independent of region.
        let language = Bundle.preferredLocalizations(from: ["en", "tr"], forPreferences: preferredLanguages).first ?? "en"
        self.bundle = bundle.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)) ?? bundle
    }

    func string(_ key: String) -> String {
        self.bundle.localizedString(forKey: key, value: key, table: nil)
    }
}
