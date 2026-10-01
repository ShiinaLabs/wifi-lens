import CoreGraphics
import Testing
@testable import WiFiLensCore

@Suite struct SpectrumHeatmapFieldGeneratorTests {
    private let generator = CPUHeatmapFieldGenerator()
    private let resolution = SpectrumHeatmapResolution(width: 640, height: 256)
    private let rssiRange = (-100.0)...(-30.0)

    private var singleRegionDomain: SpectrumHeatmapChannelDomain {
        SpectrumHeatmapChannelDomain(minChannelCoordinate: 1, maxChannelCoordinate: 9)
    }

    private func envelope(
        lower: Double = 3,
        upper: Double = 7,
        peakRSSI: Double = -50,
        baselineRSSI: Double = -100
    ) -> SpectrumHeatmapEnvelope {
        SpectrumHeatmapEnvelope(
            leftX: lower,
            rightX: upper,
            peakRSSI: peakRSSI,
            baselineRSSI: baselineRSSI
        )
    }

    private func pixel(
        forChannel channel: Double,
        rssi: Double,
        domain: SpectrumHeatmapChannelDomain = SpectrumHeatmapChannelDomain(
            minChannelCoordinate: 1,
            maxChannelCoordinate: 9
        )
    ) -> (x: Int, y: Int) {
        let rect = CGRect(x: 0, y: 0, width: resolution.width, height: resolution.height)
        let x = Int((SpectrumHeatmapLayout.xPosition(forChannelCoordinate: channel, domain: domain, in: rect)! - 0.5).rounded())
        let y = Int((SpectrumHeatmapLayout.yPosition(forRSSI: rssi, in: rect, rssiRange: rssiRange)! - 0.5).rounded())
        return (
            min(max(0, x), resolution.width - 1),
            min(max(0, y), resolution.height - 1)
        )
    }

    @Test func producesExactFloat32StorageAndBoundsSafeReads() {
        let raster = generator.generate(
            envelopes: [],
            domain: singleRegionDomain,
            rssiRange: rssiRange,
            resolution: resolution
        )

        #expect(raster.width == 640)
        #expect(raster.height == 256)
        #expect(raster.values.count == 640 * 256)
        #expect(raster.value(x: -1, y: 0) == 0)
        #expect(raster.value(x: 640, y: 0) == 0)
        #expect(raster.value(x: 0, y: -1) == 0)
        #expect(raster.value(x: 0, y: 256) == 0)
    }

    @Test func rasterConvertsToOneRGBAImageAtItsNativeResolution() {
        let raster = SpectrumHeatmapRaster(width: 2, height: 3, values: [0, 0.25, 0.5, 0.75, 1, 0])
        let image = SpectrumHeatmapRasterizer.cgImage(for: raster) { intensity in
            SpectrumHeatmapRGB(red: Double(intensity), green: 0, blue: 0)
        }

        #expect(image?.width == 2)
        #expect(image?.height == 3)
    }

    @Test func overflowedDimensionsAreSanitizedBeforeBoundsChecks() {
        let raster = SpectrumHeatmapRaster(width: Int.max, height: 2, values: [])

        #expect(raster.width == 0)
        #expect(raster.height == 0)
        #expect(raster.values.isEmpty)
        #expect(raster.value(x: 0, y: 0) == 0)
    }

    @Test func repeatedGenerationIsDeterministic() {
        let envelopes = [envelope(), envelope(lower: 2418, upper: 2442, peakRSSI: -65)]

        let first = generator.generate(
            envelopes: envelopes,
            domain: singleRegionDomain,
            rssiRange: rssiRange,
            resolution: resolution
        )
        let second = generator.generate(
            envelopes: envelopes,
            domain: singleRegionDomain,
            rssiRange: rssiRange,
            resolution: resolution
        )

        #expect(first == second)
    }

    @Test func emptyEnvelopeListProducesOnlyZeroValues() {
        let raster = generator.generate(
            envelopes: [],
            domain: singleRegionDomain,
            rssiRange: rssiRange,
            resolution: resolution
        )

        #expect(raster.values.allSatisfy { $0 == 0 })
    }

