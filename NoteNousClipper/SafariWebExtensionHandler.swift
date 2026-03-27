import SafariServices
import Foundation
import os.log

/// Handles messages from the Safari web extension JavaScript.
/// Forwards clip data to the NoteNous app via its local ClipServer (localhost:23847).
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    private let logger = Logger(subsystem: "com.notenous.app.clipper", category: "SafariExtension")
    private let clipServerURL = URL(string: "http://localhost:23847/api/clip")!

    func beginRequest(with context: NSExtensionContext) {
        guard let inputItem = context.inputItems.first as? NSExtensionItem,
              let messageDict = inputItem.userInfo?[SFExtensionMessageKey] as? [String: Any] else {
            logger.error("No valid message received from extension")
            sendResponse(context: context, payload: ["success": false, "error": "Invalid message"])
            return
        }

        logger.info("Received clip request: \(messageDict.keys.joined(separator: ", "))")

        // Forward the clip data to the NoteNous ClipServer
        guard let jsonData = try? JSONSerialization.data(withJSONObject: messageDict) else {
            sendResponse(context: context, payload: ["success": false, "error": "Failed to serialize data"])
            return
        }

        var request = URLRequest(url: clipServerURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        request.timeoutInterval = 5

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                self.logger.error("ClipServer request failed: \(error.localizedDescription)")
                self.sendResponse(context: context, payload: [
                    "success": false,
                    "error": "NoteNous app is not running. Please open NoteNous first."
                ])
                return
            }

            guard let data = data,
                  let responseDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                self.sendResponse(context: context, payload: [
                    "success": false,
                    "error": "Invalid response from NoteNous"
                ])
                return
            }

            self.logger.info("ClipServer responded successfully")
            self.sendResponse(context: context, payload: responseDict)
        }
        task.resume()
    }

    private func sendResponse(context: NSExtensionContext, payload: [String: Any]) {
        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: payload]
        context.completeRequest(returningItems: [response])
    }
}
