@testable import WiFiLensCore

import Testing
@testable import WiFi_Lens

struct FilterConditionTests {
    @Test func fieldFilterCreation() {
        let filter = FieldFilter(
            field: .band,
            comparator: .eq,
            value: .band(.band5GHz)
        )
        #expect(filter.field == .band)
        #expect(filter.comparator == .eq)
    }

    @Test func andConditionCreation() {
        let a = FilterCondition.field(FieldFilter(field: .band, comparator: .eq, value: .band(.band5GHz)))
        let b = FilterCondition.field(FieldFilter(field: .rssi, comparator: .gt, value: .integer(-60)))
        let and = FilterCondition.and([a, b])
        if case .and(let children) = and {
            #expect(children.count == 2)
        } else {
            Issue.record("Expected .and case")
        }
    }

    @Test func orConditionCreation() {
        let a = FilterCondition.field(FieldFilter(field: .band, comparator: .eq, value: .band(.band5GHz)))
        let b = FilterCondition.field(FieldFilter(field: .band, comparator: .eq, value: .band(.band6GHz)))
        let or = FilterCondition.or([a, b])
        if case .or(let children) = or {
            #expect(children.count == 2)
        } else {
            Issue.record("Expected .or case")
        }
    }

    @Test func notConditionCreation() {
        let inner = FilterCondition.field(FieldFilter(field: .ssid, comparator: .eq, value: .string("guest")))
        let not = FilterCondition.not(inner)
        if case .not(let child) = not {
            if case .field(let filter) = child {
                #expect(filter.value == .string("guest"))
            }
        } else {
            Issue.record("Expected .not case")
        }
    }
}

struct TokenizerTests {
    @Test func tokenizeSimpleQuery() {
        let tokens = APFilterQueryParser.Tokenizer.tokenize("band:5G")
        #expect(tokens == [.field("band"), .colon, .value("5G")])
    }

    @Test func tokenizeWithAND() {
        let tokens = APFilterQueryParser.Tokenizer.tokenize("band:5G AND rssi:>-60")
        #expect(tokens == [
            .field("band"), .colon, .value("5G"),
            .and,
            .field("rssi"), .colon, .gt, .value("-60")
        ])
    }

    @Test func tokenizeWithOR() {
        let tokens = APFilterQueryParser.Tokenizer.tokenize("band:5G OR band:6G")
        #expect(tokens == [
            .field("band"), .colon, .value("5G"),
            .or,
            .field("band"), .colon, .value("6G")
        ])
    }

    @Test func tokenizeWithNOT() {
        let tokens = APFilterQueryParser.Tokenizer.tokenize("NOT ssid:guest")
        #expect(tokens == [.not, .field("ssid"), .colon, .value("guest")])
    }

    @Test func tokenizeWithParentheses() {
        let tokens = APFilterQueryParser.Tokenizer.tokenize("(band:5G)")
        #expect(tokens == [.lparen, .field("band"), .colon, .value("5G"), .rparen])
    }

    @Test func tokenizeGte() {
        let tokens = APFilterQueryParser.Tokenizer.tokenize("rssi:>=-60")
        #expect(tokens == [.field("rssi"), .colon, .gte, .value("-60")])
    }

    @Test func tokenizeLte() {
        let tokens = APFilterQueryParser.Tokenizer.tokenize("rssi:<=-60")
        #expect(tokens == [.field("rssi"), .colon, .lte, .value("-60")])
    }

    @Test func tokenizeQuotedString() {
        let tokens = APFilterQueryParser.Tokenizer.tokenize("ssid:\"Office Network\"")
        #expect(tokens == [.field("ssid"), .colon, .value("Office Network")])
    }
}

struct FilterParseErrorTests {
    @Test func errorEquality() {
        let a = FilterParseError.emptyQuery
        let b = FilterParseError.emptyQuery
        #expect(a == b)
    }

    @Test func errorPositionTracking() {
        let error = FilterParseError.unexpectedToken("foo", position: 5)
        if case .unexpectedToken(_, let pos) = error {
            #expect(pos == 5)
        } else {
            Issue.record("Expected unexpectedToken case")
        }
    }

    @Test func invalidBandError() {
        let error = FilterParseError.invalidBand("7G", position: 0)
        if case .invalidBand(let band, _) = error {
            #expect(band == "7G")
        } else {
            Issue.record("Expected invalidBand case")
        }
    }
}

