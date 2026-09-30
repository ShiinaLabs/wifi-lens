import AppKit
import SwiftUI
import Testing
@testable import WiFiLensCore
@testable import WiFi_Lens

@MainActor
struct SecondaryToolbarCapsuleTests {

    @Test func capsuleSelectionUpdatesBinding() {
        var selection: SecondaryToolbarItemID = .channelsSimple
        let binding = Binding(
            get: { selection },
            set: { selection = $0 }
        )

        binding.wrappedValue = .channelsTable

        #expect(selection == .channelsTable)
    }

    @Test func capsuleCoordinatorSelectionDidChangeUpdatesBinding() {
        let descriptor = SecondaryToolbarDescriptor.forPage(.channels)!
        var selection: SecondaryToolbarItemID = .channelsSimple
        let coordinator = SecondaryToolbarCapsule.Coordinator(
            selection: Binding(
                get: { selection },
                set: { selection = $0 }
            ),
            itemIDs: descriptor.items.map(\.id)
        )
        let control = SecondaryToolbarCapsule.makeControl(
            descriptor: descriptor,
            selection: .channelsSimple,
            target: coordinator,
            action: #selector(SecondaryToolbarCapsule.Coordinator.selectionDidChange(_:))
        )

        control.selectedSegment = 1
        coordinator.selectionDidChange(control)

        #expect(selection == .channelsTable)
    }

    @Test func capsuleControlExposesStableAccessibilityIdentifiers() {
        let descriptor = SecondaryToolbarDescriptor.forPage(.channels)!
        let control = SecondaryToolbarCapsule.makeControl(
            descriptor: descriptor,
            selection: .channelsSimple,
            target: nil,
            action: nil
        )

        #expect(control.accessibilityIdentifier() == "secondary-toolbar")
        let children = control.accessibilityChildren() as? [NSAccessibilityElement]
        #expect(children?.count == 2)
        #expect(children?.map { $0.accessibilityIdentifier() ?? "" } == [
            "secondary-toolbar-channels-simple",
            "secondary-toolbar-channels-table",
        ])
        #expect(children?[0].accessibilityValue() as? Int == 1)
        #expect(children?[1].accessibilityValue() as? Int == 0)

        control.selectedSegment = 1
        control.refreshAccessibilityChildren()

        let updatedChildren = control.accessibilityChildren() as? [NSAccessibilityElement]
        #expect(updatedChildren?[0].accessibilityValue() as? Int == 0)
        #expect(updatedChildren?[1].accessibilityValue() as? Int == 1)
    }
}
