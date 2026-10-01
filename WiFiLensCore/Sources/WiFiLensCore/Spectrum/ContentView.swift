import SwiftUI
import SplitView
#if os(macOS)
import AppKit
#endif

struct SpectrumDashboardLayout {
    static let minimumPanelFraction: CGFloat = 0.08

    let viewportHeight: CGFloat

    init(viewportHeight: CGFloat) {
        self.viewportHeight = viewportHeight
    }

    var primaryHeight: CGFloat { viewportHeight * Self.initialFraction(panelCount: 3) }
    var secondaryHeight: CGFloat { viewportHeight * Self.initialFraction(panelCount: 3) }
    var tertiaryHeight: CGFloat { viewportHeight * Self.initialFraction(panelCount: 3) }

    static func normalizedPanelCount(_ count: Int) -> Int {
        min(max(count, SpectrumDashboardState.minimumPanelCount), SpectrumDashboardState.maximumPanelCount)
    }

    static func initialFraction(panelCount: Int) -> CGFloat {
        1.0 / CGFloat(normalizedPanelCount(panelCount))
    }

    static func splitKey(topID: SpectrumPanelID, bottomID: SpectrumPanelID) -> String {
        SpectrumDashboardState.boundaryKey(topID: topID, bottomID: bottomID)
    }
}

public struct ContentView: View {
    @Bindable var viewModel: ScannerViewModel
    let isVendorColumnAvailable: Bool

    @State private var sortOrder: [NSSortDescriptor] = [NSSortDescriptor(key: "ssid", ascending: true)]
    @State private var dashboardState: SpectrumDashboardState
    @AppStorage("hiddenTableColumns") private var hiddenColumnsData: String = ""

    private var hiddenColumns: Binding<Set<String>> {
        Binding(
            get: { Set(hiddenColumnsData.split(separator: ",").map(String.init).filter { !$0.isEmpty }) },
            set: { hiddenColumnsData = $0.sorted().joined(separator: ",") }
        )
    }

    public init(
        viewModel: ScannerViewModel,
        isVendorColumnAvailable: Bool,
        dashboardState: SpectrumDashboardState? = nil
    ) {
        self.viewModel = viewModel
        self.isVendorColumnAvailable = isVendorColumnAvailable
        _dashboardState = State(initialValue: dashboardState ?? SpectrumDashboardState())
    }

    public init(
        viewModel: ScannerViewModel,
        macVendorDatabaseManager: MACVendorDatabaseManager,
        dashboardState: SpectrumDashboardState? = nil
    ) {
        self.init(
            viewModel: viewModel,
            isVendorColumnAvailable: macVendorDatabaseManager.availability.isVendorColumnAvailable,
            dashboardState: dashboardState
        )
    }

    public var body: some View {
        VStack(spacing: 0) {
            contentArea
        }
        // Same guardrail as Channels.ChannelQualityView: `minWidth: 700` forces the
        // whole dashboard to lay out 700pt wide — wider than the ~600pt detail column
        // at the minimum window size, clipping the right edge. Keep only the ideals as
        // page layout hints.
        .frame(idealWidth: 1000, idealHeight: 700)
        .coordinateSpace(name: "wifi-lens.spectrum")
        .onChange(of: viewModel.hiddenBands) { _, _ in viewModel.applyGlobalFilterToBands() }
        .onChange(of: viewModel.hideHiddenSSIDs) { _, _ in viewModel.applyGlobalFilterToBands() }
    }

    @ViewBuilder
    private var contentArea: some View {
        dashboardContent
    }

