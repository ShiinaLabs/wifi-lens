import CFNetwork
import Foundation
import Network
import Testing
import WiFiLensCore
@testable import WiFi_Lens

extension NetworkDiagnosticsTests {
    @Test("stage resolver aggregates this mac from path dns and proxy and maps lan to its check")
    func stageResolverThisMacAndLan() {
        let resolver = NetworkDiagnosticStageResolver()
        let abnormalDNS: [NetworkDiagnosticCheckID: NetworkDiagnosticResult] = [
            .path: .init(id: .path, status: .normal, summary: ""),
            .dns: .init(id: .dns, status: .abnormal, summary: ""),
            .proxy: .init(id: .proxy, status: .normal, summary: ""),
            .gatewayReachability: .init(id: .gatewayReachability, status: .normal, summary: ""),
        ]

        #expect(resolver.status(for: .thisMac, results: abnormalDNS) == .abnormal)
        #expect(resolver.status(for: .lan, results: abnormalDNS) == .normal)
        let proxyOnly: [NetworkDiagnosticCheckID: NetworkDiagnosticResult] = [
            .path: .init(id: .path, status: .normal, summary: ""),
            .dns: .init(id: .dns, status: .normal, summary: ""),
            .proxy: .init(id: .proxy, status: .abnormal, summary: ""),
            .gatewayReachability: .init(id: .gatewayReachability, status: .normal, summary: ""),
        ]
        #expect(resolver.status(for: .thisMac, results: proxyOnly) == .abnormal)
        #expect(resolver.status(for: .thisMac, results: [:]) == nil)
        let missingContributors: [NetworkDiagnosticCheckID: NetworkDiagnosticResult] = [
            .path: .init(id: .path, status: .normal, summary: ""),
        ]
        #expect(resolver.status(for: .thisMac, results: missingContributors) == nil)

        #expect(resolver.status(for: .internet, results: [.internet: .init(id: .internet, status: .normal, summary: "")]) == .normal)
        #expect(resolver.status(for: .internet, results: [.internet: .init(id: .internet, status: .abnormal, summary: "")]) == .abnormal)
        #expect(resolver.status(for: .internet, results: [.internet: .init(id: .internet, status: .indeterminate, summary: "")]) == .indeterminate)
        #expect(resolver.status(for: .internet, results: [.internet: .init(id: .internet, status: .blocked, summary: "")]) == .blocked)
        let extras: [NetworkDiagnosticCheckID: NetworkDiagnosticResult] = [
            .internet: .init(id: .internet, status: .normal, summary: ""),
            .dns: .init(id: .dns, status: .abnormal, summary: ""),
            .ipv6: .init(id: .ipv6, status: .abnormal, summary: ""),
        ]
        #expect(resolver.status(for: .internet, results: extras) == .normal)
        let partial: [NetworkDiagnosticCheckID: NetworkDiagnosticResult] = [
            .dns: .init(id: .dns, status: .normal, summary: ""),
        ]

        #expect(resolver.status(for: .internet, results: partial) == nil)
    }

    @Test("pipeline presentation maps stages to stations and edges")
    func pipelinePresentation() {
        let results: [NetworkDiagnosticCheckID: NetworkDiagnosticResult] = [
            .path: .init(id: .path, status: .normal, summary: ""),
            .gatewayReachability: .init(id: .gatewayReachability, status: .abnormal, summary: ""),
            .dns: .init(id: .dns, status: .normal, summary: ""),
            .internet: .init(id: .internet, status: .normal, summary: ""),
            .ipv6: .init(id: .ipv6, status: .skipped, summary: ""),
            .proxy: .init(id: .proxy, status: .normal, summary: ""),
        ]
        let presentation = NetworkDiagnosticsPipelinePresentation.from(
            results: results,
            executionPhases: [:]
        )

        #expect(presentation.stations.map(\.kind) == [.thisMac, .router, .internet])
        #expect(presentation.edges.map(\.kind) == [.lan, .internet])
        #expect(presentation.stations[0].status == .normal)
        #expect(presentation.stations[1].status == .abnormal)
        #expect(presentation.stations[1].isUnreachable)
        #expect(presentation.stations[2].status == .normal)
        #expect(!presentation.stations[2].isUnreachable)
        #expect(presentation.edges[0].status == .abnormal)
        #expect(presentation.edges[1].status == .normal)

        let executionPhases: [NetworkDiagnosticCheckID: NetworkDiagnosticExecutionPhase] = [
            .gatewayReachability: .checking,
        ]
        let activePresentation = NetworkDiagnosticsPipelinePresentation.from(
            results: [:],
            executionPhases: executionPhases
        )

        #expect(activePresentation.edges[0].isActive)
        #expect(!activePresentation.edges[1].isActive)
    }

    @Test("workbench items interleave stage headers with check rows")
    func workbenchItemGrouping() {
        #expect(NetworkDiagnosticsWorkbenchLayout.mode(for: 519) == .compact)
        #expect(NetworkDiagnosticsWorkbenchLayout.mode(for: 520) == .condensed)
        #expect(NetworkDiagnosticsWorkbenchLayout.mode(for: 719) == .condensed)
        #expect(NetworkDiagnosticsWorkbenchLayout.mode(for: 720) == .regular)

        let path = NetworkDiagnosticResult(
            id: .path,
            status: .normal,
            summary: "connected"
        )
        let executionPhases: [NetworkDiagnosticCheckID: NetworkDiagnosticExecutionPhase] = [
            .path: .completed,
            .dns: .checking,
            .proxy: .waiting,
        ]

        #expect(NetworkDiagnosticsPresentation.workbenchItems(
            pagePhase: .idle,
            executionPhases: executionPhases,
            results: [:]
        ).isEmpty)

        let runningItems = NetworkDiagnosticsPresentation.workbenchItems(
            pagePhase: .running,
            executionPhases: executionPhases,
            results: [.path: path],
            checkIDs: [.path, .dns, .proxy]
        )
        #expect(runningItems.map(\.id) == ["header.thisMac", "check.path", "check.dns"])
        #expect(runningItems[0] == .stageHeader(.thisMac))
        #expect(runningItems[1] == .check(.init(id: .path, executionPhase: .completed, result: path)))

        let completedResults = Dictionary(uniqueKeysWithValues: makeResults(
            path: .normal,
            dns: .abnormal,
            internet: .normal,
            proxy: .indeterminate
        ).map { ($0.id, $0) })
        let completedItems = NetworkDiagnosticsPresentation.workbenchItems(
            pagePhase: .completed,
            executionPhases: executionPhases,
            results: completedResults,
            checkIDs: [.path, .dns, .ipv6, .proxy]
        )
        #expect(completedItems.map(\.id) == [
            "header.thisMac", "check.path", "check.dns", "check.proxy",
            "header.additional", "check.ipv6",
        ])
        #expect(completedItems[4] == .additionalHeader)

        let timedOutItems = NetworkDiagnosticsPresentation.workbenchItems(
            pagePhase: .completed,
            executionPhases: [.path: .completed, .dns: .waiting],
            results: [.path: path],
            checkIDs: [.path, .dns],
            endReason: .timedOut
        )
        #expect(timedOutItems.last == .check(.init(
            id: .dns,
            executionPhase: .waiting,
            result: nil,
            pendingReason: .timedOut
        )))
    }
}

