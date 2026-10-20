import AppKit
import SwiftUI

/// Title bar badge that reflects the active edition.
public struct TitleBadge: View {
    private let identity: WiFiLensEditionIdentity
    private let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var shimmerOffset: CGFloat = 0

    /// `onTap` is consumed by the OSS badge only: it opens the edition's
    /// callout. The Pro badge has no such surface and stays decorative.
    public init(identity: WiFiLensEditionIdentity, onTap: @escaping () -> Void = {}) {
        self.identity = identity
        self.onTap = onTap
    }

    public var body: some View {
        switch identity {
        case .openSource:
            ossBadge
        case .pro:
            proBadge
        }
    }

    // MARK: - OSS Badge

    private var ossBadge: some View {
        Button {
            onTap()
        } label: {
            Text(String(localized: "settings.app.title_badge_oss", comment: "OSS edition title badge text"))
                .font(.subheadline.weight(.medium))
                .foregroundColor(Color(red: 91 / 255, green: 46 / 255, blue: 166 / 255))
                .frame(height: 34)
                .padding(.horizontal, 14)
        }
        .buttonStyle(.plain)
        .background(Color(red: 245 / 255, green: 213 / 255, blue: 250 / 255), in: Capsule())
        .overlay {
            Capsule().stroke(Color(red: 91 / 255, green: 46 / 255, blue: 166 / 255), lineWidth: 1)
        }
        .accessibilityLabel(
            Text(String(localized: "settings.app.title_badge_oss", comment: "OSS edition title badge text"))
        )
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("title-badge")
    }

    // MARK: - PRO Badge

    private var proBadge: some View {
        let goldColor = Color(red: 218 / 255, green: 165 / 255, blue: 32 / 255)

        return Button {
            // no action yet
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "star.fill")
                    .font(.caption)
                Text(String(localized: "settings.app.title_badge_pro", comment: "PRO edition title badge text"))
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundColor(Color(red: 138 / 255, green: 90 / 255, blue: 0))
            .frame(height: 34)
            .padding(.horizontal, 14)
        }
        .buttonStyle(.plain)
        .background(Color(red: 255 / 255, green: 245 / 255, blue: 220 / 255), in: Capsule())
        .overlay {
            Capsule().stroke(goldColor, lineWidth: 1.5)
        }
        .shadow(color: goldColor.opacity(0.3), radius: 6, y: 2)
        .overlay {
            // One-shot entrance shimmer; hidden entirely under Reduce Motion.
            if !reduceMotion {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.4), .clear],
                            startPoint: UnitPoint(x: shimmerOffset - 0.3, y: 0.5),
                            endPoint: UnitPoint(x: shimmerOffset + 0.3, y: 0.5)
                        )
                    )
                    .mask(Capsule())
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 5)) {
                shimmerOffset = 1.5
            }
        }
        .accessibilityHidden(true)
    }
}

/// The callout anchored to the OSS title badge. A dumb presentation component:
/// the host resolves the presentation and passes it in. Every action reports
/// back through the coordinator only after the operating system accepts the
/// handoff, so a failed open neither closes the callout nor consumes state.
public struct BadgeBarView: View {
    private let presentation: BadgeBarPresentation
    private let guidance: GuidanceCoordinator
    private let onClose: () -> Void

    public init(
        presentation: BadgeBarPresentation,
        guidance: GuidanceCoordinator,
        onClose: @escaping () -> Void
    ) {
        self.presentation = presentation
        self.guidance = guidance
        self.onClose = onClose
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                row(
                    icon: "sparkles",
                    iconColor: .accentColor,
                    title: String(
                        localized: "guidance.badge_bar.pro.title",
                        comment: "Badge bar row title inviting the Pro upgrade"),
                    message: String(
                        localized: "guidance.badge_bar.pro.message",
                        comment: "Badge bar row body inviting the Pro upgrade"),
                    actionTitle: String(
                        localized: "guidance.invitation.view_pro",
                        comment: "Open the Pro product page in the App Store"),
                    identifier: "badge-bar-view-pro",
                    isProminent: true,
                    action: openAppStore
                )
                dismissButton
            }

            if presentation.offersRepositoryStar {
                Divider()
                row(
                    icon: "star",
                    iconColor: .secondary,
                    title: String(
                        localized: "guidance.badge_bar.star.title",
                        comment: "Badge bar row title inviting a star on the open-source repository"),
                    message: String(
                        localized: "guidance.badge_bar.star.message",
                        comment: "Badge bar row body inviting a star on the open-source repository"),
                    actionTitle: String(
                        localized: "guidance.badge_bar.star.action",
                        comment: "Open the open-source repository page"),
                    identifier: "badge-bar-star-repository",
                    isProminent: false,
                    action: openRepository
                )
            }
        }
        .padding(14)
        .frame(width: 340)
    }

    private var dismissButton: some View {
        Button {
            guidance.badgeBarDidDismiss()
            onClose()
        } label: {
            Image(systemName: "xmark")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            Text(String(localized: "guidance.badge_bar.dismiss", comment: "Dismiss the badge bar callout"))
        )
        .accessibilityIdentifier("badge-bar-dismiss")
    }

    private func row(
        icon: String,
        iconColor: Color,
        title: String,
        message: String,
        actionTitle: String,
        identifier: String,
        isProminent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(title).font(.headline)
            } icon: {
                Image(systemName: icon).foregroundStyle(iconColor)
            }

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            actionButton(title: actionTitle, identifier: identifier, isProminent: isProminent, action: action)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The two rows carry different visual weight: only the Pro upgrade is a
    /// filled call to action, so the star row uses the plain bordered style.
    @ViewBuilder
    private func actionButton(
        title: String,
        identifier: String,
        isProminent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        if isProminent {
            Button(action: action) {
                Text(title)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier(identifier)
        } else {
            Button(action: action) {
                Text(title)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier(identifier)
        }
    }

    private func openAppStore() {
        guard let url = ExternalLinks.url(for: .appStoreCampaignBadge),
            NSWorkspace.shared.open(url)
        else { return }
        guidance.recordSuccessfulStoreOpenIfMarketingEnabled()
        guidance.badgeBarDidDismiss()
        onClose()
    }

    private func openRepository() {
        guard let url = ExternalLinks.url(for: .github),
            NSWorkspace.shared.open(url)
        else { return }
        guidance.badgeBarDidOpenRepository()
        onClose()
    }
}
