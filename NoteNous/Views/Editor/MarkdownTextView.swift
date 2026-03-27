import SwiftUI
import AppKit

// MARK: - MOROS Color Constants for NSColor

private enum MorosNS {
    static let textMain = NSColor(white: 1.0, alpha: 0.92)
    static let textSub = NSColor(white: 1.0, alpha: 0.68)
    static let textDim = NSColor(white: 1.0, alpha: 0.45)
    static let textGhost = NSColor(white: 1.0, alpha: 0.14)
    static let oracle = NSColor(red: 0.267, green: 0.467, blue: 0.800, alpha: 1.0)
    static let signal = NSColor(red: 0.800, green: 0.133, blue: 0.200, alpha: 1.0)
    static let verdit = NSColor(red: 0.784, green: 0.831, blue: 0.941, alpha: 1.0)
    static let ambient = NSColor(red: 0.533, green: 0.600, blue: 0.733, alpha: 1.0)
    static let codeBg = NSColor(white: 1.0, alpha: 0.06)
    static let blockquoteBg = NSColor(white: 1.0, alpha: 0.03)
    static let hrColor = NSColor(white: 1.0, alpha: 0.11)
    static let checkboxDone = NSColor(red: 0.267, green: 0.467, blue: 0.800, alpha: 0.6)
}

// MARK: - MarkdownTextView

struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    var onWikilinkTrigger: ((_ query: String) -> Void)?
    var onWikilinkDismiss: (() -> Void)?
    var onContentChange: ((_ newText: String) -> Void)?
    var onCursorPositionChange: ((_ position: Int) -> Void)?
    var onWikilinkClick: ((_ title: String) -> Void)?

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
        textView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.textColor = MorosNS.textMain
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.insertionPointColor = MorosNS.oracle
        textView.selectedTextAttributes = [
            .backgroundColor: MorosNS.oracle.withAlphaComponent(0.3),
            .foregroundColor: NSColor.white
        ]
        textView.textContainerInset = NSSize(width: 16, height: 12)
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        // Enable rich paragraph styling
        textView.defaultParagraphStyle = {
            let p = NSMutableParagraphStyle()
            p.lineSpacing = 4
            return p
        }()

        textView.delegate = context.coordinator
        textView.string = text
        textView.onWikilinkClick = { title in
            context.coordinator.handleWikilinkClick(title: title)
        }
        context.coordinator.textView = textView

        scrollView.documentView = textView

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

            if let openRange = textBeforeCursor.range(of: "[[", options: .backwards) {
                let afterOpen = textBeforeCursor[openRange.upperBound...]
                if afterOpen.contains("]]") {
                    dismissWikilink()
                    return
                }
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

        func handleWikilinkClick(title: String) {
            parent.onWikilinkClick?(title)
        }

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

        // MARK: - Full Markdown Highlighting

        func applyMarkdownHighlighting() {
            guard let textView = textView else { return }
            let text = textView.string
            let fullRange = NSRange(location: 0, length: (text as NSString).length)
            guard fullRange.length > 0 else { return }

            let storage = textView.textStorage!
            let bodyFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)

            storage.beginEditing()

            // Reset to base style
            let baseParagraph = NSMutableParagraphStyle()
            baseParagraph.lineSpacing = 4

            storage.addAttributes([
                .font: bodyFont,
                .foregroundColor: MorosNS.textMain,
                .paragraphStyle: baseParagraph
            ], range: fullRange)

            // --- HEADERS: # H1 through ###### H6 with real sizes ---
            highlightHeaders(storage: storage, text: text)

            // --- BOLD: **text** ---
            applyPattern(#"\*\*(.+?)\*\*"#, to: storage, in: text, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .bold),
                .foregroundColor: MorosNS.textMain
            ])

            // --- ITALIC: *text* (not **) ---
            applyPattern(#"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#, to: storage, in: text, attributes: [
                .font: bodyFont.withTraits(.italic),
                .foregroundColor: MorosNS.textMain
            ])

            // --- STRIKETHROUGH: ~~text~~ ---
            applyPattern(#"~~(.+?)~~"#, to: storage, in: text, attributes: [
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .foregroundColor: MorosNS.textDim
            ])

            // --- CODE BLOCKS: ```...``` (multiline) ---
            highlightCodeBlocks(storage: storage, text: text)

            // --- INLINE CODE: `text` ---
            applyPattern(#"(?<!`)`(?!`)([^`]+)`(?!`)"#, to: storage, in: text, attributes: [
                .foregroundColor: MorosNS.verdit,
                .backgroundColor: MorosNS.codeBg,
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)
            ])

            // --- BLOCKQUOTES: > text ---
            applyLinePattern(#"^>\s+.+$"#, to: storage, in: text, attributes: [
                .foregroundColor: MorosNS.ambient,
                .backgroundColor: MorosNS.blockquoteBg
            ])

            // --- HORIZONTAL RULES: --- or *** or ___ ---
            applyLinePattern(#"^(---|\*\*\*|___)$"#, to: storage, in: text, attributes: [
                .foregroundColor: MorosNS.hrColor,
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .strikethroughColor: MorosNS.hrColor
            ])

            // --- CHECKLISTS: - [ ] unchecked, - [x] checked ---
            highlightChecklists(storage: storage, text: text)

            // --- BULLET LISTS: - item or * item ---
            applyPattern(#"^[\t ]*[-*]\s(?!\[)"#, to: storage, in: text, attributes: [
                .foregroundColor: MorosNS.oracle
            ], options: [.anchorsMatchLines])

            // --- NUMBERED LISTS: 1. item ---
            applyPattern(#"^[\t ]*\d+\.\s"#, to: storage, in: text, attributes: [
                .foregroundColor: MorosNS.oracle
            ], options: [.anchorsMatchLines])

            // --- WIKILINKS: [[text]] ---
            applyPattern(#"\[\[([^\[\]]+?)\]\]"#, to: storage, in: text, attributes: [
                .foregroundColor: MorosNS.oracle,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ])

            // --- TAGS: #word ---
            applyPattern(#"(?<!\w)#[a-zA-Z][a-zA-Z0-9_-]*"#, to: storage, in: text, attributes: [
                .foregroundColor: MorosNS.ambient
            ])

            // --- LINKS: [text](url) ---
            applyPattern(#"\[([^\]]+)\]\(([^)]+)\)"#, to: storage, in: text, attributes: [
                .foregroundColor: MorosNS.oracle,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ])

            // --- IMAGES: ![alt](url) ---
            applyPattern(#"!\[([^\]]*)\]\(([^)]+)\)"#, to: storage, in: text, attributes: [
                .foregroundColor: MorosNS.ambient,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ])

            // --- Hide/dim markdown syntax characters ---
            dimSyntaxCharacters(storage: storage, text: text)

            storage.endEditing()
        }

        // MARK: - Header Highlighting with Real Sizes

        private func highlightHeaders(storage: NSTextStorage, text: String) {
            let headerConfigs: [(pattern: String, fontSize: CGFloat, weight: NSFont.Weight, color: NSColor)] = [
                (#"^#\s+(.+)$"#, 28, .bold, MorosNS.textMain),       // H1
                (#"^##\s+(.+)$"#, 24, .bold, MorosNS.textMain),      // H2
                (#"^###\s+(.+)$"#, 20, .semibold, MorosNS.textMain), // H3
                (#"^####\s+(.+)$"#, 17, .semibold, MorosNS.textSub), // H4
                (#"^#####\s+(.+)$"#, 15, .medium, MorosNS.textSub),  // H5
                (#"^######\s+(.+)$"#, 14, .medium, MorosNS.textDim), // H6
            ]

            for config in headerConfigs {
                guard let regex = try? NSRegularExpression(pattern: config.pattern, options: [.anchorsMatchLines]) else { continue }
                let nsRange = NSRange(location: 0, length: (text as NSString).length)

                for match in regex.matches(in: text, range: nsRange) {
                    // Style the entire line
                    let headerParagraph = NSMutableParagraphStyle()
                    headerParagraph.lineSpacing = 6
                    headerParagraph.paragraphSpacingBefore = 8

                    storage.addAttributes([
                        .font: NSFont.systemFont(ofSize: config.fontSize, weight: config.weight),
                        .foregroundColor: config.color,
                        .paragraphStyle: headerParagraph
                    ], range: match.range)

                    // Dim the # prefix
                    let lineText = (text as NSString).substring(with: match.range)
                    if let hashEnd = lineText.firstIndex(of: " ") {
                        let hashLength = lineText.distance(from: lineText.startIndex, to: hashEnd)
                        let hashRange = NSRange(location: match.range.location, length: hashLength)
                        storage.addAttributes([
                            .foregroundColor: MorosNS.textGhost,
                            .font: NSFont.systemFont(ofSize: config.fontSize * 0.6, weight: .light)
                        ], range: hashRange)
                    }
                }
            }
        }

        // MARK: - Checklist Highlighting

        private func highlightChecklists(storage: NSTextStorage, text: String) {
            // Unchecked: - [ ] text — show empty checkbox
            if let regex = try? NSRegularExpression(pattern: #"^[\t ]*-\s\[\s\]\s"#, options: [.anchorsMatchLines]) {
                let nsRange = NSRange(location: 0, length: (text as NSString).length)
                for match in regex.matches(in: text, range: nsRange) {
                    storage.addAttributes([
                        .foregroundColor: MorosNS.textDim
                    ], range: match.range)
                }
            }

            // Checked: - [x] text — show filled checkbox + dim text
            if let regex = try? NSRegularExpression(pattern: #"^([\t ]*-\s\[[xX]\]\s)(.+)$"#, options: [.anchorsMatchLines]) {
                let nsRange = NSRange(location: 0, length: (text as NSString).length)
                for match in regex.matches(in: text, range: nsRange) {
                    // The checkbox part
                    if match.numberOfRanges > 1 {
                        storage.addAttributes([
                            .foregroundColor: MorosNS.checkboxDone
                        ], range: match.range(at: 1))
                    }
                    // The text part — strikethrough + dim
                    if match.numberOfRanges > 2 {
                        storage.addAttributes([
                            .foregroundColor: MorosNS.textDim,
                            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                            .strikethroughColor: MorosNS.textDim
                        ], range: match.range(at: 2))
                    }
                }
            }
        }

        // MARK: - Code Block Highlighting

        private func highlightCodeBlocks(storage: NSTextStorage, text: String) {
            guard let regex = try? NSRegularExpression(pattern: #"```[\s\S]*?```"#, options: []) else { return }
            let nsRange = NSRange(location: 0, length: (text as NSString).length)

            for match in regex.matches(in: text, range: nsRange) {
                storage.addAttributes([
                    .foregroundColor: MorosNS.verdit,
                    .backgroundColor: MorosNS.codeBg,
                    .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
                ], range: match.range)
            }
        }

        // MARK: - Dim Syntax Characters

        private func dimSyntaxCharacters(storage: NSTextStorage, text: String) {
            // Dim ** around bold text
            applyPattern(#"(\*\*)(?=.+?\*\*)"#, to: storage, in: text, attributes: [
                .foregroundColor: MorosNS.textGhost
            ])
            applyPattern(#"(?<=\S)(\*\*)"#, to: storage, in: text, attributes: [
                .foregroundColor: MorosNS.textGhost
            ])

            // Dim [[ and ]] around wikilinks
            applyPattern(#"\[\["#, to: storage, in: text, attributes: [
                .foregroundColor: MorosNS.oracle.withAlphaComponent(0.4)
            ])
            applyPattern(#"\]\]"#, to: storage, in: text, attributes: [
                .foregroundColor: MorosNS.oracle.withAlphaComponent(0.4)
            ])

            // Dim ` around inline code
            applyPattern(#"(?<!`)`(?!`)"#, to: storage, in: text, attributes: [
                .foregroundColor: MorosNS.textGhost
            ])

            // Dim > in blockquotes
            applyPattern(#"^>"#, to: storage, in: text, attributes: [
                .foregroundColor: MorosNS.oracle.withAlphaComponent(0.4)
            ], options: [.anchorsMatchLines])
        }

        // MARK: - Pattern Helpers

        private func applyPattern(
            _ pattern: String,
            to storage: NSTextStorage,
            in text: String,
            attributes: [NSAttributedString.Key: Any],
            options: NSRegularExpression.Options = [.anchorsMatchLines]
        ) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
            let nsRange = NSRange(location: 0, length: (text as NSString).length)
            for match in regex.matches(in: text, range: nsRange) {
                storage.addAttributes(attributes, range: match.range)
            }
        }

        private func applyLinePattern(
            _ pattern: String,
            to storage: NSTextStorage,
            in text: String,
            attributes: [NSAttributedString.Key: Any]
        ) {
            applyPattern(pattern, to: storage, in: text, attributes: attributes, options: [.anchorsMatchLines])
        }
    }
}