struct ParserTests {
    var parser = APFilterQueryParser()

    @Test func parseSimpleField() throws {
        let cond = try parser.parse("band:5G")
        if case .field(let filter) = cond {
            #expect(filter.field == .band)
            #expect(filter.comparator == .eq)
            #expect(filter.value == .band(.band5GHz))
        } else {
            Issue.record("Expected .field case")
        }
    }

    @Test func parseAND() throws {
        let cond = try parser.parse("band:5G AND rssi:>-60")
        if case .and(let children) = cond {
            #expect(children.count == 2)
        } else {
            Issue.record("Expected .and case")
        }
    }

    @Test func parseOR() throws {
        let cond = try parser.parse("band:5G OR band:6G")
        if case .or(let children) = cond {
            #expect(children.count == 2)
        } else {
            Issue.record("Expected .or case")
        }
    }

    @Test func parseNOT() throws {
        let cond = try parser.parse("NOT ssid:guest")
        if case .not(let inner) = cond {
            if case .field(let filter) = inner {
                #expect(filter.field == .ssid)
            }
        } else {
            Issue.record("Expected .not case")
        }
    }

    @Test func parseParentheses() throws {
        let cond = try parser.parse("(band:5G OR band:6G) AND rssi:>-60")
        if case .and(let children) = cond {
            #expect(children.count == 2)
            if case .or(let orChildren) = children[0] {
                #expect(orChildren.count == 2)
            }
        } else {
            Issue.record("Expected .and case")
        }
    }

    @Test func parseGte() throws {
        let cond = try parser.parse("rssi:>=-70")
        if case .field(let filter) = cond {
            #expect(filter.comparator == .gte)
            #expect(filter.value == .integer(-70))
        } else {
            Issue.record("Expected .field case")
        }
    }

    @Test func parseLte() throws {
        let cond = try parser.parse("channel:<=100")
        if case .field(let filter) = cond {
            #expect(filter.comparator == .lte)
            #expect(filter.value == .integer(100))
        } else {
            Issue.record("Expected .field case")
        }
    }

    @Test func parseGtStrict() throws {
        let cond = try parser.parse("rssi:>-60")
        if case .field(let filter) = cond {
            #expect(filter.comparator == .gt)
            #expect(filter.value == .integer(-60))
        } else {
            Issue.record("Expected .field case")
        }
    }

    @Test func parseGteNonStrict() throws {
        let cond = try parser.parse("rssi:>=-60")
        if case .field(let filter) = cond {
            #expect(filter.comparator == .gte)
            #expect(filter.value == .integer(-60))
        } else {
            Issue.record("Expected .field case")
        }
    }

    @Test func parseLtStrict() throws {
        let cond = try parser.parse("rssi:<-60")
        if case .field(let filter) = cond {
            #expect(filter.comparator == .lt)
            #expect(filter.value == .integer(-60))
        } else {
            Issue.record("Expected .field case")
        }
    }

    @Test func parseLteNonStrict() throws {
        let cond = try parser.parse("rssi:<=-60")
        if case .field(let filter) = cond {
            #expect(filter.comparator == .lte)
            #expect(filter.value == .integer(-60))
        } else {
            Issue.record("Expected .field case")
        }
    }

    @Test func parseBand24G() throws {
        let cond = try parser.parse("band:2.4G")
        if case .field(let filter) = cond {
            #expect(filter.value == .band(.band24GHz))
        } else {
            Issue.record("Expected .field case")
        }
    }

    @Test func parseBandIDFormat() throws {
        let cond = try parser.parse("band:5")
        if case .field(let filter) = cond {
            #expect(filter.value == .band(.band5GHz))
        } else {
            Issue.record("Expected .field case")
        }
    }

    @Test func parseEmptyQueryThrows() {
        #expect(throws: FilterParseError.emptyQuery) {
            _ = try parser.parse("")
        }
    }

    @Test func parseWhitespaceOnlyThrows() {
        #expect(throws: FilterParseError.emptyQuery) {
            _ = try parser.parse("   ")
        }
    }

    @Test func parseComplexExpression() throws {
        let cond = try parser.parse("(band:5G OR band:6G) AND rssi:>=-50 AND NOT ssid:Guest")
        if case .and(let children) = cond {
            #expect(children.count == 3)
        } else {
            Issue.record("Expected .and case with 3 children")
        }
    }
}

