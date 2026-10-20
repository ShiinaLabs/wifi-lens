import AppKit
import SwiftUI

/// Non-modal OSS→Pro invitation card. A dumb presentation component: the host
/// resolves the pending invitation by moment and passes it in; the card never
/// queries the coordinator's `pendingInvitation` and never filters moments
/// itself. Every action routes through the invitation's `id`.
struct ProInvitationCard: View {
    let invitation: GuidanceCoordinator.InvitationPresentation
    let guidance: GuidanceCoordinator
    /// Whether the host's own page is the active one. Pass SwiftUI-observable
    /// state only: window focus, occlusion and sheet state are read live inside
    /// the presentation poll below, so baking an `NSWindow` read into this value
    /// would freeze a snapshot that no state change can refresh.
    var isHostVisible = true
    var isInVisibleArea = true
    var hostWindow: NSWindow?
    var ownerWindowID: UUID?

    public init(
        invitation: GuidanceCoordinator.InvitationPresentation,
        guidance: GuidanceCoordinator,
        isHostVisible: Bool = true,
        isInVisibleArea: Bool = true,
        hostWindow: NSWindow? = nil,
        ownerWindowID: UUID? = nil
    ) {
        self.invitation = invitation
        self.guidance = guidance
        self.isHostVisible = isHostVisible
        self.isInVisibleArea = isInVisibleArea
        self.hostWindow = hostWindow
        self.ownerWindowID = ownerWindowID ?? invitation.ownerWindowID
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(String(localized: "guidance.invitation.title", comment: "Invitation card title"))
                    .font(.headline)
            } icon: {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.accentColor)
            }

            Text(
                String(
                    localized: .init(stringLiteral: guidance.invitationMessageKey(for: invitation.moment)),
                    comment: "Invitation card body message"
                )
            )
            .font(.callout)
            .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button {
                    openAppStore()
                } label: {
                    Text(
                        String(
                            localized: "guidance.invitation.view_pro",
                            comment: "Open the Pro product page in the App Store"))
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isOwnerWindow)
                .accessibilityIdentifier("guidance-invitation-view-pro")

                Button {
                    guidance.dismissInvitation(id: invitation.id, ownerWindowID: ownerWindowID)
                } label: {
                    Text(String(localized: "guidance.invitation.later", comment: "Dismiss the invitation for now"))
                }
                .disabled(!isOwnerWindow)
                .accessibilityIdentifier("guidance-invitation-later")

            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .task(id: isHostVisible && isInVisibleArea) {
            while !Task.isCancelled {
                if isActuallyVisible && isInVisibleArea {
                    guidance.invitationPresented(id: invitation.id, ownerWindowID: ownerWindowID)
                    return
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func openAppStore() {
        guard let url = guidance.appStoreCampaignURL(for: invitation.moment),
            NSWorkspace.shared.open(url)
        else {
            return
        }
        guidance.openInvitation(id: invitation.id, ownerWindowID: ownerWindowID)
    }

    /// Testable copy selection. The card renders copy for whatever moment it is
    /// given; analysis and roaming never produce invitations in v1, so they
    /// fall back to the diagnostics copy (unreachable through the policy).
    static func messageKey(for moment: GuidanceValueMoment) -> String {
        switch moment {
        case .diagnosticsCompleted:
            "guidance.invitation.message.diagnostics"
        case .exportSucceeded:
            "guidance.invitation.message.export"
        case .analysisLoaded, .roamingCompleted, .appReturnedAfterUse:
            "guidance.invitation.message.general"
        }
    }

    private var isActuallyVisible: Bool {
        guard isOwnerWindow,
            isHostVisible,
            NSApp.isActive,
            let hostWindow,
            hostWindow.isKeyWindow,
            hostWindow.isVisible,
            !hostWindow.isMiniaturized,
            hostWindow.attachedSheet == nil
        else { return false }
        return true
    }

    private var isOwnerWindow: Bool {
        invitation.ownerWindowID == ownerWindowID
    }
}

enum GuidanceInvitationVisibility {
    static func isGenuinelyVisible(card: CGRect, viewport: CGRect) -> Bool {
        let intersection = card.intersection(viewport)
        guard !intersection.isNull, card.width > 0, card.height > 0 else { return false }
        return intersection.height >= min(card.height * 0.5, 80)
            && intersection.width >= min(card.width * 0.5, 160)
    }
}
