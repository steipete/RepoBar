import Foundation
import Observation
import Security

@MainActor
@Observable
final class UpdateStatus {
    static let disabled = UpdateStatus()
    var isUpdateReady: Bool

    init(isUpdateReady: Bool = false) {
        self.isUpdateReady = isUpdateReady
    }
}

@MainActor
protocol UpdaterProviding: AnyObject {
    var automaticallyChecksForUpdates: Bool { get set }
    var automaticallyDownloadsUpdates: Bool { get set }
    var isAvailable: Bool { get }
    func checkForUpdates(_ sender: Any?)
}

/// No-op updater used for unsigned/dev or non-app builds so Sparkle dialogs don’t appear in development/test runs.
final class DisabledUpdaterController: UpdaterProviding {
    var automaticallyChecksForUpdates: Bool = false
    var automaticallyDownloadsUpdates: Bool = false
    let isAvailable: Bool = false
    func checkForUpdates(_: Any?) {}
}

#if canImport(Sparkle)
    import Sparkle

    extension SPUStandardUpdaterController: UpdaterProviding {
        var automaticallyChecksForUpdates: Bool {
            get { self.updater.automaticallyChecksForUpdates }
            set { self.updater.automaticallyChecksForUpdates = newValue }
        }

        var automaticallyDownloadsUpdates: Bool {
            get { self.updater.automaticallyDownloadsUpdates }
            set { self.updater.automaticallyDownloadsUpdates = newValue }
        }

        var isAvailable: Bool {
            true
        }
    }
#endif

/// Simple Sparkle wrapper so we can call from menus without passing around the updater.
@MainActor
final class SparkleController: NSObject {
    static let shared = SparkleController()
    private var updater: UpdaterProviding
    let updateStatus: UpdateStatus
    private let defaultsKey = "autoUpdateEnabled"

    override private init() {
        #if canImport(Sparkle)
            let bundleURL = Bundle.main.bundleURL
            let isBundledApp = bundleURL.pathExtension == "app"
            let isSigned = SparkleController.isDeveloperIDSigned(bundleURL: bundleURL)
            let isHomebrew = InstallOrigin.isHomebrewCask(appBundleURL: bundleURL)
            // Mirror Trimmy: disable Sparkle entirely for unsigned/dev runs to avoid dialogs and signature errors.
            let canUseSparkle = isBundledApp && isSigned && !isHomebrew
        #else
            let canUseSparkle = false
        #endif

        self.updateStatus = canUseSparkle ? UpdateStatus() : .disabled
        self.updater = DisabledUpdaterController()
        super.init()

        #if canImport(Sparkle)
            guard canUseSparkle else { return }

            let saved = (UserDefaults.standard.object(forKey: self.defaultsKey) as? Bool) ?? true
            let controller = SPUStandardUpdaterController(
                startingUpdater: false,
                updaterDelegate: self,
                userDriverDelegate: nil
            )
            controller.automaticallyChecksForUpdates = saved
            controller.automaticallyDownloadsUpdates = saved
            controller.startUpdater()
            self.updater = controller
        #endif
    }

    var canCheckForUpdates: Bool {
        self.updater.isAvailable
    }

    var automaticallyChecksForUpdates: Bool {
        get { self.updater.automaticallyChecksForUpdates }
        set {
            self.updater.automaticallyChecksForUpdates = newValue
            UserDefaults.standard.set(newValue, forKey: self.defaultsKey)
        }
    }

    var automaticallyDownloadsUpdates: Bool {
        get { self.updater.automaticallyDownloadsUpdates }
        set { self.updater.automaticallyDownloadsUpdates = newValue }
    }

    func checkForUpdates() {
        guard self.canCheckForUpdates else { return }

        self.updater.checkForUpdates(nil)
    }

    nonisolated static func isDeveloperIDSigned(bundleURL: URL) -> Bool {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundleURL as CFURL, SecCSFlags(), &staticCode) == errSecSuccess,
              let code = staticCode else { return false }

        var infoCF: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &infoCF) == errSecSuccess,
              let info = infoCF as? [String: Any],
              let certs = info[kSecCodeInfoCertificates as String] as? [SecCertificate],
              let leaf = certs.first else { return false }

        if let summary = SecCertificateCopySubjectSummary(leaf) as String? {
            return summary.hasPrefix("Developer ID Application:")
        }
        return false
    }
}

#if canImport(Sparkle)
    import Sparkle

    extension SparkleController: SPUUpdaterDelegate {
        nonisolated func updater(_: SPUUpdater, didDownloadUpdate _: SUAppcastItem) {
            Task { @MainActor in
                self.updateStatus.isUpdateReady = true
            }
        }

        nonisolated func updater(_: SPUUpdater, failedToDownloadUpdate _: SUAppcastItem, error _: Error) {
            Task { @MainActor in
                self.updateStatus.isUpdateReady = false
            }
        }

        nonisolated func userDidCancelDownload(_: SPUUpdater) {
            Task { @MainActor in
                self.updateStatus.isUpdateReady = false
            }
        }

        nonisolated func updater(
            _: SPUUpdater,
            userDidMake choice: SPUUserUpdateChoice,
            forUpdate _: SUAppcastItem,
            state: SPUUserUpdateState
        ) {
            let downloaded = state.stage == .downloaded
            Task { @MainActor in
                switch choice {
                case .install, .skip:
                    self.updateStatus.isUpdateReady = false
                case .dismiss:
                    self.updateStatus.isUpdateReady = downloaded
                @unknown default:
                    self.updateStatus.isUpdateReady = false
                }
            }
        }
    }
#endif
