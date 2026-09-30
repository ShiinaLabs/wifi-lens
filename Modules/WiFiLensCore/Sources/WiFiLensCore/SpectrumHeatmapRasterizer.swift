import CoreGraphics
import Foundation

public struct SpectrumHeatmapRGB: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

public struct SpectrumHeatmapResolution: Hashable, Sendable {
    public static let standard = SpectrumHeatmapResolution(width: 640, height: 256)

    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        let sanitizedWidth = max(0, width)
        let sanitizedHeight = max(0, height)

        guard sanitizedWidth > 0, sanitizedHeight > 0 else {
            self.width = sanitizedWidth
            self.height = sanitizedHeight
            return
        }

        let product = sanitizedWidth.multipliedReportingOverflow(by: sanitizedHeight)
        guard !product.overflow else {
            self.width = 0
            self.height = 0
            return
        }

        self.width = sanitizedWidth
        self.height = sanitizedHeight
    }

    var storageCount: Int {
        guard width > 0, height > 0 else { return 0 }
        let count = width.multipliedReportingOverflow(by: height)
        guard !count.overflow else {
            return 0
        }
        return count.partialValue
    }
}

struct SpectrumHeatmapRaster: Equatable, Sendable {
    let width: Int
    let height: Int
    let values: [Float]

    init(width: Int, height: Int, values: [Float]) {
        let resolution = SpectrumHeatmapResolution(width: width, height: height)
        self.width = resolution.width
        self.height = resolution.height

        let expectedCount = resolution.storageCount
        if values.count == expectedCount {
            self.values = values
        } else if values.count > expectedCount {
            self.values = Array(values.prefix(expectedCount))
        } else {
            self.values = values + Array(repeating: 0, count: expectedCount - values.count)
        }
    }

    func value(x: Int, y: Int) -> Float {
        guard (0..<width).contains(x), (0..<height).contains(y) else { return 0 }
        return values[y * width + x]
    }
}

public struct SpectrumHeatmapRenderKey: Hashable, Sendable {
    let model: SpectrumHeatmapModel
    let domain: SpectrumHeatmapChannelDomain
    let rssiRange: ClosedRange<Double>
    let resolution: SpectrumHeatmapResolution

    public init(model: SpectrumHeatmapModel, domain: SpectrumHeatmapChannelDomain, rssiRange: ClosedRange<Double>, resolution: SpectrumHeatmapResolution) {
        self.model = model
        self.domain = domain
        self.rssiRange = rssiRange
        self.resolution = resolution
    }
}

enum SpectrumHeatmapRasterizer {
    static let resolution = SpectrumHeatmapResolution.standard

    /// Applies a small deterministic blur in the shared channel-coordinate
    /// raster. A small kernel cannot fabricate a meaningful hotspot across
    /// the large numeric gaps present in sparse channel plans.
    static func smooth(
        _ raster: SpectrumHeatmapRaster,
        domain _: SpectrumHeatmapChannelDomain
    ) -> SpectrumHeatmapRaster {
        guard raster.width > 0, raster.height > 0 else { return raster }

        var output = Array(repeating: Float(0), count: raster.values.count)

        for y in 0..<raster.height {
            for x in 0..<raster.width {
                var sum = 0.0
                var count = 0.0
                for sampleY in max(0, y - 1)...min(raster.height - 1, y + 1) {
                    for sampleX in max(0, x - 2)...min(raster.width - 1, x + 2) {
                        sum += Double(raster.value(x: sampleX, y: sampleY))
                        count += 1
                    }
                }

                let average = count > 0 ? sum / count : 0
                output[y * raster.width + x] = Float(min(1, max(0, average)))
            }
        }

        return SpectrumHeatmapRaster(width: raster.width, height: raster.height, values: output)
    }

    static func cgImage(
        for raster: SpectrumHeatmapRaster,
        color: (Float) -> SpectrumHeatmapRGB
    ) -> CGImage? {
        guard raster.width > 0, raster.height > 0 else { return nil }

        var bytes = Array(repeating: UInt8(0), count: raster.width * raster.height * 4)
        for y in 0..<raster.height {
            for x in 0..<raster.width {
                let rgb = color(raster.value(x: x, y: y))
                let offset = (y * raster.width + x) * 4
                bytes[offset] = byte(rgb.red)
                bytes[offset + 1] = byte(rgb.green)
                bytes[offset + 2] = byte(rgb.blue)
                bytes[offset + 3] = 255
            }
        }

        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(
            width: raster.width,
            height: raster.height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: raster.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    private static func byte(_ value: Double) -> UInt8 {
        UInt8((min(1, max(0, value)) * 255).rounded())
    }

}
