import Foundation

public enum ProInterestCategory: String, CaseIterable, Codable, Equatable, Sendable {
    case longTermMonitoring
    case spectrumRecording
    case advancedDiagnostics
    case generalPro
}

struct ProInterestVisit: Codable, Hashable, Sendable {
    let category: ProInterestCategory
    let day: String
}

/// Persisted lifecycle-guidance state. The struct owns its invariants both on live
/// mutation (`recordActiveDay`) and on restore (the normalized initializer),
/// so corrupted storage can never violate them.
struct GuidanceState: Equatable, Sendable {
    static let maxActiveDayCount = 120

    var firstLaunchDate: Date?
    private(set) var activeDays: [String]
    var meaningfulCompletionCount: Int
    var lastInvitationDate: Date?
    var invitationPresentationCount: Int
    var invitationDismissalCount: Int
    var invitationsDisabled: Bool
    var invitationPresentationDates: [Date]
    var lastInvitationLaterDate: Date?
    var lastPurchaseExplorationDate: Date?
    var lastAcceleratedFollowUpDate: Date?
    var lastAcceleratedFollowUpExplorationDate: Date?
    var proInterestVisits: [ProInterestVisit]
    var lastReviewRequestDate: Date?
    var lastReviewRequestVersion: String?

    /// Restore/creation initializer. Normalizes `activeDays` (filter invalid
    /// keys, dedupe, sort, cap at `maxActiveDayCount`) so persisted or damaged
    /// data can never violate the state invariants.
    public init(
        firstLaunchDate: Date? = nil,
        activeDays: [String] = [],
        meaningfulCompletionCount: Int = 0,
        lastInvitationDate: Date? = nil,
        invitationPresentationCount: Int = 0,
        invitationDismissalCount: Int = 0,
        invitationsDisabled: Bool = false,
        lastReviewRequestDate: Date? = nil,
        lastReviewRequestVersion: String? = nil,
        invitationPresentationDates: [Date] = [],
        lastInvitationLaterDate: Date? = nil,
        lastPurchaseExplorationDate: Date? = nil,
        lastAcceleratedFollowUpDate: Date? = nil,
        lastAcceleratedFollowUpExplorationDate: Date? = nil,
        proInterestVisits: [ProInterestVisit] = []
    ) {
        self.firstLaunchDate = firstLaunchDate
        self.activeDays = Self.normalizedActiveDays(activeDays)
        self.meaningfulCompletionCount = meaningfulCompletionCount
        self.lastInvitationDate = lastInvitationDate
        self.invitationPresentationCount = invitationPresentationCount
        self.invitationDismissalCount = invitationDismissalCount
        self.invitationsDisabled = invitationsDisabled
        self.invitationPresentationDates = Array(invitationPresentationDates.sorted().suffix(20))
        self.lastInvitationLaterDate = lastInvitationLaterDate
        self.lastPurchaseExplorationDate = lastPurchaseExplorationDate
        self.lastAcceleratedFollowUpDate = lastAcceleratedFollowUpDate
        self.lastAcceleratedFollowUpExplorationDate = lastAcceleratedFollowUpExplorationDate
        self.proInterestVisits = Self.normalizedInterestVisits(proInterestVisits)
        self.lastReviewRequestDate = lastReviewRequestDate
        self.lastReviewRequestVersion = lastReviewRequestVersion
    }

    /// Records a distinct local calendar day with the injected calendar.
    /// Appends, deduplicates, sorts, and truncates to `maxActiveDayCount`.
    mutating func recordActiveDay(at date: Date, calendar: Calendar) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else {
            return
        }
        let key = String(format: "%04d-%02d-%02d", year, month, day)
        if !activeDays.contains(key) {
            activeDays.append(key)
            activeDays.sort()
        }
        if activeDays.count > Self.maxActiveDayCount {
            activeDays.removeFirst(activeDays.count - Self.maxActiveDayCount)
        }
    }

    mutating func recordProInterest(_ category: ProInterestCategory, at date: Date, calendar: Calendar) {
        let key = Self.dayKey(for: date, calendar: calendar)
        guard !proInterestVisits.contains(where: { $0.category == category && $0.day == key }) else { return }
        proInterestVisits.append(ProInterestVisit(category: category, day: key))
        proInterestVisits = Self.normalizedInterestVisits(proInterestVisits)
    }

    mutating func recordInvitationPresentation(at date: Date) {
        invitationPresentationDates.append(date)
        invitationPresentationDates = Array(invitationPresentationDates.sorted().suffix(20))
    }

    mutating func pruneLocalMarketingState(now: Date, calendar: Calendar) {
        let today = calendar.startOfDay(for: now)
        guard let oldest = calendar.date(byAdding: .day, value: -13, to: today) else { return }
        let oldestKey = Self.dayKey(for: oldest, calendar: calendar)
        proInterestVisits = proInterestVisits.filter { $0.day >= oldestKey }
        if let lastPurchaseExplorationDate,
           GuidancePolicy.localDaysBetween(lastPurchaseExplorationDate, now: now, calendar: calendar) >= 14 {
            self.lastPurchaseExplorationDate = nil
        }
    }

    static func dayKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else { return "" }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private static func normalizedInterestVisits(_ visits: [ProInterestVisit]) -> [ProInterestVisit] {
        let valid = visits.filter { isValidDayKey($0.day) }
        let unique = Array(Set(valid)).sorted {
            $0.day == $1.day ? $0.category.rawValue < $1.category.rawValue : $0.day < $1.day
        }
        return Array(unique.suffix(ProInterestCategory.allCases.count * 14))
    }

    /// Returns true when `key` matches `YYYY-MM-DD` and forms a real Gregorian
    /// calendar date. The round-trip check rejects impossible dates such as
    /// `2026-02-30` and `2026-13-01`.
    static func isValidDayKey(_ key: String) -> Bool {
        guard key.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else {
            return false
        }
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else {
            return false
        }
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        guard let date = gregorian.date(from: components) else {
            return false
        }
        let roundTrip = gregorian.dateComponents([.year, .month, .day], from: date)
        return roundTrip.year == parts[0] && roundTrip.month == parts[1] && roundTrip.day == parts[2]
    }

    private static func normalizedActiveDays(_ keys: [String]) -> [String] {
        let unique = Array(Set(keys.filter(isValidDayKey))).sorted()
        if unique.count > maxActiveDayCount {
            return Array(unique.suffix(maxActiveDayCount))
        }
        return unique
    }
}
