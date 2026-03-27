import XCTest
import SwiftUI
@testable import NoteNous

final class ColorExtensionsTests: XCTestCase {

    // MARK: - Hex Init

    func testHex6Digit() {
        let color = Color(hex: "#FF0000")
        let nsColor = NSColor(color)
        guard let components = nsColor.cgColor.components, components.count >= 3 else {
            XCTFail("Could not extract color components")
            return
        }
        // Red channel should be ~1.0, green and blue ~0.0
        XCTAssertEqual(components[0], 1.0, accuracy: 0.02, "Red channel should be 1.0")
        XCTAssertEqual(components[1], 0.0, accuracy: 0.02, "Green channel should be 0.0")
        XCTAssertEqual(components[2], 0.0, accuracy: 0.02, "Blue channel should be 0.0")
    }

    func testHex8Digit() {
        // 8-digit: AARRGGBB format — FF000080 = alpha=0xFF, r=0x00, g=0x00, b=0x80
        // But the code interprets as: (int >> 24) = a, (int >> 16 & 0xFF) = r, etc.
        // "#FF000080" => int = 0xFF000080 => a=0xFF, r=0x00, g=0x00, b=0x80
        let color = Color(hex: "#80FF0000")
        // a=0x80, r=0xFF, g=0x00, b=0x00
        let nsColor = NSColor(color)
        guard let components = nsColor.cgColor.components, components.count >= 4 else {
            XCTFail("Could not extract color components")
            return
        }
        XCTAssertEqual(components[0], 1.0, accuracy: 0.02, "Red channel should be 1.0")
        XCTAssertEqual(components[1], 0.0, accuracy: 0.02, "Green channel should be 0.0")
        XCTAssertEqual(components[2], 0.0, accuracy: 0.02, "Blue channel should be 0.0")
        XCTAssertEqual(components[3], 128.0 / 255.0, accuracy: 0.02, "Alpha should be ~0.50")
    }

    func testHex3Digit() {
        let color = Color(hex: "#F00")
        let nsColor = NSColor(color)
        guard let components = nsColor.cgColor.components, components.count >= 3 else {
            XCTFail("Could not extract color components")
            return
        }
        XCTAssertEqual(components[0], 1.0, accuracy: 0.02, "Red channel should be 1.0")
        XCTAssertEqual(components[1], 0.0, accuracy: 0.02, "Green channel should be 0.0")
        XCTAssertEqual(components[2], 0.0, accuracy: 0.02, "Blue channel should be 0.0")
    }

    // MARK: - Hex String Output

    func testHexString() {
        let color = Color(hex: "#FF0000")
        let hex = color.hexString
        // hexString returns 6-char uppercase hex without #
        XCTAssertEqual(hex.count, 6, "Hex string should be 6 characters")
        XCTAssertEqual(hex, "FF0000", "Red color should produce FF0000 hex string")
    }
}
