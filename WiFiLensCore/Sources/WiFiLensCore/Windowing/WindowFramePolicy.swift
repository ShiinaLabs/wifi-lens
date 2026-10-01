import CoreGraphics

public enum WindowFramePolicy {
    // P0 incident note:
    // The buggy scene-level code was:
    //   .windowResizability(.contentSize)
    // together with NSWindow frame autosave restoration.
    // That let SwiftUI content ideal sizes and stale restored frames produce windows
    // larger than the current screen's visible area. This policy keeps restored
    // frames screen-safe before they are shown.
    public static func shouldNormalizeLiveWindowFrame(
        currentFrame: CGRect,
        screenFrame: CGRect?,
        visibleFrame: CGRect,
        isFullScreen: Bool
    ) -> Bool {
        // A fullscreen window is expected to exceed visibleFrame because the menu
        // bar and Dock are hidden. Do not clamp those frames back down.
        guard !isFullScreen else { return false }

        guard let screenFrame else { return true }

        let likelyFullScreenRestore =
            abs(currentFrame.width - screenFrame.width) <= 1 &&
            abs(currentFrame.height - screenFrame.height) <= 1 &&
            (currentFrame.width > visibleFrame.width || currentFrame.height > visibleFrame.height)

        return !likelyFullScreenRestore
    }

    public static func normalizedFrame(
        restoredFrame: CGRect?,
        visibleFrame: CGRect,
        defaultSize: CGSize
    ) -> CGRect {
        let fallback = centeredFrame(
            size: clampedSize(defaultSize, toFit: visibleFrame.size),
            in: visibleFrame
        )

        guard let restoredFrame, isUsable(restoredFrame) else {
            return fallback
        }

        let adjustedSize = clampedSize(restoredFrame.size, toFit: visibleFrame.size)
        let adjustedOrigin = CGPoint(
            x: min(max(restoredFrame.minX, visibleFrame.minX), visibleFrame.maxX - adjustedSize.width),
            y: min(max(restoredFrame.minY, visibleFrame.minY), visibleFrame.maxY - adjustedSize.height)
        )

        return CGRect(origin: adjustedOrigin, size: adjustedSize)
    }

    private static func isUsable(_ frame: CGRect) -> Bool {
        frame.width >= 320 &&
        frame.height >= 240 &&
        frame.width.isFinite &&
        frame.height.isFinite &&
        frame.minX.isFinite &&
        frame.minY.isFinite
    }

    private static func clampedSize(_ size: CGSize, toFit limit: CGSize) -> CGSize {
        CGSize(
            width: min(max(size.width, 1), limit.width),
            height: min(max(size.height, 1), limit.height)
        )
    }

    private static func centeredFrame(size: CGSize, in visibleFrame: CGRect) -> CGRect {
        CGRect(
            x: visibleFrame.midX - (size.width / 2),
            y: visibleFrame.midY - (size.height / 2),
            width: size.width,
            height: size.height
        )
    }
}