struct EvaluateTests {
    let service = APFilterService(parser: APFilterQueryParser())

    func makeAP(ssid: String = "TestNet", band: ChannelBand = .band5GHz, rssi: Int = -50, channel: Int = 36) -> WiFiNetwork {
        WiFiNetwork(ssid: ssid, bssid: "00:11:22:33:44:55", rssi: rssi, channel: WiFiChannel(band: band, channelNumber: channel))
    }

    @Test func bandMatch() throws {
        let ap = makeAP(band: .band5GHz)
        let cond = try APFilterQueryParser().parse("band:5G")
        #expect(service.evaluate(ap, condition: cond) == true)
    }

    @Test func bandMismatch() throws {
        let ap = makeAP(band: .band24GHz)
        let cond = try APFilterQueryParser().parse("band:5G")
        #expect(service.evaluate(ap, condition: cond) == false)
    }

    @Test func rssiGreaterThan() throws {
        let ap = makeAP(rssi: -55)
        let cond = try APFilterQueryParser().parse("rssi:>-60")
        #expect(service.evaluate(ap, condition: cond) == true)
    }

    @Test func rssiLessThanMatch() throws {
        let ap = makeAP(rssi: -70)
        let cond = try APFilterQueryParser().parse("rssi:>-60")
        #expect(service.evaluate(ap, condition: cond) == false)
    }

    @Test func rssiStrictGtExcludesBoundary() throws {
        let ap = makeAP(rssi: -60)
        let cond = try APFilterQueryParser().parse("rssi:>-60")
        #expect(service.evaluate(ap, condition: cond) == false)
    }

    @Test func rssiGteIncludesBoundary() throws {
        let ap = makeAP(rssi: -60)
        let cond = try APFilterQueryParser().parse("rssi:>=-60")
        #expect(service.evaluate(ap, condition: cond) == true)
    }

    @Test func rssiStrictLtExcludesBoundary() throws {
        let ap = makeAP(rssi: -60)
        let cond = try APFilterQueryParser().parse("rssi:<-60")
        #expect(service.evaluate(ap, condition: cond) == false)
    }

    @Test func rssiLteIncludesBoundary() throws {
        let ap = makeAP(rssi: -60)
        let cond = try APFilterQueryParser().parse("rssi:<=-60")
        #expect(service.evaluate(ap, condition: cond) == true)
    }

    @Test func rssiEquals() throws {
        let ap = makeAP(rssi: -50)
        let cond = try APFilterQueryParser().parse("rssi:-50")
        #expect(service.evaluate(ap, condition: cond) == true)
    }

    @Test func ssidSubstringMatch() throws {
        let ap = makeAP(ssid: "Office-5G")
        let cond = try APFilterQueryParser().parse("ssid:Office")
        #expect(service.evaluate(ap, condition: cond) == true)
    }

    @Test func ssidSubstringMismatch() throws {
        let ap = makeAP(ssid: "Office-5G")
        let cond = try APFilterQueryParser().parse("ssid:Home")
        #expect(service.evaluate(ap, condition: cond) == false)
    }

    @Test func channelEquals() throws {
        let ap = makeAP(channel: 36)
        let cond = try APFilterQueryParser().parse("channel:36")
        #expect(service.evaluate(ap, condition: cond) == true)
    }

    @Test func channelGte() throws {
        let ap = makeAP(channel: 100)
        let cond = try APFilterQueryParser().parse("channel:>=100")
        #expect(service.evaluate(ap, condition: cond) == true)
    }

    @Test func andBothTrue() throws {
        let ap = makeAP(band: .band5GHz, rssi: -50)
        let cond = try APFilterQueryParser().parse("band:5G AND rssi:>-60")
        #expect(service.evaluate(ap, condition: cond) == true)
    }

    @Test func andOneFalse() throws {
        let ap = makeAP(band: .band24GHz, rssi: -50)
        let cond = try APFilterQueryParser().parse("band:5G AND rssi:>-60")
        #expect(service.evaluate(ap, condition: cond) == false)
    }

    @Test func orOneTrue() throws {
        let ap = makeAP(band: .band5GHz, rssi: -80)
        let cond = try APFilterQueryParser().parse("band:5G OR rssi:>-60")
        #expect(service.evaluate(ap, condition: cond) == true)
    }

