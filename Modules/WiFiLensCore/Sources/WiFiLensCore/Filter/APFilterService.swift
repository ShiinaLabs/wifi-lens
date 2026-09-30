/// Service for parsing and evaluating AP filter queries.
struct APFilterService: Sendable {
    let parser: APFilterQueryParser

    /// Evaluate whether a single AP matches a filter condition.
    func evaluate(_ ap: WiFiNetwork, condition: FilterCondition) -> Bool {
        switch condition {
        case .field(let filter):
            return evaluateField(ap, filter: filter)
        case .and(let conditions):
            return conditions.allSatisfy { evaluate(ap, condition: $0) }
        case .or(let conditions):
            return conditions.contains { evaluate(ap, condition: $0) }
        case .not(let inner):
            return !evaluate(ap, condition: inner)
        }
    }

    private func evaluateField(_ ap: WiFiNetwork, filter: FieldFilter) -> Bool {
        switch filter.field {
        case .band:
            return evaluateBand(ap, filter: filter)
        case .rssi:
            return evaluateInt(ap.rssi, filter: filter)
        case .ssid:
            return evaluateSSID(ap, filter: filter)
        case .channel:
            return evaluateInt(ap.channel.channelNumber, filter: filter)
        }
    }

    private func evaluateBand(_ ap: WiFiNetwork, filter: FieldFilter) -> Bool {
        guard case .band(let targetBand) = filter.value else { return false }
        return compare(ap.channel.band.rawValue, targetBand.rawValue, comparator: filter.comparator)
    }

    private func evaluateInt(_ actual: Int, filter: FieldFilter) -> Bool {
        guard case .integer(let target) = filter.value else { return false }
        return compare(actual, target, comparator: filter.comparator)
    }

    private func evaluateSSID(_ ap: WiFiNetwork, filter: FieldFilter) -> Bool {
        guard case .string(let needle) = filter.value else { return false }
        let ssid = ap.ssid ?? ""
        switch filter.comparator {
        case .eq: return ssid.localizedCaseInsensitiveContains(needle)
        case .gt: return false
        case .lt: return false
        case .gte: return false
        case .lte: return false
        }
    }

    /// Filter an array of APs against a query string.
    /// Returns only matching APs.
    func filter(aps: [WiFiNetwork], query: String) throws -> [WiFiNetwork] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return aps
        }
        let condition = try parser.parse(query)
        return aps.filter { evaluate($0, condition: condition) }
    }

    private func compare(_ lhs: Int, _ rhs: Int, comparator: Comparator) -> Bool {
        switch comparator {
        case .eq:  return lhs == rhs
        case .gt:  return lhs > rhs
        case .lt:  return lhs < rhs
        case .gte: return lhs >= rhs
        case .lte: return lhs <= rhs
        }
    }
}
