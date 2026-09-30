//
//  ConsoleSplitView.swift
//  WiFi Lens
//
//  Shared Xcode-style resizable bottom console. A persistent status bar always
//  occupies the bottom pane's minimum; dragging the native NSSplitView divider
//  grows the pane and reveals whatever content the caller places under the
//  status bar (for example a log console). Domain-neutral: the caller supplies
//  both panes and owns all strings/state; the controller only moves the divider
//  and never publishes changes from inside NSSplitView delegate callbacks.

import AppKit
import SwiftUI

@MainActor
private final class ConsoleDividerAnimation {
    weak var splitView: NSSplitView?
    let dividerIndex: Int
    let startPosition: CGFloat
    let endPosition: CGFloat
    let duration: TimeInterval
    private var startTime: TimeInterval = 0
    private var timer: Timer?

    init(splitView: NSSplitView,
         dividerIndex: Int,
         startPosition: CGFloat,
         endPosition: CGFloat,
         duration: TimeInterval) {
        self.splitView = splitView
        self.dividerIndex = dividerIndex
        self.startPosition = startPosition
        self.endPosition = endPosition
        self.duration = duration
    }

    func start() {
        stop()
        startTime = CACurrentMediaTime()
        apply(progress: 0)

        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let progress = min(max((CACurrentMediaTime() - startTime) / duration, 0), 1)
        let easedProgress = progress < 0.5
            ? 2 * progress * progress
            : 1 - pow(-2 * progress + 2, 2) / 2
        apply(progress: easedProgress)
        if progress >= 1 {
            stop()
        }
    }

    private func apply(progress: Double) {
        let position = startPosition + CGFloat(progress) * (endPosition - startPosition)
        splitView?.setPosition(position, ofDividerAt: dividerIndex)
    }
}

/// Moves the split divider between "status bar only" and "expanded" extents.
@MainActor
public final class ConsolePanelController: NSObject {
    let statusBarHeight: CGFloat
    let topMinimum: CGFloat
    let expandedBottom: CGFloat

    private weak var split: NSSplitView?
    private var didInitialPosition = false
    private var dividerAnimation: ConsoleDividerAnimation?

    public init(statusBarHeight: CGFloat = 30, topMinimum: CGFloat = 240, expandedBottom: CGFloat = 300) {
        self.statusBarHeight = statusBarHeight
        self.topMinimum = topMinimum
        self.expandedBottom = expandedBottom
    }

    func attach(_ splitView: NSSplitView) {
        split = splitView
        if !didInitialPosition {
            didInitialPosition = true
            let statusHeight = statusBarHeight
            DispatchQueue.main.async { [weak self] in
                self?.setBottomExtent(statusHeight, animate: false)
            }
        }
    }

    public func expandLog(animate: Bool = true) {
        setBottomExtent(expandedBottom, animate: animate)
    }

    public func collapseLog(animate: Bool = true) {
        setBottomExtent(statusBarHeight, animate: animate)
    }

    public func setBottomExtent(_ desired: CGFloat, animate: Bool = true) {
        guard let split else { return }
        let total = split.bounds.height
        let bottom = min(max(desired, statusBarHeight),
                         max(statusBarHeight, total - topMinimum))
        let position = total - bottom
        if animate {
            dividerAnimation?.stop()
            let startPosition = split.arrangedSubviews.first?.frame.maxY ?? position
            let animation = ConsoleDividerAnimation(splitView: split,
                                                     dividerIndex: 0,
                                                     startPosition: startPosition,
                                                     endPosition: position,
                                                     duration: 0.22)
            dividerAnimation = animation
            animation.start()
        } else {
            dividerAnimation?.stop()
            dividerAnimation = nil
            split.setPosition(position, ofDividerAt: 0)
        }
    }
}

/// Vertical split of `content` (flexible) over `bottom` (status bar + expandable
/// pane). Callers drive expand/collapse through the shared `controller`.
public struct ConsoleSplitView<Content: View, Bottom: View>: NSViewRepresentable {
    let content: Content
    let bottom: Bottom
    let controller: ConsolePanelController

    public init(content: Content, bottom: Bottom, controller: ConsolePanelController) {
        self.content = content
        self.bottom = bottom
        self.controller = controller
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public func makeNSView(context: Context) -> NSSplitView {
        let split = NSSplitView()
        split.isVertical = false
        split.dividerStyle = .thin
        split.delegate = context.coordinator

        let topHost = NSHostingView(rootView: AnyView(content))
        let bottomHost = NSHostingView(rootView: AnyView(bottom))
        topHost.autoresizingMask = [.width, .height]
        bottomHost.autoresizingMask = [.width, .height]

        context.coordinator.topHost = topHost
        context.coordinator.bottomHost = bottomHost
        context.coordinator.split = split
        context.coordinator.controller = controller
        context.coordinator.statusBarHeight = controller.statusBarHeight
        context.coordinator.topMinimum = controller.topMinimum

        split.addArrangedSubview(topHost)
        split.addArrangedSubview(bottomHost)
        split.setHoldingPriority(.defaultLow, forSubviewAt: 0)
        split.setHoldingPriority(.defaultLow, forSubviewAt: 1)

        controller.attach(split)
        return split
    }

    public func updateNSView(_ split: NSSplitView, context: Context) {
        context.coordinator.topHost?.rootView = AnyView(content)
        context.coordinator.bottomHost?.rootView = AnyView(bottom)
    }

    public final class Coordinator: NSObject, NSSplitViewDelegate {
        weak var topHost: NSHostingView<AnyView>?
        weak var bottomHost: NSHostingView<AnyView>?
        weak var split: NSSplitView?
        weak var controller: ConsolePanelController?
        var statusBarHeight: CGFloat = 30
        var topMinimum: CGFloat = 240

        public func splitView(_ splitView: NSSplitView,
                       constrainMinCoordinate proposedMinimumPosition: CGFloat,
                       ofSubviewAt dividerIndex: Int) -> CGFloat {
            dividerIndex == 0 ? topMinimum : proposedMinimumPosition
        }

        public func splitView(_ splitView: NSSplitView,
                       constrainMaxCoordinate proposedMaximumPosition: CGFloat,
                       ofSubviewAt dividerIndex: Int) -> CGFloat {
            guard dividerIndex == 0 else { return proposedMaximumPosition }
            return splitView.bounds.height - statusBarHeight
        }
    }
}
