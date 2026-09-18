import SwiftUI

struct NetworkDiagnosticsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var viewModel: NetworkDiagnosticsViewModel
    let guidance: GuidanceCoordinator = .shared
    @State private var expandedGroupOverride: [String: Bool] = [:]
    @State private var renderedInvitationID: UUID?
    @State private var consolePanelController = ConsolePanelController(
        statusBarHeight: 30,
        topMinimum: 240,
        expandedBottom: 300
    )
    @State private var logExpanded = false

    var body: some View {
        GeometryReader { geometry in
            let layoutMode = NetworkDiagnosticsWorkbenchLayout.mode(for: geometry.size.width)

            ConsoleSplitView(
                content: diagnosticsContent(layoutMode),
                bottom: diagnosticsConsole,
                controller: consolePanelController
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.24), value: viewModel.phase)
#if DEBUG
        // Debug-only: the current, real host consumes the one-shot staging
        // request set by the Debug menu, so a closed old window can never
        // stage into a stale view model.
        .onAppear {
            if GuidanceDebugOverrides.consumeDiagnosticsStaging() {
                viewModel.debugStageCompletedResult()
            }
        }
#endif
        .onDisappear {
            viewModel.cancel()
            if let id = renderedInvitationID {
                guidance.endInvitationPresentation(id: id)
                renderedInvitationID = nil
            }
        }
    }

    @ViewBuilder
    private func diagnosticsContent(_ layoutMode: NetworkDiagnosticsWorkbenchLayoutMode) -> some View {
        VStack(spacing: 0) {
            commandBar
            Divider()

            if viewModel.phase == .running {
                progressStrip
                Divider()
            } else if let conclusion = viewModel.conclusion {
                conclusionStrip(conclusion)
                Divider()
                if let invitation = guidance.pendingInvitation,
                   invitation.moment == .diagnosticsCompleted {
                    ProInvitationCard(invitation: invitation, guidance: guidance)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .onAppear { renderedInvitationID = invitation.id }
                }
            } else if viewModel.phase == .completed {
                sessionOutcomeStrip
                Divider()
            }

            workspace(layoutMode)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var diagnosticsConsole: some View {
        VStack(spacing: 0) {
            diagnosticsLogStatusBar
            LogTextView(text: viewModel.logText)
                .background(Color.black.opacity(0.06))
        }
    }

    private var diagnosticsLogStatusBar: some View {
        HStack(spacing: 10) {
            diagnosticsStatusLeading
            Spacer(minLength: 8)
            if !viewModel.logText.isEmpty {
                Text("\(viewModel.logStore.lines.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .background(Capsule().fill(.quaternary.opacity(0.4)))
            }
            if !viewModel.logText.isEmpty {
                Button {
                    viewModel.clearLogs()
                } label: {
                    Image(systemName: "trash").font(.caption)
                }
                .buttonStyle(.borderless)
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
                .help(String(localized: "network_diagnostics.log.clear", comment: "Clear network self-check logs action"))
                .accessibilityLabel(String(localized: "network_diagnostics.log.clear", comment: "Clear network self-check logs action"))
                .accessibilityIdentifier("network-diagnostics-log-clear")
            }
            Button {
                toggleLogPanel()
            } label: {
                Image(systemName: logExpanded ? "chevron.down" : "chevron.up")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.borderless)
            .frame(width: 30, height: 22)
            .contentShape(Rectangle())
            .help(
                String(
                    localized: logExpanded
                        ? "network_diagnostics.log.collapse"
                        : "network_diagnostics.log.expand",
                    comment: "Network self-check log panel expand or collapse action"
                )
            )
            .accessibilityLabel(
                String(
                    localized: logExpanded
                        ? "network_diagnostics.log.collapse"
                        : "network_diagnostics.log.expand",
                    comment: "Network self-check log panel expand or collapse action"
                )
            )
            .accessibilityIdentifier("network-diagnostics-log-toggle")
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 30)
    }

    @ViewBuilder
    private var diagnosticsStatusLeading: some View {
        switch viewModel.phase {
        case .idle:
            Label(
                String(localized: "network_diagnostics.state.waiting", comment: "Network self-check waiting state"),
                systemImage: "circle.dotted"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        case .running:
            HStack(spacing: 7) {
                ProgressView().controlSize(.mini)
                Text(viewModel.logStore.events.last?.message ?? String(localized: "network_diagnostics.state.checking", comment: "Network self-check running state"))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        case .completed:
            if let conclusion = viewModel.conclusion {
                Label(conclusionTitle(conclusion), systemImage: conclusionIcon(conclusion))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(conclusionColor(conclusion))
                    .lineLimit(1)
            } else {
                Label(
                    String(localized: "network_diagnostics.state.waiting", comment: "Network self-check waiting state"),
                    systemImage: "circle.dotted"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
    }

    private func toggleLogPanel() {
        let shouldExpand = !logExpanded
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
            logExpanded = shouldExpand
        }
        if shouldExpand {
            consolePanelController.expandLog(animate: !reduceMotion)
        } else {
            consolePanelController.collapseLog(animate: !reduceMotion)
        }
    }

    private var commandBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 20) {
                commandIdentity
                Spacer(minLength: 20)
                stateIndicator
                actionButton
            }

            VStack(alignment: .leading, spacing: 12) {
                commandIdentity
                HStack(spacing: 12) {
                    stateIndicator
                    Spacer(minLength: 12)
                    actionButton
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var commandIdentity: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label {
                Text(String(localized: "nav.network_diagnostics", comment: "Network Self-Check page title"))
                    .font(.headline)
            } icon: {
                Image(systemName: "stethoscope")
                    .foregroundStyle(Color.accentColor)
            }

            Text(String(localized: "network_diagnostics.description", comment: "Network self-check page description"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private var stateIndicator: some View {
        switch viewModel.phase {
        case .idle:
            Label(
                String(localized: "network_diagnostics.state.waiting", comment: "Network self-check waiting state"),
                systemImage: "circle.dotted"
            )
            .foregroundStyle(.secondary)
        case .running:
            HStack(spacing: 7) {
                ProgressView().controlSize(.small)
                Text(
                    viewModel.automaticRestartCount > 0
                        ? String(localized: "network_diagnostics.session.restarting", comment: "Network self-check automatic restart state")
                        : String(localized: "network_diagnostics.state.checking", comment: "Network self-check running state")
                )
            }
        case .completed:
            if let conclusion = viewModel.conclusion {
                Label(conclusionTitle(conclusion), systemImage: conclusionIcon(conclusion))
                    .foregroundStyle(conclusionColor(conclusion))
            }
        }
    }

    private var actionButton: some View {
        Button {
            viewModel.start()
        } label: {
            Label(actionTitle, systemImage: actionIcon)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .disabled(viewModel.phase == .running)
        .fixedSize()
        .accessibilityIdentifier("network-diagnostics-run")
    }

    private var progressStrip: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Image(systemName: activeCheckID.map(checkIcon) ?? "stethoscope")
                    .foregroundStyle(Color.accentColor)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)

                if let activeCheckID {
                    Text(checkTitle(activeCheckID))
                        .font(.callout.weight(.semibold))
                        .contentTransition(.opacity)
                }

                Spacer(minLength: 16)

                Text("\(viewModel.results.count)/\(viewModel.checkIDs.count)")
                    .font(.callout.monospacedDigit().weight(.medium))
                    .foregroundStyle(.secondary)
            }

            ProgressView(
                value: Double(viewModel.results.count),
                total: Double(viewModel.checkIDs.count)
            )
            .progressViewStyle(.linear)
            .accessibilityLabel(String(localized: "network_diagnostics.state.checking", comment: "Network self-check running state"))

            if !viewModel.fingerprintMonitoringAvailable {
                Label(
                    String(localized: "network_diagnostics.session.monitor_unavailable", comment: "Network self-check network change monitoring unavailable state"),
                    systemImage: "eye.slash"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.accentColor.opacity(0.06))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("network-diagnostics-progress")
    }

    private func conclusionStrip(_ conclusion: NetworkDiagnosticConclusion) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: conclusionIcon(conclusion))
                .font(.title3.weight(.semibold))
                .foregroundStyle(conclusionColor(conclusion))
                .frame(width: 26)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(conclusionTitle(conclusion))
                    .font(.callout.weight(.semibold))
                Text(conclusionMessage(conclusion))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if conclusion == .needsAttention,
                   let issue = viewModel.assessment?.primaryIssue {
                    let remediation = NetworkDiagnosticRemediation.forResult(issue)
                    Text(String(localized: .init(stringLiteral: remediation.actionKey), comment: "Network self-check primary remediation action"))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(conclusionColor(conclusion).opacity(0.06))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("network-diagnostics-conclusion")
    }

    private var sessionOutcomeStrip: some View {
        let message = sessionOutcomeMessage
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: sessionOutcomeIcon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.orange)
                .frame(width: 26)
                .accessibilityHidden(true)
            Text(message)
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.orange.opacity(0.06))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("network-diagnostics-session-outcome")
    }

    private var sessionOutcomeMessage: String {
        switch viewModel.endReason {
        case .timedOut:
            String(
                format: String(
                    localized: "network_diagnostics.session.timed_out",
                    comment: "Network self-check timeout summary"
                ),
                Int64(viewModel.results.count),
                Int64(viewModel.checkIDs.count)
            )
        case .cancelled:
            String(localized: "network_diagnostics.session.cancelled", comment: "Network self-check cancellation summary")
        case .superseded:
            String(localized: "network_diagnostics.session.network_changed", comment: "Network self-check unstable network summary")
        case .completed, .none:
            String(localized: "network_diagnostics.state.waiting", comment: "Network self-check waiting state")
        }
    }

    private var sessionOutcomeIcon: String {
        switch viewModel.endReason {
        case .cancelled: "xmark.circle"
        case .superseded: "arrow.triangle.2.circlepath"
        case .timedOut, .completed, .none: "clock.badge.exclamationmark"
        }
    }

    @ViewBuilder
    private func workspace(_ mode: NetworkDiagnosticsWorkbenchLayoutMode) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            pipelineView
            if viewModel.phase == .idle {
                readyWorkspace
            } else {
                resultTable(mode)
            }
        }
    }

    private var pipelineView: some View {
        NetworkDiagnosticsPipelineView(
            presentation: NetworkDiagnosticsPipelinePresentation.from(
                results: viewModel.results,
                executionPhases: viewModel.executionPhases,
                assessment: viewModel.assessment
            )
        )
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }

    private var readyWorkspace: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "network")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "network_diagnostics.state.waiting", comment: "Network self-check ready state"))
                    .font(.callout.weight(.semibold))
                Text(String(localized: "network_diagnostics.ready.message", comment: "Instructions shown before running network diagnostics"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func resultTable(_ mode: NetworkDiagnosticsWorkbenchLayoutMode) -> some View {
        Group {
            switch mode {
            case .regular:
                Table(workbenchItems) {
                    TableColumn(columnCheckTitle) { item in
                        checkCell(item)
                            .padding(.vertical, 7)
                    }
                    .width(min: 150, ideal: 190)

                    TableColumn(columnStatusTitle) { item in
                        statusCell(item)
                            .padding(.vertical, 7)
                    }
                    .width(min: 112, ideal: 132)

                    TableColumn(columnResultTitle) { item in
                        resultCell(item)
                            .padding(.vertical, 7)
                    }
                }
            case .condensed:
                Table(workbenchItems) {
                    TableColumn(columnCheckTitle) { item in
                        VStack(alignment: .leading, spacing: 5) {
                            checkCell(item)
                            statusCell(item)
                        }
                        .padding(.vertical, 7)
                    }
                    .width(min: 178, ideal: 220)

                    TableColumn(columnResultTitle) { item in
                        resultCell(item)
                            .padding(.vertical, 7)
                    }
                }
            case .compact:
                Table(workbenchItems) {
                    TableColumn(columnResultTitle) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .center, spacing: 12) {
                                checkCell(item)
                                Spacer(minLength: 8)
                                statusCell(item)
                            }
                            resultCell(item)
                        }
                        .padding(.vertical, 7)
                    }
                }
            }
        }
        .environment(\.defaultMinListRowHeight, NetworkDiagnosticsTablePresentation.minimumRowHeight)
        .alternatingRowBackgrounds(
            NetworkDiagnosticsTablePresentation.usesAlternatingRowBackgrounds ? .enabled : .disabled
        )
    }

    private func checkCell(_ row: NetworkDiagnosticsWorkbenchRow) -> some View {
        Label {
            Text(checkTitle(row.id))
                .font(.callout.weight(.semibold))
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: checkIcon(row.id))
                .foregroundStyle(.secondary)
                .frame(width: 18)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func checkCell(_ item: NetworkDiagnosticsWorkbenchItem) -> some View {
        switch item {
        case .stageHeader(let stage): stageHeaderCell(stage)
        case .additionalHeader: additionalHeaderCell
        case .check(let row): checkCell(row)
        }
    }

    @ViewBuilder
    private func statusCell(_ row: NetworkDiagnosticsWorkbenchRow) -> some View {
        if let result = row.result {
            Label(statusTitle(result.status), systemImage: statusIcon(result.status))
                .font(.caption.weight(.medium))
                .foregroundStyle(statusColor(result.status))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(statusColor(result.status).opacity(0.10), in: Capsule())
                .accessibilityLabel(statusAccessibilityLabel(for: result))
        } else if let pendingReason = row.pendingReason {
            Label(pendingTitle(for: pendingReason), systemImage: "clock.badge.exclamationmark")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.10), in: Capsule())
        } else {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text(String(localized: "network_diagnostics.state.checking", comment: "Network self-check item running state"))
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.accentColor.opacity(0.10), in: Capsule())
        }
    }

    @ViewBuilder
    private func statusCell(_ item: NetworkDiagnosticsWorkbenchItem) -> some View {
        switch item {
        case .stageHeader, .additionalHeader: EmptyView()
        case .check(let row): statusCell(row)
        }
    }

    @ViewBuilder
    private func resultCell(_ row: NetworkDiagnosticsWorkbenchRow) -> some View {
        if let result = row.result {
            VStack(alignment: .leading, spacing: 3) {
                Text(result.summary)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineSpacing(1)
                if let detail = result.detail, detail != result.summary {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineSpacing(1)
                }
                if let target = gatewayTargetText(for: result) {
                    Text(target)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if (result.status == .abnormal || result.status == .indeterminate),
                   viewModel.assessment?.primaryIssue?.id == result.id {
                    remediationView(for: result)
                }
            }
        } else if let pendingReason = row.pendingReason {
            Text(pendingDetail(for: pendingReason))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func resultCell(_ item: NetworkDiagnosticsWorkbenchItem) -> some View {
        switch item {
        case .stageHeader, .additionalHeader: EmptyView()
        case .check(let row): resultCell(row)
        }
    }

    private func stageTitle(_ stage: NetworkDiagnosticStage) -> String {
        switch stage {
        case .thisMac:
            String(localized: "network_diagnostics.stage.this_mac.title", comment: "Network self-check local environment stage title")
        case .lan:
            String(localized: "network_diagnostics.stage.lan.title", comment: "Network self-check LAN connectivity stage title")
        case .internet:
            String(localized: "network_diagnostics.stage.internet.title", comment: "Network self-check internet connectivity stage title")
        }
    }

    private var additionalTitle: String {
        String(localized: "network_diagnostics.stage.additional.title", comment: "Network self-check additional checks group title")
    }

    private func stageIcon(_ stage: NetworkDiagnosticStage) -> String {
        switch stage {
        case .thisMac: "macbook"
        case .lan: "wifi"
        case .internet: "globe"
        }
    }

    private func stageHeaderCell(_ stage: NetworkDiagnosticStage) -> some View {
        groupHeaderCell(
            id: "stage.\(String(describing: stage))",
            title: stageTitle(stage),
            icon: stageIcon(stage)
        )
    }

    private var additionalHeaderCell: some View {
        groupHeaderCell(id: "additional", title: additionalTitle, icon: "square.grid.2x2")
    }

    private func groupHeaderCell(id: String, title: String, icon: String) -> some View {
        Button {
            expandedGroupOverride[id] = !isExpanded(id: id, items: rawWorkbenchItems)
        } label: {
            HStack(spacing: 8) {
                Label {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: icon)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: isExpanded(id: id, items: rawWorkbenchItems) ? "chevron.down" : "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isHeader)
    }

    private func isExpanded(id: String, items: [NetworkDiagnosticsWorkbenchItem]) -> Bool {
        expandedGroupOverride[id] ?? !defaultsToCollapsed(id: id, items: items)
    }

    private func defaultsToCollapsed(id: String, items: [NetworkDiagnosticsWorkbenchItem]) -> Bool {
        guard viewModel.phase == .completed else { return false }
        var inGroup = false
        var allClear = true
        for item in items {
            switch item {
            case .stageHeader(let stage):
                inGroup = id == "stage.\(String(describing: stage))"
            case .additionalHeader:
                inGroup = id == "additional"
            case .check(let row):
                if inGroup, let result = row.result,
                   result.status != .normal, result.status != .skipped {
                    allClear = false
                }
            }
        }
        return allClear
    }

    private func remediationView(for result: NetworkDiagnosticResult) -> some View {
        let remediation = NetworkDiagnosticRemediation.forResult(result)
        return VStack(alignment: .leading, spacing: 2) {
            Text(String(localized: .init(stringLiteral: remediation.detectionKey), comment: "Network self-check remediation detected condition"))
                .font(.caption.weight(.medium))
            Text(String(localized: .init(stringLiteral: remediation.actionKey), comment: "Network self-check remediation next action"))
                .font(.caption)
                .foregroundStyle(.orange)
            Text(String(localized: .init(stringLiteral: remediation.rerunKey), comment: "Network self-check remediation rerun instruction"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
    }

    private var rawWorkbenchItems: [NetworkDiagnosticsWorkbenchItem] {
        NetworkDiagnosticsPresentation.workbenchItems(
            pagePhase: viewModel.phase,
            executionPhases: viewModel.executionPhases,
            results: viewModel.results,
            checkIDs: viewModel.checkIDs,
            endReason: viewModel.endReason
        )
    }

    private var workbenchItems: [NetworkDiagnosticsWorkbenchItem] {
        var filtered: [NetworkDiagnosticsWorkbenchItem] = []
        var groupCollapsed = false
        for item in rawWorkbenchItems {
            switch item {
            case .stageHeader(let stage):
                groupCollapsed = !isExpanded(id: "stage.\(String(describing: stage))", items: rawWorkbenchItems)
                filtered.append(item)
            case .additionalHeader:
                groupCollapsed = !isExpanded(id: "additional", items: rawWorkbenchItems)
                filtered.append(item)
            case .check:
                if !groupCollapsed {
                    filtered.append(item)
                }
            }
        }
        return filtered
    }

    private var activeCheckID: NetworkDiagnosticCheckID? {
        viewModel.checkIDs.first {
            viewModel.executionPhases[$0] == .checking
        }
    }

    private var columnCheckTitle: String {
        String(localized: "network_diagnostics.report.column.check", comment: "Diagnostic workbench check column title")
    }

    private var columnStatusTitle: String {
        String(localized: "network_diagnostics.report.column.status", comment: "Diagnostic workbench status column title")
    }

    private var columnResultTitle: String {
        String(localized: "network_diagnostics.report.column.result", comment: "Diagnostic workbench result column title")
    }

    private var actionTitle: String {
        switch viewModel.phase {
        case .idle:
            String(localized: "network_diagnostics.action.run", comment: "Start the network self-check button")
        case .running:
            String(localized: "network_diagnostics.state.checking", comment: "Network self-check running state")
        case .completed:
            String(localized: "network_diagnostics.action.run_again", comment: "Run the network self-check again button")
        }
    }

    private var actionIcon: String {
        switch viewModel.phase {
        case .idle: "play.fill"
        case .running: "hourglass"
        case .completed: "arrow.clockwise"
        }
    }

    private func checkTitle(_ id: NetworkDiagnosticCheckID) -> String {
        id.localizedTitle
    }

    private func checkIcon(_ id: NetworkDiagnosticCheckID) -> String {
        switch id {
        case .path: "network"
        case .gatewayReachability: "point.3.connected.trianglepath.dotted"
        case .dns: "globe"
        case .internet: "globe"
        case .ipv6: "6.circle"
        case .proxy: "arrow.triangle.branch"
        }
    }

    private func statusTitle(_ status: NetworkDiagnosticStatus) -> String {
        status.localizedTitle
    }

    private func statusIcon(_ status: NetworkDiagnosticStatus) -> String {
        status.presentation.icon
    }

    private func statusAccessibilityLabel(for result: NetworkDiagnosticResult) -> String {
        switch result.status {
        case .blocked, .skipped:
            let reason = result.detail ?? result.summary
            return "\(statusTitle(result.status)). \(reason)"
        case .normal, .abnormal, .indeterminate:
            return statusTitle(result.status)
        }
    }

    private func pendingTitle(for reason: DiagnosticRunEndReason) -> String {
        switch reason {
        case .cancelled:
            String(localized: "network_diagnostics.check.not_run_cancelled", comment: "Pending network self-check cancelled row status")
        case .timedOut, .superseded:
            String(localized: "network_diagnostics.check.not_run_timeout", comment: "Pending network self-check timeout row status")
        case .completed:
            String(localized: "network_diagnostics.check.not_run_timeout", comment: "Pending network self-check incomplete row status")
        }
    }

    private func pendingDetail(for reason: DiagnosticRunEndReason) -> String {
        switch reason {
        case .cancelled:
            String(localized: "network_diagnostics.check.not_run_cancelled", comment: "Pending network self-check cancellation detail")
        case .timedOut, .superseded, .completed:
            String(localized: "network_diagnostics.check.not_run_timeout", comment: "Pending network self-check timeout detail")
        }
    }

    private func gatewayTargetText(for result: NetworkDiagnosticResult) -> String? {
        guard result.id == .gatewayReachability else { return nil }
        let evidence = result.evidence.reduce(into: [String: String]()) { values, evidence in
            if let value = evidence.value {
                values[evidence.code] = value
            }
        }
        guard let interface = evidence["gateway.interface"],
              let address = evidence["gateway.address"] ?? evidence["gateway.no-response"]
        else { return nil }
        return String(
            format: String(
                localized: "network_diagnostics.gateway.target",
                comment: "Selected gateway target details"
            ),
            interface,
            address
        )
    }

    private func statusColor(_ status: NetworkDiagnosticStatus) -> Color {
        switch status.presentation.tone {
        case .success: .green
        case .error: .red
        case .caution: .orange
        case .informational: .blue
        case .muted: .secondary
        }
    }

    private func conclusionTitle(_ conclusion: NetworkDiagnosticConclusion) -> String {
        switch conclusion {
        case .networkNormal:
            String(localized: "network_diagnostics.conclusion.normal.title", comment: "Network self-check normal conclusion title")
        case .needsAttention:
            String(localized: "network_diagnostics.conclusion.attention.title", comment: "Network self-check attention conclusion title")
        case .networkUnavailable:
            String(localized: "network_diagnostics.conclusion.unavailable.title", comment: "Network self-check unavailable conclusion title")
        }
    }

    private func conclusionMessage(_ conclusion: NetworkDiagnosticConclusion) -> String {
        switch conclusion {
        case .networkNormal:
            String(localized: "network_diagnostics.conclusion.normal.message", comment: "Network self-check normal conclusion message")
        case .needsAttention:
            String(localized: "network_diagnostics.conclusion.attention.message", comment: "Network self-check attention conclusion message")
        case .networkUnavailable:
            String(localized: "network_diagnostics.conclusion.unavailable.message", comment: "Network self-check unavailable conclusion message")
        }
    }

    private func conclusionIcon(_ conclusion: NetworkDiagnosticConclusion) -> String {
        switch conclusion {
        case .networkNormal: "checkmark.circle.fill"
        case .needsAttention: "exclamationmark.triangle.fill"
        case .networkUnavailable: "wifi.slash"
        }
    }

    private func conclusionColor(_ conclusion: NetworkDiagnosticConclusion) -> Color {
        switch conclusion {
        case .networkNormal: .green
        case .needsAttention: .orange
        case .networkUnavailable: .red
        }
    }
}

struct NetworkDiagnosticsPipelinePresentation: Equatable, Sendable {
    enum StationKind: Hashable, Equatable, Sendable {
        case thisMac
        case router
        case internet
    }

    enum EdgeKind: Hashable, Equatable, Sendable {
        case lan
        case internet
    }

    struct Station: Equatable, Identifiable, Sendable {
        let kind: StationKind
        let status: NetworkDiagnosticStatus?
        let qualificationCode: String?
        let isUnreachable: Bool

        var id: StationKind { kind }
    }

    struct Edge: Equatable, Identifiable, Sendable {
        let kind: EdgeKind
        let status: NetworkDiagnosticStatus?
        let isActive: Bool

        var id: EdgeKind { kind }
    }

    let stations: [Station]
    let edges: [Edge]

    static func from(
        results: [NetworkDiagnosticCheckID: NetworkDiagnosticResult],
        executionPhases: [NetworkDiagnosticCheckID: NetworkDiagnosticExecutionPhase],
        assessment: NetworkDiagnosticAssessment? = nil,
        resolver: NetworkDiagnosticStageResolver = NetworkDiagnosticStageResolver()
    ) -> Self {
        let stageAssessments = assessment?.stages ?? NetworkDiagnosticStage.allCases.map { stage in
            DiagnosticStageAssessment(
                stage: stage,
                status: resolver.status(for: stage, results: results),
                qualificationCode: nil
            )
        }
        let thisMac = stageAssessments.first { $0.stage == .thisMac }?.status
        let lan = stageAssessments.first { $0.stage == .lan }?.status
        let internet = stageAssessments.first { $0.stage == .internet }?.status
        let thisMacQualification = stageAssessments.first { $0.stage == .thisMac }?.qualificationCode
        let lanQualification = stageAssessments.first { $0.stage == .lan }?.qualificationCode
        let internetQualification = stageAssessments.first { $0.stage == .internet }?.qualificationCode

        let stations = [
            Station(kind: .thisMac, status: thisMac, qualificationCode: thisMacQualification, isUnreachable: false),
            Station(kind: .router, status: lan, qualificationCode: lanQualification, isUnreachable: lan == .abnormal || lan == .blocked),
            Station(kind: .internet, status: internet, qualificationCode: internetQualification, isUnreachable: internet == .abnormal || internet == .blocked),
        ]
        let edges = [
            Edge(kind: .lan, status: lan, isActive: isActive(stage: .lan, executionPhases: executionPhases)),
            Edge(kind: .internet, status: internet, isActive: isActive(stage: .internet, executionPhases: executionPhases)),
        ]
        return Self(stations: stations, edges: edges)
    }

    private static func isActive(
        stage: NetworkDiagnosticStage,
        executionPhases: [NetworkDiagnosticCheckID: NetworkDiagnosticExecutionPhase]
    ) -> Bool {
        stage.contributingCheckIDs.contains { executionPhases[$0] == .checking }
    }
}

struct NetworkDiagnosticsPipelineView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let presentation: NetworkDiagnosticsPipelinePresentation

    var body: some View {
        HStack(spacing: 0) {
            station(presentation.stations[0])
            edge(presentation.edges[0])
            station(presentation.stations[1])
            edge(presentation.edges[1])
            station(presentation.stations[2])
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private func station(_ station: NetworkDiagnosticsPipelinePresentation.Station) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .strokeBorder(
                        stationRingColor(station),
                        style: StrokeStyle(lineWidth: 2.5, dash: station.isUnreachable ? [5, 4] : [])
                    )
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(stationRingColor(station).opacity(0.10)))
                Image(systemName: stationIcon(station.kind))
                    .font(.system(size: 19))
                    .foregroundStyle(stationRingColor(station))
            }
            Text(stationTitle(station.kind))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
            if let status = station.status {
                Label(statusTitle(status), systemImage: statusIcon(status))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(statusColor(status))
            }
            if let qualificationCode = station.qualificationCode {
                Text(qualificationTitle(qualificationCode))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(width: 110)
    }

    @ViewBuilder
    private func edge(_ edge: NetworkDiagnosticsPipelinePresentation.Edge) -> some View {
        VStack(spacing: 6) {
            edgeLabel(edge)
            rail(edge)
        }
        .frame(maxWidth: .infinity)
    }

    private func edgeLabel(_ edge: NetworkDiagnosticsPipelinePresentation.Edge) -> some View {
        HStack(spacing: 4) {
            Image(systemName: edgeIcon(edge.kind))
            Text(edgeTitle(edge.kind))
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(edgeColor(edge))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(edgeColor(edge).opacity(0.10), in: Capsule())
    }

    @ViewBuilder
    private func rail(_ edge: NetworkDiagnosticsPipelinePresentation.Edge) -> some View {
        let content = railContent(edge)
        if edge.isActive, !reduceMotion {
            SwiftUI.TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let cycle = context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 1.4) / 1.4
                content.opacity(0.45 + 0.55 * abs(cycle - 0.5) * 2)
            }
        } else {
            content
        }
    }

    private func railContent(_ edge: NetworkDiagnosticsPipelinePresentation.Edge) -> some View {
        let color = edgeColor(edge)
        let breakable = edge.status == .abnormal || edge.status == .indeterminate || edge.status == .blocked
        return ZStack {
            if breakable {
                HStack(spacing: 7) {
                    railLine(color: color, dashed: true)
                    Image(systemName: breakIcon(edge.status))
                        .font(.system(size: 13))
                        .foregroundStyle(color)
                    railLine(color: color, dashed: true)
                }
            } else {
                railLine(color: color, dashed: false, arrowhead: true)
            }
        }
        .frame(height: 20)
    }

    private func railLine(color: Color, dashed: Bool, arrowhead: Bool = false) -> some View {
        GeometryReader { geometry in
            Path { path in
                let inset: CGFloat = 1.5
                let centerY = geometry.size.height / 2
                let tipX = max(inset, geometry.size.width - inset)
                path.move(to: CGPoint(x: inset, y: centerY))
                path.addLine(to: CGPoint(x: tipX, y: centerY))
                if arrowhead {
                    let shoulderX = max(inset, tipX - 5)
                    path.move(to: CGPoint(x: shoulderX, y: centerY - 4))
                    path.addLine(to: CGPoint(x: tipX, y: centerY))
                    path.addLine(to: CGPoint(x: shoulderX, y: centerY + 4))
                }
            }
            .stroke(color, style: StrokeStyle(
                lineWidth: 2.5,
                lineCap: .round,
                lineJoin: .round,
                dash: dashed ? [7, 5] : []
            ))
        }
        .frame(height: 14)
        .frame(maxWidth: .infinity)
    }

    private func edgeColor(_ edge: NetworkDiagnosticsPipelinePresentation.Edge) -> Color {
        if edge.isActive { return .accentColor }
        guard let status = edge.status else { return .secondary }
        return statusColor(status)
    }

    private func stationRingColor(_ station: NetworkDiagnosticsPipelinePresentation.Station) -> Color {
        if station.isUnreachable { return .secondary }
        guard let status = station.status else { return .secondary }
        return statusColor(status)
    }

    private func breakIcon(_ status: NetworkDiagnosticStatus?) -> String {
        switch status {
        case .abnormal: "xmark.circle.fill"
        case .indeterminate: "questionmark.circle.fill"
        case .blocked: "lock.fill"
        default: "xmark.circle.fill"
        }
    }

    private func stationIcon(_ kind: NetworkDiagnosticsPipelinePresentation.StationKind) -> String {
        switch kind {
        case .thisMac: "macbook"
        case .router: "wifi.router"
        case .internet: "globe"
        }
    }

    private func edgeIcon(_ kind: NetworkDiagnosticsPipelinePresentation.EdgeKind) -> String {
        switch kind {
        case .lan: "wifi"
        case .internet: "globe"
        }
    }

    private func stationTitle(_ kind: NetworkDiagnosticsPipelinePresentation.StationKind) -> String {
        switch kind {
        case .thisMac:
            String(localized: "network_diagnostics.stage.this_mac.title", comment: "Network self-check local environment stage title")
        case .router:
            String(localized: "network_diagnostics.diagram.router.title", comment: "Network self-check pipeline router station title")
        case .internet:
            String(localized: "network_diagnostics.stage.internet.title", comment: "Network self-check internet connectivity stage title")
        }
    }

    private func edgeTitle(_ kind: NetworkDiagnosticsPipelinePresentation.EdgeKind) -> String {
        switch kind {
        case .lan:
            String(localized: "network_diagnostics.stage.lan.title", comment: "Network self-check LAN connectivity stage title")
        case .internet:
            String(localized: "network_diagnostics.stage.internet.title", comment: "Network self-check internet connectivity stage title")
        }
    }

    private var accessibilityLabel: String {
        presentation.stations.map { station in
            let title = stationTitle(station.kind)
            guard let status = station.status else {
                return "\(title): \(String(localized: "network_diagnostics.state.waiting", comment: "Network self-check waiting state"))"
            }
            return "\(title): \(statusTitle(status))"
        }
        .joined(separator: ", ")
    }

    private func statusTitle(_ status: NetworkDiagnosticStatus) -> String {
        String(localized: .init(stringLiteral: status.presentation.labelKey), comment: "Network self-check status label")
    }

    private func statusIcon(_ status: NetworkDiagnosticStatus) -> String {
        status.presentation.icon
    }

    private func statusColor(_ status: NetworkDiagnosticStatus) -> Color {
        switch status.presentation.tone {
        case .success: .green
        case .error: .red
        case .caution: .orange
        case .informational: .blue
        case .muted: .secondary
        }
    }

    private func qualificationTitle(_ code: String) -> String {
        switch code {
        case "gateway.unverified":
            String(localized: "network_diagnostics.gateway.unverified", comment: "Gateway qualification after successful internet access")
        case "proxy.direct-unverified":
            String(localized: "network_diagnostics.proxy.direct_unverified", comment: "Direct proxy route qualification")
        default:
            String(localized: "network_diagnostics.status.indeterminate", comment: "Network self-check uncertainty qualification")
        }
    }
}
