//! Portable Wi-Fi analysis primitives shared by the macOS applications.

mod channel_quality;
mod information_elements;
pub mod link_evidence;
pub mod regulatory;

pub use channel_quality::{
    analyze as analyze_channel_quality, AccessPoint, AnalysisConfiguration, ChannelQuality,
    ChannelWidth, TargetAccessPoint, WiFiLensAccessPointInput, WiFiLensChannelQualityConfig,
    WiFiLensChannelQualityResult,
};
pub use information_elements::{
    parse as parse_information_elements, IEData, WiFiLensIEParseResult, WiFiLensIEStringRange,
};

/// The Wi-Fi band used to select a channel block.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ChannelBand {
    /// 2.4 GHz band.
    Band2_4Ghz,
    /// 5 GHz band.
    Band5Ghz,
    /// 6 GHz band.
    Band6Ghz,
}

/// Direction of a 40 MHz span relative to its primary channel.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum SpanDirection {
    /// The secondary channel is above the primary channel.
    Upper,
    /// The secondary channel is below the primary channel.
    Lower,
}

/// Inclusive channel-number endpoints of a calculated block.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct ChannelBlock {
    /// Lowest channel number in the block.
    pub left: i64,
    /// Highest channel number in the block.
    pub right: i64,
}

/// Invalid channel-span input.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ChannelSpanError {
    /// 6 GHz block calculation requires a width of at least 20 MHz.
    SixGhzWidthBelow20Mhz { width_mhz: i64 },
}

/// Convert a channel width in MHz into the half-span in channel-number steps.
///
/// Channel numbers are spaced 5 MHz apart. This preserves the existing Swift
/// calculation, including its minimum half-span of one channel step.
pub fn channel_half_span(width_mhz: i64) -> i64 {
    let total_steps = (width_mhz as f64 / 5.0).round() as i64;
    (total_steps / 2).max(1)
}

/// Calculate the channel block containing a primary channel.
///
/// The band-specific blocks and fallback behavior match the existing Swift
/// `ChannelSpanCalculator`. In the 6 GHz branch, widths below 20 MHz return an
/// error instead of reaching a zero-divisor panic.
pub fn channel_block(
    primary_channel: i64,
    width_mhz: i64,
    band: ChannelBand,
    span_direction: Option<SpanDirection>,
) -> Result<ChannelBlock, ChannelSpanError> {
    if width_mhz == 20 {
        return Ok(ChannelBlock {
            left: primary_channel - 2,
            right: primary_channel + 2,
        });
    }

    if band == ChannelBand::Band2_4Ghz && width_mhz == 40 {
        let use_upper = match span_direction {
            Some(SpanDirection::Upper) => true,
            Some(SpanDirection::Lower) => false,
            None => primary_channel <= 7,
        };
        return Ok(if use_upper {
            ChannelBlock {
                left: primary_channel - 2,
                right: primary_channel + 6,
            }
        } else {
            ChannelBlock {
                left: primary_channel - 6,
                right: primary_channel + 2,
            }
        });
    }

    if band == ChannelBand::Band5Ghz {
        let block = match width_mhz {
            40 => match primary_channel {
                36..=40 => Some(ChannelBlock {
                    left: 34,
                    right: 42,
                }),
                44..=48 => Some(ChannelBlock {
                    left: 42,
                    right: 50,
                }),
                52..=56 => Some(ChannelBlock {
                    left: 50,
                    right: 58,
                }),
                60..=64 => Some(ChannelBlock {
                    left: 58,
                    right: 66,
                }),
                100..=104 => Some(ChannelBlock {
                    left: 98,
                    right: 106,
                }),
                108..=112 => Some(ChannelBlock {
                    left: 106,
                    right: 114,
                }),
                116..=120 => Some(ChannelBlock {
                    left: 114,
                    right: 122,
                }),
                124..=128 => Some(ChannelBlock {
                    left: 122,
                    right: 130,
                }),
                132..=136 => Some(ChannelBlock {
                    left: 130,
                    right: 138,
                }),
                140..=144 => Some(ChannelBlock {
                    left: 138,
                    right: 146,
                }),
                149..=153 => Some(ChannelBlock {
                    left: 147,
                    right: 155,
                }),
                157..=161 => Some(ChannelBlock {
                    left: 155,
                    right: 163,
                }),
                165..=169 => Some(ChannelBlock {
                    left: 163,
                    right: 171,
                }),
                173..=177 => Some(ChannelBlock {
                    left: 171,
                    right: 179,
                }),
                _ => None,
            },
            80 => match primary_channel {
                36..=48 => Some(ChannelBlock {
                    left: 34,
                    right: 50,
                }),
                52..=64 => Some(ChannelBlock {
                    left: 50,
                    right: 66,
                }),
                100..=112 => Some(ChannelBlock {
                    left: 98,
                    right: 114,
                }),
                116..=128 => Some(ChannelBlock {
                    left: 114,
                    right: 130,
                }),
                132..=144 => Some(ChannelBlock {
                    left: 130,
                    right: 146,
                }),
                149..=161 => Some(ChannelBlock {
                    left: 147,
                    right: 163,
                }),
                165..=177 => Some(ChannelBlock {
                    left: 163,
                    right: 179,
                }),
                _ => None,
            },
            160 => match primary_channel {
                36..=64 => Some(ChannelBlock {
                    left: 34,
                    right: 66,
                }),
                100..=128 => Some(ChannelBlock {
                    left: 98,
                    right: 130,
                }),
                149..=177 => Some(ChannelBlock {
                    left: 147,
                    right: 179,
                }),
                _ => None,
            },
            _ => None,
        };
        if let Some(block) = block {
            return Ok(block);
        }
    }

    if band == ChannelBand::Band6Ghz {
        if width_mhz < 20 {
            return Err(ChannelSpanError::SixGhzWidthBelow20Mhz { width_mhz });
        }

        // IEEE 802.11ax channelization: the primary can be any 20 MHz channel
        // inside a wider block, so derive the containing block from its index.
        let channels_per_block = width_mhz / 20;
        let primary_index = (primary_channel - 1) / 4;
        let block_start_index = (primary_index / channels_per_block) * channels_per_block;
        let lowest_primary = 1 + block_start_index * 4;
        return Ok(ChannelBlock {
            left: lowest_primary - 2,
            right: lowest_primary + channels_per_block * 4 - 2,
        });
    }

    let half = channel_half_span(width_mhz);
    Ok(ChannelBlock {
        left: primary_channel - half,
        right: primary_channel + half,
    })
}

