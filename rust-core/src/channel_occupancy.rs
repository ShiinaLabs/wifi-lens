use crate::{ChannelBand, WIFI_LENS_STATUS_INVALID_INPUT_SLICE, WIFI_LENS_STATUS_INVALID_POINTER};
use std::collections::HashMap;
use std::panic::{catch_unwind, AssertUnwindSafe};

/// One already-acquired AP record used for portable channel-occupancy normalization.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct ChannelOccupancyAccessPoint<'a> {
    pub bssid: &'a str,
    pub band: ChannelBand,
    pub rssi: i64,
    pub operating_width_mhz: i32,
}

/// Selected source row and normalized operating width for one BSSID-band group.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct NormalizedChannelOccupancy {
    pub source_index: usize,
    pub channel_width_mhz: i32,
}

/// Deduplicate byte-exact BSSID-plus-band groups, retaining the strictly strongest RSSI.
/// Equal RSSI retains the first source row; output group order follows first appearance.
pub fn normalize(
    access_points: &[ChannelOccupancyAccessPoint<'_>],
) -> Vec<NormalizedChannelOccupancy> {
    let mut group_indices = HashMap::with_capacity(access_points.len());
    let mut selected_rssi = Vec::with_capacity(access_points.len());
    let mut selected = Vec::with_capacity(access_points.len());

    for (source_index, access_point) in access_points.iter().enumerate() {
        let key = (access_point.band.code(), access_point.bssid);
        if let Some(&output_index) = group_indices.get(&key) {
            if access_point.rssi > selected_rssi[output_index] {
                selected_rssi[output_index] = access_point.rssi;
                selected[output_index] = NormalizedChannelOccupancy {
                    source_index,
                    channel_width_mhz: normalized_width(access_point.operating_width_mhz),
                };
            }
        } else {
            group_indices.insert(key, selected.len());
            selected_rssi.push(access_point.rssi);
            selected.push(NormalizedChannelOccupancy {
                source_index,
                channel_width_mhz: normalized_width(access_point.operating_width_mhz),
            });
        }
    }

    selected
}

fn normalized_width(width_mhz: i32) -> i32 {
    match width_mhz {
        160 | 80 | 40 => width_mhz,
        _ => 20,
    }
}

/// C-compatible input. BSSID bytes refer to one caller-owned UTF-8 buffer.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct WiFiLensChannelOccupancyInput {
    pub band: i32,
    pub rssi: i64,
    pub operating_width_mhz: i32,
    pub bssid_offset: usize,
    pub bssid_length: usize,
}

/// C-compatible output preserving the source row selected by normalization.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct WiFiLensChannelOccupancyResult {
    pub source_index: usize,
    pub channel_width_mhz: i32,
}

impl From<NormalizedChannelOccupancy> for WiFiLensChannelOccupancyResult {
    fn from(value: NormalizedChannelOccupancy) -> Self {
        Self {
            source_index: value.source_index,
            channel_width_mhz: value.channel_width_mhz,
        }
    }
}

fn parse_bssid<'a>(strings: &'a [u8], offset: usize, length: usize) -> Result<&'a str, i32> {
    let end = offset
        .checked_add(length)
        .ok_or(WIFI_LENS_STATUS_INVALID_INPUT_SLICE)?;
    let bytes = strings
        .get(offset..end)
        .ok_or(WIFI_LENS_STATUS_INVALID_INPUT_SLICE)?;
    std::str::from_utf8(bytes).map_err(|_| crate::WIFI_LENS_STATUS_INVALID_UTF8)
}

/// Normalize scan rows before RF scoring. All pointers and buffers remain caller-owned.
/// The output count reports required capacity; undersized output buffers receive no writes.
///
/// # Safety
///
/// Non-null pointers must remain valid and correctly aligned for the call.
/// Writable output must not overlap inputs or the result-count pointer. Null
/// pointers are accepted only for zero-length input/output buffers; the count
/// pointer is required.
#[no_mangle]
pub unsafe extern "C" fn wifi_lens_channel_occupancy_normalize(
    access_points: *const WiFiLensChannelOccupancyInput,
    access_point_count: usize,
    strings: *const u8,
    strings_length: usize,
    results: *mut WiFiLensChannelOccupancyResult,
    result_capacity: usize,
    result_count: *mut usize,
) -> i32 {
    if result_count.is_null()
        || (access_point_count > 0 && access_points.is_null())
        || (strings_length > 0 && strings.is_null())
        || (result_capacity > 0 && results.is_null())
    {
        return WIFI_LENS_STATUS_INVALID_POINTER;
    }

    unsafe { *result_count = 0 };
    match catch_unwind(AssertUnwindSafe(|| {
        let input_strings = if strings_length == 0 {
            &[]
        } else {
            unsafe { std::slice::from_raw_parts(strings, strings_length) }
        };
        let raw_access_points = if access_point_count == 0 {
            &[]
        } else {
            unsafe { std::slice::from_raw_parts(access_points, access_point_count) }
        };
        let mut parsed_access_points = Vec::with_capacity(access_point_count);
        for raw in raw_access_points {
            #[cfg(test)]
            if raw.rssi == i64::MIN {
                panic!("test-only panic path");
            }
            let band = ChannelBand::from_code(raw.band)?;
            let bssid = parse_bssid(input_strings, raw.bssid_offset, raw.bssid_length)?;
            parsed_access_points.push(ChannelOccupancyAccessPoint {
                bssid,
                band,
                rssi: raw.rssi,
                operating_width_mhz: raw.operating_width_mhz,
            });
        }

        let normalized = normalize(&parsed_access_points);
        unsafe { *result_count = normalized.len() };
        if normalized.len() > result_capacity {
            return Err(crate::WIFI_LENS_STATUS_OUTPUT_TOO_SMALL);
        }
        if !normalized.is_empty() {
            let output = unsafe { std::slice::from_raw_parts_mut(results, result_capacity) };
            for (destination, source) in output.iter_mut().zip(normalized) {
                *destination = source.into();
            }
        }
        Ok(())
    })) {
        Ok(Ok(())) => crate::WIFI_LENS_STATUS_OK,
        Ok(Err(status)) => status,
        Err(_) => crate::WIFI_LENS_STATUS_PANIC,
    }
}

