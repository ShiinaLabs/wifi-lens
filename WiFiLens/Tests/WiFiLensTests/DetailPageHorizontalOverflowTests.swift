import AppKit
import SwiftUI
import Testing
@testable import WiFi_Lens

/// At the main window's minimum size (820x620) the NavigationSplitView detail column is
/// about 600pt wide (820 - ~180 sidebar - divider). Detail pages must stay fully usable at
/// that width: page-level `minWidth` hints force a page to lay out wider than the column
/// (clipping its right edge), and an SSID `Text` without a `lineLimit` wraps a pathological
/// (out-of-spec, unbreakable) SSID across multiple lines, pushing the connection card past
/// the visible area. See `.agents/references/project/WINDOWING.md` for the sizing policy
/// that makes 600pt the floor the pages have to fit into.
///
/// Measurement notes (verified against the macOS 27 SDK): a page whose minimum width
/// exceeds the proposal reports that minimum through `NSHostingController.sizeThatFits`
/// (Channels and Spectrum measured 700pt before the `minWidth` hints were removed). When
/// content cannot fit, SwiftUI prefers to wrap text rather than widen the layout, so the
/// height the content needs at the fixed width proposal is the signal for wrapped text
/// (wrapped text is taller). `sizeThatFits` cannot see inside a ScrollView (its document
/// height is unbounded), so scroll-based pages are measured through their
/// `NSScrollView.documentView` frame.
@MainActor
struct DetailPageHorizontalOverflowTests {
    /// Conservative minimum detail-column width: 820 window - 180 sidebar - divider.
    private static let detailWidth: CGFloat = 600

    /// Glass materials and shadows can paint a hair outside a view's frame.
    private static let tolerance: CGFloat = 2

    /// One line of `.title3` text; two lines exceed it.
    private static let singleLineHeight: CGFloat = 30

    /// Out-of-spec SSID length (real SSIDs are at most 32 bytes), one unbreakable token —
    /// the worst case the card must degrade gracefully for.
    private static let pathologicalSSID = String(repeating: "W", count: 100)

    // MARK: - Harness

