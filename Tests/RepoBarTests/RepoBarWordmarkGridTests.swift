@testable import RepoBar
import Testing

struct RepoBarWordmarkGridTests {
    @Test
    func `grid dimensions match the seven letter wordmark`() {
        // 7 letters × (5 glyph columns + 1 spacer) − trailing spacer + padding.
        #expect(RepoBarWordmarkGrid.columns == 47)
        #expect(RepoBarWordmarkGrid.rows == 7)
        #expect(RepoBarWordmarkGrid.litMask.count == RepoBarWordmarkGrid.rows)
        #expect(RepoBarWordmarkGrid.litMask.allSatisfy { $0.count == RepoBarWordmarkGrid.columns })
    }

    @Test
    func `padding and letter spacer columns stay unlit`() {
        for row in 0 ..< RepoBarWordmarkGrid.rows {
            for column in 0 ..< RepoBarWordmarkGrid.sidePadding {
                #expect(RepoBarWordmarkGrid.litMask[row][column] == false)
                #expect(RepoBarWordmarkGrid.litMask[row][RepoBarWordmarkGrid.columns - 1 - column] == false)
            }
            for letterIndex in 0 ..< (RepoBarWordmarkGrid.word.count - 1) {
                let spacer = RepoBarWordmarkGrid.sidePadding + letterIndex * 6 + 5
                #expect(RepoBarWordmarkGrid.litMask[row][spacer] == false)
            }
        }
    }

    @Test
    func `every letter lights pixels and repeated Rs match`() {
        func letterMask(_ letterIndex: Int) -> [[Bool]] {
            let offset = RepoBarWordmarkGrid.sidePadding + letterIndex * 6
            return RepoBarWordmarkGrid.litMask.map { row in Array(row[offset ..< offset + 5]) }
        }

        for letterIndex in 0 ..< RepoBarWordmarkGrid.word.count {
            let litCount = letterMask(letterIndex).joined().count(where: { $0 })
            #expect(litCount > 10, "letter \(letterIndex) should light a full glyph")
        }
        // R appears at positions 0 and 6; identical glyphs must render identically.
        #expect(letterMask(0) == letterMask(6))
    }
}
