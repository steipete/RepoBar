import Foundation

#if os(macOS)
    import Darwin
#endif

struct UpdateDiagnostics {
    let bundlePath: String
    let resolvedBundlePath: String
    let canCheckForUpdates: Bool
    let developerIDSigned: Bool
    let homebrewCask: Bool
    let appTranslocated: Bool
    let quarantinePresent: Bool

    static func current(canCheckForUpdates: Bool) -> UpdateDiagnostics {
        let bundleURL = Bundle.main.bundleURL
        return UpdateDiagnostics(
            bundleURL: bundleURL,
            canCheckForUpdates: canCheckForUpdates,
            developerIDSigned: SparkleController.isDeveloperIDSigned(bundleURL: bundleURL)
        )
    }

    init(
        bundleURL: URL,
        canCheckForUpdates: Bool,
        developerIDSigned: Bool,
        quarantineReader: (URL) -> Bool = UpdateDiagnostics.hasQuarantineAttribute
    ) {
        let resolvedURL = bundleURL.resolvingSymlinksInPath()
        self.bundlePath = bundleURL.path
        self.resolvedBundlePath = resolvedURL.path
        self.canCheckForUpdates = canCheckForUpdates
        self.developerIDSigned = developerIDSigned
        self.homebrewCask = InstallOrigin.isHomebrewCask(appBundleURL: bundleURL)
        self.appTranslocated = bundleURL.path.contains("/AppTranslocation/") || resolvedURL.path.contains("/AppTranslocation/")
        self.quarantinePresent = quarantineReader(bundleURL)
    }

    var pasteboardText: String {
        """
        RepoBar update diagnostics
        bundle_path: \(self.bundlePath)
        resolved_bundle_path: \(self.resolvedBundlePath)
        can_check_for_updates: \(self.canCheckForUpdates)
        developer_id_signed: \(self.developerIDSigned)
        homebrew_cask: \(self.homebrewCask)
        app_translocated: \(self.appTranslocated)
        quarantine_present: \(self.quarantinePresent)
        """
    }

    private static func hasQuarantineAttribute(url: URL) -> Bool {
        #if os(macOS)
            let path = url.path
            return path.withCString { cPath in
                getxattr(cPath, "com.apple.quarantine", nil, 0, 0, 0) >= 0
            }
        #else
            return false
        #endif
    }
}
