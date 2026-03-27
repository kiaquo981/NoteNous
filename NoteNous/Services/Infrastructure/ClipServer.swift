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

            let request = String(data: data, encoding: .utf8) ?? ""
            self.routeRequest(request, connection: connection)
        }
    }

    private func routeRequest(_ rawRequest: String, connection: NWConnection) {
        let lines = rawRequest.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            sendResponse(connection: connection, status: 400, body: ["error": "Bad request"])
            return
        }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            sendResponse(connection: connection, status: 400, body: ["error": "Bad request"])
            return
        }

        let method = String(parts[0])
        let path = String(parts[1])

        // Add CORS headers for Chrome extension
        if method == "OPTIONS" {
            sendCORSPreflight(connection: connection)
            return
        }

        switch (method, path) {
        case ("GET", "/health"):
            sendResponse(connection: connection, status: 200, body: ["status": "ok", "app": "NoteNous"])

        case ("POST", "/api/clip"):
            handleClip(rawRequest: rawRequest, connection: connection)

        default:
            sendResponse(connection: connection, status: 404, body: ["error": "Not found"])
        }
    }

    // MARK: - Clip Handler

    private func handleClip(rawRequest: String, connection: NWConnection) {
        // Extract JSON body (after the empty line separating headers from body)
        guard let bodyRange = rawRequest.range(of: "\r\n\r\n") else {
            sendResponse(connection: connection, status: 400, body: ["error": "No body found"])
            return
        }

        let bodyString = String(rawRequest[bodyRange.upperBound...])
        guard let bodyData = bodyString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] else {
            sendResponse(connection: connection, status: 400, body: ["error": "Invalid JSON"])
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

            for tagName in tagNames where !tagName.isEmpty {
                let tag = NSEntityDescription.insertNewObject(forEntityName: "TagEntity", into: bgContext)
                tag.setValue(UUID(), forKey: "id")
                tag.setValue(tagName.trimmingCharacters(in: .whitespaces), forKey: "name")
                tag.setValue(Int32(1), forKey: "usageCount")
                tag.setValue(now, forKey: "createdAt")

                let tags = note.mutableSetValue(forKey: "tags")
                tags.add(tag)
            }

            do {
                try bgContext.save()
                self.logger.info("Chrome clip saved: \(noteId.uuidString)")
                self.sendResponse(connection: connection, status: 200, body: [
                    "success": true,
                    "noteId": noteId.uuidString
                ])
            } catch {
                self.logger.error("Failed to save chrome clip: \(error.localizedDescription)")
                self.sendResponse(connection: connection, status: 500, body: [
                    "success": false,
                    "error": error.localizedDescription
                ])
            }
        }
    }

    // MARK: - Response Helpers

    private func sendResponse(connection: NWConnection, status: Int, body: [String: Any]) {
        let statusText: String
        switch status {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 404: statusText = "Not Found"
        case 500: statusText = "Internal Server Error"
        default: statusText = "Unknown"
        }

        let jsonData = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

        let response = """
        HTTP/1.1 \(status) \(statusText)\r
        Content-Type: application/json\r
        Content-Length: \(jsonData.count)\r
        Access-Control-Allow-Origin: *\r
        Access-Control-Allow-Methods: GET, POST, OPTIONS\r
        Access-Control-Allow-Headers: Content-Type\r
        Connection: close\r
        \r
        \(jsonString)
        """

        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func sendCORSPreflight(connection: NWConnection) {
        let response = """
        HTTP/1.1 204 No Content\r
        Access-Control-Allow-Origin: *\r
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
