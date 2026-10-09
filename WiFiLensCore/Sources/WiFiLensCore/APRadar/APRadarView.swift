import SwiftUI

/// AP Radar page: select an access point, track its BSSID, and get audio
/// pulse feedback whose interval follows the smoothed RSSI.
public struct APRadarView: View {
    @Bindable var viewModel: APRadarViewModel
    /// True when this is the selected sidebar page. Pages stay mounted in the
    /// detail ZStack, so page switches must be observed explicitly.
    var isActive: Bool
    var onRescan: () -> Void

    public init(viewModel: APRadarViewModel, isActive: Bool, onRescan: @escaping () -> Void) {
        self.viewModel = viewModel
        self.isActive = isActive
        self.onRescan = onRescan
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showSelection = false
    @State private var secretTapTimes: [Date] = []
    /// One-shot toast shown the first time the hidden Geiger preset unlocks.
    @State private var geigerUnlockedToast = false

    /// Shared layout metrics so every card on the page reads as one system,
    /// matching the rest of the app (see OverviewView).
    private static let contentMaxWidth: CGFloat = 640
    private static let pagePadding: CGFloat = 16

    /// Tracking and signal loss share one instrument, so only entering or
    /// leaving a session transitions the page itself.
    private var stateKey: Int { viewModel.state == .idle ? 0 : 1 }

    private var sessionSnapshot: APRadarSnapshot? {
        switch viewModel.state {
        case .idle: nil
        case .tracking(let snapshot): snapshot
        case .signalLost(let snapshot):
            APRadarSnapshot(
                target: snapshot.target,
                smoothedRSSI: snapshot.lastRSSI,
                lastSeenAt: snapshot.lastSeenAt
            )
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            pageHeader
            Divider()

            // State pages animate in/out so entering or leaving scan mode
            // feels like the radar powers up/down instead of an instant swap.
            ZStack {
                switch viewModel.state {
                case .idle:
                    idleContent
                        .transition(.opacity)
                case .tracking, .signalLost:
                    if let snapshot = sessionSnapshot {
                        sessionContent(snapshot)
                            .transition(.opacity)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: stateKey)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            viewModel.setActive(isActive)
        }
        .onChange(of: isActive) { _, active in
            viewModel.setActive(active)
        }
        .onDisappear {
            viewModel.setActive(false)
        }
        .sheet(isPresented: $showSelection) {
            APSelectionView(
                viewModel: viewModel,
                onSelect: { option in
                    showSelection = false
                    viewModel.selectTarget(option)
                },
                onRescan: onRescan,
                onCancel: { showSelection = false }
            )
        }
        .overlay(alignment: .bottom) {
            if geigerUnlockedToast {
                Label(
                    String(localized: "apRadar.easterEgg.unlocked", comment: "Toast shown when the hidden Geiger counter preset is unlocked"),
                    systemImage: "gift.fill"
                )
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .glassBackground(.regular, in: Capsule())
                .padding(.bottom, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityIdentifier("apradar-easter-egg-toast")
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: geigerUnlockedToast)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("page-apRadar")
    }

    /// Hidden gesture: five quick taps on the router icon unlock the
    /// Geiger-counter sound preset and reveal it in Settings once.
    private func revealGeigerPreset() {
        if viewModel.unlockGeigerPreset() {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) {
                geigerUnlockedToast = true
            }
            Task {
                try? await Task.sleep(for: .seconds(3.5))
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) {
                    geigerUnlockedToast = false
                }
            }
        }
    }

    // MARK: - Header

    private var pageHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text(String(localized: "nav.apRadar", comment: "AP Radar sidebar navigation item"))
                .font(.title3.weight(.semibold))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    /// Adaptive layout metrics for the page. `regular` is the comfortable
    /// layout at normal window sizes; `compact` tightens spacing and shrinks
    /// the radar so small windows avoid needless scrolling.
    private struct RadarFit {
        var spacing: CGFloat
        var statusIconSize: CGFloat
        var statusIconContainer: CGFloat

        static let regular = RadarFit(
            spacing: 16,
            statusIconSize: 30,
            statusIconContainer: 160
        )
        static let compact = RadarFit(
            spacing: 10,
            statusIconSize: 24,
            statusIconContainer: 112
        )
    }

    /// Wraps a state layout so it is centered without scrolling whenever it
    /// fits the available height, then tries a compact layout, and finally
    /// falls back to a scroll view when the window is too small. Prevents
    /// clipped content and needless scrollbars at the minimum window size.
    ///
    /// Content is centered with `Spacer`s because they collapse to zero during
    /// ideal-size measurement; `.frame(maxHeight: .infinity)` instead claims
    /// to fit any height and defeats the `ViewThatFits` fallback.
    @ViewBuilder
    private func fittingContent<Regular: View, Compact: View>(
        @ViewBuilder regular: () -> Regular,
        @ViewBuilder compact: () -> Compact
    ) -> some View {
        ViewThatFits(in: .vertical) {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                regular()
                Spacer(minLength: 0)
            }
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                compact()
                Spacer(minLength: 0)
            }
            ScrollView {
                compact()
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    // MARK: - Idle

    private var idleContent: some View {
        fittingContent(
            regular: { idleLayout(fit: .regular) },
            compact: { idleLayout(fit: .compact) }
        )
    }

    private func idleLayout(fit: RadarFit) -> some View {
        VStack(spacing: fit.spacing) {
            ZStack {
                ForEach([1.0, 0.74], id: \.self) { scale in
                    Circle()
                        .stroke(Color.radarGreen.opacity(scale == 1 ? 0.10 : 0.18), lineWidth: 1)
                        .frame(width: fit.statusIconContainer * scale, height: fit.statusIconContainer * scale)
                }
                Circle()
                    .fill(Color.radarGreen.opacity(0.05))
                    .overlay(Circle().stroke(Color.radarGreen.opacity(0.24), lineWidth: 1))
                    .frame(width: fit.statusIconContainer * 0.48, height: fit.statusIconContainer * 0.48)
                Image(systemName: "wifi.router")
                    .font(.system(size: fit.statusIconSize, weight: .medium))
                    .foregroundStyle(Color.radarGreen)
            }
            .accessibilityHidden(true)
            .padding(.top, 6)

            Text(String(localized: "apRadar.description", comment: "AP Radar feature description on the idle page"))
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
                .frame(maxWidth: 380)

            Button {
                showSelection = true
            } label: {
                Label(
                    String(localized: "apRadar.selectTarget", comment: "Button to choose an access point to track"),
                    systemImage: "plus"
                )
            }
            .accessibilityIdentifier("ap-radar-select-target")
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if viewModel.latestNetworks.isEmpty {
                emptyScanState
            } else {
                Label(selectionSummary, systemImage: "wifi")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(String(localized: "apRadar.disclaimer", comment: "AP Radar disclaimer about RSSI-only guidance"))
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
                .padding(.top, 4)

            if viewModel.scanFailed {
                Label(
                    String(localized: "apRadar.scan.failed", comment: "Message shown when the latest Wi-Fi scan failed"),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }

            if let audioErrorMessage = viewModel.audioErrorMessage {
                Label(audioErrorMessage, systemImage: "speaker.slash.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(maxWidth: Self.contentMaxWidth)
        .padding(Self.pagePadding)
    }

    private var selectionSummary: String {
        let count = viewModel.selectionOptions.count
        return String(
            format: String(localized: "apRadar.summary.available", comment: "Summary of APs visible to the selector, e.g. 12 access points available"),
            count
        )
    }

    private var emptyScanState: some View {
        VStack(spacing: 8) {
            Text(String(localized: "apRadar.empty.title", comment: "Empty state when no access points were found"))
                .font(.headline)
            Text(String(localized: "apRadar.empty.description", comment: "Empty state guidance when no access points were found"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                onRescan()
            } label: {
                Label(
                    String(localized: "apRadar.rescan", comment: "Button to rescan for access points"),
                    systemImage: "arrow.clockwise"
                )
            }
            .buttonStyle(.bordered)
            .padding(.top, 2)
        }
        .frame(maxWidth: 400)
    }

    // MARK: - Tracking instrument

    private func sessionContent(_ snapshot: APRadarSnapshot) -> some View {
        let isLost = viewModel.state.isSignalLost
        return VStack(spacing: 12) {
            targetHeader(snapshot, isLost: isLost)

            GeometryReader { proxy in
                let side = max(0, min(proxy.size.width, proxy.size.height, 640))
                let coreDiameter = min(side, min(240, max(160, side * 0.55)))
                ZStack {
                    RadarBackdrop(size: proxy.size, color: isLost ? .orange : .radarGreen)
                    RadarPulseVisual(
                        smoothedRSSI: snapshot.smoothedRSSI,
                        pulseTick: viewModel.pulseTick,
                        soundEnabled: viewModel.soundEnabled,
                        reduceMotion: reduceMotion,
                        isGeiger: viewModel.soundPreset == .geiger,
                        size: side,
                        coreDiameter: coreDiameter,
                        isSuspended: viewModel.isSuspended || viewModel.isAwaitingFreshScan || isLost || snapshot.smoothedRSSI == nil
                    )
                    instrumentReadout(snapshot, isLost: isLost, diameter: coreDiameter)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
            }

            sessionDetail(snapshot, isLost: isLost)
            controlsRow
        }
        .padding(Self.pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }

    private func targetHeader(_ snapshot: APRadarSnapshot, isLost: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(snapshot.target.currentSSID ?? String(localized: "apRadar.target.hiddenNetwork", comment: "Label for an access point that hides its SSID"))
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(targetSubtitle(snapshot.target))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(targetSubtitle(snapshot.target))
            }
            Spacer(minLength: 0)
            Label(
                isLost
                    ? String(localized: "apRadar.signalLost.title", comment: "Signal lost title")
                    : snapshot.smoothedRSSI == nil
                        ? trendText(.measuring)
                        : String(localized: "apRadar.status.tracking", comment: "Status pill shown while AP Radar is tracking an access point"),
                systemImage: isLost ? "wifi.exclamationmark" : "dot.radiowaves.left.and.right"
            )
            .font(.caption.weight(.medium))
            .foregroundStyle(isLost ? Color.orange : .secondary)
            .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    /// Keep the number and trend in the same fixed core in every session state.
    private func instrumentReadout(_ snapshot: APRadarSnapshot, isLost: Bool, diameter: CGFloat) -> some View {
        VStack(spacing: diameter < 160 ? 6 : 10) {
            Image(systemName: isLost ? "wifi.exclamationmark" : "wifi.router")
                .font(.system(size: diameter < 160 ? 18 : 24, weight: .medium))
                .foregroundStyle(isLost ? Color.orange : .radarGreen)
                .contentShape(Rectangle())
                .onTapGesture { handleSecretTap() }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(rssiNumberText(snapshot.smoothedRSSI))
                    .font(.system(size: max(32, min(64, diameter * 0.28)), weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isLost ? .secondary : .primary)
                Text(String(localized: "ble.table.unit.dbm", comment: "dBm unit label"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Label(
                isLost ? String(localized: "apRadar.signalLost.title", comment: "Signal lost title") : trendText(snapshot.trend),
                systemImage: isLost ? "exclamationmark.circle" : trendSymbol(snapshot.trend)
            )
            .font(.callout.weight(.medium))
            .foregroundStyle(isLost ? .orange : trendColor(snapshot.trend))
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .help(isLost ? String(localized: "apRadar.signalLost.description", comment: "Signal lost explanation") : trendText(snapshot.trend))
        }
        .padding(diameter < 160 ? 8 : 12)
        .frame(width: diameter, height: diameter)
        .background {
            Circle().fill(.background).opacity(0.94)
        }
        .overlay {
            Circle().strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sessionAccessibilityLabel(snapshot))
    }

    private func sessionDetail(_ snapshot: APRadarSnapshot, isLost: Bool) -> some View {
        VStack(spacing: 5) {
            if let audioErrorMessage = viewModel.audioErrorMessage {
                Label(audioErrorMessage, systemImage: "speaker.slash.fill")
                    .foregroundStyle(.orange)
            } else if isLost {
                Label(String(localized: "apRadar.signalLost.rescanning", comment: "Status shown while waiting for the next scan"), systemImage: "arrow.clockwise")
            } else if let raw = snapshot.rawRSSI {
                Text(rawSignalText(raw))
            } else {
                Text(trendText(.measuring))
            }
            if let lastSeen = snapshot.lastSeenAt {
                Text(String(
                    format: String(localized: "apRadar.signalLost.lastSeen", comment: "Time the access point was last seen"),
                    Self.lastSeenFormatter.string(from: lastSeen)
                ))
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .lineLimit(2)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
    }

    private func sessionAccessibilityLabel(_ snapshot: APRadarSnapshot) -> String {
        if case .signalLost(let lost) = viewModel.state {
            return signalLostAccessibilityLabel(lost)
        }
        return trackingAccessibilityLabel(snapshot)
    }

    private func trendSymbol(_ trend: SignalTrend) -> String {
        switch trend {
        case .measuring: "waveform"
        case .gettingCloser: "arrow.up.right"
        case .stable: "minus"
        case .movingAway: "arrow.down.right"
        }
    }

    private func handleSecretTap() {
        let now = Date()
        secretTapTimes.append(now)
        secretTapTimes.removeAll { now.timeIntervalSince($0) >= 1.5 }
        if secretTapTimes.count >= 5 {
            secretTapTimes.removeAll()
            revealGeigerPreset()
        }
    }

    /// Action row that stays on one line when space allows and stacks
    /// full-width buttons when the window is narrow.
    @ViewBuilder
    private var controlsRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                soundToggleButton
                changeTargetButton
                stopTrackingButton
            }
            VStack(spacing: 10) {
                soundToggleButton
                    .frame(maxWidth: .infinity)
                changeTargetButton
                    .frame(maxWidth: .infinity)
                stopTrackingButton
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .padding(.top, 4)
    }

    private var soundToggleButton: some View {
        Button {
            viewModel.setSoundEnabled(!viewModel.soundEnabled)
        } label: {
            Label(
                viewModel.soundEnabled
                    ? String(localized: "apRadar.sound.on", comment: "Button label when sound is on")
                    : String(localized: "apRadar.sound.off", comment: "Button label when sound is off"),
                systemImage: viewModel.soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill"
            )
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("ap-radar-sound-toggle")
    }

    private var changeTargetButton: some View {
        Button {
            showSelection = true
        } label: {
            Label(
                String(localized: "apRadar.changeTarget", comment: "Button to pick a different access point"),
                systemImage: "arrow.triangle.2.circlepath"
            )
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("ap-radar-change-target")
    }

    private var stopTrackingButton: some View {
        Button(role: .destructive) {
            viewModel.stopTracking()
        } label: {
            Label(
                String(localized: "apRadar.stopTracking", comment: "Button to stop tracking the current access point"),
                systemImage: "stop.fill"
            )
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("ap-radar-stop-tracking")
    }

    private func targetSubtitle(_ target: TrackedAccessPoint) -> String {
        let band = target.band?.displayName ?? ""
        let channel = target.channel.map {
            String(format: String(localized: "apRadar.target.channel", comment: "Access point channel, e.g. Channel 149"), $0)
        } ?? ""
        return [target.bssid, band, channel]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private func trackingAccessibilityLabel(_ snapshot: APRadarSnapshot) -> String {
        let target = snapshot.target
        let ssid = target.currentSSID ?? String(localized: "apRadar.target.hiddenNetwork", comment: "Label for an access point that hides its SSID")
        let trend = trendText(snapshot.trend)
        let soundState = viewModel.soundEnabled
            ? String(localized: "apRadar.sound.state.on", comment: "VoiceOver text when sound is enabled")
            : String(localized: "apRadar.sound.state.off", comment: "VoiceOver text when sound is disabled")
        let signalStrength = snapshot.smoothedRSSI.map {
            String(
                format: String(localized: "apRadar.signal.dbm", comment: "Smoothed signal value with dBm unit for the VoiceOver summary"),
                Int($0.rounded())
            )
        } ?? "—"
        return String(
            format: String(localized: "apRadar.accessibility.tracking", comment: "VoiceOver summary of the tracked access point"),
            ssid,
            target.bssid,
            signalStrength,
            trend,
            soundState
        )
    }

    private func signalLostAccessibilityLabel(_ snapshot: APRadarLostSnapshot) -> String {
        let ssid = snapshot.target.currentSSID ?? String(localized: "apRadar.target.hiddenNetwork", comment: "Label for an access point that hides its SSID")
        return String(
            format: String(localized: "apRadar.accessibility.signalLost", comment: "VoiceOver summary for the signal lost state"),
            ssid,
            snapshot.target.bssid
        )
    }

    // MARK: - Shared bits

    private func rssiNumberText(_ smoothed: Double?) -> String {
        guard let smoothed else {
            return "—"
        }
        return "\(Int(smoothed.rounded()))"
    }

    private func rawSignalText(_ raw: Int) -> String {
        String(
            format: String(localized: "apRadar.signal.raw", comment: "Raw (un-smoothed) signal value with dBm unit"),
            raw
        )
    }

    private func trendText(_ trend: SignalTrend) -> String {
        switch trend {
        case .measuring:
            String(localized: "apRadar.trend.measuring", comment: "Trend while enough samples are being gathered")
        case .gettingCloser:
            String(localized: "apRadar.trend.gettingCloser", comment: "Trend when signal is getting stronger")
        case .stable:
            String(localized: "apRadar.trend.stable", comment: "Trend when signal is stable")
        case .movingAway:
            String(localized: "apRadar.trend.movingAway", comment: "Trend when signal is getting weaker")
        }
    }

    private func trendColor(_ trend: SignalTrend) -> Color {
        switch trend {
        case .measuring:
            .secondary
        case .gettingCloser:
            .green
        case .stable:
            .secondary
        case .movingAway:
            .orange
        }
    }

    private static let lastSeenFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()
}


// MARK: - Radar backdrop

/// Full-page backdrop behind the ripple: a soft radial tint plus a few faint
/// static concentric circles. Purely decorative — it only sets the "radar"
/// mood and never implies a direction, angle or distance.
private struct RadarBackdrop: View {
    var size: CGSize
    var color: Color

    var body: some View {
        let minSide = min(size.width, size.height)
        ZStack {
            RadialGradient(
                colors: [color.opacity(0.10), color.opacity(0.03), .clear],
                center: .center,
                startRadius: 0,
                endRadius: minSide * 0.7
            )
            ForEach([0.42, 0.65, 0.88], id: \.self) { fraction in
                Circle()
                    .stroke(color.opacity(0.07), lineWidth: 1)
                    .frame(width: minSide * fraction, height: minSide * fraction)
            }
        }
        .frame(width: size.width, height: size.height)
        .accessibilityHidden(true)
    }
}

private extension Color {
    /// Signature green used by the AP Radar ripple visual.
    static let radarGreen = Color(red: 0.26, green: 0.83, blue: 0.47)
}

// MARK: - Ripple pulse visual

/// Water-ripple pulse canvas. Signal semantics are limited to strength: each
/// audio pulse spawns a soft green ripple that expands outward from the central
/// readout, and the wave brightness follows the smoothed RSSI. The
/// ripple is purely decorative — it only expresses "a pulse happened", never
/// a direction or distance.
private struct RadarPulseVisual: View {
    let smoothedRSSI: Double?
    let pulseTick: Int
    let soundEnabled: Bool
    let reduceMotion: Bool
    /// When the Geiger preset is active, muted visuals click irregularly
    /// (exponential intervals) instead of on a fixed metronome.
    var isGeiger: Bool = false
    /// Canvas side length: as large as the page allows.
    var size: CGFloat = 220
    var coreDiameter: CGFloat = 180
    /// Pause while suspended, waiting for a first sample, or signal-lost.
    /// SwiftUI cancels the cadence task when this value changes.
    var isSuspended: Bool = false

    @State private var ripples: [Ripple] = []
    @State private var liveSmoothedRSSI: Double?
    /// Sound state mirrored into `@State` so the long-lived visual loop sees
    /// toggles instead of the initial value captured at task creation.
    @State private var soundOn = false
    /// When the last pulse beat happened (audio beat or visual fallback).
    @State private var lastPulseAt = ContinuousClock.now
    /// How long a ripple stays on screen: animation duration plus a small tail
    /// so removal never clips the last visible frame.
    private static let rippleLifetime: Duration = .milliseconds(950)

    private struct Ripple: Identifiable {
        let id = UUID()
        let strength: Double
    }

    var body: some View {
        ZStack {
            // One expanding ripple per pulse beat.
            ForEach(ripples) { ripple in
                RippleRingView(
                    reduceMotion: reduceMotion,
                    size: size,
                    strength: ripple.strength,
                    coreDiameter: coreDiameter
                )
                .id(ripple.id)
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .task(id: isSuspended) {
            guard !isSuspended else { return }
            liveSmoothedRSSI = smoothedRSSI
            soundOn = soundEnabled
            lastPulseAt = .now
            await runVisualLoop()
        }
        .onDisappear {
            ripples.removeAll()
        }
        .onChange(of: pulseTick) { _, _ in
            // Audio pulse beat: sync a ripple to the sound.
            guard soundEnabled, !isSuspended else { return }
            lastPulseAt = .now
            spawnRipple()
        }
        .onChange(of: isSuspended) { _, suspendedValue in
            if suspendedValue { ripples.removeAll() }
        }
        .onChange(of: soundEnabled) { _, enabled in
            soundOn = enabled
        }
        .onChange(of: smoothedRSSI) { _, newValue in
            liveSmoothedRSSI = newValue
        }
        .accessibilityHidden(true)
    }

    private var normalizedStrength: Double {
        guard let smoothedRSSI else { return 0 }
        return min(max((smoothedRSSI + 90) / 48, 0), 1)
    }

    private func spawnRipple() {
        let ripple = Ripple(strength: normalizedStrength)
        ripples.append(ripple)
        // Bound overlapping waves, including bursts from the stochastic preset.
        ripples = Array(ripples.suffix(6))
        Task {
            do {
                try await Task.sleep(for: Self.rippleLifetime)
            } catch {
                return
            }
            ripples.removeAll { $0.id == ripple.id }
        }
    }

    /// Visual cadence keeper. Runs for the whole lifetime of the tracking
    /// instrument while fresh samples are available:
    ///
    /// - Sound off: this loop drives the full visual cadence using the same
    ///   RSSI-to-interval mapping as the audio scheduler.
    /// - Sound on: the audio scheduler owns the cadence and fires `pulseTick`
    ///   beats; this loop only backfills when no audio beat has arrived for a
    ///   while (audio failure), then yields again once
    ///   audio beats resume.
    private func runVisualLoop() async {
        while !Task.isCancelled {
            if soundOn {
                let interval = APRadarPulseInterval.intervalSeconds(
                    forRSSI: liveSmoothedRSSI ?? -70
                )
                if secondsSince(lastPulseAt) >= interval * 1.3 {
                    spawnRipple()
                    lastPulseAt = .now
                }
                try? await Task.sleep(for: .milliseconds(120))
            } else {
                spawnRipple()
                let mean = APRadarPulseInterval.intervalSeconds(
                    forRSSI: liveSmoothedRSSI ?? -70
                )
                if isGeiger {
                    // Geiger visuals mirror the audio: irregular clicks at
                    // a mean rate that follows the signal strength.
                    let drawn = APRadarPulseInterval.nextExponentialInterval(mean: mean)
                    let deadline = ContinuousClock.now.advanced(by: .seconds(drawn))
                    while !Task.isCancelled {
                        let remaining = deadline - ContinuousClock.now
                        guard remaining > .zero else { break }
                        try? await Task.sleep(for: min(remaining, .milliseconds(100)))
                    }
                } else {
                    // Mirror the audio scheduler: wait in small steps and
                    // pull the next ripple forward when a fresh sample
                    // shortens the interval, so muted visuals react
                    // promptly too.
                    var deadline = ContinuousClock.now.advanced(by: .seconds(mean))
                    while !Task.isCancelled {
                        let remaining = deadline - ContinuousClock.now
                        guard remaining > .zero else { break }
                        try? await Task.sleep(for: min(remaining, .milliseconds(100)))
                        let desired = ContinuousClock.now.advanced(
                            by: .seconds(APRadarPulseInterval.intervalSeconds(
                                forRSSI: liveSmoothedRSSI ?? -70
                            ))
                        )
                        if desired < deadline {
                            deadline = desired
                        }
                    }
                }
            }
        }
    }

    private func secondsSince(_ instant: ContinuousClock.Instant) -> Double {
        let duration = ContinuousClock.now - instant
        return Double(duration.components.seconds)
            + Double(duration.components.attoseconds) / 1_000_000_000_000_000_000
    }
}

/// A single expanding water ripple drawn as one continuous radial-gradient
/// band whose cross-section is a single smooth crest: brightest in the middle
/// and fading out evenly towards both the inner and outer edge — a single
/// peak, no side lobes or echo crests. The band starts just outside the readout,
/// sweeps across the canvas and fades out as it travels. Stronger signals make
/// it glow brighter.
///
/// The gradient is applied with `.stroke` (not `.strokeBorder`) so the band is
/// centred on the ripple radius and lines up exactly with the gradient's
/// `startRadius`/`endRadius`; `strokeBorder` insets the stroke and distorts
/// the wave profile.
private struct RippleRingView: View {
    let reduceMotion: Bool
    var size: CGFloat
    /// Normalized 0...1 signal strength.
    var strength: Double
    /// The readout core stays clear of moving waves.
    var coreDiameter: CGFloat

    @State private var progress: Double = 0

    private func s(_ value: CGFloat) -> CGFloat {
        value * size / 220
    }

    private var rippleColor: Color { Color(red: 0.26, green: 0.83, blue: 0.47) }

    /// Maximum band thickness: on a full-page canvas the wave stays slim and
    /// elegant instead of scaling into an over-thick stroke.
    private static let maxBandWidth: CGFloat = 28

    /// Total width of the ripple band (a single crest), thinning slightly as
    /// it expands and capped for large canvases.
    private var bandWidth: CGFloat {
        min(s(12) * (1 - 0.22 * CGFloat(progress)), Self.maxBandWidth)
    }

    /// Band width at progress 1 (after thinning). Used to size the travel so
    /// the ripple's outer edge lands exactly on the canvas edge.
    private var finalBandWidth: CGFloat {
        min(s(12) * (1 - 0.22), Self.maxBandWidth)
    }

    /// Leading radius of the ripple: from just outside the readout all the way to
    /// the canvas edge. The travel is fitted so the band's outer edge reaches
    /// the canvas boundary at progress 1, letting the wave sweep the whole
    /// canvas without ever being visibly clipped by the square bounds.
    private var leadingRadius: CGFloat {
        let start = coreDiameter * 0.5 + bandWidth * 0.5 + 4
        let travel = max(0, size * 0.5 - start - finalBandWidth * 0.5)
        return start + travel * CGFloat(progress)
    }

    private var pulseOpacity: Double {
        0.55 + 0.45 * strength
    }

    /// Ripple cross-section across the band, from the inner edge to the outer
    /// edge: a sharply peaked bell with a narrow bright crest in the middle
    /// and a very fast fall-off to both edges — exactly one peak per ripple
    /// and no side lobes.
    private func waveGradient(radius: CGFloat) -> RadialGradient {
        RadialGradient(
            colors: [
                rippleColor.opacity(0.0),
                rippleColor.opacity(0.03),
                rippleColor.opacity(0.20),
                rippleColor.opacity(0.67),
                rippleColor.opacity(1.0),
                rippleColor.opacity(0.67),
                rippleColor.opacity(0.20),
                rippleColor.opacity(0.03),
                rippleColor.opacity(0.0)
            ],
            center: .center,
            startRadius: radius - bandWidth * 0.5,
            endRadius: radius + bandWidth * 0.5
        )
    }

    var body: some View {
        // Reduce Motion shows a static ring; size it so its outer edge stays
        // inside the canvas (band width is at its full progress-0 value here).
        let radius = reduceMotion ? size * 0.5 - bandWidth * 0.5 : leadingRadius
        // Gentle fade: `pow(1 - progress, 0.75)` keeps the wave visible while it
        // travels across most of the canvas, reaching zero exactly at the
        // boundary so the outer edge never looks clipped.
        let opacity = (reduceMotion ? 0.75 : 1.0) * pulseOpacity * pow(1 - progress, 0.75)
        ZStack {
            // Very soft glow behind the whole wave; kept faint so it does not
            // wash out the fade-out towards the edges.
            Circle()
                .stroke(rippleColor, lineWidth: bandWidth * 1.4)
                .blur(radius: min(s(3), 6))
                .frame(width: radius * 2, height: radius * 2)
                .opacity(0.16 * opacity)

            // Gradient band with a single smooth crest in the middle, fading
            // out to both edges — no side lobes.
            Circle()
                .stroke(waveGradient(radius: radius), lineWidth: bandWidth)
                .frame(width: radius * 2, height: radius * 2)
                .opacity(opacity)
        }
        .onAppear {
            withAnimation(.easeOut(duration: reduceMotion ? 0.35 : 0.85)) {
                progress = 1
            }
        }
    }
}