    @Test func singleGaussianContributionDecaysContinuouslyBelowItsCurve() {
        let raster = generator.generate(
            envelopes: [envelope()],
            domain: singleRegionDomain,
            rssiRange: rssiRange,
            resolution: resolution
        )
        let center = pixel(forChannel: 5, rssi: -50)
        let aboveCurve = pixel(forChannel: 5, rssi: -45)
        let nearCurve = pixel(forChannel: 5, rssi: -55)
        let deepBelowCurve = pixel(forChannel: 5, rssi: -75)

        #expect(raster.value(x: center.x, y: aboveCurve.y) == 0)
        #expect(raster.value(x: center.x, y: nearCurve.y) > raster.value(x: center.x, y: deepBelowCurve.y))
        #expect(raster.value(x: center.x, y: deepBelowCurve.y) > 0)
    }

    @Test func filledEnvelopeRetainsVisibleBodyWellBelowItsCurve() {
        let raster = generator.generate(
            envelopes: [envelope()],
            domain: singleRegionDomain,
            rssiRange: rssiRange,
            resolution: resolution
        )
        let nearCurve = pixel(forChannel: 5, rssi: -55)
        let body = pixel(forChannel: 5, rssi: -75)

        #expect(raster.value(x: body.x, y: body.y) > 0.15)
        #expect(raster.value(x: nearCurve.x, y: nearCurve.y) > raster.value(x: body.x, y: body.y))
    }

    @Test func sampledPixelsFarAboveTheGaussianCurveRemainZero() {
        let testEnvelope = envelope()
        let raster = generator.generate(
            envelopes: [testEnvelope],
            domain: singleRegionDomain,
            rssiRange: rssiRange,
            resolution: resolution
        )
        let rect = CGRect(x: 0, y: 0, width: resolution.width, height: resolution.height)
        let gaussian = SpectrumHeatmapActivity.gaussianEnvelope(for: testEnvelope)

        for x in stride(from: 0, to: resolution.width, by: 37) {
            guard let channel = SpectrumHeatmapLayout.channelCoordinate(
                forX: CGFloat(x) + 0.5,
                domain: singleRegionDomain,
                in: rect
            ) else { continue }
            let curve = gaussian.value(atX: channel)
            for y in stride(from: 0, to: resolution.height, by: 11) {
                guard let rssi = SpectrumHeatmapLayout.rssi(
                    forY: CGFloat(y) + 0.5,
                    in: rect,
                    rssiRange: rssiRange
                ) else { continue }
                if rssi > curve + 3 {
                    #expect(raster.value(x: x, y: y) == 0)
                }
            }
        }
    }

    @Test func RSSIOnlyChangesEnvelopeHeightNotItsPerAPColorWeight() {
        let strongRow = 64
        let weakRow = 192
        let rect = CGRect(x: 0, y: 0, width: resolution.width, height: resolution.height)
        let strongRSSI = SpectrumHeatmapLayout.rssi(
            forY: CGFloat(strongRow) + 0.5,
            in: rect,
            rssiRange: rssiRange
        )!
        let weakRSSI = SpectrumHeatmapLayout.rssi(
            forY: CGFloat(weakRow) + 0.5,
            in: rect,
            rssiRange: rssiRange
        )!
        let strong = generator.generate(
            envelopes: [envelope(peakRSSI: strongRSSI)],
            domain: singleRegionDomain,
            rssiRange: rssiRange,
            resolution: resolution
        )
        let weak = generator.generate(
            envelopes: [envelope(peakRSSI: weakRSSI)],
            domain: singleRegionDomain,
            rssiRange: rssiRange,
            resolution: resolution
        )
        let centerX = pixel(forChannel: 5, rssi: strongRSSI).x

        #expect(abs(Double(strong.value(x: centerX, y: strongRow)) - 0.5) < 0.01)
        #expect(abs(Double(weak.value(x: centerX, y: weakRow)) - 0.5) < 0.01)
    }

    @Test func overlappingEnvelopesAccumulateAtTheSamePixel() {
        let one = generator.generate(
            envelopes: [envelope()],
            domain: singleRegionDomain,
            rssiRange: rssiRange,
            resolution: resolution
        )
        let two = generator.generate(
            envelopes: [envelope(), envelope()],
            domain: singleRegionDomain,
            rssiRange: rssiRange,
            resolution: resolution
        )
        let sample = pixel(forChannel: 5, rssi: -50)

        #expect(two.value(x: sample.x, y: sample.y) > one.value(x: sample.x, y: sample.y))
        #expect(abs(Double(one.value(x: sample.x, y: sample.y)) - 0.5) < 0.01)
        #expect(abs(Double(two.value(x: sample.x, y: sample.y)) - sqrt(2.0 / 4.0)) < 0.01)
    }

