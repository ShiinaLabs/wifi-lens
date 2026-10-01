import Foundation
import Testing
@testable import WiFiLensCore
@testable import WiFi_Lens

@MainActor
struct GuidanceStateStoreTests {
    // MARK: - Store behavior

    @Test func emptyLoadReturnsZeroValues() {
        let defaults = makeDefaults(suite: "GuidanceStateStoreTests.empty")

        let state = UserDefaultsGuidanceStateStore(defaults: defaults).load()

        #expect(state.firstLaunchDate == nil)
        #expect(state.activeDays.isEmpty)
        #expect(state.meaningfulCompletionCount == 0)
        #expect(state.lastInvitationDate == nil)
        #expect(state.invitationPresentationCount == 0)
        #expect(state.invitationDismissalCount == 0)
        #expect(state.invitationsDisabled == false)
        #expect(state.lastReviewRequestDate == nil)
        #expect(state.lastReviewRequestVersion == nil)
    }

    @Test func fullRoundTripOfEveryField() {
        let defaults = makeDefaults(suite: "GuidanceStateStoreTests.roundTrip")
        let store = UserDefaultsGuidanceStateStore(defaults: defaults)
        let original = GuidanceState(
            firstLaunchDate: date(2026, 7, 1, hour: 9, calendar: utcCalendar),
            activeDays: ["2026-07-01", "2026-07-02"],
            meaningfulCompletionCount: 7,
            lastInvitationDate: date(2026, 7, 15, hour: 9, calendar: utcCalendar),
            invitationPresentationCount: 2,
            invitationDismissalCount: 1,
            invitationsDisabled: true,
            lastReviewRequestDate: date(2026, 8, 1, hour: 9, calendar: utcCalendar),
            lastReviewRequestVersion: "2.1.0"
        )

        store.save(original)

        #expect(store.load() == original)
    }

    @Test func savingNilOptionalsClearsThem() {
        let defaults = makeDefaults(suite: "GuidanceStateStoreTests.missingOptionals")
        let store = UserDefaultsGuidanceStateStore(defaults: defaults)
        store.save(
            GuidanceState(
                firstLaunchDate: date(2026, 7, 1, calendar: utcCalendar),
                lastInvitationDate: date(2026, 7, 15, calendar: utcCalendar),
                lastReviewRequestDate: date(2026, 8, 1, calendar: utcCalendar),
                lastReviewRequestVersion: "2.1.0"
            )
        )

        store.save(GuidanceState(meaningfulCompletionCount: 3))

        let loaded = store.load()
        #expect(loaded.firstLaunchDate == nil)
        #expect(loaded.lastInvitationDate == nil)
        #expect(loaded.lastReviewRequestDate == nil)
        #expect(loaded.lastReviewRequestVersion == nil)
        #expect(loaded.meaningfulCompletionCount == 3)
    }

    @Test func saveReplacesPreviousValues() {
        let defaults = makeDefaults(suite: "GuidanceStateStoreTests.replace")
        let store = UserDefaultsGuidanceStateStore(defaults: defaults)

        store.save(GuidanceState(meaningfulCompletionCount: 1))
        store.save(GuidanceState(meaningfulCompletionCount: 9, invitationsDisabled: true))

        let loaded = store.load()
        #expect(loaded.meaningfulCompletionCount == 9)
        #expect(loaded.invitationsDisabled == true)
    }

    @Test func userDefaultsSuitesAreIsolated() {
        let storeA = UserDefaultsGuidanceStateStore(
            defaults: makeDefaults(suite: "GuidanceStateStoreTests.isolationA")
        )
        let storeB = UserDefaultsGuidanceStateStore(
            defaults: makeDefaults(suite: "GuidanceStateStoreTests.isolationB")
        )

        storeA.save(GuidanceState(meaningfulCompletionCount: 5))

        #expect(storeB.load().meaningfulCompletionCount == 0)
        #expect(storeA.load().meaningfulCompletionCount == 5)
    }

    @Test func inMemoryStoreReturnsInitialStateAndReplacesOnSave() {
        let initial = GuidanceState(meaningfulCompletionCount: 2)
        let store = InMemoryGuidanceStateStore(initial: initial)

        #expect(store.load() == initial)

        let replacement = GuidanceState(meaningfulCompletionCount: 8)
        store.save(replacement)

        #expect(store.load() == replacement)
    }

