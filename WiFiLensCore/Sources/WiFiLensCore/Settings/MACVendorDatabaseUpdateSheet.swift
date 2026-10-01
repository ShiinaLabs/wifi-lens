import SwiftUI
import UniformTypeIdentifiers

enum MACVendorUpdateSource: String, CaseIterable, Identifiable {
    case automatic
    case manual

    var id: Self { self }

    var localizedLabel: String {
        switch self {
        case .automatic:
            String(localized: "settings.mac_vendor.update.source_automatic", comment: "Automatic IEEE download source option")
        case .manual:
            String(localized: "settings.mac_vendor.update.source_manual", comment: "Manual CSV import source option")
        }
    }
}

struct MACVendorDatabaseUpdateSheet: View {
    @Bindable var manager: MACVendorDatabaseManager
    @State private var ownerID: UUID
    @State private var source: MACVendorUpdateSource
    @State private var showsFileImporter = false
    @Environment(\.dismiss) private var dismiss

    init(
        manager: MACVendorDatabaseManager,
        initialSource: MACVendorUpdateSource = .automatic,
        ownerID: UUID = UUID()
    ) {
        self.manager = manager
        _source = State(initialValue: initialSource)
        _ownerID = State(initialValue: ownerID)
    }

    private var isBusy: Bool {
        manager.operation != .idle
    }

    private var ownedOperation: MACVendorDatabaseOperation {
        manager.operation(for: ownerID)
    }

    private var blocksDismissal: Bool {
        switch ownedOperation {
        case .installing, .clearing:
            true
        case .idle, .downloading, .readingFiles, .validating:
            false
        }
    }

    private var canImport: Bool {
        guard let counts = pendingManualImport?.registryCounts else { return false }
        return MACVendorRegistry.allCases.allSatisfy { counts[$0] != nil }
    }

    private var pendingManualImport: MACVendorDatabaseSummary? {
        manager.pendingManualImport(for: ownerID)
    }

    private var presentedError: MACVendorDatabaseError? {
        manager.presentedError(for: ownerID)
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { presentedError != nil },
            set: { isPresented in
                if !isPresented {
                    manager.dismissPresentedError(ownerID: ownerID)
                }
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "settings.mac_vendor.update.title", comment: "MAC vendor database update sheet title"))
                    .font(.title3.weight(.semibold))

                HStack {
                    Spacer(minLength: 0)
                    Picker(
                        String(localized: "settings.mac_vendor.update.source_label", comment: "MAC vendor database update source picker label"),
                        selection: $source
                    ) {
                        ForEach(MACVendorUpdateSource.allCases) { option in
                            Text(option.localizedLabel).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 300)
                    .disabled(isBusy)
                    .accessibilityLabel(String(localized: "settings.mac_vendor.update.source_label", comment: "MAC vendor database update source picker label"))
                    .accessibilityValue(source.localizedLabel)
                    .accessibilityIdentifier("settings-mac-vendor-source-picker")
                    Spacer(minLength: 0)
                }
            }
            .padding(20)

            Divider()

            ScrollView {
                Group {
                    switch source {
                    case .automatic:
                        automaticContent
                    case .manual:
                        manualContent
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }

            Divider()
            footer
                .padding(16)
        }
        .frame(width: 500, height: 520)
        .interactiveDismissDisabled(blocksDismissal)
        .fileImporter(
            isPresented: $showsFileImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: true
        ) { result in
            guard case let .success(urls) = result else { return }
            Task { await manager.prepareManualImport(urls: urls, ownerID: ownerID) }
        }
        .alert(
            presentedError?.localizedTitle
                ?? String(localized: "settings.mac_vendor.error.title", comment: "Generic MAC vendor database error title"),
            isPresented: errorIsPresented,
            presenting: presentedError
        ) { _ in
            Button(String(localized: "common.action.dismiss", comment: "Dismiss an error alert"), role: .cancel) {}
        } message: { error in
            Text(error.localizedMessage)
        }
        .onDisappear {
            let handle = manager.cancelCurrentOperation(ownerID: ownerID)
            Task {
                if let handle {
                    await manager.waitForCancellation(handle)
                }
                manager.discardPreparedManualImport(ownerID: ownerID)
            }
        }
    }

