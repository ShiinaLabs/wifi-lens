import SwiftUI

/// AP Radar page: select an access point, track its BSSID, and get audio
/// pulse feedback whose interval follows the smoothed RSSI.
struct APRadarView: View {
    @Bindable var viewModel: APRadarViewModel
    /// True when this is the selected sidebar page. Pages stay mounted in the
    /// detail ZStack, so page switches must be observed explicitly.
    var isActive: Bool
    var onRescan: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showSelection = false
    /// One-shot toast shown the first time the hidden Geiger preset unlocks.
    @State private var geigerUnlockedToast = false

    /// Shared layout metrics so every card on the page reads as one system,
    /// matching the rest of the app (see OverviewView).
    private static let contentMaxWidth: CGFloat = 640
    private static let cardRadius: CGFloat = 12
    private static let pagePadding: CGFloat = 16

    /// Stable page key for state transitions: changes only when the page
    /// switches between idle / tracking / signal lost, so per-scan snapshot
    /// updates never re-trigger the page transition animation.
    private var stateKey: Int {
        switch viewModel.state {
        case .idle: return 0
        case .tracking: return 1
        case .signalLost: return 2
        }
    }

    var body: some View {
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
                case .tracking(let snapshot):
                    trackingContent(snapshot)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.94)),
                            removal: .opacity.combined(with: .scale(scale: 0.97))
                        ))
                case .signalLost(let snapshot):
                    signalLostContent(snapshot)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.94)),
                            removal: .opacity.combined(with: .scale(scale: 0.97))
                        ))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.45), value: stateKey)
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
            SidebarBadge(style: .preview)
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
        var cardSpacing: CGFloat
        var rssiFontSize: CGFloat
        var statusIconSize: CGFloat
        var statusIconContainer: CGFloat
        var isCompact: Bool

        static let regular = RadarFit(
            spacing: 16,
            cardSpacing: 16,
            rssiFontSize: 44,
            statusIconSize: 30,
            statusIconContainer: 72,
            isCompact: false
        )
        static let compact = RadarFit(
            spacing: 10,
            cardSpacing: 10,
            rssiFontSize: 34,
            statusIconSize: 24,
            statusIconContainer: 56,
            isCompact: true
        )
    }

    /// Wraps a state layout so it is centered without scrolling whenever it
    /// fits the available height, then tries a compact layout, and finally
    /// falls back to a scroll view when the window is too small. Prevents
    /// clipped cards and needless scrollbars at the minimum window size.
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
            VStack(spacing: fit.cardSpacing) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: fit.statusIconContainer, height: fit.statusIconContainer)
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: fit.statusIconSize, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                }
                .accessibilityHidden(true)
                .padding(.top, 6)

                VStack(spacing: 8) {
                    Text(String(localized: "apRadar.description", comment: "AP Radar feature description on the idle page"))
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.primary)

                    Text(String(localized: "apRadar.disclaimer", comment: "AP Radar disclaimer about RSSI-only guidance"))
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: 440)

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
            .padding(16)
            .frame(maxWidth: .infinity)
            .glassBackground(.regular, in: RoundedRectangle(cornerRadius: Self.cardRadius))
        }
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

    // MARK: - Tracking

    private func trackingContent(_ snapshot: APRadarSnapshot) -> some View {
        GeometryReader { geo in
            // Full-page radar canvas: the ripple square is as large as the
            // whole content area (not a small tile), with the tracking cards
            // floating on top.
            let side = max(140, min(geo.size.width, geo.size.height))
            let fit: RadarFit = geo.size.height < 560 ? .compact : .regular

            ZStack {
                RadarBackdrop(size: geo.size, color: .radarGreen)

                RadarPulseVisual(
                    smoothedRSSI: snapshot.smoothedRSSI,
                    pulseTick: viewModel.pulseTick,
                    soundEnabled: viewModel.soundEnabled,
                    reduceMotion: reduceMotion,
                    isGeiger: viewModel.soundPreset == .geiger,
                    size: side,
                    onSecretTap: revealGeigerPreset,
                    isSuspended: viewModel.isSuspended
                )
                .frame(width: side, height: side)

                VStack(spacing: fit.spacing) {
                    targetCard(snapshot)
                    Spacer(minLength: 8)

                    if let audioErrorMessage = viewModel.audioErrorMessage {
                        Label(audioErrorMessage, systemImage: "speaker.slash.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity)
                            .padding(10)
                            .glassBackground(.regular, in: RoundedRectangle(cornerRadius: Self.cardRadius))
                    }

                    signalReadout(snapshot, fit: fit)
                    controlsRow
                }
                .padding(Self.pagePadding)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }

    /// Compact full-width readout floating over the radar: smoothed RSSI on
    /// the left, trend and raw RSSI on the right, strength meter below.
    private func signalReadout(_ snapshot: APRadarSnapshot, fit: RadarFit) -> some View {
        VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(rssiNumberText(snapshot.smoothedRSSI))
                        .font(.system(size: fit.rssiFontSize, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(String(localized: "ble.table.unit.dbm", comment: "dBm unit label"))
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .accessibilityHidden(true)

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 3) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(trendColor(snapshot.trend))
                            .frame(width: 8, height: 8)
                        Text(trendText(snapshot.trend))
                            .font(.headline)
                            .foregroundStyle(trendColor(snapshot.trend))
                    }
                    .accessibilityHidden(true)

                    if let raw = snapshot.rawRSSI {
                        Text(rawSignalText(raw))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                }
            }

            strengthMeter(snapshot.smoothedRSSI)
        }
        .padding(fit.isCompact ? 12 : 14)
        .frame(maxWidth: .infinity)
        .glassBackground(.regular, in: RoundedRectangle(cornerRadius: Self.cardRadius))
    }

    private func targetCard(_ snapshot: APRadarSnapshot) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(snapshot.target.currentSSID ?? String(localized: "apRadar.target.hiddenNetwork", comment: "Label for an access point that hides its SSID"))
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    statusPill
                }
                Text(targetSubtitle(snapshot.target))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .glassBackground(.regular, in: RoundedRectangle(cornerRadius: Self.cardRadius))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(trackingAccessibilityLabel(snapshot))
    }

    private var statusPill: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)
            Text(String(localized: "apRadar.status.tracking", comment: "Status pill shown while AP Radar is tracking an access point"))
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.secondary.opacity(0.12)))
        .accessibilityHidden(true)
    }

    private func strengthMeter(_ smoothed: Double?) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(String(localized: "apRadar.signal.strength", comment: "Label above the signal strength meter"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.quaternary)
                    Capsule()
                        .fill(Color.accentColor.gradient)
                        .frame(width: max(6, geo.size.width * normalizedStrength(smoothed)))
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
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

    // MARK: - Signal lost

    private func signalLostContent(_ snapshot: APRadarLostSnapshot) -> some View {
        GeometryReader { geo in
            let fit: RadarFit = geo.size.height < 560 ? .compact : .regular
            ZStack {
                RadarBackdrop(size: geo.size, color: .orange)

                VStack(spacing: fit.spacing) {
                    targetCard(snapshot: snapshot)
                    Spacer(minLength: 8)
                    lostStatusCard(snapshot, fit: fit)
                    Spacer(minLength: 8)
                    HStack(spacing: 12) {
                        changeTargetButton
                        stopTrackingButton
                    }
                    .controlSize(.large)
                }
                .padding(Self.pagePadding)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }

    private func lostStatusCard(_ snapshot: APRadarLostSnapshot, fit: RadarFit) -> some View {
        VStack(spacing: fit.cardSpacing) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.12))
                    .frame(width: fit.statusIconContainer, height: fit.statusIconContainer)
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: fit.statusIconSize, weight: .medium))
                    .foregroundStyle(.orange)
            }
            .accessibilityHidden(true)
            .padding(.top, 6)

            VStack(spacing: 6) {
                Text(String(localized: "apRadar.signalLost.title", comment: "Signal lost title"))
                    .font(.title3.weight(.semibold))
                Text(String(localized: "apRadar.signalLost.description", comment: "Signal lost explanation"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 400)

            Text(String(
                format: String(localized: "apRadar.signalLost.lastSeen", comment: "Time the access point was last seen"),
                Self.lastSeenFormatter.string(from: snapshot.lastSeenAt)
            ))
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(String(localized: "apRadar.signalLost.rescanning", comment: "Status shown while waiting for the next scan"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .glassBackground(.regular, in: RoundedRectangle(cornerRadius: Self.cardRadius))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(signalLostAccessibilityLabel(snapshot))
    }

    private func targetCard(snapshot: APRadarLostSnapshot) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(snapshot.target.currentSSID ?? String(localized: "apRadar.target.hiddenNetwork", comment: "Label for an access point that hides its SSID"))
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Text(targetSubtitle(snapshot.target))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .glassBackground(.regular, in: RoundedRectangle(cornerRadius: Self.cardRadius))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(signalLostAccessibilityLabel(snapshot))
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

    /// Normalized 0...1 signal strength used only for visuals.
    private func normalizedStrength(_ smoothed: Double?) -> Double {
        guard let smoothed else { return 0 }
        return min(max((smoothed + 90) / 48, 0), 1)
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
            ForEach([0.30, 0.52, 0.74], id: \.self) { fraction in
                Circle()
                    .stroke(color.opacity(0.10), lineWidth: 1)
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
/// audio pulse spawns a soft green ripple that expands outward from the center
/// router icon, and the icon glows more brightly with the smoothed RSSI. The
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
    /// Hidden gesture callback: five quick taps on the center icon unlock the
    /// Geiger-counter preset.
    var onSecretTap: (() -> Void)? = nil
    /// Whether the app is backgrounded/asleep or Wi-Fi is off; mirrored into
    /// `suspended` @State so the long-lived visual loop sees updates.
    var isSuspended: Bool = false

    @State private var ripples: [Ripple] = []
    @State private var liveSmoothedRSSI: Double?
    @State private var visualLoop: Task<Void, Never>?
    /// Sound state mirrored into `@State` so the long-lived visual loop sees
    /// toggles instead of the initial value captured at task creation.
    @State private var soundOn = false
    /// Runtime mirror of `isSuspended` for the long-lived visual loop.
    @State private var suspended = false
    /// When the last pulse beat happened (audio beat or visual fallback).
    @State private var lastPulseAt = ContinuousClock.now
    /// Timestamps of recent secret taps used to detect a five-tap sequence.
    @State private var secretTapTimes: [Date] = []

    /// How long a ripple stays on screen: animation duration plus a small tail
    /// so removal never clips the last visible frame.
    private static let rippleLifetime: Duration = .milliseconds(950)

    private struct Ripple: Identifiable {
        let id = UUID()
    }

    /// Scales a design value defined at 220 pt to the current canvas size.
    private func s(_ value: CGFloat) -> CGFloat {
        value * size / 220
    }

    /// Router icon size, capped so a full-page canvas does not blow the icon
    /// up together with the ripple.
    private var iconSize: CGFloat {
        min(s(46), 64)
    }

    /// Bright green used for the router icon and ripples.
    private var rippleColor: Color { Color(red: 0.26, green: 0.83, blue: 0.47) }

    var body: some View {
        ZStack {
            // One expanding ripple per pulse beat.
            ForEach(ripples) { ripple in
                RippleRingView(
                    reduceMotion: reduceMotion,
                    size: size,
                    strength: normalizedStrength,
                    iconSize: iconSize
                )
                .id(ripple.id)
            }

            // Center router icon; no background circle. Uses the app accent
            // color so it reads as part of the main UI.
            Image(systemName: "wifi.router")
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .shadow(color: Color.accentColor.opacity(0.45), radius: min(s(6), 8))
                .scaleEffect(CGFloat(0.94 + 0.12 * normalizedStrength))
                .opacity(0.7 + 0.3 * normalizedStrength)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.5), value: normalizedStrength)
                .contentShape(Rectangle())
                .onTapGesture { handleSecretTap() }
                .accessibilityHidden(true)
        }
        .frame(width: size, height: size)
        .clipped()
        .onAppear {
            liveSmoothedRSSI = smoothedRSSI
            soundOn = soundEnabled
            lastPulseAt = .now
            // Animate immediately: the moment a target is chosen, one wave
            // bursts out instead of a static page while the first scan sample
            // (and with it the first audio pulse) is still pending.
            spawnRipple()
            startVisualLoop()
        }
        .onDisappear {
            visualLoop?.cancel()
            visualLoop = nil
            ripples.removeAll()
        }
        .onChange(of: pulseTick) { _, _ in
            // Audio pulse beat: sync a ripple to the sound.
            guard soundEnabled else { return }
            lastPulseAt = .now
            spawnRipple()
        }
        .onChange(of: isSuspended) { _, suspendedValue in
            suspended = suspendedValue
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
        let ripple = Ripple()
        ripples.append(ripple)
        Task {
            try? await Task.sleep(for: Self.rippleLifetime)
            ripples.removeAll { $0.id == ripple.id }
        }
    }

    /// Detects five quick taps (each within 1.5 s of the previous one) and
    /// fires the secret unlock callback once the sequence completes.
    private func handleSecretTap() {
        let now = Date()
        secretTapTimes.append(now)
        secretTapTimes = secretTapTimes.filter { now.timeIntervalSince($0) < 1.5 }
        if secretTapTimes.count >= 5 {
            secretTapTimes.removeAll()
            onSecretTap?()
        }
    }

    /// Visual cadence keeper. Runs for the whole lifetime of the tracking
    /// page, so the radar is never static:
    ///
    /// - Sound off: this loop drives the full visual cadence using the same
    ///   RSSI-to-interval mapping as the audio scheduler.
    /// - Sound on: the audio scheduler owns the cadence and fires `pulseTick`
    ///   beats; this loop only backfills when no audio beat has arrived for a
    ///   while (first sample pending, audio failure), then yields again once
    ///   audio beats resume.
    private func startVisualLoop() {
        guard visualLoop == nil else { return }
        visualLoop = Task {
            while !Task.isCancelled {
                // While the app is backgrounded or asleep the scheduler and
                // audio are suspended, so keep the loop alive but idle: wait
                // in one long chunk instead of stepping at full visual rate,
                // then pick the cadence back up as soon as resume clears the
                // flag. No ripples are spawned while suspended.
                if suspended {
                    try? await Task.sleep(for: .seconds(1))
                    continue
                }
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
/// peak, no side lobes or echo crests. The band starts just outside the icon,
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
    /// Capped router icon size; the wave starts just outside it.
    var iconSize: CGFloat

    @State private var progress: Double = 0

    private func s(_ value: CGFloat) -> CGFloat {
        value * size / 220
    }

    private var rippleColor: Color { Color(red: 0.26, green: 0.83, blue: 0.47) }

    /// Maximum band thickness: on a full-page canvas the wave stays slim and
    /// elegant instead of scaling into an over-thick stroke.
    private static let maxBandWidth: CGFloat = 72

    /// Total width of the ripple band (a single crest), thinning slightly as
    /// it expands and capped for large canvases.
    private var bandWidth: CGFloat {
        min(s(48) * (1 - 0.22 * CGFloat(progress)), Self.maxBandWidth)
    }

    /// Band width at progress 1 (after thinning). Used to size the travel so
    /// the ripple's outer edge lands exactly on the canvas edge.
    private var finalBandWidth: CGFloat {
        min(s(48) * (1 - 0.22), Self.maxBandWidth)
    }

    /// Leading radius of the ripple: from just outside the icon all the way to
    /// the canvas edge. The travel is fitted so the band's outer edge reaches
    /// the canvas boundary at progress 1, letting the wave sweep the whole
    /// canvas without ever being visibly clipped by the square bounds.
    private var leadingRadius: CGFloat {
        let start = iconSize * 0.5 + s(12)
        let travel = size * 0.5 - start - finalBandWidth * 0.5
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
                .blur(radius: s(5))
                .frame(width: radius * 2, height: radius * 2)
                .opacity(0.12 * opacity)

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
