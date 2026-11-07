import Foundation

struct AppBundleReplacement: Equatable, Sendable {
    let version: String?
}

struct AppBundleReplacementDetector {
    private struct ExecutableIdentity: Equatable {
        let path: String
        let systemNumber: UInt64?
        let fileNumber: UInt64?
        let size: UInt64?
        let modificationDate: Date?

        init?(url: URL) {
            let resolved = url.resolvingSymlinksInPath()
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: resolved.path) else { return nil }

            self.path = resolved.path
            self.systemNumber = (attributes[.systemNumber] as? NSNumber)?.uint64Value
            self.fileNumber = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
            self.size = (attributes[.size] as? NSNumber)?.uint64Value
            self.modificationDate = attributes[.modificationDate] as? Date
        }
    }

    private struct DiskBundle {
        let executableURL: URL?
        let version: String?
        let build: String?

        init(url: URL) {
            let plistURL = url.appendingPathComponent("Contents/Info.plist")
            let plist = (try? Data(contentsOf: plistURL)).flatMap {
                try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any]
            }
            self.executableURL = (plist?["CFBundleExecutable"] as? String).map {
                url.appendingPathComponent("Contents/MacOS").appendingPathComponent($0)
            }
            self.version = plist?["CFBundleShortVersionString"] as? String
            self.build = plist?["CFBundleVersion"] as? String
        }
    }

    private let bundleURL: URL
    private let executableURL: URL?
    private let identity: ExecutableIdentity?
    private let version: String?
    private let build: String?

    init(bundleURL: URL = Bundle.main.bundleURL) {
        self.bundleURL = bundleURL
        let disk = DiskBundle(url: bundleURL)
        let executableURL = Bundle(url: bundleURL)?.executableURL ?? disk.executableURL
        self.executableURL = executableURL
        self.identity = executableURL.flatMap(ExecutableIdentity.init)
        self.version = disk.version
        self.build = disk.build
    }

    func currentReplacement() -> AppBundleReplacement? {
        // SwiftPM tests and CLI executables have no application bundle to replace.
        guard let executableURL, let identity else { return nil }

        let disk = DiskBundle(url: self.bundleURL)
        let currentIdentity = ExecutableIdentity(url: disk.executableURL ?? executableURL)
        guard currentIdentity == identity, disk.version == self.version, disk.build == self.build else {
            return AppBundleReplacement(version: disk.version)
        }

        return nil
    }
}
