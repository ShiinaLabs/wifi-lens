import SwiftUI

struct MACVendorDatabaseSettingsSection: View {
    let summary: MACVendorBundledDatabaseSummary?

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                availabilityContent
            }
            .padding(.vertical, 4)
        } header: {
            Text(String(localized: "settings.mac_vendor.header", comment: "MAC vendor database settings section heading"))
        } footer: {
            Text(String(localized: "settings.mac_vendor.footer_bundled", comment: "The bundled IEEE MAC vendor snapshot is not updated at runtime"))
        }
    }

    @ViewBuilder
    private var availabilityContent: some View {
        if let summary {
            statusRow(
                icon: "checkmark.circle.fill",
                status: String(localized: "settings.mac_vendor.status_bundled", comment: "Bundled MAC vendor database is available"),
                color: .green
            )
            installedDetailRows(summary)
        } else {
            statusRow(
                icon: "exclamationmark.triangle.fill",
                status: String(localized: "settings.mac_vendor.status_unavailable", comment: "MAC vendor database could not be loaded"),
                color: .secondary
            )
        }
    }

    private func statusRow(icon: String, status: String, color: Color) -> some View {
        LabeledContent(String(localized: "settings.mac_vendor.status_label", comment: "MAC vendor database status field label")) {
            Label(status, systemImage: icon)
                .foregroundStyle(color)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "settings.mac_vendor.status_label", comment: "MAC vendor database status field label"))
        .accessibilityValue(status)
    }

    @ViewBuilder
    private func installedDetailRows(_ summary: MACVendorBundledDatabaseSummary) -> some View {
        let source = String(localized: "settings.mac_vendor.source_ieee", comment: "Database source: bundled IEEE snapshot")
        let date = summary.sourceUpdatedDate?.formatted(date: .abbreviated, time: .omitted) ?? summary.sourceUpdatedAt
        let count = summary.totalRecordCount.formatted()

        LabeledContent(String(localized: "settings.mac_vendor.source_label", comment: "MAC vendor database source field label"), value: source)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "settings.mac_vendor.source_label", comment: "MAC vendor database source field label"))
            .accessibilityValue(source)

        LabeledContent(String(localized: "settings.mac_vendor.updated_label", comment: "IEEE MAC vendor data snapshot date field label"), value: date)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "settings.mac_vendor.updated_label", comment: "IEEE MAC vendor data snapshot date field label"))
            .accessibilityValue(date)

        LabeledContent(String(localized: "settings.mac_vendor.records_label", comment: "MAC vendor database record count field label"), value: count)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "settings.mac_vendor.records_label", comment: "MAC vendor database record count field label"))
            .accessibilityValue(count)
    }

}

#if DEBUG
private struct MACVendorDatabaseSettingsSectionPreview: View {
    var body: some View {
        Form {
            MACVendorDatabaseSettingsSection(summary: MACVendorBundledDatabase.load()?.summary)
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 480)
    }
}

#Preview("MAC vendor database settings") {
    MACVendorDatabaseSettingsSectionPreview()
}
#endif
