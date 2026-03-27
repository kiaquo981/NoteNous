import XCTest
@testable import NoteNous

final class ZettelIDGeneratorTests: XCTestCase {

    func testFormat_matchesExpectedPattern() {
        let id = ZettelIDGenerator.generate()
        // Expected format: "YYYYMMDDHHmmss-XXXX" where X is hex
        let pattern = #"^\d{14}-[0-9a-f]{4}$"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(id.startIndex..., in: id)
        let match = regex.firstMatch(in: id, range: range)
        XCTAssertNotNil(match, "ZettelID '\(id)' does not match expected format YYYYMMDDHHmmss-XXXX")
    }

    func testFormat_hasCorrectLength() {
        let id = ZettelIDGenerator.generate()
        // 14 digits + dash + 4 hex = 19 chars
        XCTAssertEqual(id.count, 19)
    }

    func testUniqueness_100IDs() {
        var ids = Set<String>()
        for _ in 0..<100 {
            ids.insert(ZettelIDGenerator.generate())
        }
        XCTAssertEqual(ids.count, 100, "Expected 100 unique IDs but got \(ids.count)")
    }
}
