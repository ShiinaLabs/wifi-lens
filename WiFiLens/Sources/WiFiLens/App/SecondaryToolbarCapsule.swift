import AppKit
import SwiftUI
import WiFiLensCore

struct SecondaryToolbarCapsule: NSViewRepresentable {
    let descriptor: SecondaryToolbarDescriptor
    @Binding var selection: SecondaryToolbarItemID

    static func makeControl(
        descriptor: SecondaryToolbarDescriptor,
        selection: SecondaryToolbarItemID,
        target: AnyObject?,
        action: Selector?
    ) -> SecondaryToolbarSegmentedControl {
        let control = SecondaryToolbarSegmentedControl(
            labels: descriptor.items.map(\.title),
            trackingMode: .selectOne,
            target: target,
            action: action
        )
        control.segmentStyle = .capsule
        control.segmentDistribution = .fillEqually
        control.controlSize = .large
        control.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)
        control.translatesAutoresizingMaskIntoConstraints = false
        control.setAccessibilityIdentifier("secondary-toolbar")
        control.setAccessibilityLabel(descriptor.items.map(\.title).joined(separator: ", "))

        if #available(macOS 26.0, *) {
            control.borderShape = .capsule
        }
        // TODO: Enable when CI Xcode ships macOS 27+ SDK (currently Xcode 26.5).
        // NSSegmentedControl.role is unavailable in the macOS 26 SDK headers.
        // if #available(macOS 27.0, *) {
        //     control.role = .valueSelection
        // }

        update(control, with: descriptor, selection: selection)
        return control
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection, itemIDs: descriptor.items.map(\.id))
    }

    func makeNSView(context: Context) -> SecondaryToolbarSegmentedControl {
        return Self.makeControl(
            descriptor: descriptor,
            selection: selection,
            target: context.coordinator,
            action: #selector(Coordinator.selectionDidChange(_:))
        )
    }

    func updateNSView(_ nsView: SecondaryToolbarSegmentedControl, context: Context) {
        nsView.target = context.coordinator
        nsView.action = #selector(Coordinator.selectionDidChange(_:))
        context.coordinator.itemIDs = descriptor.items.map(\.id)
        Self.update(nsView, with: descriptor, selection: selection)
    }

    private static func update(_ control: SecondaryToolbarSegmentedControl, with descriptor: SecondaryToolbarDescriptor, selection: SecondaryToolbarItemID) {
        if control.segmentCount != descriptor.items.count {
            control.segmentCount = descriptor.items.count
        }

        for (index, item) in descriptor.items.enumerated() {
            if item.isLocked {
                let lockImage = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)?
                    .withSymbolConfiguration(.init(pointSize: 11, weight: .medium))
                lockImage?.isTemplate = false
                if let lockImage {
                    lockImage.lockFocus()
                    NSColor.systemYellow.set()
                    NSRect(origin: .zero, size: lockImage.size).fill(using: .sourceAtop)
                    lockImage.unlockFocus()
                }
                control.setImage(lockImage, forSegment: index)
                control.setLabel(item.title, forSegment: index)
                control.setWidth(120, forSegment: index)
            } else {
                control.setLabel(item.title, forSegment: index)
                control.setWidth(110, forSegment: index)
            }
            control.setTag(index, forSegment: index)
        }

        control.segmentItemIDs = descriptor.items.map(\.id)
        let selectedIndex = descriptor.selectionIndex(for: selection)
        if control.selectedSegment != selectedIndex {
            control.selectedSegment = selectedIndex
        }
        control.refreshAccessibilityChildren()
    }

    @MainActor
    final class Coordinator: NSObject {
        @Binding private var selection: SecondaryToolbarItemID
        var itemIDs: [SecondaryToolbarItemID]

        init(selection: Binding<SecondaryToolbarItemID>, itemIDs: [SecondaryToolbarItemID] = []) {
            _selection = selection
            self.itemIDs = itemIDs
        }

        @objc func selectionDidChange(_ sender: NSSegmentedControl) {
            let index = sender.selectedSegment
            guard index >= 0 else { return }
            guard itemIDs.indices.contains(index) else { return }
            let itemID = itemIDs[index]
            if selection != itemID {
                selection = itemID
            }
        }
    }
}

final class SecondaryToolbarSegmentedControl: NSSegmentedControl {
    var segmentItemIDs: [SecondaryToolbarItemID] = []

    override func layout() {
        super.layout()
        refreshAccessibilityChildren()
    }

    func refreshAccessibilityChildren() {
        var childElements: [Any] = []
        var xOffset: CGFloat = 0

        for index in 0..<segmentCount {
            let width = self.width(forSegment: index)
            let localFrame = NSRect(x: xOffset, y: 0, width: width, height: bounds.height)
            let windowFrame = convert(localFrame, to: nil)
            let screenFrame = window?.convertToScreen(windowFrame) ?? localFrame
            let label = self.label(forSegment: index) ?? ""
            let element = SecondaryToolbarSegmentAccessibilityElement(
                control: self,
                segmentIndex: index
            )
            element.setAccessibilityRole(.radioButton)
            element.setAccessibilityFrame(screenFrame)
            element.setAccessibilityLabel(label)
            element.setAccessibilityParent(self)
            element.setAccessibilityEnabled(isEnabled)
            element.setAccessibilityValue(index == selectedSegment ? 1 : 0)
            if segmentItemIDs.indices.contains(index) {
                element.setAccessibilityIdentifier("secondary-toolbar-\(segmentItemIDs[index].rawValue)")
            }
            childElements.append(element)
            xOffset += width
        }

        setAccessibilityChildren(childElements as [Any]?)
    }
}

private final class SecondaryToolbarSegmentAccessibilityElement: NSAccessibilityElement {
    weak var control: SecondaryToolbarSegmentedControl?
    let segmentIndex: Int

    init(control: SecondaryToolbarSegmentedControl, segmentIndex: Int) {
        self.control = control
        self.segmentIndex = segmentIndex
        super.init()
    }

    override func accessibilityPerformPress() -> Bool {
        let control = self.control
        let segmentIndex = self.segmentIndex
        return MainActor.assumeIsolated { [control, segmentIndex] in
            guard let control,
                  control.isEnabled,
                  segmentIndex < control.segmentCount
            else { return false }

            control.selectedSegment = segmentIndex
            return control.sendAction(control.action, to: control.target)
        }
    }
}
