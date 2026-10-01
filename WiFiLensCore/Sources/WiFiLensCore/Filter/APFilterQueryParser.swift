/// Hand-written recursive descent parser for AP filter queries.
///
/// Grammar:
/// ```
/// condition     -> orExpr
/// orExpr        -> andExpr ("OR" andExpr)*
/// andExpr       -> unary ("AND" unary)*
/// unary         -> "NOT" unary | primary
/// primary       -> "(" condition ")" | fieldCondition
/// fieldCondition -> field comparator value
/// ```
struct APFilterQueryParser {

    // MARK: - Tokenizer

    enum Token: Equatable, Sendable {
        case field(String)
        case value(String)
        case colon
        case gt
        case lt
        case gte
        case lte
        case and
        case or
        case not
        case lparen
        case rparen
        case eof
    }

    struct Tokenizer {
        static func tokenize(_ input: String) -> [Token] {
            var tokens: [Token] = []
            var i = input.startIndex
            while i < input.endIndex {
                let ch = input[i]
                if ch.isWhitespace {
                    i = input.index(after: i)
                    continue
                }
                switch ch {
                case ":":
                    tokens.append(.colon)
                    i = input.index(after: i)
                case "(":
                    tokens.append(.lparen)
                    i = input.index(after: i)
                case ")":
                    tokens.append(.rparen)
                    i = input.index(after: i)
                case ">":
                    let next = input.index(after: i)
                    if next < input.endIndex && input[next] == "=" {
                        tokens.append(.gte)
                        i = input.index(after: next)
                    } else {
                        tokens.append(.gt)
                        i = input.index(after: i)
                    }
                case "<":
                    let next = input.index(after: i)
                    if next < input.endIndex && input[next] == "=" {
                        tokens.append(.lte)
                        i = input.index(after: next)
                    } else {
                        tokens.append(.lt)
                        i = input.index(after: i)
                    }
                case "\"":
                    let start = input.index(after: i)
                    var end = start
                    while end < input.endIndex && input[end] != "\"" {
                        end = input.index(after: end)
                    }
                    let str = String(input[start..<end])
                    tokens.append(.value(str))
                    i = end < input.endIndex ? input.index(after: end) : end
                default:
                    if ch.isLetter || ch.isNumber || ch == "." || ch == "_" || ch == "-" {
                        let start = i
                        while i < input.endIndex && (input[i].isLetter || input[i].isNumber || input[i] == "." || input[i] == "_" || input[i] == "-") {
                            i = input.index(after: i)
                        }
                        let word = String(input[start..<i])
                        switch word {
                        case "AND": tokens.append(.and)
                        case "OR": tokens.append(.or)
                        case "NOT": tokens.append(.not)
                        default:
                            var j = i
                            while j < input.endIndex && input[j].isWhitespace {
                                j = input.index(after: j)
                            }
                            if j < input.endIndex && input[j] == ":" {
                                tokens.append(.field(word))
                            } else {
                                tokens.append(.value(word))
                            }
                        }
                    } else {
                        i = input.index(after: i)
                    }
                }
            }
            return tokens
        }
    }

    // MARK: - Parser

    func parse(_ query: String) throws -> FilterCondition {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            throw FilterParseError.emptyQuery
        }
        let toks = Tokenizer.tokenize(trimmed)
        var ctx = ParseContext(tokens: toks)
        return try ctx.parseOrExpr()
    }

    private struct ParseContext {
        let tokens: [Token]
        var position: Int = 0

        mutating func parseOrExpr() throws -> FilterCondition {
            var left = try parseAndExpr()
            while peek() == .or {
                advance()
                let right = try parseAndExpr()
                if case .or(let children) = left {
                    left = .or(children + [right])
                } else {
                    left = .or([left, right])
                }
            }
            return left
        }

        mutating func parseAndExpr() throws -> FilterCondition {
            var left = try parseUnary()
            while peek() == .and {
                advance()
                let right = try parseUnary()
                if case .and(let children) = left {
                    left = .and(children + [right])
                } else {
                    left = .and([left, right])
                }
            }
            return left
        }

        mutating func parseUnary() throws -> FilterCondition {
            if peek() == .not {
                advance()
                let inner = try parseUnary()
                return .not(inner)
            }
            return try parsePrimary()
        }

        mutating func parsePrimary() throws -> FilterCondition {
            if peek() == .lparen {
                advance()
                let inner = try parseOrExpr()
                guard peek() == .rparen else {
                    throw FilterParseError.unexpectedToken(
                        describe(peek()),
                        position: position
                    )
                }
                advance()
                return inner
            }
            return try parseFieldCondition()
        }

        mutating func parseFieldCondition() throws -> FilterCondition {
            guard case .field(let fieldName) = peek() else {
                throw FilterParseError.expectedField(position: position)
            }
            advance()

            guard let field = FilterField(rawValue: fieldName) else {
                throw FilterParseError.unexpectedToken(fieldName, position: position - 1)
            }

            let comparator = try parseComparator()

            guard case .value(let rawValue) = peek() else {
                throw FilterParseError.expectedValue(position: position)
            }
            advance()

            let value = try parseValue(field: field, raw: rawValue, position: position)
            return .field(FieldFilter(field: field, comparator: comparator, value: value))
        }

        mutating func parseComparator() throws -> Comparator {
            switch peek() {
            case .colon:
                advance()
                if peek() == .gt {
                    advance()
                    return .gt
                } else if peek() == .lt {
                    advance()
                    return .lt
                } else if peek() == .gte {
                    advance()
                    return .gte
                } else if peek() == .lte {
                    advance()
                    return .lte
                }
                return .eq
            case .gt:
                advance()
                return .gt
            case .lt:
                advance()
                return .lt
            case .gte:
                advance()
                return .gte
            case .lte:
                advance()
                return .lte
            default:
                throw FilterParseError.unexpectedToken(describe(peek()), position: position)
            }
        }

        func parseValue(field: FilterField, raw: String, position: Int) throws -> FilterValue {
            switch field {
            case .band:
                return try parseBandValue(raw, position: position)
            case .rssi, .channel:
                guard let intVal = Int(raw) else {
                    throw FilterParseError.invalidNumber(raw, position: position - 1)
                }
                return .integer(intVal)
            case .ssid:
                return .string(raw)
            }
        }

        func parseBandValue(_ raw: String, position: Int) throws -> FilterValue {
            switch raw {
            case "2.4G", "2.4g", "24": return .band(.band24GHz)
            case "5G", "5g", "5": return .band(.band5GHz)
            case "6G", "6g", "6": return .band(.band6GHz)
            default: throw FilterParseError.invalidBand(raw, position: position - 1)
            }
        }

        private func peek() -> Token {
            position < tokens.count ? tokens[position] : .eof
        }

        private mutating func advance() {
            position += 1
        }

        func describe(_ token: Token) -> String {
            switch token {
            case .field(let s): return s
            case .value(let s): return s
            case .colon: return ":"
            case .gt: return ">"
            case .lt: return "<"
            case .gte: return ">="
            case .lte: return "<="
            case .and: return "AND"
            case .or: return "OR"
            case .not: return "NOT"
            case .lparen: return "("
            case .rparen: return ")"
            case .eof: return "<EOF>"
            }
        }
    }
}
