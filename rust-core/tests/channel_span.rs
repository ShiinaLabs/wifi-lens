use wifi_lens_core::{
    channel_block, channel_half_span, wifi_lens_channel_block, wifi_lens_channel_half_span,
    ChannelBand, ChannelSpanError, SpanDirection, WIFI_LENS_STATUS_INVALID_BAND,
    WIFI_LENS_STATUS_INVALID_DIRECTION, WIFI_LENS_STATUS_OK, WIFI_LENS_STATUS_WIDTH_BELOW_20_MHZ,
};

#[test]
fn channel_half_span_matches_existing_swift_cases() {
    for (width_mhz, expected) in [(20, 2), (40, 4), (80, 8), (160, 16), (5, 1), (0, 1)] {
        assert_eq!(channel_half_span(width_mhz), expected);
        assert_eq!(wifi_lens_channel_half_span(width_mhz), expected);
    }
}

#[test]
fn channel_blocks_match_shared_swift_fixtures() {
    let mut case_count = 0;
    for (line_index, line) in include_str!("fixtures/channel-span-cases.tsv")
        .lines()
        .enumerate()
    {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }

        let fields: Vec<_> = line.split_whitespace().collect();
        assert_eq!(
            fields.len(),
            6,
            "invalid fixture on line {}",
            line_index + 1
        );
        let primary_channel = fields[0].parse::<i64>().unwrap();
        let width_mhz = fields[1].parse::<i64>().unwrap();
        let band = match fields[2] {
            "24" => ChannelBand::Band2_4Ghz,
            "5" => ChannelBand::Band5Ghz,
            "6" => ChannelBand::Band6Ghz,
            value => panic!("invalid band {value} on line {}", line_index + 1),
        };
        let span_direction = match fields[3] {
            "upper" => Some(SpanDirection::Upper),
            "lower" => Some(SpanDirection::Lower),
            "-" => None,
            value => panic!("invalid span direction {value} on line {}", line_index + 1),
        };
        let expected_left = fields[4].parse::<i64>().unwrap();
        let expected_right = fields[5].parse::<i64>().unwrap();
        let actual = channel_block(primary_channel, width_mhz, band, span_direction).unwrap();

        assert_eq!(
            (actual.left, actual.right),
            (expected_left, expected_right),
            "fixture line {}",
            line_index + 1,
        );

        let band_code = match band {
            ChannelBand::Band2_4Ghz => 1,
            ChannelBand::Band5Ghz => 2,
            ChannelBand::Band6Ghz => 3,
        };
        let direction_code = match span_direction {
            None => 0,
            Some(SpanDirection::Upper) => 1,
            Some(SpanDirection::Lower) => 2,
        };
        let ffi = wifi_lens_channel_block(primary_channel, width_mhz, band_code, direction_code);
        assert_eq!(
            ffi.status,
            WIFI_LENS_STATUS_OK,
            "fixture line {}",
            line_index + 1
        );
        assert_eq!(
            (ffi.left, ffi.right),
            (expected_left, expected_right),
            "C ABI fixture line {}",
            line_index + 1,
        );
        case_count += 1;
    }
    assert_eq!(case_count, 45, "unexpected shared fixture count");
}

#[test]
fn narrow_six_ghz_widths_return_an_error_instead_of_dividing_by_zero() {
    for width_mhz in [i64::MIN, -1, 0, 1, 19] {
        assert_eq!(
            channel_block(5, width_mhz, ChannelBand::Band6Ghz, None),
            Err(ChannelSpanError::SixGhzWidthBelow20Mhz { width_mhz }),
        );
        assert_eq!(
            wifi_lens_channel_block(5, width_mhz, 3, 0).status,
            WIFI_LENS_STATUS_WIDTH_BELOW_20_MHZ,
        );
    }
}

#[test]
fn c_abi_rejects_unknown_band_and_direction_codes() {
    assert_eq!(
        wifi_lens_channel_block(6, 20, 0, 0).status,
        WIFI_LENS_STATUS_INVALID_BAND,
    );
    assert_eq!(
        wifi_lens_channel_block(6, 40, 1, 3).status,
        WIFI_LENS_STATUS_INVALID_DIRECTION,
    );
}
