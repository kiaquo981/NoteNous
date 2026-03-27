import SwiftUI
import AppKit

struct MarkdownPreviewView: NSViewRepresentable {
    let content: String
    var onWikilinkTap: ((_ title: String) -> Void)?

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

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 16, height: 12)
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        textView.delegate = context.coordinator
        context.coordinator.textView = textView

        scrollView.documentView = textView
        context.coordinator.render(content)

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.render(content)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownPreviewView
        weak var textView: NSTextView?
        private var wikilinkRanges: [(range: NSRange, title: String)] = []

        init(_ parent: MarkdownPreviewView) {
            self.parent = parent
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            if let urlString = link as? String, urlString.hasPrefix("notenous://wikilink/") {
                let title = String(urlString.dropFirst("notenous://wikilink/".count))
                    .removingPercentEncoding ?? ""
                parent.onWikilinkTap?(title)
                return true
            }
            return false
        }

        func render(_ markdown: String) {
            guard let textView = textView else { return }
            let attributed = renderMarkdown(markdown)
            textView.textStorage?.setAttributedString(attributed)
        }

        // MARK: - Markdown Renderer

        private func renderMarkdown(_ text: String) -> NSAttributedString {
            let result = NSMutableAttributedString()
            let lines = text.components(separatedBy: "\n")

            let bodyFont = NSFont.systemFont(ofSize: 14)
            let monoFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            let bodyColor = NSColor.labelColor

            var inCodeBlock = false
            var codeBlockContent = ""

            for (index, line) in lines.enumerated() {
                // Code block toggle
                if line.hasPrefix("```") {
                    if inCodeBlock {
                        // End code block
                        let codeAttr = NSMutableAttributedString(string: codeBlockContent, attributes: [
                            .font: monoFont,
                            .foregroundColor: NSColor.systemPink,
                            .backgroundColor: NSColor.quaternaryLabelColor
                        ])
                        result.append(codeAttr)
                        inCodeBlock = false
                        codeBlockContent = ""
                    } else {
                        inCodeBlock = true
                        codeBlockContent = ""
                    }
                    if index < lines.count - 1 {
                        result.append(NSAttributedString(string: "\n"))
                    }
                    continue
                }

                if inCodeBlock {
                    codeBlockContent += line + "\n"
                    continue
                }

                // Horizontal rule
                if line.trimmingCharacters(in: .whitespaces).range(of: #"^-{3,}$|^\*{3,}$|^_{3,}$"#, options: .regularExpression) != nil {
                    let ruleAttr = NSAttributedString(string: "\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\n", attributes: [
                        .foregroundColor: NSColor.separatorColor,
                        .font: bodyFont
                    ])
                    result.append(ruleAttr)
                    continue
                }

                // Headers
                if let headerMatch = line.range(of: #"^(#{1,6})\s+(.+)$"#, options: .regularExpression) {
                    let headerLine = String(line[headerMatch])
                    let hashCount = headerLine.prefix(while: { $0 == "#" }).count
                    let headerText = String(headerLine.drop(while: { $0 == "#" }).dropFirst())
                    let fontSize: CGFloat = [24, 20, 17, 15, 14, 13][min(hashCount - 1, 5)]
                    let headerAttr = renderInline(headerText, baseFont: NSFont.systemFont(ofSize: fontSize, weight: .bold), baseColor: bodyColor)
                    result.append(headerAttr)
                    if index < lines.count - 1 { result.append(NSAttributedString(string: "\n")) }
                    continue
                }

                // Blockquotes
                if line.hasPrefix(">") {
                    let quoteText = String(line.dropFirst().trimmingCharacters(in: .whitespaces))
                    let quoteAttr = renderInline(quoteText, baseFont: NSFont.systemFont(ofSize: 14).withItalic(), baseColor: NSColor.secondaryLabelColor)
                    let paragraph = NSMutableParagraphStyle()
                    paragraph.headIndent = 20
                    paragraph.firstLineHeadIndent = 20
                    quoteAttr.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: quoteAttr.length))
                    result.append(quoteAttr)
                    if index < lines.count - 1 { result.append(NSAttributedString(string: "\n")) }
                    continue
                }

                // Bullet lists
                if line.range(of: #"^\s*[-*+]\s+"#, options: .regularExpression) != nil {
                    let bulletText = line.replacingOccurrences(of: #"^\s*[-*+]\s+"#, with: "", options: .regularExpression)
                    let bulletAttr = NSMutableAttributedString(string: "  \u{2022} ", attributes: [.font: bodyFont, .foregroundColor: bodyColor])
                    bulletAttr.append(renderInline(bulletText, baseFont: bodyFont, baseColor: bodyColor))
                    if index < lines.count - 1 { bulletAttr.append(NSAttributedString(string: "\n")) }
                    result.append(bulletAttr)
                    continue
                }

                // Numbered lists
                if line.range(of: #"^\s*\d+\.\s+"#, options: .regularExpression) != nil {
                    let numberMatch = line.range(of: #"^\s*(\d+)\.\s+"#, options: .regularExpression)!
                    let numberPart = String(line[numberMatch])
                    let restText = String(line[numberMatch.upperBound...])
                    let numAttr = NSMutableAttributedString(string: "  \(numberPart.trimmingCharacters(in: .whitespaces))", attributes: [.font: bodyFont, .foregroundColor: bodyColor])
                    numAttr.append(renderInline(restText, baseFont: bodyFont, baseColor: bodyColor))
                    if index < lines.count - 1 { numAttr.append(NSAttributedString(string: "\n")) }
                    result.append(numAttr)
                    continue
                }

                // Regular paragraph
                let lineAttr = renderInline(line, baseFont: bodyFont, baseColor: bodyColor)
                result.append(lineAttr)
                if index < lines.count - 1 { result.append(NSAttributedString(string: "\n")) }
            }

            // Close any unclosed code block
            if inCodeBlock && !codeBlockContent.isEmpty {
                let codeAttr = NSAttributedString(string: codeBlockContent, attributes: [
                    .font: monoFont,
                    .foregroundColor: NSColor.systemPink,
                    .backgroundColor: NSColor.quaternaryLabelColor
                ])
                result.append(codeAttr)
            }

            return result
        }

        // MARK: - Inline Rendering

        private func renderInline(_ text: String, baseFont: NSFont, baseColor: NSColor) -> NSMutableAttributedString {
            let result = NSMutableAttributedString(string: text, attributes: [
                .font: baseFont,
                .foregroundColor: baseColor
            ])
            let nsText = text as NSString
            let fullRange = NSRange(location: 0, length: nsText.length)

            // Bold: **text**
            applyInlinePattern(#"\*\*(.+?)\*\*"#, to: result, in: nsText, fullRange: fullRange, attributes: [
                .font: NSFont.systemFont(ofSize: baseFont.pointSize, weight: .bold)
            ])

            // Italic: *text*
            applyInlinePattern(#"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#, to: result, in: nsText, fullRange: fullRange, attributes: [
                .font: baseFont.withItalic()
            ])

            // Inline code: `text`
            applyInlinePattern(#"`([^`]+)`"#, to: result, in: nsText, fullRange: fullRange, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: baseFont.pointSize - 1, weight: .regular),
                .foregroundColor: NSColor.systemPink,
                .backgroundColor: NSColor.quaternaryLabelColor
            ])

            // Wikilinks: [[text]]
            if let regex = try? NSRegularExpression(pattern: #"\[\[([^\[\]]+?)\]\]"#) {
                let matches = regex.matches(in: text, range: fullRange)
                for match in matches.reversed() {
                    let linkTitle = nsText.substring(with: match.range(at: 1))
                    let encodedTitle = linkTitle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? linkTitle
                    result.addAttributes([
                        .foregroundColor: NSColor.systemBlue,
                        .link: "notenous://wikilink/\(encodedTitle)",
                        .underlineStyle: NSUnderlineStyle.single.rawValue,
                        .cursor: NSCursor.pointingHand
                    ], range: match.range)
                }
            }

            // Tags: #word
            applyInlinePattern(#"(?<!\w)#[a-zA-Z][a-zA-Z0-9_-]*"#, to: result, in: nsText, fullRange: fullRange, attributes: [
                .foregroundColor: NSColor.systemOrange
            ])

            return result
        }

        private func applyInlinePattern(
            _ pattern: String,
            to attributed: NSMutableAttributedString,
            in nsText: NSString,
            fullRange: NSRange,
            attributes: [NSAttributedString.Key: Any]
        ) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
            let matches = regex.matches(in: nsText as String, range: fullRange)
            for match in matches {
                attributed.addAttributes(attributes, range: match.range)
            }
        }
    }
}

// MARK: - NSFont Italic Extension

private extension NSFont {
    func withItalic() -> NSFont {
        let descriptor = fontDescriptor.withSymbolicTraits(.italic)
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }
}