// MARK: - MarkdownNSTextView

final class MarkdownNSTextView: NSTextView {
    var onWikilinkClick: ((String) -> Void)?

    private static let wikilinkRegex = try! NSRegularExpression(
        pattern: #"\[\[([^\[\]]+?)\]\]"#,
        options: []
    )

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let charIndex = characterIndexForInsertion(at: point)

        if let title = extractWikilinkAt(charIndex: charIndex) {
            onWikilinkClick?(title)
            return
        }

        super.mouseDown(with: event)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard let lm = layoutManager, let tc = textContainer else { return }

        let text = string
        let nsRange = NSRange(location: 0, length: (text as NSString).length)

        for match in Self.wikilinkRegex.matches(in: text, range: nsRange) {
            let glyphRange = lm.glyphRange(forCharacterRange: match.range, actualCharacterRange: nil)
            let rect = lm.boundingRect(forGlyphRange: glyphRange, in: tc)
            let adjustedRect = rect.offsetBy(dx: textContainerInset.width, dy: textContainerInset.height)
            addCursorRect(adjustedRect, cursor: .pointingHand)
        }
    }

    private func extractWikilinkAt(charIndex: Int) -> String? {
        let text = string
        let nsText = text as NSString
        let length = nsText.length
        guard charIndex >= 0, charIndex < length else { return nil }

        let nsRange = NSRange(location: 0, length: length)
        for match in Self.wikilinkRegex.matches(in: text, range: nsRange) {
            if NSLocationInRange(charIndex, match.range) {
                let innerRange = match.range(at: 1)
                let inner = nsText.substring(with: innerRange)
                let components = inner.split(separator: "|", maxSplits: 1)
                return components[0].trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
}

// MARK: - NSFont Extension

private extension NSFont {
    func withTraits(_ traits: NSFontDescriptor.SymbolicTraits) -> NSFont {
        let descriptor = fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }
}
