import Darwin
import Foundation
@testable import RepoBar
import Testing

struct AppBundleReplacementDetectorTests {
    @Test
    func `unchanged bundle has no replacement`() throws {
        let fixture = try FakeBundle()
        defer { fixture.cleanUp() }
        let detector = AppBundleReplacementDetector(bundleURL: fixture.url)
        #expect(detector.currentReplacement() == nil)
    }

    @Test
    func `replaced executable reports new on disk version`() throws {
        let fixture = try FakeBundle()
        defer { fixture.cleanUp() }
        let detector = AppBundleReplacementDetector(bundleURL: fixture.url)
        let replacement = fixture.url.appendingPathComponent("replacement")
        try Data("replacement executable".utf8).write(to: replacement)
        // Atomic rename, like an updater replacing the executable with another inode.
        #expect(rename(replacement.path, fixture.executable.path) == 0)
        try fixture.writePlist(version: "2.0", build: "2")
        #expect(detector.currentReplacement() == AppBundleReplacement(version: "2.0"))
    }

    @Test
    func `deleted executable requests relaunch`() throws {
        let fixture = try FakeBundle()
        defer { fixture.cleanUp() }
        let detector = AppBundleReplacementDetector(bundleURL: fixture.url)
        try FileManager.default.removeItem(at: fixture.executable)
        #expect(detector.currentReplacement() == AppBundleReplacement(version: "1.0"))
    }

    @Test
    func `unreadable plist still detects executable replacement without version`() throws {
        let fixture = try FakeBundle()
        defer { fixture.cleanUp() }
        let detector = AppBundleReplacementDetector(bundleURL: fixture.url)
        try FileManager.default.removeItem(at: fixture.executable)
        try FileManager.default.removeItem(at: fixture.url.appendingPathComponent("Contents/Info.plist"))
        #expect(detector.currentReplacement() == AppBundleReplacement(version: nil))
    }

    @Test
    func `executable attribute changes are detected`() throws {
        let fixture = try FakeBundle()
        defer { fixture.cleanUp() }
        let detector = AppBundleReplacementDetector(bundleURL: fixture.url)
        try Data("different size".utf8).write(to: fixture.executable)
        #expect(detector.currentReplacement() != nil)
    }
}

private struct FakeBundle {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).app")
    var executable: URL {
        self.url.appendingPathComponent("Contents/MacOS/RepoBar")
    }

    init() throws {
        try FileManager.default.createDirectory(at: self.executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("executable".utf8).write(to: self.executable)
        try self.writePlist(version: "1.0", build: "1")
    }

    func writePlist(version: String, build: String) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: [
            "CFBundleExecutable": "RepoBar", "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": version, "CFBundleVersion": build
        ], format: .xml, options: 0)
        try data.write(to: self.url.appendingPathComponent("Contents/Info.plist"))
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: self.url)
    }
}
