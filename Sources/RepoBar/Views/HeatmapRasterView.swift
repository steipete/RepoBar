import AppKit
import QuartzCore
import RepoBarCore
import SwiftUI

struct HeatmapRasterView: NSViewRepresentable {
    let cells: [HeatmapCell]
    let accentTone: AccentTone
    let isHighlighted: Bool

    func makeNSView(context _: Context) -> HeatmapRasterNSView {
        HeatmapRasterNSView()
    }

    func updateNSView(_ nsView: HeatmapRasterNSView, context _: Context) {
        nsView.update(cells: self.cells, accentTone: self.accentTone, isHighlighted: self.isHighlighted)
    }
}

final class HeatmapRasterNSView: NSView {
    private static let imageCache: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()

    private var cells: [HeatmapCell] = []
    private var accentTone: AccentTone = .githubGreen
    private var isHighlighted: Bool = false

    private var cachedBuckets: [UInt8] = []
    private var cachedBucketHash: UInt64 = 0
    private var cachedColumns: Int = 0

    private struct GeometryKey: Hashable {
        let bucketHash: UInt64
        let columns: Int
        let size: CGSize
        let cellSide: CGFloat
        let xSpacing: CGFloat
        let xOffset: CGFloat
        let scale: CGFloat
    }

    private var cachedGeometryKey: GeometryKey?
    private var cachedRectsByBucket: [[CGRect]] = Array(repeating: [], count: 5)

