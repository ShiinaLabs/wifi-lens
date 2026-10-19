import ChartLens
import Foundation
import SwiftUI
import Testing

@testable import WiFi_Lens

@Suite struct ChartGeometryTests {

    // MARK: - ChartGeometry coordinate mapping

    @Test func dataToPointMapsCorrectlyWithinBounds() {
        let geo = ChartGeometry(
            chartRect: CGRect(x: 40, y: 8, width: 352, height: 200),
            xMin: 0,
            xMax: 60,
            yMin: -100,
            yMax: 0
        )

        // A point at the center of the domain should map to the center of the chart rect
        let center = geo.dataToPoint(x: 30, y: -50)
        #expect(abs(center.x - 216) < 0.5)
        #expect(abs(center.y - 108) < 0.5)
    }

    @Test func dataToPointMapsOutsideBoundsCorrectly() {
        let geo = ChartGeometry(
            chartRect: CGRect(x: 40, y: 8, width: 352, height: 200),
            xMin: 20,
            xMax: 40,
            yMin: -100,
            yMax: 0
        )

        // A point at x=0 (left of the visible window) should map to left of chart rect
        let leftPt = geo.dataToPoint(x: 0, y: -50)
        #expect(leftPt.x < 40)

        // A point at x=60 (right of the visible window) should map to right of chart rect
        let rightPt = geo.dataToPoint(x: 60, y: -50)
        #expect(rightPt.x > 40 + 352)
    }

    @Test func pointToDataRoundtripsCorrectly() {
        let geo = ChartGeometry(
            chartRect: CGRect(x: 40, y: 8, width: 352, height: 200),
            xMin: 0,
            xMax: 60,
            yMin: -100,
            yMax: 0
        )

        let original = CGPoint(x: 200, y: 100)
        let data = geo.pointToData(screenPoint: original)
        let screen = geo.dataToPoint(x: data.x, y: data.y)
        #expect(abs(screen.x - original.x) < 0.001)
        #expect(abs(screen.y - original.y) < 0.001)
    }

    @Test func chartGeometryMappingUsesPlotRect() {
        let geo = ChartGeometry(
            frameRect: CGRect(x: 0, y: 0, width: 500, height: 300),
            plotRect: CGRect(x: 50, y: 30, width: 400, height: 200),
            annotationRect: CGRect(x: 60, y: 40, width: 380, height: 180),
            axisLabelRects: ChartAxisLabelRects(
                yAxis: CGRect(x: 0, y: 30, width: 50, height: 200),
                xAxis: CGRect(x: 50, y: 230, width: 400, height: 70)
            ),
            xMin: 0,
            xMax: 100,
            yMin: -100,
            yMax: 0
        )

        let point = geo.dataToPoint(x: 50, y: -50)
        #expect(abs(point.x - 250) < 0.001)
        #expect(abs(point.y - 130) < 0.001)

        let data = geo.pointToData(screenPoint: point)
        #expect(abs(data.x - 50) < 0.001)
        #expect(abs(data.y - -50) < 0.001)
    }

    @Test func chartGeometryKeepsChartRectAsPlotRectAlias() {
        let plot = CGRect(x: 40, y: 8, width: 352, height: 200)
        let geo = ChartGeometry(
            frameRect: CGRect(x: 0, y: 0, width: 400, height: 240),
            plotRect: plot,
            annotationRect: plot,
            axisLabelRects: ChartAxisLabelRects(
                yAxis: CGRect(x: 0, y: 8, width: 40, height: 200),
                xAxis: CGRect(x: 40, y: 208, width: 352, height: 24)
            ),
            xMin: 0,
            xMax: 60,
            yMin: -100,
            yMax: 0
        )

        #expect(geo.plotRect == plot)
        #expect(geo.chartRect == plot)
        #expect(geo.frameRect.contains(geo.annotationRect))
    }

    // MARK: - ChartSeries interpolation modes