#[cfg(test)]
mod tests {
    use super::{
        normalize, wifi_lens_channel_occupancy_normalize, ChannelOccupancyAccessPoint,
        NormalizedChannelOccupancy, WiFiLensChannelOccupancyInput, WiFiLensChannelOccupancyResult,
    };
    use crate::{
        ChannelBand, WIFI_LENS_STATUS_INVALID_BAND, WIFI_LENS_STATUS_INVALID_INPUT_SLICE,
        WIFI_LENS_STATUS_INVALID_POINTER, WIFI_LENS_STATUS_INVALID_UTF8, WIFI_LENS_STATUS_OK,
        WIFI_LENS_STATUS_OUTPUT_TOO_SMALL, WIFI_LENS_STATUS_PANIC,
    };

    #[test]
    fn typed_normalization_preserves_identity_band_rssi_ties_and_source_order() {
        let access_points = [
            ChannelOccupancyAccessPoint {
                bssid: "aa:bb",
                band: ChannelBand::Band5Ghz,
                rssi: -50,
                operating_width_mhz: 40,
            },
            ChannelOccupancyAccessPoint {
                bssid: "aa:bb",
                band: ChannelBand::Band5Ghz,
                rssi: -70,
                operating_width_mhz: 80,
            },
            ChannelOccupancyAccessPoint {
                bssid: "aa:bb",
                band: ChannelBand::Band5Ghz,
                rssi: -50,
                operating_width_mhz: 160,
            },
            ChannelOccupancyAccessPoint {
                bssid: "aa:bb",
                band: ChannelBand::Band2_4Ghz,
                rssi: -45,
                operating_width_mhz: 80,
            },
            ChannelOccupancyAccessPoint {
                bssid: "AA:BB",
                band: ChannelBand::Band5Ghz,
                rssi: -60,
                operating_width_mhz: 320,
            },
        ];

        assert_eq!(
            normalize(&access_points),
            [
                NormalizedChannelOccupancy {
                    source_index: 0,
                    channel_width_mhz: 40,
                },
                NormalizedChannelOccupancy {
                    source_index: 3,
                    channel_width_mhz: 80,
                },
                NormalizedChannelOccupancy {
                    source_index: 4,
                    channel_width_mhz: 20,
                },
            ]
        );
    }

    #[test]
    fn typed_normalization_handles_empty_bssid_and_empty_input() {
        assert!(normalize(&[]).is_empty());
        let access_points = [
            ChannelOccupancyAccessPoint {
                bssid: "",
                band: ChannelBand::Band6Ghz,
                rssi: -80,
                operating_width_mhz: 20,
            },
            ChannelOccupancyAccessPoint {
                bssid: "",
                band: ChannelBand::Band6Ghz,
                rssi: -40,
                operating_width_mhz: 80,
            },
        ];
        assert_eq!(
            normalize(&access_points),
            [NormalizedChannelOccupancy {
                source_index: 1,
                channel_width_mhz: 80,
            }]
        );
    }

    #[test]
    fn c_abi_normalizes_and_returns_selected_original_indices() {
        let strings = b"aa:bbcc:dd";
        let inputs = [
            WiFiLensChannelOccupancyInput {
                band: 2,
                rssi: -60,
                operating_width_mhz: 40,
                bssid_offset: 0,
                bssid_length: 5,
            },
            WiFiLensChannelOccupancyInput {
                band: 2,
                rssi: -40,
                operating_width_mhz: 160,
                bssid_offset: 0,
                bssid_length: 5,
            },
            WiFiLensChannelOccupancyInput {
                band: 2,
                rssi: -50,
                operating_width_mhz: 80,
                bssid_offset: 5,
                bssid_length: 5,
            },
        ];
        let mut outputs = [WiFiLensChannelOccupancyResult::default(); 3];
        let mut output_count = 0;
        assert_eq!(
            unsafe {
                wifi_lens_channel_occupancy_normalize(
                    inputs.as_ptr(),
                    inputs.len(),
                    strings.as_ptr(),
                    strings.len(),
                    outputs.as_mut_ptr(),
                    outputs.len(),
                    &mut output_count,
                )
            },
            WIFI_LENS_STATUS_OK
        );
        assert_eq!(output_count, 2);
        assert_eq!(
            &outputs[..output_count],
            [
                WiFiLensChannelOccupancyResult {
                    source_index: 1,
                    channel_width_mhz: 160,
                },
                WiFiLensChannelOccupancyResult {
                    source_index: 2,
                    channel_width_mhz: 80,
                },
            ]
        );
    }