    private var lastAppliedRenderKey: String?
    private var lastAppliedScale: CGFloat = 0
    private var renderGeneration: UInt64 = 0
    private var renderTask: Task<Void, Never>?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
        self.layer?.actions = ["contents": NSNull()]
        self.layer?.contentsGravity = .resize
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.renderTask?.cancel()
    }

    func update(cells: [HeatmapCell], accentTone: AccentTone, isHighlighted: Bool) {
        self.cells = cells
        self.accentTone = accentTone
        self.isHighlighted = isHighlighted
        self.scheduleRender()
    }

    override func layout() {
        super.layout()
        self.scheduleRender()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        self.scheduleRender()
    }

    override func setBoundsSize(_ newSize: NSSize) {
        super.setBoundsSize(newSize)
        self.scheduleRender()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        self.scheduleRender()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        self.lastAppliedRenderKey = nil
        self.scheduleRender()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        self.lastAppliedRenderKey = nil
        self.scheduleRender()
    }

    private func scheduleRender() {
        guard self.bounds.width > 0, self.bounds.height > 0 else { return }
        guard self.window != nil else { return }

        let generation = self.renderGeneration &+ 1
        self.renderGeneration = generation
        self.renderTask?.cancel()

        let scale = max(self.window?.backingScaleFactor ?? 2, 1)
        let widthPx = max(Int((self.bounds.width * scale).rounded(.toNearestOrAwayFromZero)), 1)
        let heightPx = max(Int((self.bounds.height * scale).rounded(.toNearestOrAwayFromZero)), 1)
        let boundsSize = CGSize(width: CGFloat(widthPx) / scale, height: CGFloat(heightPx) / scale)

        let columns = HeatmapLayout.columnCount(cellCount: self.cells.count)
        let cellSide = HeatmapLayout.cellSide(forHeight: boundsSize.height, width: boundsSize.width, columns: columns)
        let xSpacing = Self.xSpacing(availableWidth: boundsSize.width, columns: columns, cellSide: cellSide, scale: scale)
        let contentWidth = Self.contentWidth(columns: columns, cellSide: cellSide, xSpacing: xSpacing)
        let xOffset = Self.balancedInset(HeatmapLayoutMetrics(
            availableWidth: boundsSize.width,
            columns: columns,
            cellSide: cellSide,
            xSpacing: xSpacing,
            contentWidth: contentWidth,
            scale: scale
        ))

        let (buckets, bucketHash) = self.ensureBuckets(columns: columns)
        let geometryKey = GeometryKey(
            bucketHash: bucketHash,
            columns: columns,
            size: boundsSize,
            cellSide: cellSide,
            xSpacing: xSpacing,
            xOffset: xOffset,
            scale: scale
        )
        let rectsByBucket = self.ensureRects(
            geometryKey: geometryKey,
            buckets: buckets,
            cellSide: cellSide,
            xSpacing: xSpacing,
            xOffset: xOffset
        )

        let (palette, paletteHash) = self.computePaletteHash()
        let appearanceKey = self.appearanceCacheKey()
        let cornerRadius = cellSide <= 3 ? 0 : cellSide * HeatmapLayout.cornerRadiusFactor

        let renderKey = [
            "v1",
            "b\(bucketHash)",
            "p\(paletteHash)",
            "c\(columns)",
            "cs\(Int(cellSide * 100))",
            "xs\(Int(xSpacing * 100))",
            "xo\(Int(xOffset * 100))",
            "cr\(Int(cornerRadius * 100))",
            "w\(widthPx)",
            "h\(heightPx)",
            "s\(Int(scale * 100))",
            "app:\(appearanceKey)"
        ].joined(separator: "|")

        if self.lastAppliedRenderKey == renderKey, self.lastAppliedScale == scale {
            return
        }

        if let cached = Self.imageCache.object(forKey: renderKey as NSString) {
            self.apply(image: cached, renderKey: renderKey, scale: scale)
            return
        }

        let payload = RenderPayload(
            widthPx: widthPx,
            heightPx: heightPx,
            scale: scale,
            rectsByBucket: rectsByBucket,
            palette: palette,
            cornerRadius: cornerRadius
        )

        self.renderTask = Task { [weak self, payload, renderKey, scale, generation] in
            if Task.isCancelled {
                return
            }
            let imageTask = Task.detached(priority: .userInitiated) { payload.renderImage() }
            let image = await imageTask.value
            if Task.isCancelled {
                return
            }
            guard let self else { return }
            guard self.renderGeneration == generation else { return }
            guard let image else { return }

            let cost = payload.cost
            Self.imageCache.setObject(image, forKey: renderKey as NSString, cost: cost)
            self.apply(image: image, renderKey: renderKey, scale: scale)
        }
    }

    private func apply(image: CGImage, renderKey: String, scale: CGFloat) {
        guard let layer = self.layer else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.contentsScale = scale
        layer.contents = image
        CATransaction.commit()
        self.lastAppliedRenderKey = renderKey
        self.lastAppliedScale = scale
    }

    private func ensureBuckets(columns: Int) -> ([UInt8], UInt64) {
        let totalCells = columns * HeatmapLayout.rows
        if self.cachedColumns == columns, self.cachedBuckets.count == totalCells {
            let hash = Self.bucketHash(for: self.cells, totalCells: totalCells)
            if hash == self.cachedBucketHash {
                return (self.cachedBuckets, hash)
            }
        }

        let (buckets, hash) = Self.buildBuckets(for: self.cells, totalCells: totalCells)
        self.cachedBuckets = buckets
        self.cachedBucketHash = hash
        self.cachedColumns = columns
        return (buckets, hash)
    }

    private func ensureRects(
        geometryKey: GeometryKey,
        buckets: [UInt8],
        cellSide: CGFloat,
        xSpacing: CGFloat,
        xOffset: CGFloat
    ) -> [[CGRect]] {
        if self.cachedGeometryKey == geometryKey {
            return self.cachedRectsByBucket
        }

        var rectsByBucket: [[CGRect]] = Array(repeating: [], count: 5)
        rectsByBucket[0].reserveCapacity(buckets.count)

        let stepX = cellSide + xSpacing
        let stepY = cellSide + HeatmapLayout.spacing

        var columnX: [CGFloat] = []
        columnX.reserveCapacity(geometryKey.columns)
        for column in 0 ..< geometryKey.columns {
            let x = xOffset + CGFloat(column) * stepX
            columnX.append(Self.snapToPixel(x, scale: geometryKey.scale))
        }

        var rowY: [CGFloat] = []
        rowY.reserveCapacity(HeatmapLayout.rows)
        for row in 0 ..< HeatmapLayout.rows {
            let y = CGFloat(row) * stepY
            rowY.append(Self.snapToPixel(y, scale: geometryKey.scale))
        }

        for index in 0 ..< buckets.count {
            let bucket = Int(buckets[index])
            let column = index / HeatmapLayout.rows
            let row = index % HeatmapLayout.rows
            let origin = CGPoint(x: columnX[column], y: rowY[row])
            let rect = CGRect(origin: origin, size: CGSize(width: cellSide, height: cellSide))
            rectsByBucket[bucket].append(rect)
        }

        self.cachedGeometryKey = geometryKey
        self.cachedRectsByBucket = rectsByBucket
        return rectsByBucket
    }

    private func appearanceCacheKey() -> String {
        let best = self.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
        return best?.rawValue ?? self.effectiveAppearance.name.rawValue
    }

    private func computePaletteHash() -> ([RGBAColor], UInt64) {
        let palette = HeatmapPalette.palette(
            accentTone: self.accentTone,
            isHighlighted: self.isHighlighted,
            appearance: self.effectiveAppearance
        )
        var hash: UInt64 = 2_166_136_261
        for color in palette {
            for byte in [color.r, color.g, color.b, color.a] {
                hash ^= UInt64(byte)
                hash &*= 16_777_619
            }
        }
        return (palette, hash)
    }

    private static func xSpacing(availableWidth: CGFloat, columns: Int, cellSide: CGFloat, scale: CGFloat) -> CGFloat {
        guard columns > 1 else { return 0 }

        let base = HeatmapLayout.spacing
        let ideal = (availableWidth - CGFloat(columns) * cellSide) / CGFloat(columns - 1)
        return Self.snapToPixel(max(base, ideal), scale: scale)
    }

    private static func contentWidth(columns: Int, cellSide: CGFloat, xSpacing: CGFloat) -> CGFloat {
        let totalSpacingX = CGFloat(max(columns - 1, 0)) * xSpacing
        return CGFloat(max(columns, 0)) * cellSide + totalSpacingX
    }

    private struct HeatmapLayoutMetrics {
        let availableWidth: CGFloat
        let columns: Int
        let cellSide: CGFloat
        let xSpacing: CGFloat
        let contentWidth: CGFloat
        let scale: CGFloat
    }

    private static func balancedInset(_ metrics: HeatmapLayoutMetrics) -> CGFloat {
        guard metrics.availableWidth >= metrics.contentWidth, metrics.columns > 0 else { return 0 }

        let stepX = metrics.cellSide + metrics.xSpacing
        let ideal = (metrics.availableWidth - metrics.contentWidth) / 2
        let step = 1 / max(metrics.scale, 1)

        var best = Self.snapToPixel(ideal, scale: metrics.scale)
        var bestScore = CGFloat.greatestFiniteMagnitude

        var candidates: [CGFloat] = []
        candidates.reserveCapacity(5)
        for delta in -2 ... 2 {
            candidates.append(Self.snapToPixel(ideal + CGFloat(delta) * step, scale: metrics.scale))
        }

        for offset in Array(Set(candidates)).sorted() {
            let left = Self.snapToPixel(offset, scale: metrics.scale)
            let lastX = Self.snapToPixel(left + CGFloat(metrics.columns - 1) * stepX, scale: metrics.scale)
            let rightEdge = lastX + metrics.cellSide
            let rightGap = metrics.availableWidth - rightEdge
            let score = abs(left - rightGap) + (rightGap < 0 ? abs(rightGap) * 10 : 0)
            if score < bestScore {
                bestScore = score
                best = left
            }
        }

        return best
    }

    private static func snapToPixel(_ value: CGFloat, scale: CGFloat) -> CGFloat {
        guard scale > 0 else { return value }

        return round(value * scale) / scale
    }

    private static func bucketIndex(for count: Int) -> UInt8 {
        switch count {
        case 0: 0
        case 1 ... 3: 1
        case 4 ... 7: 2
        case 8 ... 12: 3
        default: 4
        }
    }

    private static func buildBuckets(for cells: [HeatmapCell], totalCells: Int) -> ([UInt8], UInt64) {
        var buckets: [UInt8] = []
        buckets.reserveCapacity(totalCells)

        var hash: UInt64 = 1_469_598_103_934_665_603
        for cell in cells {
            let bucket = Self.bucketIndex(for: cell.count)
            buckets.append(bucket)
            hash ^= UInt64(bucket)
            hash &*= 1_099_511_628_211
        }
        if buckets.count < totalCells {
            let missing = totalCells - buckets.count
            for _ in 0 ..< missing {
                buckets.append(0)
                hash ^= 0
                hash &*= 1_099_511_628_211
            }
        }
        return (buckets, hash)
    }

    private static func bucketHash(for cells: [HeatmapCell], totalCells: Int) -> UInt64 {
        var hash: UInt64 = 1_469_598_103_934_665_603
        var written = 0
        for cell in cells {
            let bucket = Self.bucketIndex(for: cell.count)
            hash ^= UInt64(bucket)
            hash &*= 1_099_511_628_211
            written += 1
        }
        if written < totalCells {
            let missing = totalCells - written
            for _ in 0 ..< missing {
                hash ^= 0
                hash &*= 1_099_511_628_211
            }
        }
        return hash
    }
}

