import SwiftUI
import AppKit

// MARK: - MarkdownTextView

struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    var onWikilinkTrigger: ((_ query: String) -> Void)?
    var onWikilinkDismiss: (() -> Void)?
    var onContentChange: ((_ newText: String) -> Void)?
    var onCursorPositionChange: ((_ position: Int) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = MarkdownNSTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.usesFontPanel = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.textColor = NSColor.labelColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 16, height: 12)
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        textView.delegate = context.coordinator
        textView.string = text
        context.coordinator.textView = textView

        scrollView.documentView = textView

        // Apply initial highlighting
        DispatchQueue.main.async {
            context.coordinator.applyMarkdownHighlighting()
        }

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? MarkdownNSTextView else { return }

        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
            context.coordinator.applyMarkdownHighlighting()
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownTextView
        weak var textView: MarkdownNSTextView?
        private var isUpdating = false
        private var wikilinkTrackingRange: NSRange?

        init(_ parent: MarkdownTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView,
                  !isUpdating else { return }

            isUpdating = true
            let newText = textView.string
            parent.text = newText
            parent.onContentChange?(newText)
            applyMarkdownHighlighting()
            detectWikilinkTrigger()
            isUpdating = false
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = textView else { return }
            let position = textView.selectedRange().location
            parent.onCursorPositionChange?(position)

            // Check if we're still inside a wikilink trigger
            if wikilinkTrackingRange != nil {
                detectWikilinkTrigger()
            }
        }

        // MARK: - Wikilink Detection

        private func detectWikilinkTrigger() {
            guard let textView = textView else { return }
            let text = textView.string
            let cursorLocation = textView.selectedRange().location

            guard cursorLocation > 0 && cursorLocation <= text.count else {
                dismissWikilink()
                return
            }

            let nsText = text as NSString
            let textBeforeCursor = nsText.substring(to: cursorLocation)

            // Find the last `[[` that doesn't have a closing `]]`
            if let openRange = textBeforeCursor.range(of: "[[", options: .backwards) {
                let afterOpen = textBeforeCursor[openRange.upperBound...]
                // If there's a `]]` after the `[[`, we're not in a wikilink
                if afterOpen.contains("]]") {
                    dismissWikilink()
                    return
                }
                // We're inside an open wikilink
                let query = String(afterOpen)
                wikilinkTrackingRange = NSRange(openRange, in: textBeforeCursor)
                parent.onWikilinkTrigger?(query)
            } else {
                dismissWikilink()
            }
        }

        private func dismissWikilink() {
            if wikilinkTrackingRange != nil {
                wikilinkTrackingRange = nil
                parent.onWikilinkDismiss?()
            }
        }

        /// Inserts a completed wikilink at the current trigger position.
        func insertWikilink(title: String) {
            guard let textView = textView else { return }
            let text = textView.string
            let cursorLocation = textView.selectedRange().location

            let nsText = text as NSString
            let textBeforeCursor = nsText.substring(to: cursorLocation)

            guard let openRange = textBeforeCursor.range(of: "[[", options: .backwards) else { return }

            let startIndex = textBeforeCursor.distance(from: textBeforeCursor.startIndex, to: openRange.lowerBound)
            let replaceRange = NSRange(location: startIndex, length: cursorLocation - startIndex)
            let replacement = "[[\(title)]]"

            if textView.shouldChangeText(in: replaceRange, replacementString: replacement) {
                textView.replaceCharacters(in: replaceRange, with: replacement)
                textView.didChangeText()

                let newCursorPos = startIndex + replacement.count
                textView.setSelectedRange(NSRange(location: newCursorPos, length: 0))
            }

            wikilinkTrackingRange = nil
        }

        // MARK: - Markdown Highlighting

        func applyMarkdownHighlighting() {
            guard let textView = textView else { return }
            let text = textView.string
            let fullRange = NSRange(location: 0, length: (text as NSString).length)
            guard fullRange.length > 0 else { return }

            let storage = textView.textStorage!
            let baseFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
            let baseColor = NSColor.labelColor

            storage.beginEditing()

            // Reset to base style
            storage.addAttributes([
                .font: baseFont,
                .foregroundColor: baseColor
            ], range: fullRange)

            // Headers: lines starting with #
            applyPattern(#"^#{1,6}\s+.+$"#, to: storage, in: text, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .bold)
            ])

            // Bold: **text**
            applyPattern(#"\*\*(.+?)\*\*"#, to: storage, in: text, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .bold)
            ])

            // Italic: *text*  (but not **)
            applyPattern(#"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#, to: storage, in: text, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular).withTraits(.italic)
            ])

            // Wikilinks: [[text]]
            applyPattern(#"\[\[([^\[\]]+?)\]\]"#, to: storage, in: text, attributes: [
                .foregroundColor: NSColor.systemBlue,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ])

            // Tags: #word
            applyPattern(#"(?<!\w)#[a-zA-Z][a-zA-Z0-9_-]*"#, to: storage, in: text, attributes: [
                .foregroundColor: NSColor.systemOrange
            ])

            // Inline code: `text`
            applyPattern(#"`[^`]+`"#, to: storage, in: text, attributes: [
                .foregroundColor: NSColor.systemPink,
                .backgroundColor: NSColor.quaternaryLabelColor
            ])

            storage.endEditing()
        }

        private func applyPattern(
            _ pattern: String,
            to storage: NSTextStorage,
            in text: String,
            attributes: [NSAttributedString.Key: Any]
        ) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return }
            let nsRange = NSRange(location: 0, length: (text as NSString).length)
            let matches = regex.matches(in: text, options: [], range: nsRange)

            for match in matches {
                storage.addAttributes(attributes, range: match.range)
            }
        }
    }
}

// MARK: - MarkdownNSTextView

final class MarkdownNSTextView: NSTextView {
    // Custom NSTextView subclass for future extensions
}

// MARK: - NSFont Extension

private extension NSFont {
    func withTraits(_ traits: NSFontDescriptor.SymbolicTraits) -> NSFont {
        let descriptor = fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }
}