    private var dashboardContent: some View {
        VStack(spacing: 0) {
            dashboardToolbar

            GeometryReader { _ in
                if shouldShowEmptyState {
                    emptyState
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    SpectrumDashboardSplitLayout(
                        panelDescriptors: dashboardState.panels,
                        dashboardState: dashboardState,
                        viewModel: viewModel,
                        isVendorColumnAvailable: isVendorColumnAvailable,
                        selectedNetworkID: $viewModel.selectedNetworkID,
                        sortOrder: $sortOrder,
                        hiddenColumns: hiddenColumns,
                        onRemovePanel: removePanel
                    )
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("spectrum-dashboard")
    }

    private var dashboardToolbar: some View {
        HStack {
            Spacer()
            Button {
                addPanel()
            } label: {
                Label(
                    String(localized: "spectrum.dashboard.add_panel", comment: "Button to add a spectrum dashboard panel"),
                    systemImage: "plus"
                )
            }
            .buttonStyle(.borderless)
            .disabled(dashboardState.panels.count >= SpectrumDashboardState.maximumPanelCount)
            .accessibilityIdentifier("spectrum-dashboard-add-panel")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.bar)
    }

    private func addPanel() {
        let defaultBand = viewModel.supportedBands.min { $0.rawValue < $1.rawValue } ?? .band24GHz
        _ = dashboardState.addPanel(defaultBand: defaultBand)
    }

    private func removePanel(_ panelID: SpectrumPanelID) {
        guard dashboardState.removePanel(id: panelID) else { return }
        viewModel.releasePanelState(for: panelID)
    }

    private var shouldShowEmptyState: Bool {
        switch viewModel.accessState {
        case .waitingForAuthorization, .denied, .scanFailed: return true
        case .scanning, .grantedButSSIDUnavailable: return false
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView().scaleEffect(1.5)
            switch viewModel.accessState {
            case .waitingForAuthorization:
                Text(String(localized: "permission.location.waiting", comment: "Status while waiting for Location Services authorization")).foregroundColor(.orange)
                Button(String(localized: "common.action.open_system_settings", comment: "Button to open macOS System Settings")) { viewModel.locationManager.openLocationPreferences() }
            case .denied:
                Text(String(localized: "permission.location.required_short", comment: "Short label: Location Services required")).foregroundColor(.secondary)
                Button(String(localized: "common.action.open_location_preferences", comment: "Button to open Location Services preferences")) { viewModel.locationManager.openLocationPreferences() }
            case .scanFailed(let msg):
                Text(String(localized: "common.error.scan_failed", comment: "Generic scan failure message")).foregroundColor(.secondary)
                Text(msg).font(.caption).foregroundColor(.secondary)
            default:
                EmptyView()
            }
            Spacer()
        }
    }
}

private struct SpectrumDashboardSplitLayout: View {
    let panelDescriptors: [SpectrumPanelDescriptor]
    let dashboardState: SpectrumDashboardState
    @Bindable var viewModel: ScannerViewModel
    let isVendorColumnAvailable: Bool
    @Binding var selectedNetworkID: String?
    @Binding var sortOrder: [NSSortDescriptor]
    @Binding var hiddenColumns: Set<String>
    let onRemovePanel: (SpectrumPanelID) -> Void

    var body: some View {
        splitNode(panelDescriptors[...])
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func splitNode(_ descriptors: ArraySlice<SpectrumPanelDescriptor>) -> AnyView {
        guard let first = descriptors.first else { return AnyView(EmptyView()) }
        guard descriptors.count > 1, let next = descriptors.dropFirst().first else {
            return AnyView(panelView(for: first))
        }

        let split = VSplit(
            top: { panelView(for: first) },
            bottom: { splitNode(descriptors.dropFirst()) }
        )
        .splitter {
            SpectrumSplitter()
        }
        .fraction(
            dashboardState.fractionHolder(
                topID: first.id,
                bottomID: next.id,
                defaultFraction: SpectrumDashboardLayout.initialFraction(panelCount: descriptors.count)
            )
        )
        .constraints(
            minPFraction: SpectrumDashboardLayout.minimumPanelFraction,
            minSFraction: SpectrumDashboardLayout.minimumPanelFraction
        )

        return AnyView(split)
    }

    private func panelView(for descriptor: SpectrumPanelDescriptor) -> some View {
        SpectrumPanelContainer(
            viewModel: viewModel,
            descriptor: descriptorBinding(for: descriptor.id),
            isVendorColumnAvailable: isVendorColumnAvailable,
            canRemove: panelDescriptors.count > SpectrumDashboardState.minimumPanelCount,
            selectedNetworkID: $selectedNetworkID,
            sortOrder: $sortOrder,
            hiddenColumns: $hiddenColumns,
            onRemove: { onRemovePanel(descriptor.id) }
        )
        .id(descriptor.id)
    }

    private func descriptorBinding(for id: SpectrumPanelID) -> Binding<SpectrumPanelDescriptor> {
        Binding(
            get: {
                dashboardState.panels.first(where: { $0.id == id })
                    ?? SpectrumPanelDescriptor(id: id, viewType: .table, band: .band24GHz)
            },
            set: { dashboardState.updatePanel($0) }
        )
    }
}

@MainActor
private struct SpectrumSplitter: SplitDivider {
    @ObservedObject var styling: SplitStyling
    @State private var isHovering = false

    init() {
        styling = SplitStyling(
            color: .secondary.opacity(0.24),
            inset: 0,
            visibleThickness: 1,
            invisibleThickness: 36
        )
    }

    var body: some View {
        ZStack {
            Color.clear
            Rectangle()
                .fill(isHovering ? Color.accentColor.opacity(0.72) : styling.color)
                .frame(maxWidth: .infinity)
                .frame(height: styling.visibleThickness)
        }
        .frame(maxWidth: .infinity)
        .frame(height: styling.invisibleThickness)
        .contentShape(Rectangle())
        .onHover { hovering in
            guard hovering != isHovering else { return }
            isHovering = hovering
            updateCursor(isHovering: hovering)
        }
        .onDisappear {
            isHovering = false
            updateCursor(isHovering: false)
        }
    }

    private func updateCursor(isHovering: Bool) {
        #if os(macOS)
        if isHovering {
            NSCursor.resizeUpDown.set()
        } else {
            NSCursor.arrow.set()
        }
        #endif
    }
}