    // MARK: - State invariants

    @Test func sameLocalDayRecordsOnce() {
        var state = GuidanceState()

        state.recordActiveDay(at: date(2026, 8, 5, hour: 8, minute: 30, calendar: utcCalendar), calendar: utcCalendar)
        state.recordActiveDay(at: date(2026, 8, 5, hour: 23, minute: 30, calendar: utcCalendar), calendar: utcCalendar)

        #expect(state.activeDays == ["2026-08-05"])
    }

    @Test func consecutiveLocalDaysRecordTwoDays() {
        var state = GuidanceState()

        state.recordActiveDay(at: date(2026, 8, 5, hour: 23, minute: 59, calendar: utcCalendar), calendar: utcCalendar)
        state.recordActiveDay(at: date(2026, 8, 6, hour: 0, minute: 1, calendar: utcCalendar), calendar: utcCalendar)

        #expect(state.activeDays == ["2026-08-05", "2026-08-06"])
    }

    @Test func localCalendarDecidesTheDayBoundary() {
        // 2026-08-05T16:30Z is 2026-08-06T01:30 in Asia/Tokyo.
        let instant = date(2026, 8, 5, hour: 16, minute: 30, calendar: utcCalendar)

        var utcState = GuidanceState()
        utcState.recordActiveDay(at: instant, calendar: utcCalendar)
        #expect(utcState.activeDays == ["2026-08-05"])

        var tokyoState = GuidanceState()
        tokyoState.recordActiveDay(at: instant, calendar: tokyoCalendar)
        #expect(tokyoState.activeDays == ["2026-08-06"])
    }

    @Test func activeDayHistoryIsCappedAt120KeepingNewest() {
        let base = date(2026, 1, 1, calendar: utcCalendar)
        var state = GuidanceState()

        for day in 0..<130 {
            let d = utcCalendar.date(byAdding: .day, value: day, to: base)!
            state.recordActiveDay(at: d, calendar: utcCalendar)
        }

        #expect(state.activeDays.count == 120)
        #expect(state.activeDays.first == "2026-01-11")
        #expect(state.activeDays.last == "2026-05-10")
    }

    // MARK: - Restore normalization

    @Test func restoreNormalizesDuplicatesOrderAndCap() {
        let base = date(2026, 1, 1, calendar: utcCalendar)
        var keys: [String] = []
        for day in (0..<130).reversed() {
            let d = utcCalendar.date(byAdding: .day, value: day, to: base)!
            keys.append(dayKey(for: d, calendar: utcCalendar))
        }

        let state = GuidanceState(activeDays: keys + keys)

        #expect(state.activeDays.count == 120)
        #expect(state.activeDays.first == "2026-01-11")
        #expect(state.activeDays.last == "2026-05-10")
        #expect(state.activeDays == Array(Set(state.activeDays)).sorted())
    }

    @Test func restoreFiltersInvalidDayKeys() {
        let state = GuidanceState(
            activeDays: ["2026-07-01", "foo", "2026-02-30", "2026-13-01", "26-8-5", "2026-07-02"]
        )

        #expect(state.activeDays == ["2026-07-01", "2026-07-02"])
    }

    @Test func storeLoadRepairsDamagedActiveDays() {
        let defaults = makeDefaults(suite: "GuidanceStateStoreTests.damagedLoad")
        defaults.set(["2026-07-03", "garbage", "2026-07-01", "2026-07-01", "2026-02-30"], forKey: "guidance.activeDays")
        defaults.set(999, forKey: "guidance.completionCount")

        let state = UserDefaultsGuidanceStateStore(defaults: defaults).load()

        #expect(state.activeDays == ["2026-07-01", "2026-07-03"])
        #expect(state.meaningfulCompletionCount == 999)
    }

    // MARK: - Helpers

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private var tokyoCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }

    private func makeDefaults(suite: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        hour: Int = 12,
        minute: Int = 0,
        calendar: Calendar
    ) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }

    private func dayKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year!, components.month!, components.day!)
    }
}
