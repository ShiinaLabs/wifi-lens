import Testing
@testable import WiFiLensCore

struct ChannelSpanCalculatorTests {

    // MARK: - channelHalfSpan

    @Test func channelHalfSpanFor20MHz() {
        #expect(ChannelSpanCalculator.channelHalfSpan(for: 20) == 2)
    }

    @Test func channelHalfSpanFor40MHz() {
        #expect(ChannelSpanCalculator.channelHalfSpan(for: 40) == 4)
    }

    @Test func channelHalfSpanFor80MHz() {
        #expect(ChannelSpanCalculator.channelHalfSpan(for: 80) == 8)
    }

    @Test func channelHalfSpanFor160MHz() {
        #expect(ChannelSpanCalculator.channelHalfSpan(for: 160) == 16)
    }

    // MARK: - 20 MHz (any band)

    @Test func channelBlock20MHz24GHz() {
        let (left, right) = ChannelSpanCalculator.channelBlock(
            primaryChannel: 6, widthMHz: 20, band: .band24GHz, spanDirection: nil)
        #expect(left == 4)
        #expect(right == 8)
    }

    @Test func channelBlock20MHz5GHz() {
        let (left, right) = ChannelSpanCalculator.channelBlock(
            primaryChannel: 100, widthMHz: 20, band: .band5GHz, spanDirection: nil)
        #expect(left == 98)
        #expect(right == 102)
    }

    // MARK: - 2.4 GHz 40 MHz

    @Test func channelBlock24GHz40MHzHT40Plus() {
        let (left, right) = ChannelSpanCalculator.channelBlock(
            primaryChannel: 6, widthMHz: 40, band: .band24GHz, spanDirection: .upper)
        #expect(left == 4)
        #expect(right == 12)
    }

    @Test func channelBlock24GHz40MHzHT40Minus() {
        let (left, right) = ChannelSpanCalculator.channelBlock(
            primaryChannel: 11, widthMHz: 40, band: .band24GHz, spanDirection: .lower)
        #expect(left == 5)
        #expect(right == 13)
    }

    @Test func channelBlock24GHz40MHzFallbackLowChannel() {
        let (left, right) = ChannelSpanCalculator.channelBlock(
            primaryChannel: 6, widthMHz: 40, band: .band24GHz, spanDirection: nil)
        // primary <= 7 defaults to upper
        #expect(left == 4)
        #expect(right == 12)
    }

    @Test func channelBlock24GHz40MHzFallbackHighChannel() {
        let (left, right) = ChannelSpanCalculator.channelBlock(
            primaryChannel: 11, widthMHz: 40, band: .band24GHz, spanDirection: nil)
        // primary > 7 defaults to lower
        #expect(left == 5)
        #expect(right == 13)
    }

    // MARK: - 5 GHz 40 MHz blocks

    @Test func channelBlock5GHz40MHzCh36to40() {
        let (left, right) = ChannelSpanCalculator.channelBlock(
            primaryChannel: 36, widthMHz: 40, band: .band5GHz, spanDirection: nil)
        #expect(left == 34)
        #expect(right == 42)
    }

    @Test func channelBlock5GHz40MHzCh44to48() {
        let (left, right) = ChannelSpanCalculator.channelBlock(
            primaryChannel: 44, widthMHz: 40, band: .band5GHz, spanDirection: nil)
        #expect(left == 42)
        #expect(right == 50)
    }

    @Test func channelBlock5GHz40MHzCh149to153() {
        let (left, right) = ChannelSpanCalculator.channelBlock(
            primaryChannel: 149, widthMHz: 40, band: .band5GHz, spanDirection: nil)
        #expect(left == 147)
        #expect(right == 155)
    }

    // MARK: - 5 GHz 80 MHz blocks

    @Test func channelBlock5GHz80MHzCh36to48() {
        let (left, right) = ChannelSpanCalculator.channelBlock(
            primaryChannel: 36, widthMHz: 80, band: .band5GHz, spanDirection: nil)
        #expect(left == 34)
        #expect(right == 50)
    }

    @Test func channelBlock5GHz80MHzCh100to112() {
        let (left, right) = ChannelSpanCalculator.channelBlock(
            primaryChannel: 100, widthMHz: 80, band: .band5GHz, spanDirection: nil)
        #expect(left == 98)
        #expect(right == 114)
    }

    // MARK: - 5 GHz 160 MHz blocks

    @Test func channelBlock5GHz160MHzCh36to64() {
        let (left, right) = ChannelSpanCalculator.channelBlock(
            primaryChannel: 36, widthMHz: 160, band: .band5GHz, spanDirection: nil)
        #expect(left == 34)
        #expect(right == 66)
    }

    @Test func channelBlock5GHz160MHzCh100to128() {
        let (left, right) = ChannelSpanCalculator.channelBlock(
            primaryChannel: 100, widthMHz: 160, band: .band5GHz, spanDirection: nil)
        #expect(left == 98)
        #expect(right == 130)
    }

    // Channel 144 has no 160 MHz block — falls back to simple spanning
    @Test func channelBlock5GHz160MHzCh144NoBlock() {
        let (left, right) = ChannelSpanCalculator.channelBlock(
            primaryChannel: 144, widthMHz: 160, band: .band5GHz, spanDirection: nil)
        let half = ChannelSpanCalculator.channelHalfSpan(for: 160)
        #expect(left == 144 - half)
        #expect(right == 144 + half)
    }

    // MARK: - 6 GHz (IEEE 802.11ax containing blocks)

    @Test func channelBlock6GHz80MHzBlock() {
        // The scanned primary may be any 20 MHz primary inside the 80 MHz
        // block: 33/37/41/45 all resolve to the same block (31, 47).
        for ch in [33, 37, 41, 45] {
            let (left, right) = ChannelSpanCalculator.channelBlock(
                primaryChannel: ch, widthMHz: 80, band: .band6GHz, spanDirection: nil)
            #expect(left == 31)
            #expect(right == 47)
        }
        let (l49, r49) = ChannelSpanCalculator.channelBlock(
            primaryChannel: 49, widthMHz: 80, band: .band6GHz, spanDirection: nil)
        #expect(l49 == 47)
        #expect(r49 == 63)
    }

    @Test func channelBlock6GHz40MHzNonLowestPrimary() {
        // 37 and 33 share the 40 MHz block (31, 39).
        for ch in [33, 37] {
            let (left, right) = ChannelSpanCalculator.channelBlock(
                primaryChannel: ch, widthMHz: 40, band: .band6GHz, spanDirection: nil)
            #expect(left == 31)
            #expect(right == 39)
        }
    }

    @Test func channelBlock6GHz160MHzNonLowestPrimary() {
        // 37 and 33 share the 160 MHz block (31, 63).
        for ch in [33, 37] {
            let (left, right) = ChannelSpanCalculator.channelBlock(
                primaryChannel: ch, widthMHz: 160, band: .band6GHz, spanDirection: nil)
            #expect(left == 31)
            #expect(right == 63)
        }
    }

    @Test func channelBlock6GHz20MHzBlock() {
        let (left, right) = ChannelSpanCalculator.channelBlock(
            primaryChannel: 5, widthMHz: 20, band: .band6GHz, spanDirection: nil)
        #expect(left == 3)
        #expect(right == 7)
    }
}
