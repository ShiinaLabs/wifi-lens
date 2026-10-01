import Foundation
import ChartLens

struct BandChartLayout {
    struct LabelPlacement {
        enum Kind {
            case regular
            case compact
            case marker
        }

        let series: ChartSeriesData
        let x: CGFloat
        let y: CGFloat
        let size: CGSize
        let opacity: Double
        let kind: Kind
    }

    static func axisTickValues(xMin: Double, xMax: Double, maxChannel: Int, axisTickStartChannel: Int) -> [Int] {
        let desiredTicks = max(1, min(maxChannel - Int(xMin), 15))
        let rawStep = max(1, Int((xMax - xMin) / Double(desiredTicks)))
        let step = max(1, rawStep)
        return stride(from: Int(xMin), through: Int(xMax), by: step).filter { $0 >= axisTickStartChannel }
    }

    static func placeLabels(
        seriesData: [ChartSeriesData],
        plotRect: CGRect,
        annotationRect: CGRect,
        xMin: Double,
        scaleX: CGFloat,
        scaleY: CGFloat,
        yMin: Double,
        selectedNetworkID: String?
    ) -> [LabelPlacement] {
        let labelEstHeight: CGFloat = 14
        let lineHeight: CGFloat = labelEstHeight + 2
        let hasSelection = selectedNetworkID != nil

        let candidates = seriesData
            .filter { $0.isVisible || $0.id == selectedNetworkID }
            .sorted { a, b in
                if a.id == selectedNetworkID { return true }
                if b.id == selectedNetworkID { return false }
                return a.rssi > b.rssi
            }

        var placed: [LabelPlacement] = []
        var occupied: [CGRect] = []

        for series in candidates {
            let isSelected = series.id == selectedNetworkID
            let opacity: Double = hasSelection ? (isSelected ? 1.0 : 0.25) : 1.0
            let labelSize = estimatedLabelSize(for: series, kind: .regular, bounds: annotationRect)
            let rawX = plotRect.minX + (series.apex - xMin) * scaleX
            let rawY = plotRect.maxY - (series.displayRSSI - yMin) * scaleY - 8 - labelSize.height / 2
            let clampedX = clamp(
                rawX,
                min: annotationRect.minX + labelSize.width / 2,
                max: annotationRect.maxX - labelSize.width / 2
            )
            let candidateYs = labelCandidateYs(
                naturalY: rawY,
                labelHeight: labelSize.height,
                lineHeight: lineHeight,
                bounds: annotationRect
            )

            var accepted: LabelPlacement?
            for candidateY in candidateYs {
                let label = LabelPlacement(
                    series: series,
                    x: clampedX,
                    y: candidateY,
                    size: labelSize,
                    opacity: opacity,
                    kind: .regular
                )
                let rect = estimatedLabelRect(for: label)
                guard annotationRect.contains(rect) else { continue }
                guard !occupied.contains(where: { $0.intersects(rect) }) else { continue }
                accepted = label
                occupied.append(rect)
                break
            }

            if let accepted {
                placed.append(accepted)
            } else if isSelected {
                if let fallback = selectedFallbackPlacement(
                    for: series,
                    rawX: rawX,
                    rawY: rawY,
                    opacity: opacity,
                    annotationRect: annotationRect
                ) {
                    let fallbackRect = estimatedLabelRect(for: fallback)
                    placed.append(fallback)
                    occupied.append(fallbackRect)
                }
            }
        }
        return placed
    }

    static func estimatedLabelRect(for label: LabelPlacement) -> CGRect {
        CGRect(
            x: label.x - label.size.width / 2,
            y: label.y - label.size.height / 2,
            width: label.size.width,
            height: label.size.height
        )
    }

