//
//  MarkdownTextView.swift
//  WiFi Lens
//
//  A reusable SwiftUI view that displays Markdown as read-only, selectable rich
//  text (headings, lists, block quotes, code blocks) with correct dark-mode
//  colors and native link handling.
//

import AppKit
import SwiftUI

/// A read-only, selectable Markdown text view backed by AppKit. The attributed
/// string is produced by `MarkdownRenderer`. Optionally override the base body
/// font size; it defaults to the standard 13 pt body size.
public struct MarkdownTextView: NSViewRepresentable {
    let markdown: String
    var pointSize: CGFloat = 13

    public init(markdown: String, pointSize: CGFloat = 13) {
        self.markdown = markdown
        self.pointSize = pointSize
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.automaticallyAdjustsContentInsets = false

        // Build an explicit TextKit 1 stack. Sparkle avoids TextKit 2 for
        // block-level Markdown on macOS 12-15 because of paragraph-style
        // rendering issues, and this matches the verified layout.
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(containerSize: NSSize(width: 360, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let textView = NSTextView(frame: .zero, textContainer: textContainer)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.importsGraphics = false
        textView.usesAdaptiveColorMappingForDarkAppearance = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        textView.delegate = context.coordinator

        scrollView.documentView = textView

        refresh(textView: textView, coordinator: context.coordinator)
        return scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        refresh(textView: textView, coordinator: context.coordinator)
    }

    private func refresh(textView: NSTextView, coordinator: Coordinator) {
        // Re-render only when the source or the font size changes.
        guard coordinator.currentState != cacheKey else { return }
        let attributed = MarkdownRenderer.render(markdown, pointSize: pointSize)
        textView.textStorage?.setAttributedString(attributed)
        coordinator.currentState = cacheKey
        textView.scrollToBeginningOfDocument(nil)
    }

    private var cacheKey: String {
        "\(pointSize)|\(markdown)"
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    /// Returns the laid-out height (in points) the given Markdown needs for the
    /// provided content width, so callers can size a sheet to its content.
    public static func measureHeight(markdown: String, width: CGFloat, pointSize: CGFloat = 13) -> CGFloat {
        let attributed = MarkdownRenderer.render(markdown, pointSize: pointSize)
        let layoutManager = NSLayoutManager()
        let textStorage = NSTextStorage(attributedString: attributed)
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(size: NSSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)
        layoutManager.ensureLayout(for: textContainer)
        return layoutManager.usedRect(for: textContainer).height
    }

    public final class Coordinator: NSObject, NSTextViewDelegate {
        var currentState: String?

        public func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            let url: URL?
            if let linkURL = link as? URL {
                url = linkURL
            } else if let string = link as? String {
                url = URL(string: string)
            } else {
                url = nil
            }

            guard let url, let scheme = url.scheme?.lowercased() else { return true }
            // Only allow safe, common link schemes; ignore anything else.
            switch scheme {
            case "http", "https", "mailto":
                NSWorkspace.shared.open(url)
            default:
                break
            }
            return true
        }
    }
}
