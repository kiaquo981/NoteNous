import Foundation
import Network
import CoreData
import os.log

/// Lightweight local HTTP server for Chrome extension communication.
/// Listens on localhost:23847 and accepts clip data via POST /api/clip.
final class ClipServer {
    static let shared = ClipServer()

    private let logger = Logger(subsystem: "com.notenous.app", category: "ClipServer")
    private let port: UInt16 = 23847
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.notenous.clipserver", qos: .utility)

    /// Allowed CORS origins — browser extensions and local development only.
    private let allowedOriginPrefixes = [
        "chrome-extension://",
        "safari-web-extension://",
        "http://localhost",
        "http://127.0.0.1"
    ]

    /// Timeout for accumulating a complete HTTP request body (seconds).
    private let receiveTimeout: TimeInterval = 5.0

    private init() {}

    func start() {
        guard listener == nil else {
            logger.info("ClipServer already running")
            return
        }

        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true

            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            listener?.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.logger.info("ClipServer listening on localhost:\(self?.port ?? 0)")
                case .failed(let error):
                    self?.logger.error("ClipServer failed: \(error.localizedDescription)")
                    self?.listener = nil
                default:
                    break
                }
            }

            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }

            listener?.start(queue: queue)
        } catch {
            logger.error("ClipServer could not start: \(error.localizedDescription)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        logger.info("ClipServer stopped")
    }

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let error = error {
                self.logger.error("Connection error: \(error.localizedDescription)")
                connection.cancel()
                return
            }

            guard let data = data, !data.isEmpty else {
                if isComplete { connection.cancel() }
                return
            }

            let headerString = String(data: data, encoding: .utf8) ?? ""

            // Parse Content-Length from headers to determine if we need more data
            let expectedContentLength = self.parseContentLength(from: headerString)
            let bodyStart = self.bodyOffset(in: headerString)

            if let expectedContentLength = expectedContentLength, let bodyStart = bodyStart {
                let receivedBodyLength = data.count - bodyStart
                if receivedBodyLength < expectedContentLength {
                    // Need to accumulate more data
                    self.accumulateBody(
                        connection,
                        accumulated: data,
                        expectedTotal: bodyStart + expectedContentLength,
                        deadline: Date().addingTimeInterval(self.receiveTimeout)
                    )
                    return
                }
            }

            self.routeRequest(headerString, connection: connection)
        }
    }

    /// Accumulates received data until expectedTotal bytes arrive or timeout.
    private func accumulateBody(_ connection: NWConnection, accumulated: Data, expectedTotal: Int, deadline: Date) {
        guard Date() < deadline else {
            logger.warning("Receive timeout: accumulated \(accumulated.count)/\(expectedTotal) bytes, proceeding with partial data")
            let request = String(data: accumulated, encoding: .utf8) ?? ""
            routeRequest(request, connection: connection)
            return
        }

        let remaining = expectedTotal - accumulated.count
        guard remaining > 0 else {
            let request = String(data: accumulated, encoding: .utf8) ?? ""
            routeRequest(request, connection: connection)
            return
        }

        connection.receive(minimumIncompleteLength: 1, maximumLength: remaining) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let error = error {
                self.logger.error("Connection error during accumulation: \(error.localizedDescription)")
                connection.cancel()
                return
            }

            var combined = accumulated
            if let data = data {
                combined.append(data)
            }

            if combined.count >= expectedTotal || isComplete {
                let request = String(data: combined, encoding: .utf8) ?? ""
                self.routeRequest(request, connection: connection)
            } else {
                self.accumulateBody(connection, accumulated: combined, expectedTotal: expectedTotal, deadline: deadline)
            }
        }
    }

    /// Parses Content-Length header value from raw HTTP request string.
    private func parseContentLength(from request: String) -> Int? {
        let lines = request.components(separatedBy: "\r\n")
        for line in lines {
            let lower = line.lowercased()
            if lower.hasPrefix("content-length:") {
                let value = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                return Int(value)
            }
        }
        return nil
    }

    /// Returns the byte offset where the HTTP body begins (after \r\n\r\n).
    private func bodyOffset(in request: String) -> Int? {
        guard let range = request.range(of: "\r\n\r\n") else { return nil }
        return request.distance(from: request.startIndex, to: range.upperBound)
    }

    private func routeRequest(_ rawRequest: String, connection: NWConnection) {
        let lines = rawRequest.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            sendResponse(connection: connection, status: 400, body: ["error": "Bad request"], origin: nil)
            return
        }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            sendResponse(connection: connection, status: 400, body: ["error": "Bad request"], origin: nil)
            return
        }

        let method = String(parts[0])
        let path = String(parts[1])

        // Extract Origin header
        let origin = extractHeader("Origin", from: lines)

        // Validate origin for CORS — reject unknown origins
        if let origin = origin, !isAllowedOrigin(origin) {
            logger.warning("Rejected request from disallowed origin: \(origin)")
            sendResponse(connection: connection, status: 403, body: ["error": "Forbidden: origin not allowed"], origin: nil)
            return
        }

        // Add CORS headers for browser extension
        if method == "OPTIONS" {
            sendCORSPreflight(connection: connection, origin: origin)
            return
        }

        switch (method, path) {
        case ("GET", "/health"):
            sendResponse(connection: connection, status: 200, body: ["status": "ok", "app": "NoteNous"], origin: origin)

        case ("POST", "/api/clip"):
            handleClip(rawRequest: rawRequest, connection: connection, origin: origin)

        default:
            sendResponse(connection: connection, status: 404, body: ["error": "Not found"], origin: origin)
        }
    }

    // MARK: - Origin Validation

    private func extractHeader(_ name: String, from lines: [String]) -> String? {
        let prefix = "\(name): "
        for line in lines {
            if line.hasPrefix(prefix) {
                return String(line.dropFirst(prefix.count))
            }
        }
        return nil
    }

    private func isAllowedOrigin(_ origin: String) -> Bool {
        allowedOriginPrefixes.contains { origin.hasPrefix($0) }
    }

    // MARK: - Clip Handler

    private func handleClip(rawRequest: String, connection: NWConnection, origin: String? = nil) {
        // Extract JSON body (after the empty line separating headers from body)
        guard let bodyRange = rawRequest.range(of: "\r\n\r\n") else {
            sendResponse(connection: connection, status: 400, body: ["error": "No body found"], origin: origin)
            return
        }

        let bodyString = String(rawRequest[bodyRange.upperBound...])
        guard let bodyData = bodyString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] else {
            sendResponse(connection: connection, status: 400, body: ["error": "Invalid JSON"], origin: origin)
            return
        }

        let title = json["title"] as? String ?? "Untitled Clip"
        let url = json["url"] as? String
        let selectedText = json["selectedText"] as? String
        let pageContent = json["pageContent"] as? String
        let noteTypeRaw = json["noteType"] as? Int ?? 0
        let contextNote = json["context"] as? String
        let tagNames = json["tags"] as? [String] ?? []

        let bgContext = CoreDataStack.shared.newBackgroundContext()
        bgContext.perform { [weak self] in
            guard let self = self else { return }

            let note = NSEntityDescription.insertNewObject(forEntityName: "NoteEntity", into: bgContext)
            let noteId = UUID()
            let now = Date()

            note.setValue(noteId, forKey: "id")
            note.setValue(title, forKey: "title")
            note.setValue(url, forKey: "sourceURL")
            note.setValue(title, forKey: "sourceTitle")
            note.setValue(Int16(noteTypeRaw), forKey: "noteTypeRaw")
            note.setValue(contextNote, forKey: "contextNote")

            var content = ""
            if let selectedText = selectedText, !selectedText.isEmpty {
                content = "> \(selectedText)"
            }
            if let pageContent = pageContent, !pageContent.isEmpty, content.isEmpty {
                content = String(pageContent.prefix(2000))
            }
            if let url = url {
                content += content.isEmpty ? "Source: \(url)" : "\n\nSource: \(url)"
            }

            note.setValue(content, forKey: "content")
            note.setValue(content, forKey: "contentPlainText")
            note.setValue(now, forKey: "createdAt")
            note.setValue(now, forKey: "updatedAt")
            note.setValue(Int16(0), forKey: "paraCategoryRaw")
            note.setValue(Int16(0), forKey: "codeStageRaw")
            note.setValue(false, forKey: "aiClassified")
            note.setValue(Float(0), forKey: "aiConfidence")
            note.setValue(Double(0), forKey: "positionX")
            note.setValue(Double(0), forKey: "positionY")
            note.setValue(false, forKey: "isPinned")
            note.setValue(false, forKey: "isArchived")

            // Use TagService to deduplicate tags (issue #9)
            let tagService = TagService(context: bgContext)
            for tagName in tagNames where !tagName.isEmpty {
                let trimmed = tagName.trimmingCharacters(in: .whitespaces)
                let tag = tagService.findOrCreate(name: trimmed)
                let tags = note.mutableSetValue(forKey: "tags")
                tags.add(tag)
                tag.usageCount += 1
            }

            do {
                try bgContext.save()
                self.logger.info("Chrome clip saved: \(noteId.uuidString)")
                self.sendResponse(connection: connection, status: 200, body: [
                    "success": true,
                    "noteId": noteId.uuidString
                ], origin: origin)
            } catch {
                self.logger.error("Failed to save chrome clip: \(error.localizedDescription)")
                self.sendResponse(connection: connection, status: 500, body: [
                    "success": false,
                    "error": error.localizedDescription
                ], origin: origin)
            }
        }
    }

    // MARK: - Response Helpers

    private func sendResponse(connection: NWConnection, status: Int, body: [String: Any], origin: String?) {
        let statusText: String
        switch status {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 403: statusText = "Forbidden"
        case 404: statusText = "Not Found"
        case 500: statusText = "Internal Server Error"
        default: statusText = "Unknown"
        }

        let jsonData = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

        // Only include CORS headers if origin is provided and allowed
        let corsHeader = origin.map { "Access-Control-Allow-Origin: \($0)\r\n" } ?? ""

        let response = """
        HTTP/1.1 \(status) \(statusText)\r
        Content-Type: application/json\r
        Content-Length: \(jsonData.count)\r
        \(corsHeader)Access-Control-Allow-Methods: GET, POST, OPTIONS\r
        Access-Control-Allow-Headers: Content-Type\r
        Connection: close\r
        \r
        \(jsonString)
        """

        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func sendCORSPreflight(connection: NWConnection, origin: String?) {
        let corsOrigin = origin ?? ""
        let response = """
        HTTP/1.1 204 No Content\r
        Access-Control-Allow-Origin: \(corsOrigin)\r
        Access-Control-Allow-Methods: GET, POST, OPTIONS\r
        Access-Control-Allow-Headers: Content-Type\r
        Access-Control-Max-Age: 86400\r
        Connection: close\r
        \r\n
        """

        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
