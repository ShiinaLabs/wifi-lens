import Foundation
import Testing
import WiFiLensCore
@testable import WiFi_Lens

@Suite("Diagnostic Migration")
@MainActor
struct DiagnosticMigrationTests {
    @Test("OverviewView reads diagnosis from store")
    func readsFromStore() async {
        let store = WiFiObservationStore()
        let vm = ScannerViewModel(store: store)
        let overview = OverviewView(viewModel: vm, store: store)

        store.diagnosis = DiagnosticResult(
            icon: "wifi.slash",
            title: "Weak Signal",
            message: "Move closer",
            severity: .critical
        )

        #expect(overview.store.diagnosis?.icon == "wifi.slash")
        #expect(overview.store.diagnosis?.severity == .critical)
    }

    @Test("Store diagnosis is nil when not set")
    func diagnosisNilByDefault() {
        let store = WiFiObservationStore()
        #expect(store.diagnosis == nil)
    }

    @Test("DiagnosticSeverity maps to expected colors")
    func severityColors() {
        #expect(DiagnosticSeverity.excellent.color == .green)
        #expect(DiagnosticSeverity.warning.color == .orange)
        #expect(DiagnosticSeverity.critical.color == .red)
        #expect(DiagnosticSeverity.ok.color == .mint)
    }

    @Test("WiFiObservationStore apply updates recommendation slices and errors")
    func storeApplyUpdatesSlicesAndErrors() {
        let store = WiFiObservationStore()
        let analysis = ChannelQuality(
            channel: 11,
            band: "24",
            bandDisplay: "2.4 GHz",
            qualityScore: 42,
            qualityLevel: .busy,
            apCount: 5,
            coChannelCount: 3,
            adjacentCount: 2,
            interferenceScore: 58,
            overlapLevel: .high,
            strongestNeighborRSSI: -57,
            isCurrentChannel: true
        )
        var recommendation = ChannelRecommendation(from: analysis)
        recommendation.scoreSelected = true
        recommendation.classification = .recommended

        let first = WiFiObservation(
            channelAnalysis: [analysis],
            channelRecommendation: [recommendation],
            errors: [.environmentScanFailed("test error")]
        )
        let second = WiFiObservation(errors: [.environmentScanFailed("test error 2")])

        store.apply(first)
        store.apply(second)

        #expect(store.channelAnalysis?.count == 1)
        #expect(store.channelRecommendation?.count == 1)
        #expect(store.errors.count == 2)
        #expect(store.lastUpdated != nil)
    }
}
