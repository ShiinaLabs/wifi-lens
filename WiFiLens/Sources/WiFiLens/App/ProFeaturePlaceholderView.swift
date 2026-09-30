import SwiftUI
import WiFiLensCore

struct ProBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "lock.fill")
                .font(.system(size: 10, weight: .semibold))

            Text("PRO")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(0.4)
        }
        .foregroundStyle(Color(red: 0.92, green: 0.57, blue: 0.02))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            Capsule()
                .fill(Color(red: 1.0, green: 0.82, blue: 0.28).opacity(0.22))
        }
        .overlay {
            Capsule()
                .stroke(
                    Color(red: 0.95, green: 0.62, blue: 0.08).opacity(0.28),
                    lineWidth: 1
                )
        }
        .fixedSize()
        .accessibilityLabel(String(localized: "pro.accessibility.badge", comment: "Accessibility label for Pro badge"))
    }
}

struct ProFeaturePlaceholderView<CustomSkeleton: View>: View {
    let featureName: String
    let featureDescription: String
    let featureIcon: String
    let campaign: ExternalDestination
    @ViewBuilder var customSkeleton: () -> CustomSkeleton
    @Environment(\.colorScheme) private var colorScheme

    init(
        featureName: String,
        featureDescription: String,
        featureIcon: String,
        campaign: ExternalDestination = .appStoreCampaignPreviewLock,
        @ViewBuilder customSkeleton: @escaping () -> CustomSkeleton
    ) {
        self.featureName = featureName
        self.featureDescription = featureDescription
        self.featureIcon = featureIcon
        self.campaign = campaign
        self.customSkeleton = customSkeleton
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [Color(red: 0.10, green: 0.12, blue: 0.20), Color.clear]
                        : [Color(red: 0.94, green: 0.95, blue: 0.98), Color.clear],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(spacing: 18) {
                    customSkeleton()
                        .accessibilityHidden(true)

                    Spacer().frame(height: 24)

                    VStack(spacing: 8) {
                        Text(featureName)
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text(featureDescription)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    
                    HStack(spacing: 6) {
                        Text("PRO")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        LinearGradient(
                            colors: [.accentColor, .accentColor.opacity(0.8)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
                    
                    Button {
                        openAppStore()
                    } label: {
                        HStack(spacing: 6) {
                            Text(String(localized: "pro.learn_more", comment: "Learn more button for Pro features"))
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
                .padding(32)
                .frame(maxWidth: 480)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(format: String(localized: "pro.accessibility.feature_fmt", comment: "Pro feature accessibility label"), featureName))
    }
    
    private func openAppStore() {
        guard let url = ExternalLinks.url(for: campaign) else { return }
        NSWorkspace.shared.open(url)
    }
}

extension ProFeaturePlaceholderView where CustomSkeleton == ProFeatureScreenshotPlaceholder {
    init(
        featureName: String,
        featureDescription: String,
        featureIcon: String,
        campaign: ExternalDestination = .appStoreCampaignPreviewLock
    ) {
        self.featureName = featureName
        self.featureDescription = featureDescription
        self.featureIcon = featureIcon
        self.campaign = campaign
        self.customSkeleton = { ProFeatureScreenshotPlaceholder(systemImage: featureIcon) }
    }
}

struct MenuBarFeaturePreviewRow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "menubar.rectangle")
                    .foregroundColor(.blue)
                    .frame(width: 20)

                Text(String(localized: "settings.features.menubar_label", comment: "Menu bar icon feature toggle label"))
                    .font(.body)

                Spacer()

                // Toggle("", isOn: .constant(false))
                //    .labelsHidden()
                //    .disabled(true)
                //    .accessibilityHidden(true)
                ProBadge()
            }

            Text(String(localized: "settings.features.menubar_description", comment: "Description of menu bar icon feature"))
                .font(.callout)
                .foregroundColor(.secondary)

            Button {
                guard let url = ExternalLinks.url(for: .appStore) else { return }
                NSWorkspace.shared.open(url)
            } label: {
                HStack(spacing: 6) {
                    Text(String(localized: "pro.learn_more", comment: "Learn more button for Pro features"))
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                }
            }
            .buttonStyle(.link)
            .font(.callout)
        }
        .padding(.vertical, 4)
    }
}

struct ProFeatureScreenshotPlaceholder: View {
    let systemImage: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(backgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.08), radius: 18, y: 8)

