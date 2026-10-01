import Testing
import AppKit
@testable import WiFiLensCore
@testable import WiFi_Lens

@MainActor
struct SpectrumTablePanelTests {
    @Test func tablePanelInitializesWithViewModelAndBindings() {
        let vm = ScannerViewModel()
        let sort = [NSSortDescriptor(key: "ssid", ascending: true)]
        let panel = SpectrumTablePanel(
            viewModel: vm,
            isVendorColumnAvailable: true,
            sortOrder: .constant(sort),
            hiddenColumns: .constant([])
        )
        #expect(panel.isVendorColumnAvailable)
    }
}
