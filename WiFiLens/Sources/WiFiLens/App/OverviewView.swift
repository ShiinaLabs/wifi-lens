import SwiftUI
import SceneKit

struct OverviewView: View {
    @Bindable var viewModel: ScannerViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(OverviewVisualStyle.storageKey) private var overviewVisualStyleRaw = OverviewVisualStyle.system.rawValue

    let store: WiFiObservationStore

    @State private var stableScore = StableScore()
    @State private var displayLevel: ChannelQuality.QualityLevel = .excellent
    @State private var displayScore: Int = 100

    init(viewModel: ScannerViewModel, store: WiFiObservationStore = .shared) {
        self.viewModel = viewModel
        self.store = store
    }

    private var wifi: NetworkInterfaceInfo? {
        viewModel.networkInfo.first(where: { $0.ssid != nil })
    }

    private var currentChannelQuality: ChannelRecommendation? {
        guard wifi?.channel != nil else { return nil }
        return viewModel.channelRecommendations.first(where: { $0.isCurrentChannel })
    }

    private var recommendedChannels: [ChannelRecommendation] {
        viewModel.channelRecommendations.filter(\.isRecommended)
    }

    private var recommendationAvailability: ChannelRecommendationAvailability {
        .from(viewModel.channelRecommendations)
    }

    private var overviewVisualStyle: OverviewVisualStyle.ResolvedStyle {
        OverviewVisualStyle.fromPersistedValue(overviewVisualStyleRaw)
            .resolved(reduceMotion: reduceMotion)
    }

    private var totalNetworks: Int {
        guard viewModel.isWiFiAvailable else { return 0 }
        return viewModel.cachedTotalNetworks
    }

