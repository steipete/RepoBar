import AppKit
import RepoBarCore
import SwiftUI

struct RepoAutocompleteWindowView: NSViewRepresentable {
    let suggestions: [Repository]
    @Binding var selectedIndex: Int
    let keyboardNavigating: Bool
    let onSelect: (String) -> Void
    let width: CGFloat
    @Binding var isShowing: Bool

    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if self.isShowing, !self.suggestions.isEmpty {
            context.coordinator.showDropdown(
                on: nsView,
                suggestions: self.suggestions,
                selectedIndex: self.$selectedIndex,
                keyboardNavigating: self.keyboardNavigating,
                width: self.width
            )
        } else {
            context.coordinator.hideDropdown()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: self.onSelect, isShowing: self.$isShowing, selectedIndex: self.$selectedIndex)
    }

    @MainActor
    class Coordinator: NSObject {
        private final class DropdownWindow: NSPanel {
            override var canBecomeKey: Bool {
                false
            }

            override var canBecomeMain: Bool {
                false
            }
        }

        private var dropdownWindow: NSWindow?
        private var hostingView: NSHostingView<AnyView>?
        private let onSelect: (String) -> Void
        @Binding var isShowing: Bool
        @Binding var selectedIndex: Int
        private nonisolated(unsafe) var clickMonitor: Any?
        private var anchorTopY: CGFloat?
        private var anchorLeftX: CGFloat?

        init(onSelect: @escaping (String) -> Void, isShowing: Binding<Bool>, selectedIndex: Binding<Int>) {
            self.onSelect = onSelect
            self._isShowing = isShowing
            self._selectedIndex = selectedIndex
            super.init()
        }

        deinit {
            if let monitor = clickMonitor {
                DispatchQueue.main.async {
                    NSEvent.removeMonitor(monitor)
                }
            }
        }

        @MainActor
        private func cleanupClickMonitor() {
            if let monitor = clickMonitor {
                NSEvent.removeMonitor(monitor)
                self.clickMonitor = nil
            }
        }

        @MainActor
        func showDropdown(
            on view: NSView,
            suggestions: [Repository],
            selectedIndex: Binding<Int>,
            keyboardNavigating: Bool,
            width: CGFloat
        ) {
            guard let parentWindow = view.window else { return }

            if self.dropdownWindow == nil {
                let window = DropdownWindow(
                    contentRect: NSRect(x: 0, y: 0, width: width, height: 200),
                    styleMask: [.borderless, .nonactivatingPanel],
                    backing: .buffered,
                    defer: false
                )
                window.isOpaque = false
                window.backgroundColor = .clear
                window.hasShadow = true
                window.level = .floating
                window.isReleasedWhenClosed = false
                window.acceptsMouseMovedEvents = true
                window.isFloatingPanel = true
                window.collectionBehavior = [.transient, .ignoresCycle]

                let hostingView = NSHostingView(rootView: AnyView(EmptyView()))
                window.contentView = hostingView

                self.dropdownWindow = window
                self.hostingView = hostingView
            }

            guard let window = dropdownWindow,
                  let hostingView else { return }

            let resolvedWidth = max(420, width + 160)
            let maxVisibleRows = min(AppLimits.Autocomplete.settingsSearchLimit, 10)
            let visibleRows = min(maxVisibleRows, suggestions.count)
            let rowHeight: CGFloat = 52
            let dividerHeight: CGFloat = 1
            let resolvedHeight = (rowHeight * CGFloat(visibleRows) + dividerHeight * CGFloat(max(0, visibleRows - 1))).rounded(.up)
            let content = RepoAutocompleteListView(
                suggestions: suggestions,
                selectedIndex: selectedIndex,
                keyboardNavigating: keyboardNavigating,
                height: resolvedHeight,
                rowHeight: rowHeight
            ) { [weak self] fullName in
                self?.onSelect(fullName)
                self?.isShowing = false
            }
            .frame(width: resolvedWidth)
            .frame(height: resolvedHeight)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )

            hostingView.rootView = AnyView(content)

            let viewFrame = view.convert(view.bounds, to: nil)
            let screenFrame = parentWindow.convertToScreen(viewFrame)
            let computedTopY = (screenFrame.minY - 6).rounded(.toNearestOrAwayFromZero)
            let computedLeftX = screenFrame.minX.rounded(.toNearestOrAwayFromZero)
            if self.anchorTopY == nil || abs((self.anchorTopY ?? computedTopY) - computedTopY) > 1 {
                self.anchorTopY = computedTopY
            }
            if self.anchorLeftX == nil || abs((self.anchorLeftX ?? computedLeftX) - computedLeftX) > 1 {
                self.anchorLeftX = computedLeftX
            }

            let topY = self.anchorTopY ?? computedTopY
            let leftX = self.anchorLeftX ?? computedLeftX
            let windowFrame = NSRect(
                x: leftX,
                y: topY - resolvedHeight,
                width: resolvedWidth,
                height: resolvedHeight
            )
            let shouldAnimate = resolvedHeight > window.frame.height
            window.setFrame(windowFrame, display: false, animate: shouldAnimate)

            if window.parent == nil {
                parentWindow.addChildWindow(window, ordered: .above)
            }
            window.orderFront(nil)

            if self.clickMonitor == nil {
                self.clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                    if event.window != window {
                        self?.isShowing = false
                    }
                    return event
                }
            }
        }

        @MainActor
        func hideDropdown() {
            self.cleanupClickMonitor()
            self.anchorTopY = nil
            self.anchorLeftX = nil

            if let window = dropdownWindow {
                if let parent = window.parent {
                    parent.removeChildWindow(window)
                }
                window.orderOut(nil)
            }
        }
    }
}

