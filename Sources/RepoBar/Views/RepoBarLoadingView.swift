import SwiftUI

/// Pixel-glyph layout for the animated "REPOBAR" contribution grid shown while
/// data loads. Mirrors the wordmark animation on https://repobar.app.
enum RepoBarWordmarkGrid {
    static let rows = 7
    static let sidePadding = 3
    static let word = "REPOBAR"
    /// Each glyph is 5 columns wide plus 1 spacer column between letters.
    static let columns = sidePadding * 2 + word.count * 6 - 1

    private static let glyphs: [Character: [String]] = [
        "R": ["XXXX.", "X...X", "X...X", "XXXX.", "X.X..", "X..X.", "X...X"],
        "E": ["XXXXX", "X....", "X....", "XXXX.", "X....", "X....", "XXXXX"],
        "P": ["XXXX.", "X...X", "X...X", "XXXX.", "X....", "X....", "X...."],
        "O": [".XXX.", "X...X", "X...X", "X...X", "X...X", "X...X", ".XXX."],
        "B": ["XXXX.", "X...X", "X...X", "XXXX.", "X...X", "X...X", "XXXX."],
        "A": [".XXX.", "X...X", "X...X", "XXXXX", "X...X", "X...X", "X...X"]
    ]

    /// Row-major lit mask: `litMask[row][column]` is true where the wordmark
    /// has a filled pixel.
    static let litMask: [[Bool]] = {
        var mask = Array(repeating: Array(repeating: false, count: columns), count: rows)
        for (letterIndex, letter) in word.enumerated() {
            guard let glyph = glyphs[letter] else { continue }

            let offset = sidePadding + letterIndex * 6
            for row in 0 ..< rows {
                for (columnIndex, pixel) in glyph[row].enumerated() where pixel == "X" {
                    mask[row][offset + columnIndex] = true
                }
            }
        }
        return mask
    }()
}

/// Contribution-graph grid that spells "REPOBAR" while content loads: cells
/// pop in staggered by column (like the website's year strip), then shimmer
/// gently for as long as loading continues.
struct RepoBarLoadingGridView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startDate = Date()

    private struct Cell {
        let column: Int
        let row: Int
        /// Palette bucket 0...4; letters use 3/4, sparse background noise uses 1.
        let level: Int
        let appearDelay: Double
    }

    private static let appearDuration = 0.5
    private static let columnStagger = 0.028
    private static let shimmerPeriod = 2.6

    private static let cells: [Cell] = {
        var generator = SplitMix64(seed: 0x5245_504F_4241_5221)
        var cells: [Cell] = []
        cells.reserveCapacity(RepoBarWordmarkGrid.rows * RepoBarWordmarkGrid.columns)
        for row in 0 ..< RepoBarWordmarkGrid.rows {
            for column in 0 ..< RepoBarWordmarkGrid.columns {
                let lit = RepoBarWordmarkGrid.litMask[row][column]
                let level: Int = if lit {
                    Double.random(in: 0 ... 1, using: &generator) > 0.35 ? 4 : 3
                } else {
                    Double.random(in: 0 ... 1, using: &generator) > 0.88 ? 1 : 0
                }
                let jitter = Double.random(in: 0 ... 0.2, using: &generator)
                cells.append(Cell(
                    column: column,
                    row: row,
                    level: level,
                    appearDelay: Double(column) * columnStagger + jitter
                ))
            }
        }
        return cells
    }()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: self.reduceMotion)) { timeline in
            Canvas { context, size in
                let elapsed = timeline.date.timeIntervalSince(self.startDate)
                self.draw(in: &context, size: size, elapsed: elapsed, animated: !self.reduceMotion)
            }
        }
        .accessibilityHidden(true)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, elapsed: Double, animated: Bool) {
        let columns = CGFloat(RepoBarWordmarkGrid.columns)
        let rows = CGFloat(RepoBarWordmarkGrid.rows)
        let step = min(size.width / columns, size.height / rows)
        guard step > 0 else { return }

        let gap = max(0.5, step * 0.18)
        let side = step - gap
        let originX = (size.width - (step * columns - gap)) / 2
        let originY = (size.height - (step * rows - gap)) / 2
        let palette = Self.palette(for: self.colorScheme)

        for cell in Self.cells {
            var opacity = 1.0
            var scale = 1.0
            if animated, cell.level >= 3 {
                let progress = min(max((elapsed - cell.appearDelay) / Self.appearDuration, 0), 1)
                let eased = 1 - pow(1 - progress, 3)
                opacity = eased
                scale = 0.4 + 0.6 * eased
                // Gentle brightness wave across the word once the pop-in settled.
                let shimmerStrength = min(max((elapsed - 1.8) / 0.8, 0), 1)
                if shimmerStrength > 0 {
                    let phase = elapsed * (2 * .pi / Self.shimmerPeriod) - Double(cell.column) * 0.28
                    opacity *= 1 - 0.25 * shimmerStrength * (0.5 + 0.5 * sin(phase))
                }
            }
            guard opacity > 0 else { continue }

            let scaledSide = side * scale
            let inset = (side - scaledSide) / 2
            let rect = CGRect(
                x: originX + CGFloat(cell.column) * step + inset,
                y: originY + CGFloat(cell.row) * step + inset,
                width: scaledSide,
                height: scaledSide
            )
            context.fill(
                Path(roundedRect: rect, cornerRadius: scaledSide * 0.2),
                with: .color(palette[cell.level].opacity(opacity))
            )
        }
    }

    /// Level 0 mirrors the empty heatmap cell; lit levels follow GitHub's
    /// contribution greens — the bright dark-mode set matches the website,
    /// the light set matches `HeatmapRasterView`'s in-app palette.
    private static func palette(for colorScheme: ColorScheme) -> [Color] {
        if colorScheme == .dark {
            return [
                Color(nsColor: .quaternaryLabelColor),
                Color(red: 0.055, green: 0.267, blue: 0.161),
                Color(red: 0.0, green: 0.427, blue: 0.196),
                Color(red: 0.149, green: 0.651, blue: 0.255),
                Color(red: 0.224, green: 0.827, blue: 0.325)
            ]
        }
        return [
            Color(nsColor: .quaternaryLabelColor),
            Color(red: 0.74, green: 0.86, blue: 0.75).opacity(0.6),
            Color(red: 0.56, green: 0.76, blue: 0.6).opacity(0.65),
            Color(red: 0.3, green: 0.62, blue: 0.38).opacity(0.7),
            Color(red: 0.18, green: 0.46, blue: 0.24).opacity(0.75)
        ]
    }
}

/// Deterministic RNG so the grid's speckle pattern is stable across renders.
private struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        self.state &+= 0x9E37_79B9_7F4A_7C15
        var z = self.state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
