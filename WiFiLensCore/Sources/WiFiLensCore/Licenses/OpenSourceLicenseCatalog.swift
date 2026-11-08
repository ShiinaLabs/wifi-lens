import Foundation

struct OpenSourceComponent: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let version: String
    let licenses: [OpenSourceLicense]
    let copyright: String?
    let repositoryURL: URL?
    let additionalNotices: [String]
    let editions: [WiFiLensEditionIdentity]
}

struct OpenSourceDataSource: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let provider: String
    let note: String
    let url: URL?
}

enum OpenSourceLicense: String, CaseIterable, Hashable, Sendable {
    case apache2 = "Apache-2.0"
    case mit = "MIT"
    case bsd2 = "BSD-2-Clause"
    case zlib = "Zlib"

    var text: String {
        switch self {
        case .apache2:
            OpenSourceLicenseTexts.apache2
        case .mit:
            OpenSourceLicenseTexts.mit
        case .bsd2:
            OpenSourceLicenseTexts.bsd2
        case .zlib:
            OpenSourceLicenseTexts.zlib
        }
    }
}

/// Components that link into the shipping app, ordered by display name.
///
/// This is the package set reachable from each edition's app target, not every
/// package resolved in `Package.resolved`. The AppStage family, SwiftNIO,
/// Swift Atomics, and Swift Collections are resolved by tooling but not linked
/// into either app, so they are intentionally absent.
enum OpenSourceLicenseCatalog {
    static let components: [OpenSourceComponent] = [
        OpenSourceComponent(
            id: "chart-lens",
            name: "ChartLens",
            version: "rev e2e00e5",
            licenses: [.apache2],
            copyright: nil,
            repositoryURL: URL(string: "https://github.com/ShiinaLabs/chart-lens"),
            additionalNotices: [],
            editions: [.openSource, .pro]
        ),
        OpenSourceComponent(
            id: "eventsource",
            name: "EventSource",
            version: "1.5.1",
            licenses: [.mit],
            copyright: "Copyright 2025 Mattt (https://mat.tt)",
            repositoryURL: URL(string: "https://github.com/mattt/eventsource"),
            additionalNotices: [],
            editions: [.openSource, .pro]
        ),
        OpenSourceComponent(
            id: "grdb.swift",
            name: "GRDB.swift",
            version: "7.11.1",
            licenses: [.mit],
            copyright: "Copyright (C) 2015-2025 Gwendal Roué",
            repositoryURL: URL(string: "https://github.com/groue/GRDB.swift"),
            additionalNotices: [],
            editions: [.pro]
        ),
        OpenSourceComponent(
            id: "hdrhistogram-swift",
            name: "HdrHistogram",
            version: "0.2.0",
            licenses: [.apache2],
            copyright: nil,
            repositoryURL: URL(string: "https://github.com/HdrHistogram/hdrhistogram-swift"),
            additionalNotices: [],
            editions: [.pro]
        ),
        OpenSourceComponent(
            id: "markdownkit",
            name: "MarkdownKit",
            version: "rev f399a66",
            licenses: [.mit],
            copyright: "Copyright (c) 2026 ShiinaLabs",
            repositoryURL: URL(string: "https://github.com/ShiinaLabs/MarkdownKit"),
            additionalNotices: [],
            editions: [.openSource, .pro]
        ),
        OpenSourceComponent(
            id: "swift-sdk",
            name: "MCP Swift SDK",
            version: "0.12.1",
            licenses: [.apache2, .mit],
            copyright: "Copyright (c) 2024-2025 Model Context Protocol a Series of LF Projects, LLC.",
            repositoryURL: URL(string: "https://github.com/modelcontextprotocol/swift-sdk"),
            additionalNotices: [OpenSourceLicenseTexts.swiftSDKDocumentationNotice],
            editions: [.openSource, .pro]
        ),
        OpenSourceComponent(
            id: "sparkle",
            name: "Sparkle",
            version: "2.10.0",
            licenses: [.mit, .bsd2, .zlib],
            copyright: """
                Copyright (c) 2006-2013 Andy Matuschak.
                Copyright (c) 2009-2013 Elgato Systems GmbH.
                Copyright (c) 2011-2014 Kornel Lesiński.
                Copyright (c) 2015-2017 Mayur Pawashe.
                Copyright (c) 2014 C.W. Betts.
                Copyright (c) 2014 Petroules Corporation.
                Copyright (c) 2014 Big Nerd Ranch.
                """,
            repositoryURL: URL(string: "https://github.com/sparkle-project/Sparkle"),
            additionalNotices: [OpenSourceLicenseTexts.sparkleExternalLicenses],
            editions: [.openSource]
        ),
        OpenSourceComponent(
            id: "splitview",
            name: "SplitView",
            version: "rev ed01704",
            licenses: [.mit],
            copyright: "Copyright (c) 2023 Steven G. Harris",
            repositoryURL: URL(string: "https://github.com/ShiinaLabs/SplitView"),
            additionalNotices: [],
            editions: [.openSource, .pro]
        ),
        OpenSourceComponent(
            id: "swift-numerics",
            name: "Swift Numerics",
            version: "1.1.1",
            licenses: [.apache2],
            copyright: nil,
            repositoryURL: URL(string: "https://github.com/apple/swift-numerics"),
            additionalNotices: [],
            editions: [.pro]
        ),
        OpenSourceComponent(
            id: "swift-system",
            name: "Swift System",
            version: "1.8.1",
            licenses: [.apache2],
            copyright: nil,
            repositoryURL: URL(string: "https://github.com/apple/swift-system"),
            additionalNotices: [],
            editions: [.openSource, .pro]
        ),
        OpenSourceComponent(
            id: "swift-log",
            name: "SwiftLog",
            version: "1.15.1",
            licenses: [.apache2],
            copyright: "Copyright 2018, 2019 The SwiftLog Project",
            repositoryURL: URL(string: "https://github.com/apple/swift-log"),
            additionalNotices: [OpenSourceLicenseTexts.swiftLogNotice],
            editions: [.openSource, .pro]
        ),
    ]

    static let dataSources: [OpenSourceDataSource] = [
        OpenSourceDataSource(
            id: "ieee-mac-vendor",
            name: "IEEE MAC Vendor Database",
            provider: "IEEE Registration Authority",
            note: """
                Registry data remains the property of the IEEE Standards Association and its registrants. \
                IEEE does not endorse WiFi Lens.
                """,
            url: URL(string: "https://standards.ieee.org/products-programs/regauth/")
        )
    ]

    static func components(for identity: WiFiLensEditionIdentity) -> [OpenSourceComponent] {
        components.filter { $0.editions.contains(identity) }
    }
}
