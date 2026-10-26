import XCTest
@testable import Neon_Vision_Editor

@MainActor
final class ForkCodeFoldingTests: XCTestCase {

    func testHiddenLineCountAndFoldability() {
        let region = ForkFoldRange(headerLine: 2, endLine: 7, depth: 1)
        XCTAssertEqual(region.hiddenLineCount, 5)
        XCTAssertTrue(region.isFoldable)

        let single = ForkFoldRange(headerLine: 4, endLine: 4, depth: 1)
        XCTAssertEqual(single.hiddenLineCount, 0)
        XCTAssertFalse(single.isFoldable)
    }

    func testNormalizeDropsNonFoldableRegions() {
        let input = [
            ForkFoldRange(headerLine: 0, endLine: 10, depth: 1),
            ForkFoldRange(headerLine: 5, endLine: 5, depth: 2), // single line → dropped
        ]
        let out = ForkCodeFolding.normalize(input)
        XCTAssertEqual(out.map(\.headerLine), [0])
    }

    func testNormalizeKeepsWidestRegionPerHeader() {
        let input = [
            ForkFoldRange(headerLine: 1, endLine: 4, depth: 2),
            ForkFoldRange(headerLine: 1, endLine: 20, depth: 1), // wider → wins
            ForkFoldRange(headerLine: 1, endLine: 8, depth: 3),
        ]
        let out = ForkCodeFolding.normalize(input)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].endLine, 20)
        XCTAssertEqual(out[0].depth, 1)
    }

    func testNormalizeSortsByHeaderLine() {
        let input = [
            ForkFoldRange(headerLine: 9, endLine: 12, depth: 1),
            ForkFoldRange(headerLine: 2, endLine: 6, depth: 1),
            ForkFoldRange(headerLine: 5, endLine: 7, depth: 2),
        ]
        let out = ForkCodeFolding.normalize(input)
        XCTAssertEqual(out.map(\.headerLine), [2, 5, 9])
    }

    func testLevelRangeIsOneThroughNine() {
        XCTAssertEqual(ForkCodeFolding.levelRange, 1...9)
    }
}
