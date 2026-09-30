/// Errors thrown during query string parsing.
enum FilterParseError: Error, Equatable, Sendable {
    case emptyQuery
    case unexpectedToken(String, position: Int)
    case expectedField(position: Int)
    case expectedValue(position: Int)
    case unexpectedEOF(position: Int)
    case invalidBand(String, position: Int)
    case invalidNumber(String, position: Int)
}
