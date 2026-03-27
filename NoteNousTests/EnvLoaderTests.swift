import XCTest
@testable import NoteNous

final class EnvLoaderTests: XCTestCase {

    /// Mirror of EnvLoader.parseEnv for isolated unit testing.
    private func parseEnv(_ contents: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            result[key] = value
        }
        return result
    }

    func testParseEnv() {
        let contents = "KEY=value"
        let result = parseEnv(contents)
        XCTAssertEqual(result["KEY"], "value")
    }

    func testParseEnvWithQuotes() {
        let contents = """
        API_KEY="sk-test-1234"
        SECRET='my-secret'
        """
        let result = parseEnv(contents)
        XCTAssertEqual(result["API_KEY"], "sk-test-1234", "Double quotes should be stripped")
        XCTAssertEqual(result["SECRET"], "my-secret", "Single quotes should be stripped")
    }

    func testParseEnvComments() {
        let contents = """
        # This is a comment
        REAL_KEY=real_value
        # Another comment
        """
        let result = parseEnv(contents)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result["REAL_KEY"], "real_value")
    }

    func testParseEnvEmpty() {
        let contents = """

        KEY=value

        OTHER=data

        """
        let result = parseEnv(contents)
        XCTAssertEqual(result.count, 2, "Empty lines should be ignored")
        XCTAssertEqual(result["KEY"], "value")
        XCTAssertEqual(result["OTHER"], "data")
    }

    func testAPIKeyRetrieval() {
        let contents = "OPENROUTER_API_KEY=sk-or-test-abc123"
        let result = parseEnv(contents)
        let apiKey = result["OPENROUTER_API_KEY"]
        XCTAssertNotNil(apiKey)
        XCTAssertEqual(apiKey, "sk-or-test-abc123")
    }
}
