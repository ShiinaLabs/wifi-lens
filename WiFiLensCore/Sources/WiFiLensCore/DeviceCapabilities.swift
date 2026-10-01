import IOKit

enum DeviceCapabilities {
    static var hasBattery: Bool {
        let matchDict = IOServiceMatching("AppleSmartBattery")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matchDict)
        if service == 0 { return false }
        IOObjectRelease(service)
        return true
    }

    static var isPortable: Bool { hasBattery }
}