    @Test func orBothFalse() throws {
        let ap = makeAP(band: .band24GHz, rssi: -80)
        let cond = try APFilterQueryParser().parse("band:5G OR rssi:>-60")
        #expect(service.evaluate(ap, condition: cond) == false)
    }

    @Test func notInvertsMatch() throws {
        let ap = makeAP(ssid: "Guest")
        let cond = try APFilterQueryParser().parse("NOT ssid:Guest")
        #expect(service.evaluate(ap, condition: cond) == false)
    }

    @Test func notInvertsMismatch() throws {
        let ap = makeAP(ssid: "Office")
        let cond = try APFilterQueryParser().parse("NOT ssid:Guest")
        #expect(service.evaluate(ap, condition: cond) == true)
    }

    @Test func parenthesesPrecedence() throws {
        let ap = makeAP(band: .band5GHz, rssi: -80)
        let cond = try APFilterQueryParser().parse("(band:5G OR band:6G) AND rssi:>-60")
        #expect(service.evaluate(ap, condition: cond) == false)
    }
}

struct FilterIntegrationTests {
    let service = APFilterService(parser: APFilterQueryParser())

    func makeAP(ssid: String = "TestNet", band: ChannelBand = .band5GHz, rssi: Int = -50, channel: Int = 36, bssid: String = "00:11:22:33:44:55") -> WiFiNetwork {
        WiFiNetwork(ssid: ssid, bssid: bssid, rssi: rssi, channel: WiFiChannel(band: band, channelNumber: channel))
    }

    @Test func filterReturnsMatchingAPs() throws {
        let aps = [
            makeAP(ssid: "Office", band: .band5GHz, rssi: -50, bssid: "aa:bb:cc:dd:ee:01"),
            makeAP(ssid: "Home", band: .band24GHz, rssi: -70, bssid: "aa:bb:cc:dd:ee:02"),
            makeAP(ssid: "Guest", band: .band5GHz, rssi: -45, bssid: "aa:bb:cc:dd:ee:03"),
        ]
        let result = try service.filter(aps: aps, query: "band:5G")
        #expect(result.count == 2)
    }

    @Test func filterEmptyQueryReturnsAll() throws {
        let aps = [
            makeAP(ssid: "A", bssid: "aa:bb:cc:dd:ee:01"),
            makeAP(ssid: "B", bssid: "aa:bb:cc:dd:ee:02"),
        ]
        let result = try service.filter(aps: aps, query: "")
        #expect(result.count == 2)
    }

    @Test func filterNoMatchReturnsEmpty() throws {
        let aps = [
            makeAP(ssid: "Office", band: .band24GHz, bssid: "aa:bb:cc:dd:ee:01"),
        ]
        let result = try service.filter(aps: aps, query: "band:5G")
        #expect(result.isEmpty)
    }

    @Test func filterComplexQuery() throws {
        let aps = [
            makeAP(ssid: "Office-5G", band: .band5GHz, rssi: -50, channel: 36, bssid: "aa:bb:cc:dd:ee:01"),
            makeAP(ssid: "Office-5G", band: .band5GHz, rssi: -80, channel: 36, bssid: "aa:bb:cc:dd:ee:02"),
            makeAP(ssid: "Home-24", band: .band24GHz, rssi: -40, channel: 6, bssid: "aa:bb:cc:dd:ee:03"),
        ]
        let result = try service.filter(aps: aps, query: "band:5G AND rssi:>-60")
        #expect(result.count == 1)
        #expect(result.first?.bssid == "aa:bb:cc:dd:ee:01")
    }

    @Test func filterWithOR() throws {
        let aps = [
            makeAP(ssid: "Office", band: .band5GHz, bssid: "aa:bb:cc:dd:ee:01"),
            makeAP(ssid: "Home", band: .band24GHz, bssid: "aa:bb:cc:dd:ee:02"),
            makeAP(ssid: "Guest", band: .band6GHz, bssid: "aa:bb:cc:dd:ee:03"),
        ]
        let result = try service.filter(aps: aps, query: "band:5G OR band:6G")
        #expect(result.count == 2)
    }

    @Test func filterInvalidQueryThrows() {
        let aps = [makeAP()]
        #expect(throws: FilterParseError.self) {
            _ = try service.filter(aps: aps, query: "???")
        }
    }
}
