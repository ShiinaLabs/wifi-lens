import CFNetwork
import Foundation
import Network
import Testing
@testable import WiFiLensCore
@testable import WiFi_Lens

extension NetworkDiagnosticsTests {
    @Test("DNS resolution preserves quorum, evidence, privacy, and fallback outcomes")
    func dnsOutcomeMatrix() async {
        let result = await DNSResolutionCheck(resolver: StubDNSResolver(.resolved)).run()

        #expect(result.status == .normal)
        #expect(result.evidence.contains(.init(code: "dns.success-count", value: "3/3")))
        #expect(result.evidence.contains(.init(code: "dns.failure-count", value: "0/3")))
        #expect(result.evidence.contains(.init(code: "dns.indeterminate-count", value: "0/3")))

        let mixed = await DNSResolutionCheck(
            resolver: StubDNSResolver(outcomes: [.resolved, .failed, .resolved])
        ).run()
        #expect(mixed.status == .indeterminate)
        #expect(mixed.evidence.contains(.init(code: "dns.success-count", value: "2/3")))
        #expect(mixed.evidence.contains(.init(code: "dns.failure-count", value: "1/3")))

        let mapped = await DNSResolutionCheck(
            resolver: MappingDNSResolver(outcomes: [
                "www.apple.com": .resolved,
                "www.microsoft.com": .failed,
                "www.msftconnecttest.com": .indeterminate,
            ])
        ).run()
        #expect(mapped.evidence.contains(.init(code: "dns.sample.apple", value: "resolved")))
        #expect(mapped.evidence.contains(.init(code: "dns.sample.microsoft", value: "failed")))
        #expect(mapped.evidence.contains(.init(code: "dns.sample.msft-connect-test", value: "indeterminate")))
        #expect(!mapped.evidence.contains { $0.value == "www.apple.com" })

        let failed = await DNSResolutionCheck(resolver: StubDNSResolver(.failed)).run()
        #expect(failed.status == .abnormal)
        #expect(failed.evidence.contains(.init(code: "dns.success-count", value: "0/3")))
        #expect(failed.evidence.contains(.init(code: "dns.failure-count", value: "3/3")))

        let indeterminate = await DNSResolutionCheck(resolver: StubDNSResolver(.indeterminate)).run()
        #expect(indeterminate.status == .indeterminate)
        #expect(indeterminate.evidence.contains(.init(code: "dns.indeterminate-count", value: "3/3")))

        let testDomain = "example.com"
        let privateSummary = await DNSResolutionCheck(
            resolver: StubDNSResolver(.resolved),
            probeTargets: [testDomain, "example.net", "example.org"]
        ).run()
        #expect(!privateSummary.summary.localizedCaseInsensitiveContains(testDomain))
    }

    @Test("DNS uses the three authoritative third-party probe targets")
    func dnsProbeTargets() {
        let check = DNSResolutionCheck(resolver: StubDNSResolver(.resolved))

        #expect(check.probeTargets == [
            "www.apple.com",
            "www.microsoft.com",
            "www.msftconnecttest.com",
        ])
    }

    @Test("independent DNS samples start concurrently and aggregate in target order")
    func dnsSamplesRunConcurrently() async {
        let resolver = ConcurrentDNSResolver()
        let result = await DNSResolutionCheck(
            resolver: resolver,
            timeout: .seconds(1)
        ).run()

        #expect(await resolver.maximumInFlight == 3)
        #expect(result.evidence.contains(.init(code: "dns.success-count", value: "3/3")))
    }

    @Test("an indeterminate DNS sample is retried once")
    func dnsIndeterminateSampleRetriesOnce() async {
        let resolver = StubDNSResolver(outcomes: [.indeterminate, .resolved, .resolved, .resolved])
        let result = await DNSResolutionCheck(resolver: resolver).run()

        #expect(result.status == .normal)
        #expect(await resolver.invocationCount == 4)
    }

    @Test("cancelling DNS sampling does not retry or exceed one attempt per host")
    func dnsCancellationStopsSampling() async {
        let resolver = CancellationAwareDNSResolver()
        let check = DNSResolutionCheck(resolver: resolver, timeout: .seconds(30))
        let task = Task { await check.run() }

        await resolver.waitForInvocation()
        task.cancel()
        _ = await task.value

        #expect(await resolver.invocationCount <= 3)
    }
}

