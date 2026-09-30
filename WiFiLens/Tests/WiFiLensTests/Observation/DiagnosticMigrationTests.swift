import Foundation
import Testing
@testable import WiFiLensCore
@testable import WiFi_Lens

@Suite("Diagnostic Migration")
@MainActor
struct DiagnosticMigrationTests {
    @Test("OverviewView reads diagnosis from store")
    func readsFromStore() async {
        let store = WiFiObservationStore()
        let vm = ScannerViewModel(store: store)
        let overview = OverviewView(viewModel: vm, store: store)
        store.diagnosis = DiagnosticResult(icon: "wifi.slash", title: "Weak Signal", message: "Move closer", severity: .critical)
        #expect(overview.store.diagnosis?.icon == "wifi.slash")
        #expect(overview.store.diagnosis?.severity == .critical)
    }
}
