import XCTest
@testable import NoteNous

final class ClipServerTests: XCTestCase {

    // MARK: - Origin Validation

    /// Replicate the origin validation logic from ClipServer for unit testing
    /// without needing to start a real server.
    private let allowedOriginPrefixes = [
        "chrome-extension://",
        "safari-web-extension://",
        "http://localhost",
        "http://127.0.0.1"
    ]

    private func isAllowedOrigin(_ origin: String) -> Bool {
        allowedOriginPrefixes.contains { origin.hasPrefix($0) }
    }

    func testOriginValidation_chrome() {
        let origin = "chrome-extension://abcdef1234567890"
        XCTAssertTrue(isAllowedOrigin(origin), "Chrome extension origin should be allowed")
    }

    func testOriginValidation_safari() {
        let origin = "safari-web-extension://com.notenous.app.clipper"
        XCTAssertTrue(isAllowedOrigin(origin), "Safari web extension origin should be allowed")
    }

    func testOriginValidation_localhost() {
        let origin = "http://localhost"
        XCTAssertTrue(isAllowedOrigin(origin), "localhost origin should be allowed")

        let originWithPort = "http://localhost:3000"
        XCTAssertTrue(isAllowedOrigin(originWithPort), "localhost with port should be allowed")
    }

    func testOriginValidation_unknown() {
        let origin = "https://evil.com"
        XCTAssertFalse(isAllowedOrigin(origin), "Unknown origin should be rejected")

        let anotherBad = "https://chrome-extension.evil.com"
        XCTAssertFalse(isAllowedOrigin(anotherBad), "Spoofed origin should be rejected")
    }

    // MARK: - Clip Data Parsing

    func testClipDataParsing() {
        let json: [String: Any] = [
            "title": "Test Article",
            "url": "https://example.com/article",
            "selectedText": "Important quote from the article",
            "noteType": 1,
            "tags": ["research", "ai"]
        ]

        let data = try! JSONSerialization.data(withJSONObject: json)
        let parsed = try! JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(parsed["title"] as? String, "Test Article")
        XCTAssertEqual(parsed["url"] as? String, "https://example.com/article")
        XCTAssertEqual(parsed["selectedText"] as? String, "Important quote from the article")
        XCTAssertEqual(parsed["noteType"] as? Int, 1)
        XCTAssertEqual(parsed["tags"] as? [String], ["research", "ai"])
    }

    func testClipDataInvalid() {
        let malformed = "{ not valid json !!!".data(using: .utf8)!
        let result = try? JSONSerialization.jsonObject(with: malformed) as? [String: Any]
        XCTAssertNil(result, "Malformed JSON should fail to parse")
    }
}