private struct RepoAutocompleteListView: View {
    let suggestions: [Repository]
    @Binding var selectedIndex: Int
    let keyboardNavigating: Bool
    let height: CGFloat
    let rowHeight: CGFloat
    let onSelect: (String) -> Void
    @State private var mouseHoverTriggered = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(self.suggestions.enumerated()), id: \.element.id) { index, repo in
                        RepoAutocompleteRow(
                            repo: repo,
                            isSelected: index == self.selectedIndex
                        ) {
                            self.onSelect(repo.fullName)
                        }
                        .frame(height: self.rowHeight)
                        .id(index)
                        .onHover { hovering in
                            if hovering {
                                self.mouseHoverTriggered = true
                                self.selectedIndex = index
                            }
                        }

                        if index < self.suggestions.count - 1 {
                            Divider()
                                .padding(.horizontal, 8)
                        }
                    }
                }
            }
            .scrollIndicators(.visible)
            .frame(height: self.height)
            .onChange(of: self.selectedIndex) { _, newIndex in
                let shouldScroll = newIndex >= 0
                    && newIndex < self.suggestions.count
                    && self.keyboardNavigating
                    && !self.mouseHoverTriggered
                if shouldScroll {
                    withAnimation(.easeInOut(duration: 0.1)) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
                self.mouseHoverTriggered = false
            }
        }
    }
}

private struct RepoAutocompleteRow: View {
    let repo: Repository
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: self.onTap) {
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(self.repo.fullName)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        HStack(spacing: 6) {
                            if self.repo.isFork {
                                Badge(text: "Fork")
                            }
                            if self.repo.isArchived {
                                Badge(text: "Archived")
                            }
                            if self.repo.discussionsEnabled == true {
                                Badge(text: "Discussions")
                            }
                            if let lang = self.repo.language, !lang.isEmpty {
                                Badge(text: lang)
                            }
                        }
                    }

                    if let description = self.repo.description, !description.isEmpty {
                        Text(description)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    } else {
                        Text(self.subtitleText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("★ \(Self.compactCount(self.repo.stars))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    if let pushedAt = self.repo.pushedAt {
                        Text("pushed \(Self.compactAge(since: pushedAt))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(self.isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(
            HStack {
                if self.isSelected {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 2)
                }
                Spacer()
            }
            .allowsHitTesting(false)
        )
    }

    private var subtitleText: String {
        var parts: [String] = []
        parts.append("★ \(Self.compactCount(self.repo.stars))")
        parts.append("⑂ \(Self.compactCount(self.repo.forks))")
        parts.append("\(Self.compactCount(self.repo.openIssues)) issues")
        if let pushedAt = self.repo.pushedAt {
            parts.append("pushed \(Self.compactAge(since: pushedAt))")
        }
        return parts.joined(separator: "  •  ")
    }

    private static func compactCount(_ value: Int) -> String {
        guard value >= 1000 else { return "\(value)" }

        let divisor: Double
        let suffix: String
        if value >= 1_000_000 {
            divisor = 1_000_000
            suffix = "m"
        } else {
            divisor = 1000
            suffix = "k"
        }

        let scaled = Double(value) / divisor
        let rounded = (scaled * 10).rounded() / 10
        let text = if rounded.truncatingRemainder(dividingBy: 1) == 0 {
            "\(Int(rounded))"
        } else {
            String(format: "%.1f", rounded)
        }
        return "\(text)\(suffix)"
    }

    private static func compactAge(since date: Date) -> String {
        let seconds = max(0, Date().timeIntervalSince(date))
        let minutes = Int(seconds / 60)
        if minutes < 1 {
            return "now"
        }
        if minutes < 60 {
            return "\(minutes)m"
        }

        let hours = minutes / 60
        if hours < 24 {
            return "\(hours)h"
        }

        let days = hours / 24
        if days < 7 {
            return "\(days)d"
        }

        let weeks = days / 7
        if weeks < 8 {
            return "\(weeks)w"
        }

        let months = days / 30
        if months < 24 {
            return "\(months)mo"
        }

        let years = days / 365
        return "\(years)y"
    }
}

private struct Badge: View {
    let text: String

    var body: some View {
        Text(self.text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.primary.opacity(0.06), in: Capsule())
            .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }
}
