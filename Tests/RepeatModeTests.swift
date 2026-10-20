import XCTest
@testable import RepeatCore

final class RepeatModeTests: XCTestCase {
    func testSingleRepeatStaysOnEveryTrack() {
        for index in 0..<3 {
            XCTAssertEqual(RepeatMode.one.nextIndex(after: index, count: 3, automatic: true), index)
        }
    }

    func testListRepeatTraversesAndWraps() {
        var index = 0
        var visited = [index]
        for _ in 0..<6 {
            index = RepeatMode.all.nextIndex(after: index, count: 3, automatic: true)!
            visited.append(index)
        }
        XCTAssertEqual(visited, [0, 1, 2, 0, 1, 2, 0])
    }

    func testRepeatOffStopsAtEnd() {
        XCTAssertEqual(RepeatMode.off.nextIndex(after: 0, count: 3, automatic: true), 1)
        XCTAssertNil(RepeatMode.off.nextIndex(after: 2, count: 3, automatic: true))
    }

    func testNextButtonEscapesSingleRepeat() {
        XCTAssertEqual(RepeatMode.one.nextIndex(after: 0, count: 3, automatic: false), 1)
        XCTAssertNil(RepeatMode.one.nextIndex(after: 2, count: 3, automatic: false))
        XCTAssertEqual(RepeatMode.all.nextIndex(after: 2, count: 3, automatic: false), 0)
    }

    func testOneItemListAndEmptyList() {
        XCTAssertEqual(RepeatMode.all.nextIndex(after: 0, count: 1, automatic: true), 0)
        XCTAssertEqual(RepeatMode.one.nextIndex(after: 0, count: 1, automatic: true), 0)
        XCTAssertNil(RepeatMode.off.nextIndex(after: 0, count: 1, automatic: true))
        for mode in RepeatMode.allCases {
            XCTAssertNil(mode.nextIndex(after: 0, count: 0, automatic: true))
            XCTAssertNil(mode.nextIndex(after: -1, count: 3, automatic: true))
            XCTAssertNil(mode.nextIndex(after: 3, count: 3, automatic: true))
        }
    }
}
