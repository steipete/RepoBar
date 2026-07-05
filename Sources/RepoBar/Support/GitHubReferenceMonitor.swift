import AppKit
import RepoBarCore

@MainActor
final class GitHubReferenceMonitor {
    private let minimumBareDigits: Int
    private let pasteboard: NSPasteboard
    private let onPasteboardWithoutReference: () async -> Void
    private let onReferences: ([GitHubReferenceQuery], String) async -> Void
    private var pasteboardPoller: PasteboardTextPoller?
    private var isRunning = false

    init(
        minimumBareDigits: Int = AppLimits.GitHubReferenceMonitor.minimumBareDigits,
        pasteboard: NSPasteboard = .general,
        onPasteboardWithoutReference: @escaping () async -> Void = {},
        onReferences: @escaping ([GitHubReferenceQuery], String) async -> Void
    ) {
        self.minimumBareDigits = minimumBareDigits
        self.pasteboard = pasteboard
        self.onPasteboardWithoutReference = onPasteboardWithoutReference
        self.onReferences = onReferences
    }

    func start() {
        guard self.isRunning == false else { return }

        if self.pasteboardPoller == nil {
            self.startPasteboardTimer()
        }
        self.isRunning = true
    }

    func stop() {
        self.pasteboardPoller?.stop()
        self.pasteboardPoller = nil
        self.isRunning = false
    }

    private func startPasteboardTimer() {
        let poller = PasteboardTextPoller(pasteboard: self.pasteboard) { [weak self] text in
            Task { @MainActor in
                self?.handlePasteboardText(text)
            }
        }
        poller.start()
        self.pasteboardPoller = poller
    }

    private func handlePasteboardText(_ text: String) {
        let queries = Self.queries(from: text, minimumBareDigits: self.minimumBareDigits)
        guard queries.isEmpty == false else {
            Task { await self.onPasteboardWithoutReference() }
            return
        }

        Task { await self.onReferences(queries, text) }
    }

    static func query(from rawText: String, minimumBareDigits: Int = AppLimits.GitHubReferenceMonitor.minimumBareDigits) -> GitHubReferenceQuery? {
        GitHubReferenceTranslator.query(from: rawText, minimumBareDigits: minimumBareDigits)
    }

    static func queries(from rawText: String, minimumBareDigits: Int = AppLimits.GitHubReferenceMonitor.minimumBareDigits) -> [GitHubReferenceQuery] {
        GitHubReferenceTranslator.queries(from: rawText, minimumBareDigits: minimumBareDigits)
    }
}

struct PasteboardPollCadence {
    private(set) var unchangedPollCount = 0

    var nextInterval: DispatchTimeInterval {
        self.unchangedPollCount >= 5 ? .seconds(5) : .seconds(1)
    }

    var nextLeeway: DispatchTimeInterval {
        self.unchangedPollCount >= 5 ? .seconds(2) : .milliseconds(500)
    }

    mutating func record(didChange: Bool) {
        self.unchangedPollCount = didChange ? 0 : self.unchangedPollCount + 1
    }
}

private final class PasteboardTextPoller: @unchecked Sendable {
    private let pasteboard: NSPasteboard
    private let queue = DispatchQueue(label: "com.steipete.repobar.github-reference-pasteboard", qos: .background)
    private let onText: @Sendable (String) -> Void
    private var timer: DispatchSourceTimer?
    private var lastChangeCount: Int
    private var cadence = PasteboardPollCadence()
    private let graceDelay: DispatchTimeInterval = .milliseconds(100)

    init(pasteboard: NSPasteboard, onText: @escaping @Sendable (String) -> Void) {
        self.pasteboard = pasteboard
        self.onText = onText
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() {
        self.queue.async { [weak self] in
            guard let self, self.timer == nil else { return }

            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.setEventHandler { [weak self] in
                self?.tick()
            }
            self.timer = timer
            self.scheduleNextPoll()
            timer.resume()
        }
    }

    func stop() {
        self.queue.async { [weak self] in
            self?.timer?.cancel()
            self?.timer = nil
        }
    }

    private func tick() {
        self.readPasteboardChangeCount { [weak self] changeCount in
            guard let self, self.timer != nil else { return }

            let didChange = changeCount != self.lastChangeCount
            self.cadence.record(didChange: didChange)
            guard didChange else {
                self.scheduleNextPoll()
                return
            }

            self.lastChangeCount = changeCount
            self.queue.asyncAfter(deadline: .now() + self.graceDelay) { [weak self] in
                guard let self, self.timer != nil else { return }

                self.readPasteboardSnapshot { [weak self] delayedSnapshot in
                    guard let self, self.timer != nil else { return }

                    defer { self.scheduleNextPoll() }

                    guard changeCount == delayedSnapshot.changeCount else { return }
                    guard let text = delayedSnapshot.text else { return }

                    self.onText(text)
                }
            }
        }
    }

    private func scheduleNextPoll() {
        self.timer?.schedule(
            deadline: .now() + self.cadence.nextInterval,
            leeway: self.cadence.nextLeeway
        )
    }

    private func readPasteboardChangeCount(_ completion: @escaping @Sendable (Int) -> Void) {
        DispatchQueue.main.async { [pasteboard = self.pasteboard, queue = self.queue] in
            let changeCount = pasteboard.changeCount
            queue.async {
                completion(changeCount)
            }
        }
    }

    private func readPasteboardSnapshot(_ completion: @escaping @Sendable (PasteboardSnapshot) -> Void) {
        DispatchQueue.main.async { [pasteboard = self.pasteboard, queue = self.queue] in
            let snapshot = PasteboardSnapshot(
                changeCount: pasteboard.changeCount,
                text: Self.readPasteboardText(from: pasteboard)
            )
            queue.async {
                completion(snapshot)
            }
        }
    }

    private static func readPasteboardText(from pasteboard: NSPasteboard) -> String? {
        if let direct = pasteboard.string(forType: .string) {
            return direct
        }

        let preferredTypes: [NSPasteboard.PasteboardType] = [
            .init("public.utf8-plain-text"),
            .init("public.utf16-external-plain-text"),
            .init("public.text")
        ]
        for item in pasteboard.pasteboardItems ?? [] {
            for type in preferredTypes {
                if let value = item.string(forType: type) {
                    return value
                }
            }
        }
        return nil
    }
}

private struct PasteboardSnapshot {
    let changeCount: Int
    let text: String?
}