    private func host(_ view: some View, width: CGFloat = Self.detailWidth) -> (NSHostingController<some View>, NSWindow) {
        let controller = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .resizable]
        window.setContentSize(NSSize(width: width, height: 800))
        window.layoutIfNeeded()
        return (controller, window)
    }

    /// The width the content requires when the column proposes `width`. A page with a
    /// `minWidth` hint above the proposal reports that minimum — the clipping regression.
    private func requiredWidth(of view: some View, width: CGFloat = Self.detailWidth) -> CGFloat {
        let (controller, _) = host(view, width: width)
        return controller.sizeThatFits(
            in: NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        ).width
    }

    /// The height the content requires when the column proposes `width`. Wrapped text
    /// grows this; truncated text does not.
    private func requiredHeight(of view: some View, width: CGFloat = Self.detailWidth) -> CGFloat {
        let (controller, _) = host(view, width: width)
        return controller.sizeThatFits(
            in: NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        ).height
    }

    /// The laid-out size of a scroll-based view's document at `width` — what the user can
    /// scroll through. Wrapped text grows the height; clipped content grows the width.
    private func scrollDocumentSize(of view: some View, width: CGFloat = Self.detailWidth) -> CGSize? {
        let (controller, _) = host(view, width: width)
        var found: NSScrollView?
        func walk(_ subject: NSView) {
            if found == nil, let scroll = subject as? NSScrollView {
                found = scroll
                return
            }
            subject.subviews.forEach(walk)
        }
        walk(controller.view)
        guard let doc = found?.documentView else { return nil }
        return doc.frame.size
    }

    /// A page must not require more width than the column offers. This is the assertion
    /// that catches page-level `minWidth` hints (Channels and Spectrum previously laid
    /// out 700pt wide inside a 600pt column).
    private func assertFitsWidth(_ view: some View) {
        let required = requiredWidth(of: view)
        #expect(
            required <= Self.detailWidth + Self.tolerance,
            "Page requires \(required)pt at a \(Self.detailWidth)pt proposal — right edge would be clipped"
        )
    }

    /// A scroll-based page must not clip horizontally: its document must not be wider
    /// than the scroll view's clip view.
    private func assertNoScrollClipping(_ view: some View) {
        let (controller, _) = host(view)
        var problems: [String] = []
        func walk(_ subject: NSView) {
            if let scroll = subject as? NSScrollView,
               !scroll.hasHorizontalScroller,
               let doc = scroll.documentView {
                let clip = scroll.contentView.bounds.width
                if doc.frame.width > clip + Self.tolerance {
                    problems.append("doc \(doc.frame.width) > clip \(clip)")
                }
            }
            subject.subviews.forEach(walk)
        }
        walk(controller.view)
        #expect(problems.isEmpty, "Scroll content clips horizontally: \(problems)")
    }

    // MARK: - Fixtures

    private func makeScannerViewModel(ssid: String) -> ScannerViewModel {
        let viewModel = ScannerViewModel(store: .shared)
        // Explicit state so the test does not depend on real hardware state. On macOS
        // the location authorization state that grants SSID access is `.authorized`.
        viewModel.locationManager.authorizationStatus = .authorized
        viewModel.wifiPowerState = .poweredOn
        viewModel.networkInfo = [
            NetworkInterfaceInfo(
                interfaceName: "en0",
                hardwareMAC: "AA:BB:CC:DD:EE:FF",
                ipv4Addresses: ["192.168.1.10"],
                subnetMasks: ["255.255.255.0"],
                router: "192.168.1.1",
                dnsServers: ["8.8.8.8"],
                ssid: ssid,
                bssid: "AA:BB:CC:DD:EE:FF",
                channel: 149,
                band: .band5GHz,
                rssi: -62,
                txRate: 866,
                phyMode: "802.11ax",
                security: "WPA3"
            )
        ]
        viewModel.channelRecommendations = channelFixtures
        return viewModel
    }

    /// A current channel plus a recommended channel, so the connection card, health row,
    /// and channel advice/status cards all render.
    private var channelFixtures: [ChannelRecommendation] {
        var current = ChannelRecommendation(from: ChannelQuality(
            channel: 149, band: "5", bandDisplay: "5 GHz", qualityScore: 82,
            qualityLevel: .excellent, apCount: 3, coChannelCount: 2, adjacentCount: 1,
            interferenceScore: 40, overlapLevel: .low, strongestNeighborRSSI: -70,
            isRecommended: false, isCurrentChannel: true, showInSimpleView: true,
            recommendationScore: 82, recommendationLevel: .excellent,
            recommendationConfidence: .exact, recommendationState: .currentGoodEnough
        ))
        current.scoreSelected = true
        current.recommendationReasons = [.lowInterference]

        var recommended = ChannelRecommendation(from: ChannelQuality(
            channel: 36, band: "5", bandDisplay: "5 GHz", qualityScore: 90,
            qualityLevel: .excellent, apCount: 1, coChannelCount: 0, adjacentCount: 0,
            interferenceScore: 10, overlapLevel: .low, strongestNeighborRSSI: -80,
            isRecommended: true, isCurrentChannel: false, showInSimpleView: true,
            recommendationScore: 92, recommendationLevel: .excellent,
            recommendationConfidence: .exact, recommendationState: .recommended
        ))
        recommended.scoreSelected = true
        recommended.recommendationReasons = [.clearSpectrum]
        return [current, recommended]
    }

    private func makeRoamingViewModel() -> RoamingTestViewModel {
        let viewModel = RoamingTestViewModel()
        viewModel.state = .running
        viewModel.currentSSID = "Office-Guest-Network-5GHz-Extended-2"
        viewModel.currentBSSID = "AA:BB:CC:DD:EE:FF"
        viewModel.currentRSSI = -62
        viewModel.currentChannel = 149
        viewModel.currentTxRate = 866
        viewModel.gatewayLatency = 12.3
        let start = Date(timeIntervalSinceNow: -60)
        viewModel.segments = [
            RoamingSegment(bssid: "AA:BB:CC:DD:EE:FF", startTime: start, endTime: nil, samples: [
                RoamingSample(timestamp: start, rssi: -60, channel: 149, txRate: 866, gatewayLatency: 10),
                RoamingSample(timestamp: start.addingTimeInterval(10), rssi: -62, channel: 149, txRate: 700, gatewayLatency: 12),
            ]),
            RoamingSegment(bssid: "00:11:22:33:44:55", startTime: start.addingTimeInterval(20), endTime: nil, samples: [
                RoamingSample(timestamp: start.addingTimeInterval(20), rssi: -65, channel: 36, txRate: 600, gatewayLatency: 15),
                RoamingSample(timestamp: start.addingTimeInterval(30), rssi: -64, channel: 36, txRate: 640, gatewayLatency: 14),
            ]),
        ]
        viewModel.transitions = [
            APTransitionEvent(
                timestamp: start.addingTimeInterval(20),
                fromBSSID: "AA:BB:CC:DD:EE:FF",
                toBSSID: "00:11:22:33:44:55",
                rssiBefore: -62, rssiAfter: -65,
                channelBefore: 149, channelAfter: 36
            )
        ]
        return viewModel
    }

    // MARK: - Regression: every page fits the minimum detail width

    @Test("Overview fits the minimum detail width")
    func overviewFitsMinimumDetailWidth() {
        let viewModel = makeScannerViewModel(ssid: "Office")
        assertFitsWidth(OverviewView(viewModel: viewModel))
        assertNoScrollClipping(OverviewView(viewModel: viewModel))
    }

    @Test("Channels simple mode fits the minimum detail width")
    func channelsSimpleFitsMinimumDetailWidth() {
        let viewModel = makeScannerViewModel(ssid: "Office")
        let view = ChannelQualityView(channels: viewModel.channelRecommendations, mode: .simple)
        assertFitsWidth(view)
        assertNoScrollClipping(view)
    }

    @Test("Channels table mode fits the minimum detail width")
    func channelsTableFitsMinimumDetailWidth() {
        let viewModel = makeScannerViewModel(ssid: "Office")
        let view = ChannelQualityView(channels: viewModel.channelRecommendations, mode: .table)
        assertFitsWidth(view)
        assertNoScrollClipping(view)
    }

    @Test("Interfaces simple mode fits the minimum detail width")
    func interfacesSimpleFitsMinimumDetailWidth() {
        let viewModel = makeScannerViewModel(ssid: "Office")
        let view = InterfacesView(
            interfaces: viewModel.networkInfo,
            scannerViewModel: viewModel,
            throughputMonitor: viewModel.throughputMonitor,
            mode: .simple
        )
        assertFitsWidth(view)
        assertNoScrollClipping(view)
    }

    @Test("Interfaces details mode fits the minimum detail width")
    func interfacesDetailsFitsMinimumDetailWidth() {
        let viewModel = makeScannerViewModel(ssid: "Office")
        let view = InterfacesView(
            interfaces: viewModel.networkInfo,
            scannerViewModel: viewModel,
            throughputMonitor: viewModel.throughputMonitor,
            mode: .details
        )
        assertFitsWidth(view)
        assertNoScrollClipping(view)
    }

    @Test("Spectrum dashboard fits the minimum detail width")
    func spectrumFitsMinimumDetailWidth() {
        let viewModel = makeScannerViewModel(ssid: "Office")
        assertFitsWidth(ContentView(viewModel: viewModel, isVendorColumnAvailable: true))
    }

    @Test("Network self-check fits the minimum detail width")
    func networkDiagnosticsFitsMinimumDetailWidth() {
        assertFitsWidth(NetworkDiagnosticsView(viewModel: NetworkDiagnosticsViewModel()))
    }

    @Test("Roaming active state fits the minimum detail width")
    func roamingActiveFitsMinimumDetailWidth() {
        let view = RoamingTestView(viewModel: makeRoamingViewModel())
        assertFitsWidth(view)
        assertNoScrollClipping(view)
    }

    // MARK: - Regression: pathological SSID truncates instead of wrapping

    @Test("Overview connection card truncates a pathological SSID at the minimum detail width")
    func overviewConnectionCardTruncatesPathologicalSSID() {
        // Relative measurement: both hosts share every layout cost (globe, cards, locale,
        // fonts); only the SSID differs. If the card wraps instead of truncating, the
        // pathological host grows by a full text line.
        let shortSize = scrollDocumentSize(
            of: OverviewView(viewModel: makeScannerViewModel(ssid: "Office")),
            width: Self.detailWidth
        )
        let pathologicalSize = scrollDocumentSize(
            of: OverviewView(viewModel: makeScannerViewModel(ssid: Self.pathologicalSSID)),
            width: Self.detailWidth
        )

        let delta = (pathologicalSize?.height ?? 0) - (shortSize?.height ?? 0)
        #expect(
            delta <= Self.singleLineHeight,
            "Pathological SSID must truncate to one line, not wrap: document grew by \(delta)pt"
        )
    }

    // MARK: - Detector controls
    //
    // These validate the measurement itself. If either fails, the height probe is not a
    // reliable overflow detector on this macOS version and the regressions above must not
    // be trusted until the harness is reworked.

    @Test("Control: the detector reports a layout known to overflow")
    func controlDetectorCatchesKnownOverflow() {
        // Same shape as the connection card before the fix: an unbounded SSID text that
        // cannot compress must wrap, pushing the layout past one line of text.
        let overflowing = HStack(spacing: 12) {
            Text(Self.pathologicalSSID)
                .font(.title3)
                .fontWeight(.semibold)
            Spacer()
            Text("-62 dBm")
        }
        let height = requiredHeight(of: overflowing)
        #expect(
            height > Self.singleLineHeight,
            "Detector must flag an unconstrained long-text layout (height \(height))"
        )
    }

    @Test("Control: the detector accepts the same layout once the text is truncatable")
    func controlDetectorAcceptsTruncatableLayout() {
        // The fixed shape: a line-limited text truncates and the trailing cluster stays
        // intact at its intrinsic width, so the layout fits within one text line.
        let fixed = HStack(spacing: 12) {
            Text(Self.pathologicalSSID)
                .font(.title3)
                .fontWeight(.semibold)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 12)
            Text("-62 dBm")
                .fixedSize(horizontal: true, vertical: false)
        }
        let height = requiredHeight(of: fixed)
        #expect(
            height <= Self.singleLineHeight,
            "Detector must accept the truncatable layout (height \(height))"
        )
    }

    @Test("Control: the width probe reports a page-level minimum above the proposal")
    func controlWidthProbeCatchesMinimumWidthHint() {
        // A `minWidth` hint above the proposal forces the layout wider than the column —
        // exactly what Channels and Spectrum did before the fix. The width probe must
        // report it.
        let hinted = Color.clear.frame(minWidth: 700)
        let required = requiredWidth(of: hinted)
        #expect(
            required > Self.detailWidth + Self.tolerance,
            "Width probe must flag a 700pt minimum inside a 600pt proposal (width \(required))"
        )
    }
}