private struct RGBAColor: Hashable {
    let r: UInt8
    let g: UInt8
    let b: UInt8
    let a: UInt8
}

private enum HeatmapPalette {
    static func palette(accentTone: AccentTone, isHighlighted: Bool, appearance: NSAppearance) -> [RGBAColor] {
        var result: [RGBAColor] = []
        appearance.performAsCurrentDrawingAppearance {
            if isHighlighted {
                let base = NSColor.selectedMenuItemTextColor
                result = [
                    self.rgba(base.withAlphaComponent(0.36)),
                    self.rgba(base.withAlphaComponent(0.56)),
                    self.rgba(base.withAlphaComponent(0.72)),
                    self.rgba(base.withAlphaComponent(0.86)),
                    self.rgba(base.withAlphaComponent(0.96))
                ]
                return
            }

            let empty = NSColor.quaternaryLabelColor
            switch accentTone {
            case .githubGreen:
                result = [
                    self.rgba(empty),
                    self.rgba(NSColor(srgbRed: 0.74, green: 0.86, blue: 0.75, alpha: 0.6)),
                    self.rgba(NSColor(srgbRed: 0.56, green: 0.76, blue: 0.6, alpha: 0.65)),
                    self.rgba(NSColor(srgbRed: 0.3, green: 0.62, blue: 0.38, alpha: 0.7)),
                    self.rgba(NSColor(srgbRed: 0.18, green: 0.46, blue: 0.24, alpha: 0.75))
                ]
            case .system:
                let accent = NSColor.controlAccentColor
                result = [
                    self.rgba(empty),
                    self.rgba(accent.withAlphaComponent(0.22)),
                    self.rgba(accent.withAlphaComponent(0.36)),
                    self.rgba(accent.withAlphaComponent(0.5)),
                    self.rgba(accent.withAlphaComponent(0.65))
                ]
            }
        }
        return result
    }

