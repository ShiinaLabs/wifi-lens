import AppKit
import SwiftUI
import WiFiLensCore

/// First-run welcome sheet. A dumb presentation component: it receives the
/// edition configuration and the claiming host id, and every action routes
/// through `OnboardingCoordinator`. It never checks bundle identifiers,
/// StoreKit, or receipts, and it never calls any permission API.
struct WelcomeView: View {
    let configuration: OnboardingConfiguration
    let coordinator: OnboardingCoordinator
    let hostID: UUID
    var onStart: (SidebarPage, SecondaryToolbarItemID?) -> Void = { _, _ in }

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    coordinator.completeWelcomeWithoutRouting(hostID: hostID)
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(String(localized: "onboarding.welcome.close", comment: "Close first-run welcome sheet"))
                .keyboardShortcut(.cancelAction)
            }

            appIcon
                .padding(.top, 2)

            Text(String(localized: "onboarding.welcome.title", comment: "First-run welcome sheet title"))
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 16)

            Text(String(localized: "onboarding.welcome.body", comment: "First-run welcome sheet body"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 300)
                .padding(.top, 6)

            if !configuration.highlights.isEmpty {
                highlightsList
                    .padding(.top, 20)
            }

            Button {
                startAnalyzing()
            } label: {
                Label {
                    Text(
                        String(
                            localized: .init(stringLiteral: configuration.primaryActionKey),
                            comment: "Primary first-run welcome action"
                        )
                    )
                } icon: {
                    Image(systemName: "play.fill")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("onboarding-start-analyzing")
            .padding(.top, 20)

            if configuration.showsProLink, let proURL = configuration.proURL {
                Button {
                    learnAboutPro(proURL)
                } label: {
                    Label {
                        Text(String(localized: "onboarding.welcome.learn_pro", comment: "OSS secondary first-run welcome action"))
                    } icon: {
                        Image(systemName: "arrow.up.right")
                            .font(.caption.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("onboarding-learn-pro")
                .padding(.top, 12)
            }

            Button {
                coordinator.completeWelcomeWithoutRouting(hostID: hostID)
                dismiss()
            } label: {
                Text(String(localized: "onboarding.welcome.skip", comment: "Skip first-run welcome action"))
                    .font(.callout)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("onboarding-skip")
            .padding(.top, 14)

            if let discordURL = ExternalLinks.url(for: .discord) {
                Link(destination: discordURL) {
                    Label {
                        Text(String(localized: "onboarding.welcome.discord", comment: "Discord community link in first-run welcome sheet"))
                    } icon: {
                        Image("Discord")
                            .resizable()
                            .frame(width: 12, height: 12)
                    }
                    .font(.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.tertiary)
                .accessibilityIdentifier("onboarding-discord")
                .padding(.top, 10)
            }
        }
        .padding(22)
        .frame(width: 400)
    }

    private var appIcon: some View {
        Group {
            if let icon = NSImage(named: "AppIcon") {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 76, height: 76)
            } else {
                // Fallback only when the asset catalog icon is unavailable.
                Image(systemName: "wifi")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 76, height: 76)
            }
        }
        .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
        .accessibilityHidden(true)
    }

    private var highlightsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(configuration.highlights, id: \.titleKey) { highlight in
                Label {
                    Text(
                        String(
                            localized: .init(stringLiteral: highlight.titleKey),
                            comment: "First-run welcome feature highlight"
                        )
                    )
                    .font(.callout)
                } icon: {
                    Image(systemName: highlight.icon)
                        .font(.body)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 22)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    private func startAnalyzing() {
        let route = configuration.startRoute ?? .overview
        if let resolved = coordinator.completeWelcomeStart(hostID: hostID, startRoute: route) {
            onStart(resolved, configuration.startToolbarSelection)
        }
        dismiss()
    }

    private func learnAboutPro(_ url: URL) {
        guard NSWorkspace.shared.open(url) else {
            // Keep the welcome visible and do not mark completion.
            AppLogger.guidance.error("onboarding pro link open failed")
            return
        }
        coordinator.completeWelcomeAfterOpeningProURL(hostID: hostID, openedSuccessfully: true)
        dismiss()
    }
}
