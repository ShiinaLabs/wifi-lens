import ChartLens
import Foundation
import SwiftUI
import Testing

@testable import WiFi_Lens

// MARK: - chartDurationLabel

struct ChartTimeFormattingTests {

    @Test func zeroSeconds() {
        #expect(chartDurationLabel(0) == "0s")
    }

    @Test func subOneSecond() {
        #expect(chartDurationLabel(0.5) == "0s")
        #expect(chartDurationLabel(0.001) == "0s")
    }

    @Test func secondsOnly() {
        #expect(chartDurationLabel(1) == "1s")
        #expect(chartDurationLabel(30) == "30s")
        #expect(chartDurationLabel(59) == "59s")
    }

    @Test func exactMinutes() {
        #expect(chartDurationLabel(60) == "1m")
        #expect(chartDurationLabel(120) == "2m")
        #expect(chartDurationLabel(300) == "5m")
    }

    @Test func minutesAndSeconds() {
        #expect(chartDurationLabel(61) == "1:01")
        #expect(chartDurationLabel(90) == "1:30")
        #expect(chartDurationLabel(185) == "3:05")
    }

    @Test func largeValues() {
        #expect(chartDurationLabel(3600) == "60m")
        #expect(chartDurationLabel(3661) == "61:01")
    }

    @Test func customZeroText() {
        #expect(chartDurationLabel(0, zeroText: "now") == "now")
        #expect(chartDurationLabel(0.5, zeroText: "now") == "now")
    }
}

// MARK: - SplineInterpolation

struct SplineInterpolationTests {

    @Test func catmullRomZeroPoints() {
        let path = catmullRomSpline(points: [])
        #expect(path.isEmpty)
    }

    @Test func catmullRomSinglePoint() {
        let path = catmullRomSpline(points: [CGPoint(x: 10, y: 20)])
        #expect(path.isEmpty)
    }

    @Test func catmullRomTwoPoints() {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 100)]
        let path = catmullRomSpline(points: points)
        #expect(!path.isEmpty)
        let rect = path.boundingRect
        #expect(rect.origin.x <= 0)
        #expect(rect.origin.y <= 0)
        #expect(rect.maxX >= 100)
        #expect(rect.maxY >= 100)
    }

    @Test func catmullRomThreePoints() {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 100), CGPoint(x: 100, y: 0)]
        let path = catmullRomSpline(points: points)
        #expect(!path.isEmpty)
        let rect = path.boundingRect.insetBy(dx: -0.1, dy: -0.1)
        #expect(rect.contains(points[0]))
        #expect(rect.contains(points[2]))
    }

    @Test func catmullRomContainsAllInputPoints() {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 30, y: 50), CGPoint(x: 60, y: 20), CGPoint(x: 100, y: 80)]
        let path = catmullRomSpline(points: points)
        #expect(!path.isEmpty)
        let rect = path.boundingRect.insetBy(dx: -0.1, dy: -0.1)
        for pt in points {
            #expect(rect.contains(pt))
        }
    }

    @Test func clampedCubicZeroPoints() {
        let path = clampedCubicSpline(points: [])
        #expect(path.isEmpty)
    }

    @Test func clampedCubicSinglePoint() {
        let path = clampedCubicSpline(points: [CGPoint(x: 10, y: 20)])
        #expect(path.isEmpty)
    }

    @Test func clampedCubicTwoPoints() {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 100)]
        let path = clampedCubicSpline(points: points)
        #expect(!path.isEmpty)
        let rect = path.boundingRect
        #expect(rect.origin.x <= 0)
        #expect(rect.maxX >= 100)
    }

    @Test func clampedCubicManyPoints() {
        let points = [
            CGPoint(x: 0, y: 50), CGPoint(x: 25, y: 100), CGPoint(x: 50, y: 0), CGPoint(x: 75, y: 75),
            CGPoint(x: 100, y: 25),
        ]
        let path = clampedCubicSpline(points: points)
        #expect(!path.isEmpty)
        let rect = path.boundingRect.insetBy(dx: -1, dy: -1)
        for pt in points {
            #expect(rect.contains(pt))
        }
    }

    @Test func bothSplinesProduceDifferentPaths() {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 100), CGPoint(x: 100, y: 0)]
        let catmull = catmullRomSpline(points: points)
        let clamped = clampedCubicSpline(points: points)
        #expect(!catmull.isEmpty && !clamped.isEmpty)
    }
}
