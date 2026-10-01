import Foundation

@MainActor
public protocol WiFiLensUpdateChecking: AnyObject {
    var automaticallyChecksForUpdates: Bool { get set }
    func checkForUpdates()
}
