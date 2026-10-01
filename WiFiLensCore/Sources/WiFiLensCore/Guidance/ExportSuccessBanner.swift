import SwiftUI

/// Bottom-anchored, non-modal export success banner (OSS `.banner` strategy
/// only). Renders nothing while there is no feedback. When the coordinator has
/// a pending export invitation, the banner hosts the invitation card and
/// captures the exact rendered token for host-lifecycle end semantics — it
/// never re-queries `pendingInvitation` later to guess which token it showed.
public struct ExportSuccessBanner: View {
    let guidance: GuidanceCoordinator

    public init(guidance: GuidanceCoordinator) {
        self.guidance = guidance
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var renderedInvitationID: UUID?

    public var body: some View {
        if guidance.exportFeedback != nil {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label {
                        Text(String(localized: "export.success_banner_message", comment: "Export success banner message"))
                            .font(.headline)
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    Spacer()
                    Button {
                        guidance.dismissExportFeedback()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(String(localized: "common.action.dismiss", comment: "Dismiss/close alert button"))
                }

                if let invitation = guidance.pendingInvitation, invitation.moment == .exportSucceeded {
                    ProInvitationCard(invitation: invitation, guidance: guidance)
                        .onAppear { renderedInvitationID = invitation.id }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: guidance.exportFeedback != nil)
            .onDisappear {
                if let id = renderedInvitationID {
                    renderedInvitationID = nil
                    guidance.endInvitationPresentation(id: id)
                }
            }
            .accessibilityIdentifier("export-success-banner")
        }
    }
}
