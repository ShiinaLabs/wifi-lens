import AppKit
import Testing
@testable import WiFiLensCore
@testable import WiFi_Lens

@Suite struct WindowFramePolicyTests {
    @Test func fullscreenWindowFrameIsNotNormalized() {
        let visibleFrame = CGRect(x: 0, y: 38, width: 1512, height: 945)
        let screenFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let currentFrame = screenFrame

        let shouldNormalize = WindowFramePolicy.shouldNormalizeLiveWindowFrame(
            currentFrame: currentFrame,
            screenFrame: screenFrame,
            visibleFrame: visibleFrame,
            isFullScreen: true
        )

        #expect(shouldNormalize == false)
    }

    @Test func likelyFullscreenRestoreFrameIsNotNormalizedPrematurely() {
        let visibleFrame = CGRect(x: 0, y: 38, width: 1512, height: 945)
        let screenFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let currentFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)

        let shouldNormalize = WindowFramePolicy.shouldNormalizeLiveWindowFrame(
            currentFrame: currentFrame,
            screenFrame: screenFrame,
            visibleFrame: visibleFrame,
            isFullScreen: false
        )

        #expect(shouldNormalize == false)
    }

    @Test func normalRestoredWindowStillGetsNormalized() {
        let visibleFrame = CGRect(x: 0, y: 38, width: 1512, height: 945)
        let screenFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let currentFrame = CGRect(x: -40, y: -30, width: 1800, height: 1200)

        let shouldNormalize = WindowFramePolicy.shouldNormalizeLiveWindowFrame(
            currentFrame: currentFrame,
            screenFrame: screenFrame,
            visibleFrame: visibleFrame,
            isFullScreen: false
        )

        #expect(shouldNormalize)
    }

    @Test func restoredFrameContainedByVisibleFrameIsKept() {
        let visibleFrame = CGRect(x: 0, y: 38, width: 1512, height: 945)
        let restoredFrame = CGRect(x: 120, y: 120, width: 980, height: 700)
        let defaultSize = CGSize(width: 900, height: 700)

        let normalized = WindowFramePolicy.normalizedFrame(
            restoredFrame: restoredFrame,
            visibleFrame: visibleFrame,
            defaultSize: defaultSize
        )

        #expect(normalized == restoredFrame)
    }

    @Test func oversizedRestoredFrameIsClampedIntoVisibleFrame() {
        let visibleFrame = CGRect(x: 0, y: 38, width: 1512, height: 945)
        let restoredFrame = CGRect(x: -40, y: -30, width: 1800, height: 1200)
        let defaultSize = CGSize(width: 900, height: 700)

        let normalized = WindowFramePolicy.normalizedFrame(
            restoredFrame: restoredFrame,
            visibleFrame: visibleFrame,
            defaultSize: defaultSize
        )

        #expect(visibleFrame.contains(normalized))
        #expect(normalized.width == visibleFrame.width)
        #expect(normalized.height == visibleFrame.height)
    }

    @Test func severelyInvalidRestoredFrameFallsBackToDefaultSize() {
        let visibleFrame = CGRect(x: 0, y: 38, width: 1512, height: 945)
        let restoredFrame = CGRect(x: 3000, y: 3000, width: 0, height: 1)
        let defaultSize = CGSize(width: 900, height: 700)

        let normalized = WindowFramePolicy.normalizedFrame(
            restoredFrame: restoredFrame,
            visibleFrame: visibleFrame,
            defaultSize: defaultSize
        )

        #expect(normalized.width == defaultSize.width)
        #expect(normalized.height == defaultSize.height)
        #expect(visibleFrame.contains(normalized))
    }

    @Test func defaultFrameIsCenteredWhenNoRestoredFrameExists() {
        let visibleFrame = CGRect(x: 40, y: 50, width: 1440, height: 900)
        let defaultSize = CGSize(width: 900, height: 700)

        let normalized = WindowFramePolicy.normalizedFrame(
            restoredFrame: nil,
            visibleFrame: visibleFrame,
            defaultSize: defaultSize
        )

        #expect(normalized.width == defaultSize.width)
        #expect(normalized.height == defaultSize.height)
        #expect(visibleFrame.contains(normalized))
        #expect(abs(normalized.midX - visibleFrame.midX) < 0.5)
        #expect(abs(normalized.midY - visibleFrame.midY) < 0.5)
    }
}
