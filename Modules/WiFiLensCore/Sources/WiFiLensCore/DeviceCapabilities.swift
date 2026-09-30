import IOKit

public enum DeviceCapabilities {
    public static var hasBattery: Bool {
        let matchDict = IOServiceMatching("AppleSmartBattery")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matchDict)
        if service == 0 { return false }
        IOObjectRelease(service)
        return true
    }

    public static var isPortable: Bool { hasBattery }
}