            VStack(spacing: 14) {
                HStack(spacing: 8) {
                    Circle().fill(Color.red.opacity(0.75)).frame(width: 8, height: 8)
                    Circle().fill(Color.yellow.opacity(0.75)).frame(width: 8, height: 8)
                    Circle().fill(Color.green.opacity(0.75)).frame(width: 8, height: 8)
                    Spacer()
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.12))
                        .frame(width: 72, height: 8)
                }

                HStack(spacing: 14) {
                    Image(systemName: systemImage)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.blue)
                        .frame(width: 42, height: 42)
                        .background(Circle().fill(Color.blue.opacity(0.12)))

                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.primary.opacity(0.30))
                            .frame(width: 138, height: 10)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.primary.opacity(0.14))
                            .frame(width: 192, height: 8)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.primary.opacity(0.10))
                            .frame(width: 154, height: 8)
                    }

                    Spacer()
                }

                VStack(spacing: 8) {
                    previewLine(widthRatio: 0.92)
                    previewLine(widthRatio: 0.78)
                    previewLine(widthRatio: 0.86)
                }
            }
            .padding(18)
        }
    }

    private var backgroundColor: Color {
        colorScheme == .dark
            ? Color(red: 0.13, green: 0.14, blue: 0.16)
            : Color(red: 0.96, green: 0.97, blue: 0.98)
    }

    private func previewLine(widthRatio: CGFloat) -> some View {
        GeometryReader { geometry in
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.10))
                    .frame(width: geometry.size.width * widthRatio, height: 9)
                Spacer(minLength: 0)
            }
        }
        .frame(height: 9)
    }
}

struct TimelineSkeletonView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                // Section 1 header
                sectionHeader
                
                // Section 1 rows
                timelineRow(titleWidth: 0.65, subtitleWidth: 0.48, markerOpacity: 0.30)
                timelineRow(titleWidth: 0.55, subtitleWidth: 0.40, markerOpacity: 0.22, showBadge: true)
                
                Spacer().frame(height: 12)

                // Section 2 header
                sectionHeader
                
                // Section 2 rows
                timelineRow(titleWidth: 0.70, subtitleWidth: 0.52, markerOpacity: 0.18)
                timelineRow(titleWidth: 0.60, subtitleWidth: 0.44, markerOpacity: 0.30)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.primary.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
            )
    }

    private var sectionHeader: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.primary.opacity(0.20))
                .frame(width: 40, height: 8)

            Rectangle()
                .fill(Color.primary.opacity(0.14))
                .frame(height: 1)
        }
        .padding(.bottom, 8)
    }

    private func timelineRow(
        titleWidth: CGFloat,
        subtitleWidth: CGFloat,
        markerOpacity: Double,
        showBadge: Bool = false
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            // Time column
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.primary.opacity(0.20))
                .frame(width: 78, height: 8)

            // Track marker
            Circle()
                .fill(Color.primary.opacity(markerOpacity))
                .frame(width: 12, height: 12)

            // Event card
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.25))
                    .frame(width: 16, height: 16)

                VStack(alignment: .leading, spacing: 5) {
                    GeometryReader { geo in
                        HStack(spacing: 0) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.primary.opacity(0.40))
                                .frame(width: geo.size.width * titleWidth, height: 9)
                            Spacer(minLength: 0)
                        }
                    }
                    .frame(height: 9)

                    GeometryReader { geo in
                        HStack(spacing: 0) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.primary.opacity(0.22))
                                .frame(width: geo.size.width * subtitleWidth, height: 7)
                            Spacer(minLength: 0)
                        }
                    }
                    .frame(height: 7)
                }

                Spacer(minLength: 8)

                if showBadge {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.10))
                        .frame(width: 56, height: 22)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.primary.opacity(0.08))
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.06 : 0.035), radius: 6, y: 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    )
            )
        }
        .frame(minHeight: 46, alignment: .top)
        .padding(.bottom, 6)
    }
}

struct StatisticsSkeletonView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            summaryCard
            metricGrid
            distributionCard
        }
    }

    private var summaryCard: some View {
        card {
            VStack(alignment: .leading, spacing: 8) {
                line(widthRatio: 0.30, height: 10, opacity: 0.28)
                line(widthRatio: 0.46, height: 8, opacity: 0.16)
                line(widthRatio: 0.38, height: 7, opacity: 0.12)
            }
        }
    }

    private var metricGrid: some View {
        HStack(spacing: 12) {
            metricCell
            metricCell
            metricCell
        }
    }

    private var metricCell: some View {
        VStack(alignment: .leading, spacing: 6) {
            line(widthRatio: 0.55, height: 7, opacity: 0.14)
            line(widthRatio: 0.40, height: 12, opacity: 0.30)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardShape)
    }

    private var distributionCard: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                line(widthRatio: 0.26, height: 10, opacity: 0.28)
                line(widthRatio: 0.86, height: 8, opacity: 0.16)
                line(widthRatio: 0.68, height: 8, opacity: 0.12)
                line(widthRatio: 0.74, height: 8, opacity: 0.10)
            }
        }
    }

    private func card(@ViewBuilder content: () -> some View) -> some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardShape)
    }

    private var cardShape: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.primary.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }

    private func line(widthRatio: CGFloat, height: CGFloat, opacity: Double) -> some View {
        GeometryReader { geometry in
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.primary.opacity(opacity))
                .frame(width: geometry.size.width * widthRatio, height: height)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: height)
    }
}

