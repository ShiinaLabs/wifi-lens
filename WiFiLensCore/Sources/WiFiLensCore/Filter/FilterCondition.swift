/// A tree representing a parsed filter query.
indirect enum FilterCondition: Sendable, Equatable {
    case field(FieldFilter)
    case and([FilterCondition])
    case or([FilterCondition])
    case not(FilterCondition)
}

/// A single field comparison (e.g., `band:5G`, `rssi:>-60`).
struct FieldFilter: Sendable, Equatable {
    let field: FilterField
    let comparator: Comparator
    let value: FilterValue
}

/// Supported filter fields.
enum FilterField: String, Sendable, CaseIterable {
    case band
    case rssi
    case ssid
    case channel
}

/// Comparison operators.
enum Comparator: Sendable, Equatable {
    case eq
    case gt
    case lt
    case gte
    case lte
}

/// The value side of a field comparison.
enum FilterValue: Sendable, Equatable {
    case string(String)
    case integer(Int)
    case band(ChannelBand)
}
