import SwiftUI

struct HeatmapView: View {
    let cells: [HeatmapCell]
    let accentTone: AccentTone
    private let columns = 53 // roughly a year
    private let rows = 7
    private let spacing: CGFloat = 2
    private var summary: String {
        let total = cells.map(\.count).reduce(0, +)
        let maxVal = cells.map(\.count).max() ?? 0
        return "Commit activity heatmap, total \(total) commits, max \(maxVal) in a day."
    }

    init(cells: [HeatmapCell], accentTone: AccentTone = .githubGreen) {
        self.cells = cells
        self.accentTone = accentTone
    }

    var body: some View {
        let grid = HeatmapLayout.reshape(cells: self.cells, columns: self.columns, rows: self.rows)
        Canvas { context, size in
            let cellSide = self.cellSide(for: size)
            for (x, column) in grid.enumerated() {
                for (y, cell) in column.enumerated() {
                    let origin = CGPoint(
                        x: CGFloat(x) * (cellSide + self.spacing),
                        y: CGFloat(y) * (cellSide + self.spacing))
                    let rect = CGRect(origin: origin, size: CGSize(width: cellSide, height: cellSide))
                    let path = Path(roundedRect: rect, cornerRadius: cellSide * 0.2)
                    context.fill(path, with: .color(self.color(for: cell.count)))
                }
            }
        }
        .aspectRatio(CGFloat(self.columns) / CGFloat(self.rows), contentMode: .fit)
        .frame(maxWidth: .infinity, minHeight: 48, maxHeight: 120, alignment: .leading)
        .accessibilityLabel(self.summary)
        .accessibilityElement(children: .ignore)
    }

    private func color(for count: Int) -> Color {
        let palette = self.palette()
        switch count {
        case 0: return palette[0]
        case 1...3: return palette[1]
        case 4...7: return palette[2]
        case 8...12: return palette[3]
        default: return palette[4]
        }
    }

    private func palette() -> [Color] {
        switch self.accentTone {
        case .githubGreen:
            return [
                Color(nsColor: .controlBackgroundColor),
                Color(red: 0.78, green: 0.93, blue: 0.79),
                Color(red: 0.51, green: 0.82, blue: 0.56),
                Color(red: 0.2, green: 0.65, blue: 0.32),
                Color(red: 0.12, green: 0.45, blue: 0.2),
            ]
        case .system:
            let accent = Color.accentColor
            return [
                Color(nsColor: .controlBackgroundColor),
                accent.opacity(0.25),
                accent.opacity(0.45),
                accent.opacity(0.7),
                accent.opacity(0.9),
            ]
        }
    }

    private func cellSide(for size: CGSize) -> CGFloat {
        let totalSpacingX = CGFloat(self.columns - 1) * self.spacing
        let totalSpacingY = CGFloat(self.rows - 1) * self.spacing
        let availableWidth = max(size.width - totalSpacingX, 0)
        let availableHeight = max(size.height - totalSpacingY, 0)
        let side = min(availableWidth / CGFloat(self.columns), availableHeight / CGFloat(self.rows))
        return max(2, min(10, floor(side)))
    }
}

enum HeatmapLayout {
    static func reshape(cells: [HeatmapCell], columns: Int, rows: Int) -> [[HeatmapCell]] {
        var padded = cells
        if padded.count < columns * rows {
            let missing = columns * rows - padded.count
            padded.append(contentsOf: Array(repeating: HeatmapCell(date: Date(), count: 0), count: missing))
        }
        return stride(from: 0, to: padded.count, by: rows).map { index in
            Array(padded[index..<min(index + rows, padded.count)])
        }
    }
}
