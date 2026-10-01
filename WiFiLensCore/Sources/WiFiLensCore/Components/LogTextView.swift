//
//  LogTextView.swift
//  WiFi Lens
//
//  Shared native log console: a non-editable NSTextView in its own scroll view,
//  so the user can select any span of log output (across lines) and copy it —
//  SwiftUI's per-line Text selection cannot do that. Appends keep the view
//  scrolled to the end, like a console. Domain-neutral.

import AppKit
import SwiftUI

public struct LogTextView: NSViewRepresentable {
    let text: String
    var fontSize: CGFloat = 11

    public init(text: String, fontSize: CGFloat = 11) {
        self.text = text
        self.fontSize = fontSize
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.textColor = .labelColor
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                                       height: CGFloat.greatestFiniteMagnitude)

        scrollView.documentView = textView
        context.coordinator.textView = textView
        return scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        if textView.font?.pointSize != fontSize {
            textView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        }
        if textView.string != text {
            textView.string = text
            if !text.isEmpty {
                textView.scrollToEndOfDocument(nil)
            }
        }
    }

    public final class Coordinator {
        weak var textView: NSTextView?
    }
}
