import Foundation
import Testing
@testable import WiFiLensCore

@Suite struct RegulatoryDatabaseTests {

    // MARK: - Channel range validity

    @Test("2.4 GHz channels are within valid range for all regions")
    func valid24GHzChannels() {
        for domain in [RegulatoryDomain.US, .JP, .CN, .EU] {
            guard let rules = RegulatoryDatabase.rules[domain]?["24"] else {
                #expect(Bool(false), "Missing 2.4 GHz rules for \(domain.rawValue)")
                continue
            }
            for ch in rules.allowedChannels {
                #expect(ch >= 1 && ch <= 14, "\(domain.rawValue) 2.4 GHz channel \(ch) out of range")
            }
        }
    }

    @Test("5 GHz channels are within valid range for all regions")
    func valid5GHzChannels() {
        for domain in [RegulatoryDomain.US, .JP, .CN, .EU] {
            guard let rules = RegulatoryDatabase.rules[domain]?["5"] else {
                #expect(Bool(false), "Missing 5 GHz rules for \(domain.rawValue)")
                continue
            }
            for ch in rules.allowedChannels {
                #expect(ch >= 36 && ch <= 165, "\(domain.rawValue) 5 GHz channel \(ch) out of range")
            }
        }
    }

    @Test("6 GHz channels are within valid range")
    func valid6GHzChannels() {
        for domain in [RegulatoryDomain.US, .JP, .EU] {
            guard let rules = RegulatoryDatabase.rules[domain]?["6"] else { continue }
            for ch in rules.allowedChannels {
                #expect(ch >= 1 && ch <= 233, "\(domain.rawValue) 6 GHz channel \(ch) out of range")
            }
        }
    }

    // MARK: - DFS metadata

    @Test("DFS channels have correct metadata flags")
    func dfsChannelsHaveCorrectMetadata() {
        guard let usRules = RegulatoryDatabase.rules[.US]?["5"] else {
            #expect(Bool(false), "Missing US 5 GHz rules")
            return
        }
        let dfsChannels: Set<Int> = [52, 56, 60, 64, 100, 104, 108, 112, 116, 120, 124, 128, 132, 136, 140, 144]
        for ch in dfsChannels {
            guard let meta = usRules.channelMeta[ch] else {
                #expect(Bool(false), "US channel \(ch) should have DFS metadata")
                continue
            }
            #expect(meta.isDFS, "US channel \(ch) should be marked DFS")
            #expect(meta.requiresCAC, "US channel \(ch) should require CAC")
            #expect(meta.forcedSwitchRisk, "US channel \(ch) should have forced switch risk")
        }
    }

