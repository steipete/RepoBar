import AppKit
import Observation
import SwiftUI

@MainActor
protocol MenuItemMeasuring: AnyObject {
    func measuredHeight(width: CGFloat) -> CGFloat
}

@MainActor
protocol MenuItemHighlighting: AnyObject {
    func setHighlighted(_ highlighted: Bool)
}

@MainActor
@Observable
final class MenuItemHighlightState {
    var isHighlighted = false
}

private enum MenuItemSelectionBackgroundMetrics {
    static let horizontalInset: CGFloat = 6
    static let verticalInset: CGFloat = 2
    static let cornerRadius: CGFloat = 6
}

private enum MenuItemMeasurementMetrics {
    static let proposedHeight: CGFloat = 720
    static let maxHeight: CGFloat = 360
    static let fallbackHeight: CGFloat = 28
}

private struct MenuItemSelectionBackground: Shape {
    func path(in rect: CGRect) -> Path {
        let inset = rect.insetBy(
            dx: MenuItemSelectionBackgroundMetrics.horizontalInset,
            dy: MenuItemSelectionBackgroundMetrics.verticalInset
        )
        return RoundedRectangle(
            cornerRadius: MenuItemSelectionBackgroundMetrics.cornerRadius,
            style: .continuous
        ).path(in: inset)
    }
}

struct MenuItemContainerView<Content: View>: View {
    @Bindable var highlightState: MenuItemHighlightState
    let showsSubmenuIndicator: Bool
    @ViewBuilder let content: Content

    var body: some View {
        self.content
            .fixedSize(horizontal: false, vertical: true)
            .padding(.trailing, self.showsSubmenuIndicator ? MenuStyle.menuItemContainerTrailingPadding : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.menuItemHighlighted, self.highlightState.isHighlighted)
            .foregroundStyle(MenuHighlightStyle.primary(self.highlightState.isHighlighted))
            .background(alignment: .topLeading) {
                if self.highlightState.isHighlighted {
                    MenuItemSelectionBackground()
                        .fill(MenuHighlightStyle.selectionBackground(true))
                }
            }
            .overlay(alignment: .topTrailing) {
                if self.showsSubmenuIndicator {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(MenuHighlightStyle.secondary(self.highlightState.isHighlighted))
                        .padding(.top, 8)
                        .padding(.trailing, MenuStyle.menuItemContainerTrailingPadding)
                }
            }
    }
}

@MainActor
final class MenuItemHostingView: NSView, MenuItemMeasuring, MenuItemHighlighting {
    private let highlightState: MenuItemHighlightState?
    private let hostingController: NSHostingController<AnyView>
    private var contentVersion: Int = 0
    private var cachedWidth: CGFloat?
    private var cachedHeight: CGFloat?
    private var cachedContentVersion: Int = -1

    override var allowsVibrancy: Bool {
        true
    }

    override var focusRingType: NSFocusRingType {
        get { MenuFocusRingStyle.type }
        set {}
    }

    override var intrinsicContentSize: NSSize {
        let size = self.hostingController.view.intrinsicContentSize
        guard self.bounds.width > 0 else { return size }

        return NSSize(width: self.bounds.width, height: size.height)
    }

    init(rootView: AnyView, highlightState: MenuItemHighlightState) {
        self.highlightState = highlightState
        self.hostingController = NSHostingController(rootView: rootView)
        super.init(frame: .zero)
        self.contentVersion = 1
        self.configureHostingView()
    }

    @MainActor
    required init(rootView: AnyView) {
        self.highlightState = nil
        self.hostingController = NSHostingController(rootView: rootView)
        super.init(frame: .zero)
        self.contentVersion = 1
        self.configureHostingView()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        self.hostingController.view.frame = self.bounds
    }

    func setHighlighted(_ highlighted: Bool) {
        self.highlightState?.isHighlighted = highlighted
    }

    func measuredHeight(width: CGFloat) -> CGFloat {
        if self.cachedWidth == width, self.cachedContentVersion == self.contentVersion, let cachedHeight = self.cachedHeight {
            return cachedHeight
        }
        if self.frame.size.width != width || self.bounds.size.width != width {
            self.frame.size.width = width
            self.bounds.size.width = width
            self.hostingController.view.frame = self.bounds
            self.invalidateIntrinsicContentSize()
        }

        let proposed = NSSize(width: width, height: MenuItemMeasurementMetrics.proposedHeight)
        let measured = self.hostingController.sizeThatFits(in: proposed)
        let safeHeight = self.safeMeasuredHeight(from: measured.height)
        let scale = self.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let rounded = ceil(safeHeight * scale) / scale
        self.cachedWidth = width
        self.cachedHeight = rounded
        self.cachedContentVersion = self.contentVersion
        return rounded
    }

    func updateRootView(_ rootView: AnyView) {
        self.hostingController.rootView = rootView
        self.contentVersion += 1
        self.cachedWidth = nil
        self.cachedHeight = nil
        self.invalidateIntrinsicContentSize()
    }

    func updateHighlightableRootView(_ content: AnyView, showsSubmenuIndicator: Bool) {
        guard let highlightState = self.highlightState else {
            self.updateRootView(content)
            return
        }

        let wrapped = MenuItemContainerView(
            highlightState: highlightState,
            showsSubmenuIndicator: showsSubmenuIndicator
        ) {
            content
        }
        self.updateRootView(AnyView(wrapped))
    }

    private func configureHostingView() {
        self.hostingController.view.translatesAutoresizingMaskIntoConstraints = true
        self.hostingController.view.autoresizingMask = [.width, .height]
        self.hostingController.view.frame = self.bounds
        self.addSubview(self.hostingController.view)
        if #available(macOS 13.0, *) {
            self.hostingController.sizingOptions = [.minSize, .intrinsicContentSize]
        }
    }

    private func safeMeasuredHeight(from height: CGFloat) -> CGFloat {
        if height.isFinite, height > 0 {
            return min(height, MenuItemMeasurementMetrics.maxHeight)
        }

        let intrinsic = self.hostingController.view.intrinsicContentSize.height
        if intrinsic.isFinite, intrinsic > 0 {
            return min(intrinsic, MenuItemMeasurementMetrics.maxHeight)
        }

        return MenuItemMeasurementMetrics.fallbackHeight
    }
}