struct InsightsSkeletonView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusCard
            insightCard(iconOpacity: 0.28)
            insightCard(iconOpacity: 0.20)
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            line(widthRatio: 0.34, height: 10, opacity: 0.28)
            line(widthRatio: 0.60, height: 8, opacity: 0.16)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardShape)
    }

    private func insightCard(iconOpacity: Double) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(iconOpacity))
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 6) {
                line(widthRatio: 0.50, height: 9, opacity: 0.26)
                line(widthRatio: 0.70, height: 7, opacity: 0.14)
            }

            Spacer(minLength: 8)

            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.10))
                .frame(width: 56, height: 22)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardShape)
    }

    private var cardShape: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.primary.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }

    private func line(widthRatio: CGFloat, height: CGFloat, opacity: Double) -> some View {
        GeometryReader { geometry in
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.primary.opacity(opacity))
                .frame(width: geometry.size.width * widthRatio, height: height)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: height)
    }
}

struct WiFiCallingSkeletonView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusCard
            carrierCard
            probeCard
        }
    }

    private var statusCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.primary.opacity(0.10)))

            VStack(alignment: .leading, spacing: 6) {
                line(widthRatio: 0.34, height: 10, opacity: 0.28)
                line(widthRatio: 0.64, height: 8, opacity: 0.14)
            }

            Spacer(minLength: 8)

            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.10))
                .frame(width: 58, height: 22)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardShape)
    }

    private var carrierCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                line(widthRatio: 0.28, height: 9, opacity: 0.24)
                line(widthRatio: 0.52, height: 8, opacity: 0.14)
            }

            Spacer(minLength: 8)

            RoundedRectangle(cornerRadius: 5)
                .fill(Color.primary.opacity(0.12))
                .frame(width: 86, height: 26)
                .overlay(alignment: .trailing) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.trailing, 8)
                }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardShape)
    }

    private var probeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            line(widthRatio: 0.30, height: 10, opacity: 0.26)
            probeRow
            probeRow
            probeRow
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardShape)
    }

    private var probeRow: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.primary.opacity(0.16))
                .frame(width: 8, height: 8)
            line(widthRatio: 0.46, height: 8, opacity: 0.16)
            Spacer(minLength: 8)
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.primary.opacity(0.10))
                .frame(width: 42, height: 8)
        }
    }

    private var cardShape: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.primary.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }

    private func line(widthRatio: CGFloat, height: CGFloat, opacity: Double) -> some View {
        GeometryReader { geometry in
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.primary.opacity(opacity))
                .frame(width: geometry.size.width * widthRatio, height: height)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: height)
    }
}

struct RecordingSkeletonView: View {
    var body: some View {
        VStack(spacing: 0) {
            // Signal info card
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.primary.opacity(0.30))
                    .frame(width: 6, height: 6)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.primary.opacity(0.40))
                    .frame(width: 52, height: 9)
                Spacer()
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.primary.opacity(0.18))
                    .frame(width: 72, height: 7)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            // Status bar
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.22))
                        .frame(width: 28, height: 8)
                }
                HStack(spacing: 4) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.22))
                        .frame(width: 40, height: 8)
                }
                Spacer()
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.18))
                    .frame(width: 44, height: 20)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            // Chart area
            GeometryReader { geo in
                Path { path in
                    let w = geo.size.width
                    let h = geo.size.height
                    path.move(to: CGPoint(x: 0, y: h * 0.5))
                    path.addCurve(
                        to: CGPoint(x: w * 0.5, y: h * 0.3),
                        control1: CGPoint(x: w * 0.15, y: h * 0.2),
                        control2: CGPoint(x: w * 0.35, y: h * 0.6)
                    )
                    path.addCurve(
                        to: CGPoint(x: w, y: h * 0.4),
                        control1: CGPoint(x: w * 0.65, y: h * 0.05),
                        control2: CGPoint(x: w * 0.85, y: h * 0.55)
                    )
                }
                .stroke(Color.primary.opacity(0.20), lineWidth: 1.5)
            }
            .frame(height: 80)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            Divider()

            // Table rows
            VStack(spacing: 0) {
                tableRow
                Divider().padding(.leading, 16)
                tableRow
                Divider().padding(.leading, 16)
                tableRow
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var tableRow: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.primary.opacity(0.20))
                .frame(width: 90, height: 8)
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.primary.opacity(0.14))
                .frame(width: 52, height: 8)
            Spacer()
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.primary.opacity(0.16))
                .frame(width: 36, height: 8)
        }
        .padding(.horizontal, 16)
        .frame(height: 28)
    }
}