    private static func selectedFallbackPlacement(
        for series: ChartSeriesData,
        rawX: CGFloat,
        rawY: CGFloat,
        opacity: Double,
        annotationRect: CGRect
    ) -> LabelPlacement? {
        for kind in [LabelPlacement.Kind.compact, .marker] {
            let size = estimatedLabelSize(for: series, kind: kind, bounds: annotationRect)
            guard size.width > 0, size.height > 0 else { continue }
            let x = clamp(rawX, min: annotationRect.minX + size.width / 2, max: annotationRect.maxX - size.width / 2)
            let y = clamp(rawY, min: annotationRect.minY + size.height / 2, max: annotationRect.maxY - size.height / 2)
            let placement = LabelPlacement(series: series, x: x, y: y, size: size, opacity: opacity, kind: kind)
            guard annotationRect.contains(estimatedLabelRect(for: placement)) else { continue }
            return placement
        }
        return nil
    }

    private static func estimatedLabelSize(for series: ChartSeriesData, kind: LabelPlacement.Kind, bounds: CGRect) -> CGSize {
        switch kind {
        case .regular:
            let labelCharacterCount = "\(series.channel) \(series.displaySSID)\(estimatedTrendSuffix(for: series))".count
            let width = min(max(100, CGFloat(labelCharacterCount) * 6.5), 220)
            return CGSize(width: width, height: 14)
        case .compact:
            guard bounds.width >= 24, bounds.height >= 14 else { return .zero }
            let labelCharacterCount = "CH \(series.channel)".count
            let width = min(max(32, CGFloat(labelCharacterCount) * 6.5), min(60, bounds.width))
            return CGSize(width: width, height: 14)
        case .marker:
            let size = min(6, bounds.width, bounds.height)
            return CGSize(width: size, height: size)
        }
    }

    private static func estimatedTrendSuffix(for series: ChartSeriesData) -> String {
        guard !series.trendArrow.isEmpty else { return "" }
        let delta = series.trendDelta == 0 ? "" : " \(series.trendDelta > 0 ? "+" : "")\(series.trendDelta)"
        return " \(series.trendArrow)\(delta)"
    }

    private static func labelCandidateYs(
        naturalY: CGFloat,
        labelHeight: CGFloat,
        lineHeight: CGFloat,
        bounds: CGRect
    ) -> [CGFloat] {
        let minY = bounds.minY + labelHeight / 2
        let maxY = bounds.maxY - labelHeight / 2
        guard minY <= maxY else { return [] }
        let clampedNaturalY = clamp(naturalY, min: minY, max: maxY)
        var values: [CGFloat] = [clampedNaturalY]

        for lane in 1...6 {
            let down = clampedNaturalY + CGFloat(lane) * lineHeight
            let up = clampedNaturalY - CGFloat(lane) * lineHeight
            if down <= maxY { values.append(down) }
            if up >= minY { values.append(up) }
        }

        return values
    }

    private static func clamp(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
        guard minValue <= maxValue else { return (minValue + maxValue) / 2 }
        return Swift.min(Swift.max(value, minValue), maxValue)
    }

    static func nearestSeries(at location: CGPoint, in series: [ChartSeriesData], geometry: ChartGeometry, radius: CGFloat) -> (ChartSeriesData, CGPoint)? {
        guard geometry.chartRect.contains(location) else { return nil }
        var best: (ChartSeriesData, CGPoint)?
        var bestDist: CGFloat = radius

        for s in series {
            let leftX = geometry.dataToPoint(x: Double(s.left), y: geometry.yMin).x
            let rightX = geometry.dataToPoint(x: Double(s.right), y: geometry.yMin).x
            if location.x < leftX - radius || location.x > rightX + radius { continue }

            for pt in s.displayCurvePoints {
                let screenPt = geometry.dataToPoint(x: pt.x, y: pt.y)
                let dx = screenPt.x - location.x
                let dy = screenPt.y - location.y
                let dist = sqrt(dx * dx + dy * dy)
                if dist < bestDist {
                    bestDist = dist
                    best = (s, screenPt)
                }
            }
        }
        return best
    }
}
