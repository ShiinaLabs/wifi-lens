import SwiftUI
import ChartLens
import WiFiLensCore

#if DEBUG

enum DebugChartMode: String {
    case singleAP
    case multiAP
}

private struct DebugOscillator {
    var phase: Double = 0

    mutating func advance(speed: Double) {
        phase += 0.025 * speed
    }

    func rssi(center: Int, amplitude: Int) -> Int {
        center + Int(Double(amplitude) * sin(phase))
    }
}

enum DebugChartSeriesAdapter {
    static func seriesData(from scenario: DebugScenario, band: ChannelBand) -> [ChartSeriesData] {
        DebugScenarioBuilder.seriesSources(from: scenario, band: band).map { source in
            let ap = source.ap
            let render = ChartSeriesRenderState(
                displayRSSI: Double(ap.rssi),
                color: Color(hex: ap.colorHex),
                isFilteredOut: ap.filtered,
                isVisible: ap.visible,
                trendArrow: ap.trend.arrow,
                trendDelta: ap.trendDelta
            )
            return ChartSeriesData(domain: source.domain, render: render)
        }
    }
}

struct DebugChartView: View {
    let mode: DebugChartMode

    @State private var bandVM = BandChartViewModel(band: .band5GHz)
    @State private var selectedNetworkID: String?
    @State private var timer: Timer?

    @State private var oscillator = DebugOscillator()
    @State private var centerRSSI: Double = -50
    @State private var amplitude: Double = 30
    @State private var speed: Double = 1.0
    @State private var channel: Int = 52
    @State private var channelWidthMHz: Int = 20
    @State private var selectedBand: ChannelBand = .band5GHz
    @State private var isRunning: Bool = true

    @State private var scenarioStore = DebugScenarioStore()
    @State private var multiScenario = DebugScenarioBuilder.scenario(for: .labelCollision)
    @State private var selectedPreset: DebugScenarioPreset = .labelCollision
    @State private var didLoadMultiScenario = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let debugPalette = [
        "#3B82F6", "#10B981", "#F59E0B", "#EF4444",
        "#8B5CF6", "#0EA5E9", "#22C55E", "#F97316",
        "#2563EB", "#16A34A", "#EA580C", "#7C3AED",
    ]

    init(mode: DebugChartMode = .singleAP) {
        self.mode = mode
    }

    var body: some View {
        VStack(spacing: 0) {
            switch mode {
            case .singleAP:
                singleAPWorkbench
            case .multiAP:
                multiAPWorkbench
            }
        }
        .onAppear {
            if mode == .singleAP {
                startTimer()
                tick()
            } else {
                enterMultiAPMode()
            }
        }
        .onDisappear { stopTimer() }
        .onChange(of: isRunning) { _, running in
            guard mode == .singleAP else { return }
            if running { startTimer() } else { stopTimer() }
        }
        .onChange(of: centerRSSI) { _, _ in tickIfSingleAP() }
        .onChange(of: amplitude) { _, _ in tickIfSingleAP() }
        .onChange(of: channel) { _, _ in tickIfSingleAP() }
        .onChange(of: channelWidthMHz) { _, _ in tickIfSingleAP() }
    }

    // MARK: - Workbenches

    private var singleAPWorkbench: some View {
        VStack(spacing: 0) {
            singleAPControls
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

            Divider()

            chartView
                .padding(.horizontal, 8)
        }
    }

    private var multiAPWorkbench: some View {
        VStack(spacing: 0) {
            multiAPControls
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

            Divider()

            chartView
                .frame(minHeight: 280)
                .padding(.horizontal, 8)
                .accessibilityIdentifier("debug-multi-ap-chart")

            Divider()

            multiAPTable
                .frame(minHeight: 190)
                .accessibilityIdentifier("debug-multi-ap-table")
        }
    }

    private var chartView: some View {
        WiFiBandChart(
            model: bandVM.renderModel,
            selectedNetworkID: $selectedNetworkID,
            onResetZoom: { bandVM.resetZoom() },
            onToggleExpand: { bandVM.toggleExpand() },
            onApplyZoom: { lo, hi in bandVM.applyZoom(lo: lo, hi: hi) }
        )
    }

    // MARK: - Single AP Controls