/// C-compatible result returned by [`wifi_lens_channel_block`].
#[repr(C)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct WiFiLensChannelBlockResult {
    /// Zero on success, otherwise one of the `WIFI_LENS_STATUS_*` values.
    pub status: i32,
    /// Lowest channel number when status is zero.
    pub left: i64,
    /// Highest channel number when status is zero.
    pub right: i64,
}

pub const WIFI_LENS_STATUS_OK: i32 = 0;
pub const WIFI_LENS_STATUS_INVALID_BAND: i32 = 1;
pub const WIFI_LENS_STATUS_INVALID_DIRECTION: i32 = 2;
pub const WIFI_LENS_STATUS_WIDTH_BELOW_20_MHZ: i32 = 3;
pub const WIFI_LENS_STATUS_PANIC: i32 = 4;
pub const WIFI_LENS_STATUS_INVALID_POINTER: i32 = 5;
pub const WIFI_LENS_STATUS_INVALID_INPUT_SLICE: i32 = 6;
pub const WIFI_LENS_STATUS_OUTPUT_TOO_SMALL: i32 = 7;
pub const WIFI_LENS_STATUS_INVALID_UTF8: i32 = 8;
pub const WIFI_LENS_STATUS_INVALID_WIDTH: i32 = 9;
pub const WIFI_LENS_STATUS_INVALID_LINK_EVIDENCE: i32 = 10;
pub const WIFI_LENS_STATUS_INVALID_REGULATORY_INPUT: i32 = 11;
pub const WIFI_LENS_MAX_CHANNEL_QUALITIES: usize = 105;
pub const WIFI_LENS_IE_MAX_TEXT_BYTES: usize = 32 * (256 * 2 + 1);

fn ffi_result(
    operation: impl FnOnce() -> Result<ChannelBlock, i32> + std::panic::UnwindSafe,
) -> WiFiLensChannelBlockResult {
    match std::panic::catch_unwind(operation) {
        Ok(Ok(block)) => WiFiLensChannelBlockResult {
            status: WIFI_LENS_STATUS_OK,
            left: block.left,
            right: block.right,
        },
        Ok(Err(status)) => WiFiLensChannelBlockResult {
            status,
            left: 0,
            right: 0,
        },
        Err(_) => WiFiLensChannelBlockResult {
            status: WIFI_LENS_STATUS_PANIC,
            left: 0,
            right: 0,
        },
    }
}

/// C ABI entry point for [`channel_half_span`].
#[no_mangle]
pub extern "C" fn wifi_lens_channel_half_span(width_mhz: i64) -> i64 {
    channel_half_span(width_mhz)
}

/// C ABI entry point for [`channel_block`].
///
/// Integer codes are defined in `include/wifi_lens_core.h`. Any Rust panic is
/// caught here so it cannot unwind through the C ABI.
#[no_mangle]
pub extern "C" fn wifi_lens_channel_block(
    primary_channel: i64,
    width_mhz: i64,
    band: i32,
    direction: i32,
) -> WiFiLensChannelBlockResult {
    ffi_result(|| {
        let band = match band {
            1 => ChannelBand::Band2_4Ghz,
            2 => ChannelBand::Band5Ghz,
            3 => ChannelBand::Band6Ghz,
            _ => return Err(WIFI_LENS_STATUS_INVALID_BAND),
        };
        let span_direction = match direction {
            0 => None,
            1 => Some(SpanDirection::Upper),
            2 => Some(SpanDirection::Lower),
            _ => return Err(WIFI_LENS_STATUS_INVALID_DIRECTION),
        };

        channel_block(primary_channel, width_mhz, band, span_direction).map_err(|error| match error
        {
            ChannelSpanError::SixGhzWidthBelow20Mhz { .. } => WIFI_LENS_STATUS_WIDTH_BELOW_20_MHZ,
        })
    })
}

#[cfg(test)]
mod tests;