    var body: some View {
        ZStack {
            // Subtle gradient behind hero — breaks the "all system materials" feel
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(red: 0.10, green: 0.12, blue: 0.20), Color.clear]
                    : [Color(red: 0.94, green: 0.95, blue: 0.98), Color.clear],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 360)
            .frame(maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea()

            if overviewVisualStyle == .worldMap {
                EqualEarthWorldMapBackdrop(colorScheme: colorScheme)
                    .frame(height: 360)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .ignoresSafeArea(edges: .top)
                    .accessibilityHidden(true)
            }

            ScrollView {
                ZStack(alignment: .top) {
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        VStack(spacing: 16) {
                            // The globe remains the hero visual. The reduced-motion
                            // map is a quiet background layer behind the connection card.
                            if overviewVisualStyle == .globe {
                                let stateColor = wifi != nil ? rssiColor(wifi!.rssi ?? -100) : Color.secondary
                                EarthGlobeView(color: stateColor, reduceMotion: reduceMotion)
                                    .frame(width: 240, height: 240)
                                    .accessibilityHidden(true)
                            } else {
                                Color.clear
                                    .frame(height: 180)
                                    .accessibilityHidden(true)
                            }

                            if !viewModel.locationManager.isAuthorizedForSSID {
                                authorizationCard
                            }

                            if !viewModel.isWiFiAvailable {
                                wifiOffCard
                            } else if let wifi {
                                connectionCard(wifi)
                                signalHealthRow(wifi)
                                if recommendationAvailability != .currentGoodEnough {
                                    diagnosticCard(wifi)
                                }
                                if let current = currentChannelQuality, hasBetterChannel(current) {
                                    channelAdviceCard(current)
                                } else if !viewModel.channelRecommendations.isEmpty {
                                    channelStatusCard(recommendationAvailability)
                                }
                            } else {
                                noConnectionCard
                            }
                            if viewModel.locationManager.isAuthorizedForSSID && viewModel.isWiFiAvailable {
                                environmentCard
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(16)
                        .frame(maxWidth: 640)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .onChange(of: currentChannelQuality?.rfScore) { _, newRaw in
            let raw = newRaw ?? 100
            displayScore = stableScore.update(score: raw)
            displayLevel = .from(score: displayScore)
        }
        } // ZStack
    }

    // MARK: - Connection Hero

    private func connectionCard(_ wifi: NetworkInterfaceInfo) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(wifi.displaySSID)
                        .font(.title3)
                        .fontWeight(.semibold)
                        // Long SSIDs are a single unbreakable token; without a line
                        // limit they widen the card past the detail column at the
                        // minimum window size. Truncate instead of overflowing.
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(wifi.displaySSID)
                    HStack(spacing: 6) {
                        Circle().fill(Color.green).frame(width: 6, height: 6).accessibilityHidden(true)
                        Text(String(localized: "common.label.connected", comment: "Connected state indicator"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        if let ch = wifi.channel {
                            Text(String(format: String(localized: "format.band_channel_separator", comment: "Band and channel separator with values"), bandName(ch), ch))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(String(format: String(localized: "format.rssi_dbm", comment: "RSSI value with dBm unit"), wifi.rssi ?? -100))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(rssiColor(wifi.rssi ?? -100))
                        .accessibilityLabel(String(format: String(localized: "roaming.accessibility.rssi_fmt", comment: "RSSI accessibility label with value and quality"), wifi.rssi ?? -100, signalLabel(wifi.rssi ?? -100)))
                    signalBars(wifi.rssi ?? -100)
                }
                // Keep the RSSI cluster intact at its intrinsic width when the SSID
                // compresses; all squeezing happens on the truncatable left side.
                .fixedSize(horizontal: true, vertical: false)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(.quaternary).frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(rssiColor(wifi.rssi ?? -100))
                        .frame(width: geo.size.width * rssiFraction(wifi.rssi ?? -100), height: 6)
                }
            }
            .frame(height: 6)
        }
        .padding(16)
        .glassBackground(.regular, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Signal Health Row

    private func signalHealthRow(_ wifi: NetworkInterfaceInfo) -> some View {
        HStack(spacing: 10) {
            healthPill(
                icon: "wave.3.right",
                label: String(localized: "overview.health.signal_label", comment: "Signal strength health indicator label"),
                value: signalLabel(wifi.rssi ?? -100),
                color: rssiColor(wifi.rssi ?? -100)
            )

            if currentChannelQuality != nil {
                healthPill(
                    icon: "chart.bar.fill",
                    label: String(localized: "overview.health.channel_label", comment: "Channel quality health indicator label"),
                    value: displayLevel.displayName,
                    color: Color(hex: displayLevel.color)
                )
            }

            healthPill(
                icon: "lock.shield.fill",
                label: String(localized: "overview.health.security_label", comment: "Security health indicator label"),
                value: securityShort(wifi.security),
                color: wifi.security.contains("WPA3") ? .green : .orange
            )
        }
    }

    private func healthPill(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .accessibilityHidden(true)
            Text(value)
                .font(.callout.weight(.semibold))
                .foregroundColor(.primary)
                .lineLimit(1)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .glassBackground(.regular, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(format: String(localized: "common.accessibility.metric_fmt", comment: "Label: value format for VoiceOver metric"), label, value))
    }

    // MARK: - Diagnostic Card

    private func diagnosticCard(_ wifi: NetworkInterfaceInfo) -> some View {
        let diag = store.diagnosis ?? DiagnosticResult.unknown

        return HStack(spacing: 12) {
            Image(systemName: diag.icon)
                .font(.largeTitle)
                .foregroundColor(diag.severity.color)
                .frame(width: 36)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(diag.title)
                    .font(.subheadline.weight(.semibold))
                Text(diag.message)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .glassBackground(.regular, in: RoundedRectangle(cornerRadius: 12))
    }



    // MARK: - Channel Advice

    private func channelStatusCard(_ availability: ChannelRecommendationAvailability) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: availability.icon)
                .foregroundColor(availability == .available ? .orange : .secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(availability.title)
                    .font(.callout.weight(.semibold))
                Text(availability.message)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .glassBackground(.regular, in: RoundedRectangle(cornerRadius: 12))
    }

    private func channelAdviceCard(_ current: ChannelRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)
                Text(String(localized: "overview.channel_advice.header", comment: "Header for recommended channels card"))
                    .font(.callout.weight(.semibold))
            }

            ForEach(recommendedChannels.prefix(2).filter { $0.channel != current.channel }) { ch in
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color(hex: ch.rfLevel.color).opacity(0.15))
                            .frame(width: 32, height: 32)
                            .accessibilityHidden(true)
                        Text("\(ch.channel)")
                            .font(.title3.weight(.bold))
                            .foregroundColor(Color(hex: ch.rfLevel.color))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text("\(ch.bandDisplay) — \(ch.recommendationLevel.displayName)")
                                .font(.callout.weight(.medium))
                            if !ch.recommendationReasons.isEmpty {
                                ReasonPopover(reasons: ch.recommendationReasons)
                            }
                        }
                        Text(String(format: String(localized: "format.network_score_with_ap_count", comment: "Network score display with nearby AP count"), ch.recommendationScore, ch.apCount))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(10)
//                .glassBackground(.regular, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(16)
        .glassBackground(.regular, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - No Connection

    private var noConnectionCard: some View {
        VStack(spacing: 12) {
            Text(String(localized: "overview.status.not_connected", comment: "Empty state when not connected to any Wi-Fi network"))
                .font(.title3)
                .fontWeight(.semibold)
            Text(String(localized: "overview.status.connect_prompt", comment: "Prompt to connect to Wi-Fi for diagnostics"))
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .glassBackground(.regular, in: RoundedRectangle(cornerRadius: 12))
    }

    private var wifiOffCard: some View {
        WiFiOffView()
            .padding(.horizontal, 0)
    }

    // MARK: - Authorization Card

    private var authorizationCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "location.circle")
                .font(.title2)
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "permission.location.services_required_title", comment: "Alert title: Location Services permission needed"))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(String(localized: "permission.location.macos_requires", comment: "Explanation of macOS LS requirement with privacy reassurance"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button(String(localized: "common.action.authorize", comment: "Authorize/request permission button")) {
                viewModel.requestAuthorization()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(12)
        .glassBackground(.regular, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Environment Summary

    private var environmentCard: some View {
        HStack(spacing: 16) {
            Image(systemName: "globe")
                .font(.title3)
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: String(localized: "overview.environment.summary_fmt", comment: "Banner showing count of detected networks"), totalNetworks))
                    .font(.subheadline.weight(.semibold))
                Text(bandSummary)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .glassBackground(.regular, in: RoundedRectangle(cornerRadius: 12))
    }

    private var bandSummary: String {
        viewModel.cachedBandSummary
    }

    // MARK: - Helpers

    private func hasBetterChannel(_ current: ChannelRecommendation) -> Bool {
        recommendedChannels.contains(where: { $0.channel != current.channel && $0.recommendationScore > current.recommendationScore })
    }

    private func rssiColor(_ rssi: Int) -> Color {
        if rssi >= -55 { return .green }
        if rssi >= -70 { return .yellow }
        if rssi >= -85 { return .orange }
        return .red
    }

    private func rssiFraction(_ rssi: Int) -> CGFloat {
        max(0, min(1, CGFloat(rssi + 100) / 70))
    }

    private func signalLabel(_ rssi: Int) -> String {
        if rssi >= -55 { return String(localized: "overview.signal.strong", comment: "Strong signal level label") }
        if rssi >= -70 { return String(localized: "overview.signal.good", comment: "Good signal level label") }
        if rssi >= -85 { return String(localized: "channels.quality.moderate", comment: "Moderate channel quality tier") }
        return String(localized: "overview.signal.weak", comment: "Weak signal level label")
    }

    private func signalBars(_ rssi: Int) -> some View {
        let active = rssi >= -85 ? (rssi >= -70 ? (rssi >= -55 ? 3 : 2) : 1) : 0
        return HStack(spacing: 2) {
            ForEach(0..<3) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i < active ? rssiColor(rssi) : Color.secondary.opacity(0.15))
                    .frame(width: 4, height: CGFloat(6 + i * 4))
                    .accessibilityHidden(true)
            }
        }
        .accessibilityLabel(String(format: String(localized: "roaming.accessibility.rssi_fmt", comment: "RSSI accessibility label with value and quality"), rssi, signalLabel(rssi)))
    }

    private func bandName(_ ch: Int) -> String {
        if ch <= 14 { return String(localized: "wifi.band.24ghz", comment: "2.4 GHz Wi-Fi band name") }
        if ch <= 170 { return String(localized: "wifi.band.5ghz", comment: "5 GHz Wi-Fi band name") }
        return String(localized: "wifi.band.6ghz", comment: "6 GHz Wi-Fi band name")
    }

    private func securityShort(_ sec: String) -> String {
        if sec.contains("WPA3") { return "WPA3" }
        if sec.contains("WPA2") { return "WPA2" }
        if sec.contains("WPA") { return "WPA" }
        if sec == "—" || sec == String(localized: "common.label.none", comment: "Generic none/empty value label") { return String(localized: "wifi.security.open", comment: "Open/no password security type") }
        return sec
    }
}

private struct EqualEarthWorldMapBackdrop: View {
    let colorScheme: ColorScheme

    var body: some View {
        GeometryReader { geometry in
            let cropWidth = min(620, max(480, geometry.size.width * 0.48))
            let cropHeight: CGFloat = 300
            let imageWidth = min(
                max(560, cropWidth * 1.12),
                cropHeight * 684 / 340.306
            )
            let imageHeight = imageWidth * 340.306 / 684

            // Use the layout system's actual top-trailing anchor. The map is
            // fitted inside this crop so its top edge is not cut by the safe
            // area; the visual treatment comes from the mask, not displacement.
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Image("EqualEarthWorldMap")
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .frame(width: imageWidth, height: imageHeight)
                        .foregroundStyle(
                            colorScheme == .dark
                                ? Color.white.opacity(0.12)
                                : Color.black.opacity(0.07)
                        )
                        .blur(radius: 3.0)
                        // Fit the source entirely inside the crop so the
                        // northern edge and both American continents remain
                        // visible at the top-trailing anchor.
                        .offset(x: 0, y: 0)
                }
                .frame(width: cropWidth, height: cropHeight)
                .mask(
                    RadialGradient(
                        stops: [
                            .init(color: .black, location: 0.05),
                            .init(color: .black.opacity(0.82), location: 0.38),
                            .init(color: .black.opacity(0.28), location: 0.72),
                            .init(color: .clear, location: 1),
                        ],
                        center: .topTrailing,
                        startRadius: 18,
                        endRadius: max(cropWidth, cropHeight) * 1.15
                    )
                )
                // Fade the image before the right edge as well. The map can
                // remain top-trailing without ending in a visible vertical
                // crop line.
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0.0),
                            .init(color: .black, location: 0.78),
                            .init(color: .black.opacity(0.72), location: 0.92),
                            .init(color: .clear, location: 1.0),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - 3D Earth Globe

/// Plain container that only creates the SceneKit globe once its window is
/// actually on screen. Even with `isPlaying = false`, SCNView renders a
/// frame when it first attaches to a window, so a never-ordered-front
/// NSWindow (e.g. the ones in DetailPageHorizontalOverflowTests) makes
/// SceneKit render into a 0x0 drawable — a fatal Metal texture-description
/// validation assertion that crashes the test host on headless CI. Keeping
/// the SCNView out of the hierarchy until the window is visible avoids the
/// Metal render path entirely.
private final class GlobeContainerView: NSView {
    private var visibilityObserver: NSObjectProtocol?
    private var globeView: SCNView?
    private var pendingTint: NSColor?

    /// Respects Reduce Motion: when enabled, the globe renders a static frame
    /// and the SceneKit render loop is stopped instead of playing ambient motion.
    var reduceMotion: Bool = false {
        didSet {
            guard reduceMotion != oldValue else { return }
            if reduceMotion {
                globeView?.isPlaying = false
            } else {
                updatePlaybackIfVisible()
            }
        }
    }

    var scene: SCNScene? {
        didSet { updatePlaybackIfVisible() }
    }

    var tint: NSColor? {
        didSet {
            pendingTint = tint
            applyTint()
        }
    }

    /// Idempotent — safe to call from scene/tint didSet, makeNSView's
    /// deferred block, viewDidMoveToWindow, and the visibility notification.
    func updatePlaybackIfVisible() {
        guard let window, window.isVisible, !bounds.isEmpty else { return }
        guard globeView == nil else {
            globeView?.isPlaying = !reduceMotion
            return
        }
        guard let scene else { return }
        let view = SCNView()
        view.backgroundColor = .clear
        view.allowsCameraControl = false
        view.isJitteringEnabled = true
        view.antialiasingMode = .multisampling8X
        view.preferredFramesPerSecond = 0
        view.scene = scene
        view.isPlaying = !reduceMotion
        view.frame = bounds
        view.autoresizingMask = [.width, .height]
        addSubview(view)
        globeView = view
        applyTint()
    }

    private func applyTint() {
        guard let globeView, let scene = globeView.scene, let tint else { return }
        if let tilt = scene.rootNode.childNode(withName: "tilt", recursively: false) {
            if let innerGlow = tilt.childNode(withName: "innerGlow", recursively: false) {
                innerGlow.geometry?.materials.first?.diffuse.contents = tint.withAlphaComponent(0.06)
            }
            if let glow = tilt.childNode(withName: "glow", recursively: false) {
                glow.geometry?.materials.first?.diffuse.contents = tint.withAlphaComponent(0.08)
            }
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Remove the previous observer (either the one for the old window,
        // or the one for the window we are detaching from).
        if let visibilityObserver {
            NotificationCenter.default.removeObserver(visibilityObserver)
            self.visibilityObserver = nil
        }
        guard let window else { return }
        // Fires when the window becomes visible (occlusion state changes),
        // catching the "window shown after the view was created" case.
        // `queue: .main` + `[weak self]` keeps the callback on the main
        // actor and lets the view outlive the observer without a deinit
        // that touches MainActor state from a background thread.
        visibilityObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            // queue: .main guarantees the callback runs on the main actor.
            MainActor.assumeIsolated {
                self?.updatePlaybackIfVisible()
            }
        }
        updatePlaybackIfVisible()
    }
}

private struct EarthGlobeView: NSViewRepresentable {
    let color: Color
    let reduceMotion: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> GlobeContainerView {
        let scene = SCNScene()

        // Axial tilt container — Earth rotates at 23.5° from orbital plane
        let tiltNode = SCNNode()
        tiltNode.eulerAngles = SCNVector3(0.41, 0, 0)
        tiltNode.name = "tilt"
        scene.rootNode.addChildNode(tiltNode)

        // Earth sphere with mipmapped texture for anti-aliasing
        let earth = SCNSphere(radius: 1)
        earth.segmentCount = 96
        let material = SCNMaterial()
        material.diffuse.contents = NSColor(red: 0.08, green: 0.12, blue: 0.35, alpha: 1)
        
        let image = NSImage(named: "Earth")
        material.diffuse.contents = image
        
        material.diffuse.mipFilter = .linear
        material.diffuse.maxAnisotropy = 4
        material.lightingModel = .constant
        earth.materials = [material]
        let earthNode = SCNNode(geometry: earth)
        earthNode.name = "earth"
        tiltNode.addChildNode(earthNode)

        // Pole caps — cover equirectangular projection artifacts
        let capGeom = SCNCylinder(radius: 0.04, height: 0.02)
        capGeom.firstMaterial?.diffuse.contents = NSColor(red: 0.06, green: 0.10, blue: 0.28, alpha: 1)
        let northCap = SCNNode(geometry: capGeom)
        northCap.position = SCNVector3(0, 0.99, 0)
        earthNode.addChildNode(northCap)
        let southCap = SCNNode(geometry: capGeom)
        southCap.position = SCNVector3(0, -0.99, 0)
        earthNode.addChildNode(southCap)

        // Atmosphere glows — on tilt container so they tilt with Earth
        let innerGlow = SCNSphere(radius: 1.03)
        innerGlow.segmentCount = 64
        let innerGlowMat = SCNMaterial()
        innerGlowMat.diffuse.contents = NSColor.blue.withAlphaComponent(0.04)
        innerGlowMat.transparency = 0.15
        innerGlowMat.isDoubleSided = true
        innerGlow.materials = [innerGlowMat]
        let innerGlowNode = SCNNode(geometry: innerGlow)
        innerGlowNode.name = "innerGlow"
        tiltNode.addChildNode(innerGlowNode)

        let glow = SCNSphere(radius: 1.08)
        glow.segmentCount = 64
        let glowMat = SCNMaterial()
        glowMat.diffuse.contents = NSColor.blue.withAlphaComponent(0.06)
        glowMat.transparency = 0.2
        glowMat.isDoubleSided = true
        glow.materials = [glowMat]
        let glowNode = SCNNode(geometry: glow)
        glowNode.name = "glow"
        tiltNode.addChildNode(glowNode)

        // ---- Data-flow visualization on earthNode (rotates with Earth) ----

        let hubColor = NSColor.systemCyan.withAlphaComponent(0.9)
        let tubeColor = NSColor.systemCyan.withAlphaComponent(0.10)
        let arcRadius: CGFloat = 1.028
        let hubRadius: CGFloat = 1.025

        // lat/lon → unit 3D point
        func spherePoint(lat: CGFloat, lon: CGFloat) -> SCNVector3 {
            let latR = lat * .pi / 180; let lonR = lon * .pi / 180
            return SCNVector3(cos(latR) * cos(lonR), sin(latR), cos(latR) * sin(lonR))
        }

        // Hub cities
        let hubs: [(CGFloat, CGFloat)] = [
            (37.4, -122.1), (40.7, -74.0), (51.5, -0.1), (35.7, 139.8),
            (1.3, 103.8), (50.1, 8.7), (-33.9, 151.2), (-23.5, -46.6),
        ]
        let hubPairs: [(Int, Int)] = [(0,1),(1,2),(2,5),(3,4),(4,7),(5,3),(0,3),(6,4),(7,0),(2,3)]
        var tubeNodes: [SCNNode] = []

        // Create hub dots + store unit positions for tubes
        var hubUnitPos: [SCNVector3] = []
        var hubNodes: [SCNNode] = []
        for (lat, lon) in hubs {
            let p = spherePoint(lat: lat, lon: lon)
            hubUnitPos.append(p)

            let dot = SCNSphere(radius: 0.014)
            dot.firstMaterial?.diffuse.contents = hubColor
            dot.firstMaterial?.emission.contents = hubColor
            let node = SCNNode(geometry: dot)
            node.position = SCNVector3(p.x * hubRadius, p.y * hubRadius, p.z * hubRadius)
            earthNode.addChildNode(node)
            hubNodes.append(node)
        }

        // Connection tubes between hub pairs
        for (a, b) in hubPairs {
            let fromU = hubUnitPos[a]; let toU = hubUnitPos[b]
            let fromP = SCNVector3(fromU.x * arcRadius, fromU.y * arcRadius, fromU.z * arcRadius)
            let toP   = SCNVector3(toU.x   * arcRadius, toU.y   * arcRadius, toU.z   * arcRadius)
            let midP  = SCNVector3((fromP.x+toP.x)/2, (fromP.y+toP.y)/2, (fromP.z+toP.z)/2)
            let dx = toP.x - fromP.x; let dy = toP.y - fromP.y; let dz = toP.z - fromP.z
            let chordLen = sqrt(dx*dx + dy*dy + dz*dz)

            let tube = SCNCylinder(radius: 0.0012, height: chordLen)
            tube.firstMaterial?.diffuse.contents = tubeColor
            let tubeNode = SCNNode(geometry: tube)
            tubeNode.position = midP
            tubeNode.look(at: toP, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 1, 0))
            earthNode.addChildNode(tubeNode)
            tubeNodes.append(tubeNode)
        }

        // Camera
        let camera = SCNCamera()
        camera.fieldOfView = 40
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, 3.5)
        scene.rootNode.addChildNode(cameraNode)

        // Keep node references so Reduce Motion can start/stop ambient motion.
        context.coordinator.scene = scene
        context.coordinator.earthNode = earthNode
        context.coordinator.innerGlowNode = innerGlowNode
        context.coordinator.glowNode = glowNode
        context.coordinator.hubNodes = hubNodes
        context.coordinator.tubeNodes = tubeNodes
        context.coordinator.reduceMotion = reduceMotion

        if !reduceMotion {
            startAnimations(on: context.coordinator)
        }

        let container = GlobeContainerView()
        container.tint = NSColor(color)
        container.reduceMotion = reduceMotion
        container.scene = scene
        DispatchQueue.main.async { container.updatePlaybackIfVisible() }
        return container
    }

    func updateNSView(_ nsView: GlobeContainerView, context: Context) {
        nsView.tint = NSColor(color)
        nsView.reduceMotion = reduceMotion
        let coordinator = context.coordinator
        guard coordinator.reduceMotion != reduceMotion else { return }
        coordinator.reduceMotion = reduceMotion
        if reduceMotion {
            stopAnimations(on: coordinator)
        } else {
            startAnimations(on: coordinator)
        }
    }

    class Coordinator {
        var scene: SCNScene?
        var earthNode: SCNNode?
        var innerGlowNode: SCNNode?
        var glowNode: SCNNode?
        var hubNodes: [SCNNode] = []
        var tubeNodes: [SCNNode] = []
        var reduceMotion = false
    }

    // MARK: - Ambient Motion

    private func startAnimations(on coordinator: Coordinator) {
        guard let earthNode = coordinator.earthNode,
              let innerGlowNode = coordinator.innerGlowNode,
              let glowNode = coordinator.glowNode else { return }

        // Remove any existing keys first so repeated start transitions can
        // never stack duplicate CAAnimation instances on the same node.
        stopAnimations(on: coordinator)

        for node in coordinator.hubNodes {
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 0.3; pulse.toValue = 1.0; pulse.duration = 1.2
            pulse.autoreverses = true; pulse.repeatCount = .greatestFiniteMagnitude
            node.addAnimation(pulse, forKey: "pulse")
        }

        for tube in coordinator.tubeNodes {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.15; fade.toValue = 0.45; fade.duration = Double.random(in: 2...4)
            fade.autoreverses = true; fade.repeatCount = .greatestFiniteMagnitude
            tube.addAnimation(fade, forKey: "flow")
        }

        let rotate = CABasicAnimation(keyPath: "rotation")
        rotate.fromValue = SCNVector4(0, 1, 0, 0)
        rotate.toValue = SCNVector4(0, 1, 0, Float.pi * 2)
        rotate.duration = 60
        rotate.repeatCount = .greatestFiniteMagnitude
        earthNode.addAnimation(rotate, forKey: "rotate")
        innerGlowNode.addAnimation(rotate, forKey: "rotate")
        glowNode.addAnimation(rotate, forKey: "rotate")
    }

    private func stopAnimations(on coordinator: Coordinator) {
        coordinator.hubNodes.forEach { $0.removeAnimation(forKey: "pulse") }
        coordinator.tubeNodes.forEach { $0.removeAnimation(forKey: "flow") }
        coordinator.earthNode?.removeAnimation(forKey: "rotate")
        coordinator.innerGlowNode?.removeAnimation(forKey: "rotate")
        coordinator.glowNode?.removeAnimation(forKey: "rotate")
    }
}
