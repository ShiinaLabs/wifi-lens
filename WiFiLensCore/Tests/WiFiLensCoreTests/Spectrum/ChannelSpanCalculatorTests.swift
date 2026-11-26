import Foundation
import Testing

@testable import WiFiLensCore

struct ChannelSpanCalculatorTests {

    @Test func channelHalfSpanMatchesExistingCases() {
        #expect(ChannelSpanCalculator.channelHalfSpan(for: 20) == 2)
        #expect(ChannelSpanCalculator.channelHalfSpan(for: 40) == 4)
        #expect(ChannelSpanCalculator.channelHalfSpan(for: 80) == 8)
        #expect(ChannelSpanCalculator.channelHalfSpan(for: 160) == 16)
    }

    @Test func narrowSixGhzWidthUsesStableFallbackThroughSwiftAPI() {
        let (left, right) = ChannelSpanCalculator.channelBlock(
            primaryChannel: 5,
            widthMHz: 0,
            band: .band6GHz,
            spanDirection: nil
        )
        #expect(left == 4)
        #expect(right == 6)
    }

    @Test func channelBlocksMatchSharedRustFixtures() throws {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("rust-core", isDirectory: true)
            .appendingPathComponent("tests", isDirectory: true)
            .appendingPathComponent("fixtures", isDirectory: true)
            .appendingPathComponent("channel-span-cases.tsv")
        let fixtures = try String(contentsOf: fixtureURL, encoding: .utf8)
        var caseCount = 0

        for (lineIndex, line) in fixtures.split(whereSeparator: \.isNewline).enumerated() {
            if line.isEmpty || line.first == "#" {
                continue
            }

            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count == 6 else {
                Issue.record("Invalid channel span fixture on line \(lineIndex + 1)")
                continue
            }

            let primaryChannel = try #require(Int(fields[0]))
            let widthMHz = try #require(Int(fields[1]))
            guard let band = ChannelBand(id: String(fields[2])) else {
                Issue.record("Invalid band in channel span fixture on line \(lineIndex + 1)")
                continue
            }
            let spanDirection: SpanDirection?
            switch fields[3] {
            case "upper": spanDirection = .upper
            case "lower": spanDirection = .lower
            case "-": spanDirection = nil
            default:
                Issue.record("Invalid direction in channel span fixture on line \(lineIndex + 1)")
                continue
            }
            let expectedLeft = try #require(Int(fields[4]))
            let expectedRight = try #require(Int(fields[5]))
            let (left, right) = ChannelSpanCalculator.channelBlock(
                primaryChannel: primaryChannel,
                widthMHz: widthMHz,
                band: band,
                spanDirection: spanDirection
            )

            #expect(left == expectedLeft, "fixture line \(lineIndex + 1)")
            #expect(right == expectedRight, "fixture line \(lineIndex + 1)")
            caseCount += 1
        }

        #expect(caseCount == 45)
    }
}
