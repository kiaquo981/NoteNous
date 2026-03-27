import Foundation

struct ZettelIDGenerator {
    static func generate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHHmmss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let timestamp = formatter.string(from: Date())
        let hex = String(format: "%04x", arc4random_uniform(0xFFFF))
        return "\(timestamp)-\(hex)"
    }
}