    private static func rgba(_ nsColor: NSColor) -> RGBAColor {
        let rgb = nsColor.usingColorSpace(.deviceRGB) ?? nsColor
        func clamp(_ value: CGFloat) -> UInt8 {
            UInt8(max(0, min(255, (value * 255).rounded())))
        }
        return RGBAColor(
            r: clamp(rgb.redComponent),
            g: clamp(rgb.greenComponent),
            b: clamp(rgb.blueComponent),
            a: clamp(rgb.alphaComponent)
        )
    }
}

private struct RenderPayload {
    let widthPx: Int
    let heightPx: Int
    let scale: CGFloat
    let rectsByBucket: [[CGRect]]
    let palette: [RGBAColor]
    let cornerRadius: CGFloat

    var cost: Int {
        self.widthPx * self.heightPx * 4
    }

    func renderImage() -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: self.widthPx,
            height: self.heightPx,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.setShouldAntialias(self.cornerRadius > 0)
        context.setAllowsAntialiasing(self.cornerRadius > 0)
        context.interpolationQuality = .none

        context.clear(CGRect(x: 0, y: 0, width: self.widthPx, height: self.heightPx))
        context.translateBy(x: 0, y: CGFloat(self.heightPx))
        context.scaleBy(x: self.scale, y: -self.scale)

        if self.cornerRadius <= 0 {
            for bucket in 0 ..< min(self.rectsByBucket.count, self.palette.count) {
                let rects = self.rectsByBucket[bucket]
                if rects.isEmpty {
                    continue
                }
                self.setFillColor(self.palette[bucket], on: context)
                context.fill(rects)
            }
        } else {
            for bucket in 0 ..< min(self.rectsByBucket.count, self.palette.count) {
                let rects = self.rectsByBucket[bucket]
                if rects.isEmpty {
                    continue
                }
                let path = CGMutablePath()
                for rect in rects {
                    path.addRoundedRect(in: rect, cornerWidth: self.cornerRadius, cornerHeight: self.cornerRadius)
                }
                context.addPath(path)
                self.setFillColor(self.palette[bucket], on: context)
                context.fillPath()
            }
        }

        return context.makeImage()
    }

    private func setFillColor(_ color: RGBAColor, on context: CGContext) {
        context.setFillColor(
            red: CGFloat(color.r) / 255,
            green: CGFloat(color.g) / 255,
            blue: CGFloat(color.b) / 255,
            alpha: CGFloat(color.a) / 255
        )
    }
}