    private var singleAPControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 16) {
                Button {
                    isRunning.toggle()
                } label: {
                    Image(systemName: isRunning ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.plain)
                .help(isRunning ? "Pause" : "Resume")

                bandPicker
            }

            HStack(spacing: 12) {
                paramSlider(label: "Center", value: $centerRSSI, range: -90...(-20), format: "%.0f dBm")
                paramSlider(label: "Amplitude", value: $amplitude, range: 0...45, format: "%.0f dB")
                paramSlider(label: "Speed", value: $speed, range: 0.1...5.0, format: "%.1fx")
                singleAPChannelControls
            }
        }
        .font(.system(size: 10))
    }

    private func paramSlider(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        format: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(label): \(String(format: format, value.wrappedValue))")
                .foregroundColor(.secondary)
            Slider(value: value, in: range) {
                Text(label)
            }
            .controlSize(.mini)
            .frame(width: 120)
        }
    }

    private var singleAPChannelControls: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Channel: \(channel)")
                    .foregroundColor(.secondary)
                Stepper("", value: $channel, in: 1...selectedBand.maxChannel)
                    .controlSize(.mini)
            }
            widthPicker(selection: $channelWidthMHz)
        }
    }

    // MARK: - Multi AP Controls

    private var multiAPControls: some View {
        HStack(spacing: 10) {
            bandPicker

            Picker("Preset", selection: $selectedPreset.animation(reduceMotion ? nil : .bouncy)) {
                ForEach(DebugScenarioPreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            .pickerStyle(.menu)
            .controlSize(.small)
            .frame(width: 170)
            .onChange(of: selectedPreset) { _, preset in
                loadPreset(preset)
            }

            Button {
                addAP()
            } label: {
                Label("Add AP", systemImage: "plus")
            }
            .controlSize(.small)

            Button {
                loadPreset(selectedPreset)
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
            }
            .controlSize(.small)

            Spacer()

            Text("\(activeAPCount) active / \(multiScenario.aps.count) rows")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .font(.system(size: 11))
    }

    private var bandPicker: some View {
        Picker("Band", selection: bandSelection.animation(reduceMotion ? nil : .bouncy)) {
            Text("2.4 GHz").tag(ChannelBand.band24GHz)
            Text("5 GHz").tag(ChannelBand.band5GHz)
            Text("6 GHz").tag(ChannelBand.band6GHz)
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .frame(width: 240)
    }

    private func widthPicker(selection: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Width: \(selection.wrappedValue) MHz")
                .foregroundColor(.secondary)
            Picker("", selection: selection.animation(reduceMotion ? nil : .bouncy)) {
                ForEach(DebugScenarioBuilder.allowedWidths(for: selectedBand), id: \.self) { width in
                    Text("\(width)").tag(width)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.mini)
            .frame(width: selectedBand == .band24GHz ? 74 : 140)
        }
    }

    // MARK: - Multi AP Table

    private var multiAPTable: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                multiAPTableHeader
                    .padding(.bottom, 4)

                ForEach(multiScenario.aps) { ap in
                    multiAPRow(ap)
                        .accessibilityIdentifier("debug-multi-ap-row-\(ap.id.uuidString)")
                }
            }
            .padding(8)
        }
    }

    private var multiAPTableHeader: some View {
        HStack(spacing: 8) {
            headerCell("On", width: 34, alignment: .center)
            headerCell("SSID", width: 130)
            headerCell("Ch", width: 80, alignment: .center)
            headerCell("Width", width: 82, alignment: .center)
            headerCell("RSSI", width: 92, alignment: .center)
            headerCell("Color", width: 70, alignment: .center)
            headerCell("Hidden", width: 54, alignment: .center)
            headerCell("Visible", width: 54, alignment: .center)
            headerCell("Filtered", width: 58, alignment: .center)
            headerCell("k", width: 34, alignment: .center)
            headerCell("r", width: 34, alignment: .center)
            headerCell("v", width: 34, alignment: .center)
            headerCell("WPA3", width: 48, alignment: .center)
            headerCell("CC", width: 44, alignment: .center)
            headerCell("Trend", width: 86, alignment: .center)
            headerCell("Delta", width: 78, alignment: .center)
            headerCell("", width: 62, alignment: .center)
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundColor(.secondary)
    }

    private func multiAPRow(_ ap: DebugAPConfig) -> some View {
        HStack(spacing: 8) {
            rowCell(width: 34, alignment: .center) {
                Toggle("", isOn: apBinding(ap.id, \.enabled, default: true))
                    .labelsHidden()
            }
            rowCell(width: 130) {
                TextField("SSID", text: apBinding(ap.id, \.ssid, default: ""))
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
            }
            rowCell(width: 80, alignment: .center) {
                Stepper(value: apBinding(ap.id, \.channel, default: 1), in: 1...selectedBand.maxChannel) {
                    Text("\(ap.channel)")
                        .monospacedDigit()
                        .frame(width: 28, alignment: .trailing)
                }
                .controlSize(.mini)
            }
            rowCell(width: 82, alignment: .center) {
                Picker("", selection: apBinding(ap.id, \.widthMHz, default: 20)) {
                    ForEach(DebugScenarioBuilder.allowedWidths(for: selectedBand), id: \.self) { width in
                        Text("\(width)").tag(width)
                    }
                }
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(width: 78)
            }
            rowCell(width: 92, alignment: .center) {
                Stepper(value: apBinding(ap.id, \.rssi, default: -55), in: Constants.rssiNoiseFloor...(-1)) {
                    Text("\(ap.rssi)")
                        .monospacedDigit()
                        .frame(width: 34, alignment: .trailing)
                }
                .controlSize(.mini)
            }
            rowCell(width: 70, alignment: .center) {
                colorMenu(for: ap)
            }
            checkboxCell(width: 54, binding: apBinding(ap.id, \.hiddenSSID, default: false))
            checkboxCell(width: 54, binding: apBinding(ap.id, \.visible, default: true))
            checkboxCell(width: 58, binding: apBinding(ap.id, \.filtered, default: false))
            checkboxCell(width: 34, binding: apBinding(ap.id, \.supportsK, default: false))
            checkboxCell(width: 34, binding: apBinding(ap.id, \.supportsR, default: false))
            checkboxCell(width: 34, binding: apBinding(ap.id, \.supportsV, default: false))
            checkboxCell(width: 48, binding: apBinding(ap.id, \.supportsWPA3, default: false))
            rowCell(width: 44, alignment: .center) {
                TextField("CC", text: apBinding(ap.id, \.country, default: ""))
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .frame(width: 42)
            }
            rowCell(width: 86, alignment: .center) {
                Picker("", selection: apBinding(ap.id, \.trend, default: .none)) {
                    ForEach(DebugTrend.allCases, id: \.self) { trend in
                        Text(trend.title).tag(trend)
                    }
                }
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(width: 82)
            }
            rowCell(width: 78, alignment: .center) {
                Stepper(value: apBinding(ap.id, \.trendDelta, default: 0), in: -30...30) {
                    Text("\(ap.trendDelta)")
                        .monospacedDigit()
                        .frame(width: 28, alignment: .trailing)
                }
                .controlSize(.mini)
            }
            rowCell(width: 62, alignment: .center) {
                HStack(spacing: 6) {
                    Button {
                        duplicateAP(ap)
                    } label: {
                        Image(systemName: "plus.square.on.square")
                    }
                    .buttonStyle(.plain)
                    .help("Duplicate")

                    Button {
                        deleteAP(ap.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .help("Delete")
                }
            }
        }
        .frame(height: 34)
        .font(.system(size: 11))
    }

    private func headerCell(_ title: String, width: CGFloat, alignment: Alignment = .leading) -> some View {
        Text(title)
            .frame(width: width, alignment: alignment)
    }

    private func rowCell<Content: View>(
        width: CGFloat,
        alignment: Alignment = .leading,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(width: width, alignment: alignment)
    }

    private func checkboxCell(width: CGFloat, binding: Binding<Bool>) -> some View {
        rowCell(width: width, alignment: .center) {
            Toggle("", isOn: binding)
                .labelsHidden()
        }
    }

    private func colorMenu(for ap: DebugAPConfig) -> some View {
        Menu {
            ForEach(debugPalette, id: \.self) { colorHex in
                Button {
                    updateAP(ap.id) { $0.colorHex = colorHex }
                } label: {
                    Text(colorHex)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(Color(hex: ap.colorHex))
                    .frame(width: 12, height: 12)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8))
            }
            .frame(width: 48)
        }
        .menuStyle(.borderlessButton)
        .controlSize(.small)
        .help(ap.colorHex)
    }

    // MARK: - State Updates

    private var activeAPCount: Int {
        multiScenario.aps.filter(\.enabled).count
    }

    private var bandSelection: Binding<ChannelBand> {
        Binding(
            get: { selectedBand },
            set: { changeBand($0) }
        )
    }

    private func apBinding<Value>(
        _ id: DebugAPConfig.ID,
        _ keyPath: WritableKeyPath<DebugAPConfig, Value>,
        default defaultValue: Value
    ) -> Binding<Value> {
        Binding(
            get: {
                multiScenario.aps.first(where: { $0.id == id })?[keyPath: keyPath] ?? defaultValue
            },
            set: { newValue in
                updateAP(id) { $0[keyPath: keyPath] = newValue }
            }
        )
    }

    private func updateAP(_ id: DebugAPConfig.ID, edit: (inout DebugAPConfig) -> Void) {
        guard let index = multiScenario.aps.firstIndex(where: { $0.id == id }) else { return }
        edit(&multiScenario.aps[index])
        multiScenario.presetID = nil
        applyMultiScenario(save: true)
    }

    private func addAP() {
        ensureMultiScenarioLoaded()
        multiScenario.aps.append(DebugScenarioBuilder.defaultAP(for: selectedBand, index: multiScenario.aps.count + 1))
        multiScenario.presetID = nil
        applyMultiScenario(save: true)
    }

    private func duplicateAP(_ ap: DebugAPConfig) {
        guard let index = multiScenario.aps.firstIndex(where: { $0.id == ap.id }) else { return }
        var copy = ap
        copy.id = UUID()
        copy.ssid = ap.ssid.isEmpty ? "Copy" : "\(ap.ssid) Copy"
        multiScenario.aps.insert(copy, at: index + 1)
        multiScenario.presetID = nil
        applyMultiScenario(save: true)
    }

    private func deleteAP(_ id: DebugAPConfig.ID) {
        multiScenario.aps.removeAll { $0.id == id }
        multiScenario.presetID = nil
        applyMultiScenario(save: true)
    }

    private func loadPreset(_ preset: DebugScenarioPreset) {
        multiScenario = DebugScenarioBuilder.scenario(for: preset)
        selectedBand = DebugScenarioBuilder.band(for: multiScenario)
        bandVM = BandChartViewModel(band: selectedBand)
        selectedNetworkID = nil
        didLoadMultiScenario = true
        applyMultiScenario(save: true)
    }

    private func ensureMultiScenarioLoaded() {
        guard !didLoadMultiScenario else { return }
        multiScenario = scenarioStore.load()
        selectedPreset = DebugScenarioPreset(rawValue: multiScenario.presetID ?? "") ?? .labelCollision
        didLoadMultiScenario = true
    }

    private func enterSingleAPMode() {
        stopTimer()
        bandVM = BandChartViewModel(band: selectedBand)
        selectedNetworkID = nil
        oscillator = DebugOscillator()
        tick()
        if isRunning { startTimer() }
    }

    private func enterMultiAPMode() {
        stopTimer()
        ensureMultiScenarioLoaded()
        selectedBand = DebugScenarioBuilder.band(for: multiScenario)
        bandVM = BandChartViewModel(band: selectedBand)
        selectedNetworkID = nil
        applyMultiScenario(save: false)
    }

    private func changeBand(_ band: ChannelBand) {
        guard selectedBand != band || bandVM.band != band else { return }
        selectedBand = band
        bandVM = BandChartViewModel(band: band)
        selectedNetworkID = nil
        switch mode {
        case .singleAP:
            channel = min(channel, band.maxChannel)
            if !DebugScenarioBuilder.allowedWidths(for: band).contains(channelWidthMHz) {
                channelWidthMHz = 20
            }
            oscillator = DebugOscillator()
            tick()
        case .multiAP:
            ensureMultiScenarioLoaded()
            multiScenario.bandID = band.id
            multiScenario.presetID = nil
            applyMultiScenario(save: true)
        }
    }

    private func applyMultiScenario(save: Bool) {
        multiScenario.bandID = selectedBand.id
        multiScenario = DebugScenarioBuilder.normalized(multiScenario)
        if bandVM.band != selectedBand {
            bandVM = BandChartViewModel(band: selectedBand)
        }
        let series = DebugChartSeriesAdapter.seriesData(from: multiScenario, band: selectedBand)
        bandVM.debugInject(series: series)
        if !bandVM.validateSelection(selectedNetworkID) {
            selectedNetworkID = nil
        }
        if save {
            scenarioStore.save(multiScenario)
        }
    }

    // MARK: - Timer

    private func startTimer() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in tick() }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tickIfSingleAP() {
        guard mode == .singleAP else { return }
        tick()
    }

    private func tick() {
        guard mode == .singleAP else { return }
        oscillator.advance(speed: speed)
        let rssi = oscillator.rssi(center: Int(centerRSSI), amplitude: Int(amplitude))
        let block = ChannelSpanCalculator.channelBlock(
            primaryChannel: channel,
            widthMHz: channelWidthMHz,
            band: selectedBand
        )
        let domain = ChartSeriesDomainData(
            id: "debug-signal",
            ssid: "TestSignal",
            bssid: "aa:bb:cc:dd:ee:ff",
            channel: channel,
            left: block.left,
            apex: Double(block.left + block.right) / 2.0,
            right: block.right,
            rssi: rssi,
            phyMode: "",
            channelWidth: "",
            supportsK: false,
            supportsR: false,
            supportsV: false,
            supportsWPA3: false,
            isHiddenSSID: false,
            security: "",
            mcs: "",
            nss: "",
            country: ""
        )
        let render = ChartSeriesRenderState(displayRSSI: Double(rssi), color: .blue, isVisible: true)
        let series = ChartSeriesData(domain: domain, render: render)
        bandVM.debugInject(series: [series])
    }
}

#endif