    #[test]
    fn c_abi_rejects_invalid_band_utf8_slices_and_capacity_without_partial_output() {
        let sentinel = WiFiLensChannelOccupancyResult {
            source_index: usize::MAX,
            channel_width_mhz: -1,
        };
        let mut output = [sentinel; 2];
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
            output = [sentinel; 2];
            assert_eq!(
                unsafe {
                    wifi_lens_channel_occupancy_normalize(
                        &input,
                        1,
                        strings.as_ptr(),
                        strings.len(),
                        output.as_mut_ptr(),
                        output.len(),
                        &mut output_count,
                    )
                },
                expected_status
            );
            assert_eq!(output_count, expected_count);
            assert_eq!(output, [sentinel; 2]);
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
                    output.as_mut_ptr(),
                    output.len(),
                    &mut output_count,
                )
            },
            WIFI_LENS_STATUS_INVALID_UTF8
        );
        assert_eq!(output, [sentinel; 2]);
        assert_eq!(output_count, 0);

        let inputs = [base, WiFiLensChannelOccupancyInput { band: 1, ..base }];
        assert_eq!(
            unsafe {
                wifi_lens_channel_occupancy_normalize(
                    inputs.as_ptr(),
                    inputs.len(),
                    strings.as_ptr(),
                    strings.len(),
                    output.as_mut_ptr(),
                    1,
                    &mut output_count,
                )
            },
            WIFI_LENS_STATUS_OUTPUT_TOO_SMALL
        );
        assert_eq!(output_count, 2);
        assert_eq!(output, [sentinel; 2]);
    }

    #[test]
    fn c_abi_rejects_null_pointers_and_catches_panics_without_writing_output() {
        let mut output = [WiFiLensChannelOccupancyResult {
            source_index: usize::MAX,
            channel_width_mhz: -1,
        }];
        let sentinel = output;
        let mut output_count = 77;
        let input = WiFiLensChannelOccupancyInput {
            band: 2,
            rssi: -40,
            operating_width_mhz: 20,
            bssid_offset: 0,
            bssid_length: 0,
        };
        assert_eq!(
            unsafe {
                wifi_lens_channel_occupancy_normalize(
                    std::ptr::null(),
                    1,
                    std::ptr::null(),
                    0,
                    output.as_mut_ptr(),
                    output.len(),
                    &mut output_count,
                )
            },
            WIFI_LENS_STATUS_INVALID_POINTER
        );
        assert_eq!(output, sentinel);

        assert_eq!(
            unsafe {
                wifi_lens_channel_occupancy_normalize(
                    &input,
                    1,
                    std::ptr::null(),
                    1,
                    output.as_mut_ptr(),
                    output.len(),
                    &mut output_count,
                )
            },
            WIFI_LENS_STATUS_INVALID_POINTER
        );
        assert_eq!(output, sentinel);
        assert_eq!(
            unsafe {
                wifi_lens_channel_occupancy_normalize(
                    &input,
                    1,
                    std::ptr::null(),
                    0,
                    std::ptr::null_mut(),
                    1,
                    &mut output_count,
                )
            },
            WIFI_LENS_STATUS_INVALID_POINTER
        );
        assert_eq!(output, sentinel);
        assert_eq!(
            unsafe {
                wifi_lens_channel_occupancy_normalize(
                    &input,
                    1,
                    std::ptr::null(),
                    0,
                    output.as_mut_ptr(),
                    output.len(),
                    std::ptr::null_mut(),
                )
            },
            WIFI_LENS_STATUS_INVALID_POINTER
        );
        assert_eq!(output, sentinel);
        assert_eq!(
            unsafe {
                wifi_lens_channel_occupancy_normalize(
                    std::ptr::null(),
                    0,
                    std::ptr::null(),
                    0,
                    std::ptr::null_mut(),
                    0,
                    &mut output_count,
                )
            },
            WIFI_LENS_STATUS_OK
        );
        assert_eq!(output_count, 0);

        let panic_input = WiFiLensChannelOccupancyInput {
            rssi: i64::MIN,
            ..input
        };
        assert_eq!(
            unsafe {
                wifi_lens_channel_occupancy_normalize(
                    &panic_input,
                    1,
                    std::ptr::null(),
                    0,
                    output.as_mut_ptr(),
                    output.len(),
                    &mut output_count,
                )
            },
            WIFI_LENS_STATUS_PANIC
        );
        assert_eq!(output, sentinel);
        assert_eq!(output_count, 0);
    }
}
