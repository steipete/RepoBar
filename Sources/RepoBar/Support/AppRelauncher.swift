import AppKit
import RepoBarCore

@MainActor
enum AppRelauncher {
    static func relaunch() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            #"while /bin/kill -0 "$1" 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open "$0""#,
            Bundle.main.bundlePath,
            String(ProcessInfo.processInfo.processIdentifier)
        ]
        do {
            try process.run()
            NSApp.terminate(nil)
        } catch {
            RepoBarLogging.logger("relaunch").error("Could not start app relaunch: \(error.localizedDescription)")
        }
    }
}
