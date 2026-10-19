import SwiftUI

enum BuildConfig {
    case oss
    case pro

    static var current: BuildConfig {
        #if OSS
            .oss
        #elseif PRO
            .pro
        #else
            .oss
        #endif
    }
}

/// True when `-UITest` is present in launch arguments.
/// Use to skip behavior that interferes with UI testing (e.g. disabling sidebar items).
enum UITestMode {
    static let isActive: Bool = CommandLine.arguments.contains("-UITest")
}
