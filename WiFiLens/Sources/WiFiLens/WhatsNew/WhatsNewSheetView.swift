import SwiftUI
import WiFiLensCore

/// What's New sheet displayed after a version update.
///
/// The sheet uses a landscape layout because release notes are text-heavy: a
/// horizontal header carries the app identity and the version, while a wide
/// reading column scrolls the Markdown body. The Markdown body is produced by
/// `MarkdownRenderer` and displayed via `MarkdownTextView`.
struct WhatsNewSheetView: View {
    let coordinator: WhatsNewCoordinator
    var onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            markdownContent
                .frame(width: contentWidth, height: contentHeight)
            Divider()
            doneButton
        }
        // The width is fixed for a readable landscape column; the height hugs
        // the Markdown content so short release notes don't leave a large void.
        .frame(width: 640)
    }

    // MARK: - Adaptive sizing

    private var contentWidth: CGFloat {
        640 - 24 * 2
    }

    private var contentHeight: CGFloat {
        guard let markdown = loadMarkdown() else { return 180 }
        let measured = MarkdownTextView.measureHeight(
            markdown: markdown,
            width: contentWidth
        )
        // Clamp to a comfortable min/max so the sheet stays compact for short
        // notes and scrolls (rather than growing unbounded) for long ones.
        return min(max(measured + 24, 110), 340)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            appIcon

            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: "whatsnew.review", comment: "What's New sheet title"))
                    .font(.title2.weight(.semibold))
                Text(coordinator.versionString)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                coordinator.markSeen()
                dismiss()
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(String(localized: "whatsnew.close", comment: "Close What's New sheet"))
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var appIcon: some View {
        Group {
            if let icon = NSImage(named: "AppIcon") {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 56, height: 56)
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 56, height: 56)
            }
        }
        .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
        .accessibilityHidden(true)
    }

    // MARK: - Content

    private var markdownContent: some View {
        Group {
            if let markdown = loadMarkdown() {
                MarkdownTextView(markdown: markdown)
            } else {
                Text(String(localized: "whatsnew.unavailable", comment: "Fallback when release notes file is missing"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    /// Resolves which localized release-notes file to load.
    ///
    /// Uses the bundle's preferred localizations rather than the global
    /// `Locale.current`, so the Markdown matches the app's own language even
    /// when the user has set a per-app language override in System Settings.
    /// Only simplified Chinese (`zh-Hans`) notes are shipped, so any Chinese
    /// script resolves to that file; otherwise the localization tag is used
    /// verbatim and falls back to `en`.
    private func resolvedMarkdownLanguage() -> String? {
        for preferred in Bundle.main.preferredLocalizations {
            let candidate: String
            if preferred.hasPrefix("zh") {
                candidate = "zh-Hans"
            } else {
                candidate = preferred
            }
            if Bundle.main.url(forResource: candidate, withExtension: "md", subdirectory: nil) != nil {
                return candidate
            }
        }
        return "en"
    }

    private func loadMarkdown() -> String? {
        guard let url = Bundle.main.url(forReleaseNotesLanguage: resolvedMarkdownLanguage()) else {
            return nil
        }
        guard let data = try? Data(contentsOf: url),
              let markdown = String(data: data, encoding: .utf8) else {
            return nil
        }
        // The sheet header supplies the title and version, so drop a leading
        // `# Heading` to avoid repeating it inside the reading pane.
        return dropLeadingTitle(from: markdown)
    }

    private func dropLeadingTitle(from markdown: String) -> String {
        let lines = markdown.components(separatedBy: "\n")
        if let first = lines.first, first.trimmingCharacters(in: .whitespaces).hasPrefix("#") {
            return lines.dropFirst().joined(separator: "\n")
        }
        return markdown
    }

    // MARK: - Footer

    private var doneButton: some View {
        HStack {
            Spacer()
            Button {
                coordinator.markSeen()
                dismiss()
                onDismiss()
            } label: {
                Text(String(localized: "whatsnew.done", comment: "Done button in What's New sheet"))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("whatsnew-done")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

private extension Bundle {
    /// Returns the URL for the release notes file matching the given language code,
    /// falling back to English if no match exists.
    func url(forReleaseNotesLanguage languageCode: String?) -> URL? {
        let languages: [String]
        if let code = languageCode {
            languages = [code, "en"]
        } else {
            languages = ["en"]
        }
        for lang in languages {
            if let url = url(forResource: lang, withExtension: "md", subdirectory: nil) {
                return url
            }
        }
        return nil
    }
}
