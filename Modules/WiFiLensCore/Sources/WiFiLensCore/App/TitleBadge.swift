import SwiftUI

/// Title bar badge that reflects the active edition.
public struct TitleBadge: View {
    private let identity: WiFiLensEditionIdentity

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var shimmerOffset: CGFloat = 0

    public init(identity: WiFiLensEditionIdentity) {
        self.identity = identity
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
            // no action yet
        } label: {
            Text(String(localized: "settings.app.title_badge_oss", comment: "OSS edition title badge text"))
                .font(.subheadline.weight(.medium))
                .foregroundColor(Color(red: 91/255, green: 46/255, blue: 166/255))
                .frame(height: 34)
                .padding(.horizontal, 14)
        }
        .buttonStyle(.plain)
        .background(Color(red: 245/255, green: 213/255, blue: 250/255), in: Capsule())
        .overlay {
            Capsule().stroke(Color(red: 91/255, green: 46/255, blue: 166/255), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }

    // MARK: - PRO Badge

    private var proBadge: some View {
        let goldColor = Color(red: 218/255, green: 165/255, blue: 32/255)

        return Button {
            // no action yet
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "star.fill")
                    .font(.caption)
                Text(String(localized: "settings.app.title_badge_pro", comment: "PRO edition title badge text"))
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundColor(Color(red: 138/255, green: 90/255, blue: 0))
            .frame(height: 34)
            .padding(.horizontal, 14)
        }
        .buttonStyle(.plain)
        .background(Color(red: 255/255, green: 245/255, blue: 220/255), in: Capsule())
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
