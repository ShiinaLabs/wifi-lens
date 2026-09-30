import Foundation

/// Persisted lifecycle-guidance state. The struct owns its invariants both on live
/// mutation (`recordActiveDay`) and on restore (the normalized initializer),
/// so corrupted storage can never violate them.
public struct GuidanceState: Equatable, Sendable {
    public static let maxActiveDayCount = 120

    public var firstLaunchDate: Date?
    public private(set) var activeDays: [String]
    public var meaningfulCompletionCount: Int
    public var lastInvitationDate: Date?
    public var invitationPresentationCount: Int
    public var invitationDismissalCount: Int
    public var invitationsDisabled: Bool
    public var lastReviewRequestDate: Date?
    public var lastReviewRequestVersion: String?

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
        lastReviewRequestVersion: String? = nil
    ) {
        self.firstLaunchDate = firstLaunchDate
        self.activeDays = Self.normalizedActiveDays(activeDays)
        self.meaningfulCompletionCount = meaningfulCompletionCount
        self.lastInvitationDate = lastInvitationDate
        self.invitationPresentationCount = invitationPresentationCount
        self.invitationDismissalCount = invitationDismissalCount
        self.invitationsDisabled = invitationsDisabled
        self.lastReviewRequestDate = lastReviewRequestDate
        self.lastReviewRequestVersion = lastReviewRequestVersion
    }

    /// Records a distinct local calendar day with the injected calendar.
    /// Appends, deduplicates, sorts, and truncates to `maxActiveDayCount`.
    public mutating func recordActiveDay(at date: Date, calendar: Calendar) {
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

    /// Returns true when `key` matches `YYYY-MM-DD` and forms a real Gregorian
    /// calendar date. The round-trip check rejects impossible dates such as
    /// `2026-02-30` and `2026-13-01`.
    public static func isValidDayKey(_ key: String) -> Bool {
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
