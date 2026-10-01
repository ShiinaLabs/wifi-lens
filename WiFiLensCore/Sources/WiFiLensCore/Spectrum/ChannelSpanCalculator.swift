import Foundation

import Foundation

/// Exact port of `series.py` channel span calculation logic.
public enum ChannelSpanCalculator {

    /// Convert MHz channel width into half-span measured in channel number steps.
    /// Channel numbers are spaced 5 MHz apart. A 20 MHz channel covers ~4 steps,
    /// so half-span is 2; 40 MHz → 4; 80 → 8; 160 → 16.
    public static func channelHalfSpan(for widthMHz: Int) -> Int {
        let totalSteps = Int(round(Double(widthMHz) / 5.0))
        return max(1, totalSteps / 2)
    }

    /// Calculate the actual channel block (left, right) for a primary channel + width + band.
    /// WiFi channels occupy predefined blocks, especially for wider channels.
    public static func channelBlock(
        primaryChannel: Int,
        widthMHz: Int,
        band: ChannelBand
    ) -> (left: Int, right: Int) {
        channelBlock(primaryChannel: primaryChannel, widthMHz: widthMHz, band: band, spanDirection: nil)
    }

    static func channelBlock(
        primaryChannel: Int,
        widthMHz: Int,
        band: ChannelBand,
        spanDirection: SpanDirection?
    ) -> (left: Int, right: Int) {
        if widthMHz == 20 {
            return (primaryChannel - 2, primaryChannel + 2)
        }

        if band == .band24GHz {
            if widthMHz == 40 {
                if spanDirection == .upper {
                    return (primaryChannel - 2, primaryChannel + 6)
                } else if spanDirection == .lower {
                    return (primaryChannel - 6, primaryChannel + 2)
                } else {
                    // Default: heuristic based on primary channel position
                    if primaryChannel <= 7 {
                        return (primaryChannel - 2, primaryChannel + 6)
                    } else {
                        return (primaryChannel - 6, primaryChannel + 2)
                    }
                }
            }
        }

        if band == .band5GHz {
            if widthMHz == 40 {
                switch primaryChannel {
                case 36...40:  return (34, 42)
                case 44...48:  return (42, 50)
                case 52...56:  return (50, 58)
                case 60...64:  return (58, 66)
                case 100...104: return (98, 106)
                case 108...112: return (106, 114)
                case 116...120: return (114, 122)
                case 124...128: return (122, 130)
                case 132...136: return (130, 138)
                case 140...144: return (138, 146)
                case 149...153: return (147, 155)
                case 157...161: return (155, 163)
                case 165...169: return (163, 171)
                case 173...177: return (171, 179)
                default: break
                }
            } else if widthMHz == 80 {
                switch primaryChannel {
                case 36...48:   return (34, 50)
                case 52...64:   return (50, 66)
                case 100...112: return (98, 114)
                case 116...128: return (114, 130)
                case 132...144: return (130, 146)
                case 149...161: return (147, 163)
                case 165...177: return (163, 179)
                default: break
                }
            } else if widthMHz == 160 {
                switch primaryChannel {
                case 36...64:   return (34, 66)
                case 100...128: return (98, 130)
                // No 160 MHz block between 132-144
                case 149...177: return (147, 179)
                default: break
                }
            }
        }

        if band == .band6GHz {
            // IEEE 802.11ax 6 GHz channelization: the scanned/control primary
            // can be any 20 MHz primary inside a 40/80/160 MHz block (e.g. all
            // of 33/37/41/45 live in the same 80 MHz block). Derive the
            // containing block from the primary index instead of extending
            // upward from the primary channel.
            let channelsPerBlock = widthMHz / 20
            let primaryIndex = (primaryChannel - 1) / 4
            let blockStartIndex = (primaryIndex / channelsPerBlock) * channelsPerBlock
            let lowestPrimary = 1 + blockStartIndex * 4
            return (
                lowestPrimary - 2,
                lowestPrimary + channelsPerBlock * 4 - 2
            )
        }

        // Fallback for any unmatched cases
        let half = channelHalfSpan(for: widthMHz)
        return (primaryChannel - half, primaryChannel + half)
    }
}