    @Test func aggregateDensityAtLeastThreeSaturatesNormalization() {
        let row = 128
        let rect = CGRect(x: 0, y: 0, width: resolution.width, height: resolution.height)
        let peakRSSI = SpectrumHeatmapLayout.rssi(
            forY: CGFloat(row) + 0.5,
            in: rect,
            rssiRange: rssiRange
        )!
        let raster = generator.generate(
            envelopes: [
                envelope(peakRSSI: peakRSSI),
                envelope(peakRSSI: peakRSSI),
                envelope(peakRSSI: peakRSSI),
                envelope(peakRSSI: peakRSSI),
                envelope(peakRSSI: peakRSSI)
            ],
            domain: singleRegionDomain,
            rssiRange: rssiRange,
            resolution: resolution
        )
        let sample = pixel(forChannel: 5, rssi: peakRSSI)

        #expect(raster.value(x: sample.x, y: sample.y) > 0.99)
    }

    @Test func disjointEnvelopesProduceUnionCoverage() {
        let domain = SpectrumHeatmapChannelDomain(minChannelCoordinate: 1, maxChannelCoordinate: 9)
        let raster = generator.generate(
            envelopes: [
                envelope(lower: 2, upper: 3),
                envelope(lower: 7, upper: 8)
            ],
            domain: domain,
            rssiRange: rssiRange,
            resolution: resolution
        )
        let left = pixel(forChannel: 2.5, rssi: -95, domain: domain)
        let right = pixel(forChannel: 7.5, rssi: -95, domain: domain)
        let middle = pixel(forChannel: 5, rssi: -95, domain: domain)

        #expect(raster.value(x: left.x, y: left.y) > 0)
        #expect(raster.value(x: right.x, y: right.y) > 0)
        #expect(raster.value(x: middle.x, y: middle.y) == 0)
    }

    @Test func contributionAtTheEnvelopeEdgeIsMaximumAndTransitionIsMonotonic() {
        let domain = singleRegionDomain
        let rect = CGRect(x: 0, y: 0, width: resolution.width, height: resolution.height)
        let curveRSSI = SpectrumHeatmapLayout.rssi(
            forY: 100.5,
            in: rect,
            rssiRange: rssiRange
        )!
        let raster = generator.generate(
            envelopes: [envelope(peakRSSI: curveRSSI)],
            domain: domain,
            rssiRange: rssiRange,
            resolution: resolution
        )
        let x = pixel(forChannel: 5, rssi: curveRSSI, domain: domain).x

        #expect(raster.value(x: x, y: 101) > 0)
        #expect(raster.value(x: x, y: 130) > 0)
        for y in 101..<130 {
            #expect(raster.value(x: x, y: y) >= raster.value(x: x, y: y + 1) - 0.0001)
        }
    }

    @Test func sparseChannelGapPixelsRemainDark() {
        let domain = SpectrumHeatmapChannelDomain(minChannelCoordinate: 1, maxChannelCoordinate: 170)
        let raster = generator.generate(
            envelopes: [envelope(lower: 34, upper: 50, peakRSSI: -45)],
            domain: domain,
            rssiRange: rssiRange,
            resolution: resolution
        )
        let rect = CGRect(x: 0, y: 0, width: resolution.width, height: resolution.height)
        let gapColumns = (0..<resolution.width).filter { x in
            guard let channel = SpectrumHeatmapLayout.channelCoordinate(
                forX: CGFloat(x) + 0.5,
                domain: domain,
                in: rect
            ) else { return false }
            return channel > 50 && channel < 149
        }

        #expect(!gapColumns.isEmpty)
        #expect(gapColumns.allSatisfy { x in
            (0..<resolution.height).allSatisfy { y in raster.value(x: x, y: y) == 0 }
        })
    }

    @Test func smoothingRemainsLocalAndClampsOutput() {
        let domain = SpectrumHeatmapChannelDomain(minChannelCoordinate: 1, maxChannelCoordinate: 9)
        let raw = SpectrumHeatmapRaster(
            width: 100,
            height: 5,
            values: {
                var values = Array(repeating: Float(0), count: 500)
                values[2 * 100 + 50] = 1
                return values
            }()
        )

        let smoothed = SpectrumHeatmapRasterizer.smooth(raw, domain: domain)

        #expect(smoothed.value(x: 49, y: 2) > 0)
        #expect(smoothed.value(x: 51, y: 2) > 0)
        #expect(smoothed.values.allSatisfy { (0...1).contains($0) })
    }
}
