import Testing
@testable import WiFi_Lens

struct OverviewVisualStyleTests {

    @Test("System mode uses the world map when Reduce Motion is enabled")
    func systemModeUsesWorldMapWithReduceMotion() {
        #expect(OverviewVisualStyle.system.resolved(reduceMotion: true) == .worldMap)
    }

    @Test("System mode uses the globe when Reduce Motion is disabled")
    func systemModeUsesGlobeWithoutReduceMotion() {
        #expect(OverviewVisualStyle.system.resolved(reduceMotion: false) == .globe)
    }

    @Test("Explicit world map mode always uses the world map")
    func explicitWorldMapModeAlwaysUsesWorldMap() {
        #expect(OverviewVisualStyle.worldMap.resolved(reduceMotion: false) == .worldMap)
        #expect(OverviewVisualStyle.worldMap.resolved(reduceMotion: true) == .worldMap)
    }

    @Test("Explicit globe mode always uses the globe")
    func explicitGlobeModeAlwaysUsesGlobe() {
        #expect(OverviewVisualStyle.globe.resolved(reduceMotion: false) == .globe)
        #expect(OverviewVisualStyle.globe.resolved(reduceMotion: true) == .globe)
    }

    @Test("Unknown persisted values fall back to system mode")
    func unknownRawValueFallsBackToSystem() {
        #expect(OverviewVisualStyle(rawValue: "unknown") == nil)
        #expect(OverviewVisualStyle.fromPersistedValue("unknown") == .system)
    }
}
