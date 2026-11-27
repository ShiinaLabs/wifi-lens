use wifi_lens_core::channel_occupancy::{
    normalize, wifi_lens_channel_occupancy_normalize, ChannelOccupancyAccessPoint,
    NormalizedChannelOccupancy, WiFiLensChannelOccupancyInput, WiFiLensChannelOccupancyResult,
};
use wifi_lens_core::{
    ChannelBand, WIFI_LENS_STATUS_INVALID_BAND, WIFI_LENS_STATUS_INVALID_INPUT_SLICE,
    WIFI_LENS_STATUS_INVALID_POINTER, WIFI_LENS_STATUS_INVALID_UTF8, WIFI_LENS_STATUS_OK,
    WIFI_LENS_STATUS_OUTPUT_TOO_SMALL,
};

fn parse_band(value: &str) -> ChannelBand {
    match value {
        "1" => ChannelBand::Band2_4Ghz,
        "2" => ChannelBand::Band5Ghz,
        "3" => ChannelBand::Band6Ghz,
        value => panic!("invalid band {value}"),
    }
}

#[test]
fn fixtures_match_typed_and_c_apis() {
    let mut case_count = 0;
    for (line_index, line) in include_str!("fixtures/channel-occupancy-cases.tsv")
        .lines()
        .skip(2)
        .enumerate()
    {
        if line.trim().is_empty() || line.starts_with('#') {
            continue;
        }
        let fields: Vec<_> = line.split_whitespace().collect();
        assert_eq!(
            fields.len(),
            12,
            "invalid fixture on line {}",
            line_index + 1
        );

        let access_points = [
            ChannelOccupancyAccessPoint {
                bssid: fields[1],
                band: parse_band(fields[2]),
                rssi: fields[3].parse().unwrap(),
                operating_width_mhz: fields[4].parse().unwrap(),
            },
            ChannelOccupancyAccessPoint {
                bssid: fields[5],
                band: parse_band(fields[6]),
                rssi: fields[7].parse().unwrap(),
                operating_width_mhz: fields[8].parse().unwrap(),
            },
        ];
        let expected_index: usize = fields[9].parse().unwrap();
        let expected_width: i32 = fields[10].parse().unwrap();
        let expected_count: usize = fields[11].parse().unwrap();
        let normalized = normalize(&access_points);
        assert_eq!(normalized.len(), expected_count, "fixture {}", fields[0]);
        assert_eq!(
            normalized[0],
            NormalizedChannelOccupancy {
                source_index: expected_index,
                channel_width_mhz: expected_width,
            },
            "typed fixture {}",
            fields[0]
        );

        let mut strings = Vec::new();
        let mut inputs = Vec::new();
        for access_point in &access_points {
            let offset = strings.len();
            strings.extend_from_slice(access_point.bssid.as_bytes());
            let band = match access_point.band {
                ChannelBand::Band2_4Ghz => 1,
                ChannelBand::Band5Ghz => 2,
                ChannelBand::Band6Ghz => 3,
            };
            inputs.push(WiFiLensChannelOccupancyInput {
                band,
                rssi: access_point.rssi,
                operating_width_mhz: access_point.operating_width_mhz,
                bssid_offset: offset,
                bssid_length: access_point.bssid.len(),
            });
        }
        let mut outputs = [WiFiLensChannelOccupancyResult::default(); 2];
        let mut output_count = 0;
        let status = unsafe {
            wifi_lens_channel_occupancy_normalize(
                inputs.as_ptr(),
                inputs.len(),
                strings.as_ptr(),
                strings.len(),
                outputs.as_mut_ptr(),
                outputs.len(),
                &mut output_count,
            )
        };
        assert_eq!(status, WIFI_LENS_STATUS_OK, "C ABI fixture {}", fields[0]);
        assert_eq!(output_count, expected_count, "C ABI fixture {}", fields[0]);
        assert_eq!(
            outputs[0],
            WiFiLensChannelOccupancyResult {
                source_index: expected_index,
                channel_width_mhz: expected_width,
            },
            "C ABI fixture {}",
            fields[0]
        );
        case_count += 1;
    }
    assert_eq!(case_count, 6);
}

#[test]
fn c_abi_rejects_invalid_band_utf8_slices_capacity_pointers_and_panics() {
    let sentinel = WiFiLensChannelOccupancyResult {
        source_index: usize::MAX,
        channel_width_mhz: -1,
    };
    let mut outputs = [sentinel; 2];
    let mut output_count = usize::MAX;
    let strings = b"aa";
    let base = WiFiLensChannelOccupancyInput {
        band: 2,
        rssi: -40,
        operating_width_mhz: 40,
        bssid_offset: 0,
        bssid_length: 2,
    };

    for (input, expected_status, expected_count) in [
        (
            WiFiLensChannelOccupancyInput { band: 99, ..base },
            WIFI_LENS_STATUS_INVALID_BAND,
            0,
        ),
        (
            WiFiLensChannelOccupancyInput {
                bssid_offset: 2,
                ..base
            },
            WIFI_LENS_STATUS_INVALID_INPUT_SLICE,
            0,
        ),
        (
            WiFiLensChannelOccupancyInput {
                bssid_length: 3,
                ..base
            },
            WIFI_LENS_STATUS_INVALID_INPUT_SLICE,
            0,
        ),
    ] {
        outputs = [sentinel; 2];
        assert_eq!(
            unsafe {
                wifi_lens_channel_occupancy_normalize(
                    &input,
                    1,
                    strings.as_ptr(),
                    strings.len(),
                    outputs.as_mut_ptr(),
                    outputs.len(),
                    &mut output_count,
                )
            },
            expected_status
        );
        assert_eq!(output_count, expected_count);
        assert_eq!(outputs, [sentinel; 2]);
    }

    let invalid_utf8 = [0xff];
    let invalid_utf8_input = WiFiLensChannelOccupancyInput {
        bssid_length: 1,
        ..base
    };
    assert_eq!(
        unsafe {
            wifi_lens_channel_occupancy_normalize(
                &invalid_utf8_input,
                1,
                invalid_utf8.as_ptr(),
                invalid_utf8.len(),
                outputs.as_mut_ptr(),
                outputs.len(),
                &mut output_count,
            )
        },
        WIFI_LENS_STATUS_INVALID_UTF8
    );

    assert_eq!(
        unsafe {
            wifi_lens_channel_occupancy_normalize(
                std::ptr::null(),
                1,
                std::ptr::null(),
                0,
                outputs.as_mut_ptr(),
                outputs.len(),
                &mut output_count,
            )
        },
        WIFI_LENS_STATUS_INVALID_POINTER
    );
    assert_eq!(
        unsafe {
            wifi_lens_channel_occupancy_normalize(
                &base,
                1,
                strings.as_ptr(),
                strings.len(),
                outputs.as_mut_ptr(),
                outputs.len(),
                std::ptr::null_mut(),
            )
        },
        WIFI_LENS_STATUS_INVALID_POINTER
    );

    let two_groups = [base, WiFiLensChannelOccupancyInput { band: 1, ..base }];
    assert_eq!(
        unsafe {
            wifi_lens_channel_occupancy_normalize(
                two_groups.as_ptr(),
                two_groups.len(),
                strings.as_ptr(),
                strings.len(),
                outputs.as_mut_ptr(),
                1,
                &mut output_count,
            )
        },
        WIFI_LENS_STATUS_OUTPUT_TOO_SMALL
    );
    assert_eq!(output_count, 2);
}
