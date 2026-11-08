import SwiftUI

struct OpenSourceLicensesView: View {
    let identity: WiFiLensEditionIdentity
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selection: Selection?

    private enum Selection: Hashable {
        case component(String)
        case dataSource(String)
    }

    private var components: [OpenSourceComponent] {
        let all = OpenSourceLicenseCatalog.components(for: identity)
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    private var dataSources: [OpenSourceDataSource] {
        let all = OpenSourceLicenseCatalog.dataSources
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return all }
        return all.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
                || $0.provider.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                sidebar
                    .frame(width: 260)
                Divider()
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 760, height: 600)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("open-source-licenses")
        .onAppear(perform: selectFirstIfNeeded)
        .onChange(of: query) { _, _ in selectFirstIfNeeded() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(
                    String(
                        localized: "settings.about.licenses",
                        comment: "Open source licenses settings row and page title")
                )
                .font(.title2.weight(.semibold))
                Text(
                    String(
                        localized: "licenses.subtitle",
                        comment: "Open source licenses page subtitle")
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(String(localized: "common.action.dismiss", comment: "Dismiss an alert"))
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            TextField(
                String(localized: "licenses.search.placeholder", comment: "Search open source components"),
                text: $query
            )
            .textFieldStyle(.roundedBorder)
            .padding(12)
            .accessibilityIdentifier("open-source-licenses-search")

            if components.isEmpty && dataSources.isEmpty {
                emptyState
            } else {
                List(selection: $selection) {
                    if !components.isEmpty {
                        Section {
                            ForEach(components) { component in
                                componentRow(component)
                                    .tag(Selection.component(component.id))
                            }
                        } header: {
                            Text(
                                String(
                                    localized: "licenses.section.components",
                                    comment: "Open source components section header")
                            )
                        }
                    }

                    if !dataSources.isEmpty {
                        Section {
                            ForEach(dataSources) { source in
                                dataSourceRow(source)
                                    .tag(Selection.dataSource(source.id))
                            }
                        } header: {
                            Text(
                                String(
                                    localized: "licenses.section.data_sources",
                                    comment: "Third-party data sources section header")
                            )
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
            Text(String(localized: "licenses.empty", comment: "No open source components match the search"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
    }

    private func componentRow(_ component: OpenSourceComponent) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(component.name)
                .font(.body.weight(.medium))
            Text("\(component.version) · \(licenseLabel(component.licenses))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func dataSourceRow(_ source: OpenSourceDataSource) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(source.name)
                .font(.body.weight(.medium))
            Text(source.provider)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .component(let id):
            if let component = OpenSourceLicenseCatalog.components(for: identity).first(where: { $0.id == id }) {
                componentDetail(component)
            } else {
                emptyDetail
            }
        case .dataSource(let id):
            if let source = OpenSourceLicenseCatalog.dataSources.first(where: { $0.id == id }) {
                dataSourceDetail(source)
            } else {
                emptyDetail
            }
        case nil:
            emptyDetail
        }
    }

    private var emptyDetail: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(String(localized: "licenses.empty", comment: "No open source components match the search"))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func componentDetail(_ component: OpenSourceComponent) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(component.name)
                        .font(.title2.weight(.semibold))
                    Text(component.version)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 6) {
                    ForEach(component.licenses, id: \.self) { license in
                        Text(license.rawValue)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.secondary.opacity(0.12)))
                    }
                }

                if let copyright = component.copyright, !copyright.isEmpty {
                    Text(copyright)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let repositoryURL = component.repositoryURL {
                    Link(
                        String(localized: "licenses.repository", comment: "Repository link in license detail"),
                        destination: repositoryURL
                    )
                    .font(.callout)
                }

                Divider()

                ForEach(component.licenses, id: \.self) { license in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(license.rawValue)
                            .font(.headline)
                        Text(license.text)
                            .font(.callout)
                    }
                }

                if !component.additionalNotices.isEmpty {
                    Divider()
                    Text(
                        String(
                            localized: "licenses.section.additional_notices",
                            comment: "Additional license notices section header")
                    )
                    .font(.headline)
                    ForEach(Array(component.additionalNotices.enumerated()), id: \.offset) { _, notice in
                        Text(notice)
                            .font(.callout)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
    }

    private func dataSourceDetail(_ source: OpenSourceDataSource) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(source.name)
                    .font(.title2.weight(.semibold))
                Text(source.provider)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let url = source.url {
                    Link(source.provider, destination: url)
                        .font(.callout)
                }
                Divider()
                Text(source.note)
                    .font(.callout)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
    }

    private func licenseLabel(_ licenses: [OpenSourceLicense]) -> String {
        licenses.map(\.rawValue).joined(separator: " + ")
    }

    private func selectFirstIfNeeded() {
        let visibleComponents = Set(components.map { Selection.component($0.id) })
        let visibleDataSources = Set(dataSources.map { Selection.dataSource($0.id) })
        if let selection, visibleComponents.contains(selection) || visibleDataSources.contains(selection) {
            return
        }
        if let first = components.first {
            selection = .component(first.id)
        } else if let first = dataSources.first {
            selection = .dataSource(first.id)
        } else {
            selection = nil
        }
    }
}

#if DEBUG
    #Preview("Open Source Licenses") {
        OpenSourceLicensesView(identity: .openSource)
    }
#endif