    private var automaticContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "settings.mac_vendor.update.automatic_title", comment: "Heading for automatic IEEE registry download"))
                    .font(.headline)
                Text(String(localized: "settings.mac_vendor.update.automatic_description", comment: "Description of downloading the IEEE registry database"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                informationRow(
                    icon: "arrow.down.circle",
                    text: String(localized: "settings.mac_vendor.update.download_size", comment: "Approximate IEEE registry download size: 5.6 MB")
                )
                informationRow(
                    icon: "lock.macwindow",
                    text: String(localized: "settings.mac_vendor.update.local_scan_privacy", comment: "Privacy statement: BSSIDs, SSIDs, and scan data never leave this Mac during the IEEE download")
                )
                informationRow(
                    icon: "network",
                    text: String(localized: "settings.mac_vendor.update.ip_metadata", comment: "Privacy statement: IEEE receives standard IP request metadata")
                )
                informationRow(
                    icon: "building.columns",
                    text: String(localized: "settings.mac_vendor.update.no_endorsement", comment: "Statement that IEEE does not endorse WiFi Lens")
                )
            }
        }
    }

    private var manualContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "settings.mac_vendor.update.manual_title", comment: "Heading for manual IEEE CSV import"))
                    .font(.headline)
                Text(String(localized: "settings.mac_vendor.update.manual_description", comment: "Instructions to download and select all four IEEE CSV registry files"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(MACVendorRegistry.allCases, id: \.self) { registry in
                    Link(destination: registry.downloadURL) {
                        HStack(spacing: 8) {
                            Text(registry.rawValue)
                                .font(.body.monospaced())
                            Spacer()
                            Text(registry.downloadURL.lastPathComponent)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .accessibilityHidden(true)
                        }
                    }
                    .accessibilityLabel(
                        String(
                            format: String(localized: "settings.mac_vendor.update.registry_download_accessibility", comment: "Accessibility label for a registry CSV download link; registry name argument"),
                            registry.rawValue
                        )
                    )
                }
            }

            Button(String(localized: "settings.mac_vendor.update.choose_files", comment: "Choose exactly four IEEE registry CSV files action")) {
                showsFileImporter = true
            }
            .disabled(isBusy)
            .accessibilityLabel(String(localized: "settings.mac_vendor.update.choose_files", comment: "Choose exactly four IEEE registry CSV files action"))
            .accessibilityHint(String(localized: "settings.mac_vendor.update.choose_files_hint", comment: "Choose the MA-L, MA-M, MA-S, and IAB CSV files"))
            .accessibilityIdentifier("settings-mac-vendor-choose-files-button")

            validationSummary
        }
    }

    private var validationSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "settings.mac_vendor.update.validation_header", comment: "Manual registry file validation summary heading"))
                .font(.subheadline.weight(.semibold))

            VStack(spacing: 6) {
                ForEach(MACVendorRegistry.allCases, id: \.self) { registry in
                    validationRow(for: registry)
                }
            }

            if canImport, let summary = pendingManualImport {
                Text(
                    String(
                        format: String(localized: "settings.mac_vendor.update.validation_ready", comment: "All four files are valid and ready to import; total record count argument"),
                        summary.totalRecordCount.formatted()
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(String(localized: "settings.mac_vendor.update.validation_ready_accessibility", comment: "Validation succeeded for all four registry files"))
                .accessibilityValue(summary.totalRecordCount.formatted())
            }
        }
    }

    private func validationRow(for registry: MACVendorRegistry) -> some View {
        let count = pendingManualImport?.registryCounts[registry]
        let statusText: String
        if let count {
            statusText = String(
                format: String(localized: "settings.mac_vendor.update.registry_valid", comment: "Validated registry row with registry name and record count arguments"),
                registry.rawValue,
                count.formatted()
            )
        } else {
            statusText = String(
                format: String(localized: "settings.mac_vendor.update.registry_waiting", comment: "Registry row waiting for validation; registry name argument"),
                registry.rawValue
            )
        }

        return HStack(spacing: 8) {
            Image(systemName: count == nil ? "circle.dotted" : "checkmark.circle.fill")
                .foregroundStyle(count == nil ? Color.secondary : Color.green)
                .accessibilityHidden(true)
            Text(statusText)
                .font(.callout)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(registry.rawValue)
        .accessibilityValue(
            count.map {
                String(
                    format: String(localized: "settings.mac_vendor.update.registry_valid_value", comment: "Accessibility value for a valid registry with record count argument"),
                    $0.formatted()
                )
            } ?? String(localized: "settings.mac_vendor.update.registry_waiting_value", comment: "Accessibility value for a registry awaiting validation")
        )
    }

    private func informationRow(icon: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon)
                .frame(width: 18)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button(String(localized: "common.action.cancel", comment: "Cancel and close the MAC vendor database update sheet"), role: .cancel) {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .disabled(blocksDismissal)
            .accessibilityHint(cancelAccessibilityHint)

            Spacer()

            operationProgress

            if !isBusy {
                switch source {
                case .automatic:
                    Button(String(localized: "settings.mac_vendor.update.download", comment: "Download and install MAC vendor registry data from IEEE")) {
                        downloadAndInstall()
                    }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("settings-mac-vendor-download-button")
                case .manual:
                    if canImport {
                        Button(String(localized: "settings.mac_vendor.update.import", comment: "Confirm import of the four validated registry files")) {
                            confirmManualImport()
                        }
                        .keyboardShortcut(.defaultAction)
                        .accessibilityHint(String(localized: "settings.mac_vendor.update.import_hint", comment: "Install the validated local registry database"))
                        .accessibilityIdentifier("settings-mac-vendor-import-button")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var operationProgress: some View {
        switch ownedOperation {
        case .idle:
            EmptyView()
        case let .downloading(completed, total):
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                VStack(alignment: .leading, spacing: 1) {
                    Text(String(localized: "settings.mac_vendor.update.downloading", comment: "Downloading IEEE registry files progress label"))
                    Text(
                        String(
                            format: String(localized: "settings.mac_vendor.update.progress_count", comment: "Completed and total registry file progress arguments"),
                            completed,
                            total
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                Text(String(localized: "settings.mac_vendor.update.downloading", comment: "Downloading IEEE registry files progress label"))
            )
            .accessibilityValue(
                String(
                    format: String(localized: "settings.mac_vendor.update.progress_accessibility_value", comment: "Accessible download progress with completed and total registry file count arguments"),
                    completed,
                    total
                )
            )
        case .readingFiles:
            indeterminateProgress(
                String(localized: "settings.mac_vendor.update.reading_files", comment: "Reading selected registry CSV files progress label")
            )
        case .validating:
            indeterminateProgress(
                String(localized: "settings.mac_vendor.update.validating", comment: "Validating registry CSV data progress label")
            )
        case .installing:
            indeterminateProgress(
                String(localized: "settings.mac_vendor.update.installing", comment: "Installing registry database progress label")
            )
        case .clearing:
            indeterminateProgress(
                String(localized: "settings.mac_vendor.update.clearing", comment: "Clearing registry database progress label")
            )
        }
    }

    private func indeterminateProgress(_ label: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }

    private var cancelAccessibilityHint: String {
        switch ownedOperation {
        case .downloading, .readingFiles, .validating:
            String(localized: "settings.mac_vendor.update.cancel_operation_hint", comment: "Cancel the current registry operation and close the sheet")
        case .idle, .installing, .clearing:
            String(localized: "settings.mac_vendor.update.cancel_hint", comment: "Discard any prepared import and close the sheet")
        }
    }

    private func downloadAndInstall() {
        let startingRevision = manager.databaseRevision
        Task {
            await manager.downloadAndInstall(ownerID: ownerID)
            if manager.databaseRevision != startingRevision {
                dismiss()
            }
        }
    }

    private func confirmManualImport() {
        let startingRevision = manager.databaseRevision
        Task {
            await manager.confirmManualImport(ownerID: ownerID)
            if manager.databaseRevision != startingRevision {
                dismiss()
            }
        }
    }
}

extension MACVendorDatabaseError {
    var localizedTitle: String {
        switch self {
        case .invalidHTTPStatus, .disallowedRedirect, .downloadFailed, .automaticDownloadFailed:
            String(localized: "settings.mac_vendor.error.download_title", comment: "IEEE registry download error title")
        case .fileReadFailed, .wrongFileCount, .fileTooLarge, .totalSizeExceeded, .invalidEncoding:
            String(localized: "settings.mac_vendor.error.files_title", comment: "Manual registry file selection or reading error title")
        case .malformedCSV, .missingColumns, .mixedRegistries, .duplicateRegistry, .missingRegistry,
             .invalidAssignment, .invalidOrganization, .tooFewRecords, .conflictingAssignment:
            String(localized: "settings.mac_vendor.error.validation_title", comment: "Registry CSV validation error title")
        case .unsupportedSchema, .persistenceFailure, .noPreparedImport:
            String(localized: "settings.mac_vendor.error.database_title", comment: "Local registry database error title")
        }
    }

    var localizedMessage: String {
        switch self {
        case let .wrongFileCount(expected, actual):
            String(format: String(localized: "settings.mac_vendor.error.wrong_file_count", comment: "Wrong registry CSV file count; expected and actual arguments"), expected, actual)
        case let .fileTooLarge(file, maximumBytes):
            String(format: String(localized: "settings.mac_vendor.error.file_too_large", comment: "Registry CSV exceeds size limit; file name and maximum byte size arguments"), file, ByteCountFormatter.string(fromByteCount: Int64(maximumBytes), countStyle: .file))
        case let .totalSizeExceeded(maximumBytes):
            String(format: String(localized: "settings.mac_vendor.error.total_size_exceeded", comment: "Selected registry CSV files exceed total size limit; maximum byte size argument"), ByteCountFormatter.string(fromByteCount: Int64(maximumBytes), countStyle: .file))
        case let .invalidEncoding(file):
            String(format: String(localized: "settings.mac_vendor.error.invalid_encoding", comment: "Registry CSV text encoding is unsupported; file name argument"), file)
        case let .malformedCSV(file):
            String(format: String(localized: "settings.mac_vendor.error.malformed_csv", comment: "Registry CSV is malformed; file name argument"), file)
        case let .missingColumns(file, columns):
            String(format: String(localized: "settings.mac_vendor.error.missing_columns", comment: "Registry CSV lacks required columns; file name and column list arguments"), file, columns.joined(separator: ", "))
        case let .mixedRegistries(file):
            String(format: String(localized: "settings.mac_vendor.error.mixed_registries", comment: "Registry CSV contains more than one registry type; file name argument"), file)
        case let .duplicateRegistry(registry):
            String(format: String(localized: "settings.mac_vendor.error.duplicate_registry", comment: "Two selected CSV files represent the same registry; registry name argument"), registry.rawValue)
        case let .missingRegistry(registry):
            String(format: String(localized: "settings.mac_vendor.error.missing_registry", comment: "A required registry CSV is missing; registry name argument"), registry.rawValue)
        case let .invalidAssignment(file, registry, assignment):
            String(format: String(localized: "settings.mac_vendor.error.invalid_assignment", comment: "Registry assignment is invalid; file, registry, and assignment arguments"), file, registry.rawValue, assignment)
        case let .invalidOrganization(file):
            String(format: String(localized: "settings.mac_vendor.error.invalid_organization", comment: "Registry CSV has an invalid organization field; file name argument"), file)
        case let .tooFewRecords(registry, minimum, actual):
            String(format: String(localized: "settings.mac_vendor.error.too_few_records", comment: "Registry contains too few valid records; registry, minimum, and actual arguments"), registry.rawValue, minimum, actual)
        case let .conflictingAssignment(prefix, prefixLength):
            String(format: String(localized: "settings.mac_vendor.error.conflicting_assignment", comment: "Registry data contains a conflicting prefix assignment; prefix and prefix length arguments"), prefix, prefixLength)
        case let .invalidHTTPStatus(registry, statusCode):
            String(format: String(localized: "settings.mac_vendor.error.http_status", comment: "IEEE registry download returned an invalid HTTP status; registry and status arguments"), registry.rawValue, statusCode)
        case let .disallowedRedirect(url):
            String(format: String(localized: "settings.mac_vendor.error.disallowed_redirect", comment: "IEEE registry download redirected to a disallowed address; URL argument"), url.absoluteString)
        case let .downloadFailed(registry):
            String(format: String(localized: "settings.mac_vendor.error.download_failed", comment: "IEEE registry download failed; registry name argument"), registry.rawValue)
        case .automaticDownloadFailed:
            String(localized: "settings.mac_vendor.error.automatic_download_failed", comment: "Automatic IEEE registry batch download failed")
        case let .fileReadFailed(file):
            String(format: String(localized: "settings.mac_vendor.error.file_read_failed", comment: "Selected registry CSV could not be read; file name argument"), file)
        case let .unsupportedSchema(version):
            String(format: String(localized: "settings.mac_vendor.error.unsupported_schema", comment: "Saved registry database uses an unsupported schema; version argument"), version)
        case .persistenceFailure:
            String(localized: "settings.mac_vendor.error.persistence_failure", comment: "Local registry database could not be saved, loaded, or removed")
        case .noPreparedImport:
            String(localized: "settings.mac_vendor.error.no_prepared_import", comment: "No validated manual registry import is ready")
        }
    }
}

#if DEBUG
@MainActor
enum MACVendorDatabasePreviewFactory {
    static func makeManager() -> MACVendorDatabaseManager {
        MACVendorDatabaseManager(
            resolver: MACVendorResolver(),
            service: MACVendorDatabasePreviewService(
                installedDatabase: makeDatabase(source: .ieeeDownload),
                manualDatabase: makeDatabase(source: .manualImport)
            )
        )
    }

    private static func makeDatabase(source: MACVendorDatabaseSource) -> MACVendorDatabase {
        let counts: [MACVendorRegistry: Int] = [
            .maL: 3,
            .maM: 2,
            .maS: 1,
            .iab: 1,
        ]
        let entries = [
            MACVendorEntry(prefix: "001122", prefixLength: 24, organization: "Example Networks"),
            MACVendorEntry(prefix: "001123", prefixLength: 24, organization: "Example Systems"),
            MACVendorEntry(prefix: "001124", prefixLength: 24, organization: "Example Labs"),
            MACVendorEntry(prefix: "0011223", prefixLength: 28, organization: "Example Mobile"),
            MACVendorEntry(prefix: "0011224", prefixLength: 28, organization: "Example Devices"),
            MACVendorEntry(prefix: "001122334", prefixLength: 36, organization: "Example Sensors"),
            MACVendorEntry(prefix: "001122335", prefixLength: 36, organization: "Example Instruments"),
        ]

        return MACVendorDatabase(
            schemaVersion: MACVendorDatabase.schemaVersion,
            createdAt: Date(timeIntervalSince1970: 1_753_238_400),
            source: source,
            registries: MACVendorRegistry.allCases.map { registry in
                MACVendorRegistryMetadata(
                    registry: registry,
                    validRecordCount: counts[registry] ?? 0,
                    sha256: "preview",
                    sourceURL: source == .ieeeDownload ? registry.downloadURL : nil
                )
            },
            entries: entries
        )
    }
}

private actor MACVendorDatabasePreviewService: MACVendorDatabaseServicing {
    private var installedDatabase: MACVendorDatabase?
    private let manualDatabase: MACVendorDatabase

    init(installedDatabase: MACVendorDatabase, manualDatabase: MACVendorDatabase) {
        self.installedDatabase = installedDatabase
        self.manualDatabase = manualDatabase
    }

    func load() async throws -> MACVendorDatabase? {
        installedDatabase
    }

    func download(
        createdAt: Date,
        progress: @Sendable (Int) async -> Void
    ) async throws -> MACVendorDatabase {
        for completed in 1...MACVendorRegistry.allCases.count {
            await progress(completed)
        }
        return installedDatabase ?? manualDatabase
    }

    func prepareManualImport(urls: [URL], createdAt: Date) async throws -> MACVendorDatabase {
        manualDatabase
    }

    func install(_ database: MACVendorDatabase) async throws {
        installedDatabase = database
    }

    func clear() async throws {
        installedDatabase = nil
    }
}

private struct MACVendorDatabaseUpdateSheetPreview: View {
    @State private var manager = MACVendorDatabasePreviewFactory.makeManager()
    @State private var ownerID = UUID()

    var body: some View {
        MACVendorDatabaseUpdateSheet(
            manager: manager,
            initialSource: .manual,
            ownerID: ownerID
        )
            .task {
                await manager.prepareManualImport(urls: [], ownerID: ownerID)
            }
    }
}

#Preview("MAC vendor database manual import") {
    MACVendorDatabaseUpdateSheetPreview()
}
#endif