    @Test("Non-DFS channels do not have DFS metadata")
    func nonDFSChannelsHaveNoMetadata() {
        guard let usRules = RegulatoryDatabase.rules[.US]?["5"] else { return }
        let nonDFSchannels: Set<Int> = [36, 40, 44, 48, 149, 153, 157, 161, 165]
        for ch in nonDFSchannels {
            #expect(usRules.channelMeta[ch] == nil || usRules.channelMeta[ch]!.isDFS == false,
                     "US channel \(ch) should not have DFS metadata")
        }
    }

    // MARK: - Region-specific rules

    @Test("US allows 2.4 GHz channels 1-11")
    func us24GHzChannels() {
        guard let rules = RegulatoryDatabase.rules[.US]?["24"] else {
            #expect(Bool(false))
            return
        }
        #expect(rules.allowedChannels == Set(1...11))
    }

    @Test("JP includes channel 14 in 2.4 GHz rules")
    func jpChannel14Present() {
        guard let rules = RegulatoryDatabase.rules[.JP]?["24"] else {
            #expect(Bool(false))
            return
        }
        #expect(rules.allowedChannels.contains(14), "JP should allow channel 14")
        #expect(rules.channelMeta[14] != nil, "JP channel 14 should have metadata")
    }

    @Test("CN has no 6 GHz channels")
    func cnNo6GHz() {
        guard let rules = RegulatoryDatabase.rules[.CN]?["6"] else {
            #expect(Bool(false))
            return
        }
        #expect(rules.allowedChannels.isEmpty, "CN should have no 6 GHz channels")
    }

    @Test("CN has no DFS channels (no UNII-2/UNII-2e)")
    func cnNoDFSchannels() {
        guard let rules = RegulatoryDatabase.rules[.CN]?["5"] else {
            #expect(Bool(false))
            return
        }
        let dfsRange = Set(52...64).union(Set(100...144))
        for ch in rules.allowedChannels {
            #expect(!dfsRange.contains(ch), "CN should not allow DFS channel \(ch)")
        }
        #expect(rules.channelMeta.isEmpty, "CN should have no channel metadata (no DFS region)")
    }

    @Test("EU allows 2.4 GHz channels 1-13")
    func eu24GHzIncludes12And13() {
        guard let rules = RegulatoryDatabase.rules[.EU]?["24"] else {
            #expect(Bool(false))
            return
        }
        #expect(rules.allowedChannels.contains(12))
        #expect(rules.allowedChannels.contains(13))
    }

    @Test("EU 5 GHz DFS channels cover 52-64 and 100-140")
    func euDFSchannelRange() {
        guard let rules = RegulatoryDatabase.rules[.EU]?["5"] else {
            #expect(Bool(false))
            return
        }
        let expectedDFS: Set<Int> = [52, 56, 60, 64, 100, 104, 108, 112, 116, 120, 124, 128, 132, 136, 140]
        for ch in expectedDFS {
            guard let meta = rules.channelMeta[ch] else {
                #expect(Bool(false), "EU channel \(ch) missing DFS metadata")
                continue
            }
            #expect(meta.isDFS, "EU channel \(ch) should be DFS")
        }
        // Channel 144 should NOT be in EU
        #expect(rules.channelMeta[144] == nil || rules.channelMeta[144]!.isDFS == false,
                 "EU should not have channel 144 as DFS")
    }

    @Test("JP 5 GHz includes channels 36-144 with DFS blocks")
    func jp5GHzChannelSet() {
        guard let rules = RegulatoryDatabase.rules[.JP]?["5"] else {
            #expect(Bool(false))
            return
        }
        // JP has 36-48 (non-DFS) and 52-144 (includes DFS blocks W53 + W56)
        #expect(rules.allowedChannels.contains(36))
        #expect(rules.allowedChannels.contains(52))
        #expect(rules.allowedChannels.contains(140))
        // JP does NOT have 149-165
        #expect(!rules.allowedChannels.contains(149))
        #expect(!rules.allowedChannels.contains(165))
    }

    @Test("US 6 GHz LPI allows the full 1-233 band")
    func us6GHzLPIAllowsFullBand() {
        guard let rules = RegulatoryDatabase.rules[.US]?["6"] else {
            #expect(Bool(false))
            return
        }
        #expect(rules.allowedChannels == Set(stride(from: 1, through: 233, by: 4)),
                "US 6 GHz LPI should allow all channels 1-233")
        // U-NII-6 (97-117) and U-NII-8 (185-233) are LPI-eligible per 47 CFR 15.407(a)(5)
        for ch in [97, 101, 117, 185, 189, 233] {
            #expect(rules.allowedChannels.contains(ch), "US 6 GHz should allow LPI channel \(ch)")
        }
    }

    // MARK: - Rule completeness

    @Test("All known domains have rules for all three bands")
    func allDomainsHaveAllBands() {
        for domain in [RegulatoryDomain.US, .JP, .CN, .EU] {
            guard let rules = RegulatoryDatabase.rules[domain] else {
                #expect(Bool(false), "Missing rules for \(domain.rawValue)")
                continue
            }
            #expect(rules["24"] != nil, "\(domain.rawValue) missing 2.4 GHz rules")
            #expect(rules["5"] != nil, "\(domain.rawValue) missing 5 GHz rules")
            #expect(rules["6"] != nil, "\(domain.rawValue) missing 6 GHz rules")
        }
    }
}