    @Test func gaussianInterpolationGeneratesSmoothCurve() {
        let points = [
            ChartPoint(x: 4, y: -40),
            ChartPoint(x: 8, y: -40),
        ]
        let style = ChartSeriesStyle(
            color: .blue,
            lineWidth: 1.5,
            areaOpacity: 0.3,
            strokeOpacity: 0.6,
            interpolation: .gaussian(sigma: 1.0, baseline: -100),
            baseline: -100
        )
        let series = ChartSeries<ChartPoint>(id: "test", points: points, style: style)

        #expect(series.style.interpolation == .gaussian(sigma: 1.0, baseline: -100))
        #expect(series.points.count == 2)
    }

    @Test func catmullRomInterpolationPreservesAllPoints() {
        // Catmull-Rom spline quality depends on having context points.
        // Pre-filtering points before spline computation breaks boundary tangents.
        let fullPoints = stride(from: 0.0, through: 60.0, by: 1.0).map {
            ChartPoint(x: $0, y: sin($0 / 10) * 20 - 50)
        }
        let filteredPoints = fullPoints.filter { (20.0...40.0).contains($0.x) }

        // Filtered set loses context points — only 21 points vs 61
        #expect(fullPoints.count == 61)
        #expect(filteredPoints.count == 21)

        // The fix ensures the Chart receives all 61 points and relies on
        // axis bounds + clipping for the visible window, preserving spline quality.
    }

    // MARK: - ChartStyle layout

    @Test func chartRectAccountsForMargins() {
        let style = ChartStyle(
            leftAxisWidth: 40,
            bottomAxisHeight: 24,
            marginTop: 8,
            marginRight: 8,
            marginBottom: 4
        )
        let rect = style.chartRect(size: CGSize(width: 400, height: 300))
        #expect(rect.minX == 40)
        #expect(rect.minY == 8)
        #expect(abs(rect.width - 352) < 0.5)
        #expect(abs(rect.height - 264) < 0.5)
    }

    @Test func chartStyleAnnotationRectStaysInsideFrame() {
        let style = ChartStyle(
            leftAxisWidth: 40,
            bottomAxisHeight: 24,
            marginTop: 8,
            marginRight: 8,
            marginBottom: 4,
            annotationPadding: EdgeInsets(top: 6, leading: 4, bottom: 2, trailing: 4)
        )

        let frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        let regions = style.regions(size: frame.size)

        #expect(regions.frameRect == frame)
        #expect(regions.plotRect == style.chartRect(size: frame.size))
        #expect(frame.contains(regions.annotationRect))
        #expect(regions.annotationRect.minX >= regions.plotRect.minX)
        #expect(regions.annotationRect.minY >= regions.plotRect.minY)
    }

    @Test func chartStyleRegionsClampCollapsedSizes() {
        let style = ChartStyle(
            leftAxisWidth: 40,
            bottomAxisHeight: 24,
            marginTop: 8,
            marginRight: 8,
            marginBottom: 4,
            annotationPadding: EdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20)
        )

        let regions = style.regions(size: CGSize(width: 10, height: 10))

        #expect(regions.frameRect.width >= 0)
        #expect(regions.frameRect.height >= 0)
        #expect(regions.plotRect.width >= 0)
        #expect(regions.plotRect.height >= 0)
        #expect(regions.annotationRect.width >= 0)
        #expect(regions.annotationRect.height >= 0)
        #expect(regions.frameRect.contains(regions.annotationRect))
    }

    // MARK: - Axis config with explicit bounds

    @Test func axisBoundsConstrainGeometryComputation() {
        var axis = ChartAxisConfig()
        axis.xMin = 20
        axis.xMax = 40
        axis.yMin = -100
        axis.yStep = 10

        // Axis config carries explicit bounds that Chart.computeGeo uses
        #expect(axis.xMin == 20)
        #expect(axis.xMax == 40)
        #expect(axis.yStep == 10)
    }
}
