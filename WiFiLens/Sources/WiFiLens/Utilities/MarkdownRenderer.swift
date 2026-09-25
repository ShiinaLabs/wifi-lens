//
//  MarkdownRenderer.swift
//  WiFi Lens
//
//  Compatibility facade for the shared MarkdownKit renderer.
//

import AppKit
import MarkdownKit

/// Keeps the app's existing renderer API while delegating rendering to MarkdownKit.
enum MarkdownRenderer {
    static func render(_ markdown: String, pointSize: CGFloat = 13) -> NSAttributedString {
        MarkdownKit.MarkdownRenderer.render(markdown, pointSize: pointSize)
    }
}
