import SwiftUI
import AppKit
import UniformTypeIdentifiers
import WiFiLensCore

/// How export success feedback is presented. A presentation concern only —
/// the guidance policy never reads it.
enum ExportSuccessPresentation: Equatable, Sendable {
    case banner            // OSS: non-modal success banner + invitation
    case preserveExisting  // Pro: keep the existing success alert
}

/// Shared PNG snapshot export service used by both editions.
/// Composites all visible band charts into a single high-resolution PNG image.
@MainActor
enum ExportService {

    // MARK: - Image Export

    static func exportImage(viewModel: ScannerViewModel) {
        let bands = viewModel.bandViewModels.filter { !viewModel.hiddenBands.contains($0.band.id) }
        guard !bands.isEmpty else {
            showError(String(localized: "export.error.no_visible_bands", comment: "No visible bands to export"))
            return
        }

        let logicalSize = CGSize(width: 1200, height: 400)
        let scale: CGFloat = 2.0

        // Render each band chart via ImageRenderer — reuses the exact same WiFiBandChart
        var chartImages: [(band: ChannelBand, image: NSImage)] = []
        for vm in bands {
            let renderer = ImageRenderer(
                content: WiFiBandChart(
                    model: vm.renderModel,
                    selectedNetworkID: .constant(viewModel.selectedNetworkID),
                    onResetZoom: { vm.resetZoom() },
                    onToggleExpand: { vm.toggleExpand() },
                    onApplyZoom: { lo, hi in vm.applyZoom(lo: lo, hi: hi) }
                )
                .frame(width: logicalSize.width, height: logicalSize.height)
            )
            renderer.scale = scale
            if let image = renderer.nsImage {
                chartImages.append((band: vm.band, image: image))
            }
        }

        guard !chartImages.isEmpty else {
            showError(String(localized: "export.error.render_failed", comment: "Chart rendering failed"))
            return
        }

        // Composite vertically
        let pixelSize = CGSize(width: logicalSize.width * scale, height: logicalSize.height * scale)
        let totalHeight = pixelSize.height * CGFloat(chartImages.count)
        let composite = NSImage(size: NSSize(width: pixelSize.width, height: totalHeight))

        composite.lockFocus()
        for (idx, entry) in chartImages.enumerated() {
            let y = totalHeight - pixelSize.height * CGFloat(idx + 1)
            entry.image.draw(in: NSRect(x: 0, y: y, width: pixelSize.width, height: pixelSize.height))
        }
        composite.unlockFocus()

        // Convert to PNG
        guard let tiff = composite.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
            showError(String(localized: "export.error.encode_failed", comment: "PNG encoding failed"))
            return
        }

        // Present save panel
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "\(String(localized: "export.default_image_filename", comment: "Default filename for image export"))_\(formattedTimestamp()).png"

        panel.begin { [panel] response in
            guard response == .OK, let url = panel.url else { return }
            Task.detached(priority: .userInitiated) {
                do {
                    try png.write(to: url)
                    await MainActor.run {
                        // Presentation is an explicit edition strategy: OSS shows the
                        // non-modal banner (which records the moment), Pro keeps its
                        // existing success alert and records the moment for rating
                        // eligibility only.
                        switch EditionComposition.exportSuccessPresentation {
                        case .banner:
                            GuidanceCoordinator.shared.handleExportSucceeded()
                        case .preserveExisting:
                            GuidanceCoordinator.shared.record(.exportSucceeded)
                            showSuccess(String(localized: "export.image_saved_message", comment: "Chart image exported successfully"))
                        }
                    }
                } catch {
                    await MainActor.run {
                        showError(String(format: String(localized: "export.failed.message", comment: "Export failed error"), error.localizedDescription))
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private static func formattedTimestamp() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd_HHmmss"
        return fmt.string(from: Date())
    }

    private static func showSuccess(_ message: String) {
        let alert = NSAlert()
        alert.messageText = String(localized: "export.saved_title", comment: "Export complete alert title")
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.runModal()
    }

    private static func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = String(localized: "export.failed.title", comment: "Export failed alert title")
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}
