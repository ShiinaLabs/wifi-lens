import SwiftUI
import WiFiLensCore

enum MarkdownExportCommandContribution {
    case available(@MainActor (ScannerViewModel) -> Void)
    case lockedPreview
}

struct EditionCompositionContext {
    let mainWindowID: UUID
    let mainWindowState: AnyObject
    let scannerViewModel: ScannerViewModel
    let macVendorDatabaseManager: MACVendorDatabaseManager
    let isMACVendorDatabaseAvailable: Bool
    let selectedPage: Binding<SidebarPage>
    let secondaryToolbarSelections: Binding<SecondaryToolbarSelections>
    let bleEnabled: Binding<Bool>
    let openMainWindow: (SidebarPage?) -> Void
}
