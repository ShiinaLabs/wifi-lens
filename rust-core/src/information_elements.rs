use crate::{
    WIFI_LENS_STATUS_INVALID_POINTER, WIFI_LENS_STATUS_OUTPUT_TOO_SMALL, WIFI_LENS_STATUS_PANIC,
};

const FLAG_SUPPORTS_80211K: u32 = 1 << 0;
const FLAG_SUPPORTS_80211R: u32 = 1 << 1;
const FLAG_SUPPORTS_80211V: u32 = 1 << 2;
const FLAG_SUPPORTS_80211W: u32 = 1 << 3;
const FLAG_SUPPORTS_WPA3: u32 = 1 << 4;
const FLAG_HT_SUPPORTED: u32 = 1 << 5;
const FLAG_VHT_SUPPORTED: u32 = 1 << 6;
const FLAG_HE_SUPPORTED: u32 = 1 << 7;
const FLAG_EHT_SUPPORTED: u32 = 1 << 8;
const FLAG_SUPPORTS_40_MHZ: u32 = 1 << 9;
const FLAG_HIDDEN_SSID: u32 = 1 << 10;
const FLAG_HAS_COUNTRY_CODE: u32 = 1 << 11;
const FLAG_HAS_GROUP_CIPHER: u32 = 1 << 12;
const RSN_OUI: [u8; 3] = [0x00, 0x0F, 0xAC];

#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct IEData {
    pub supports_80211k: bool,
    pub supports_80211r: bool,
    pub supports_80211v: bool,
    pub supports_80211w: bool,
    pub supports_wpa3: bool,
    pub ht_supported: bool,
    pub vht_supported: bool,
    pub he_supported: bool,
    pub eht_supported: bool,
    pub supports_40_mhz: bool,
    pub ht_channel_operation: Option<i32>,
    pub vht_channel_operation: Option<i32>,
    pub max_mcs_index: Option<i32>,
    pub spatial_streams: Option<i32>,
    pub akm_suites: Vec<&'static str>,
    pub pairwise_ciphers: Vec<&'static str>,
    pub group_cipher: Option<&'static str>,
    pub country_code: Option<[u8; 3]>,
    pub is_hidden_ssid: bool,
}

fn parse_ht_capabilities(data: &[u8], result: &mut IEData) {
    let ht_capabilities = u16::from_le_bytes([data[0], data[1]]);
    result.supports_40_mhz = ht_capabilities & (1 << 1) != 0;

    let mcs_bytes = &data[3..13];
    let mut highest_global = None;
    for (byte_index, byte) in mcs_bytes.iter().take(4).enumerate() {
        for bit in 0..8 {
            if byte & (1 << bit) != 0 {
                let index = (byte_index * 8 + bit) as i32;
                highest_global =
                    Some(highest_global.map_or(index, |current: i32| current.max(index)));
            }
        }
    }

    match highest_global {
        Some(index @ 0..=31) => {
            result.max_mcs_index = Some(index % 8);
            result.spatial_streams = Some(index / 8 + 1);
        }
        _ => {
            result.max_mcs_index = None;
            result.spatial_streams = None;
        }
    }
}

fn parse_ht_operation(data: &[u8], result: &mut IEData) {
    let operation_info = data[1];
    let secondary_channel_offset = operation_info & 0x03;
    let sta_channel_width_any = operation_info & 0x04 != 0;
    result.ht_channel_operation = match (secondary_channel_offset, sta_channel_width_any) {
        (0, _) => Some(0),
        (1, true) => Some(1),
        (3, true) => Some(2),
        (1 | 3, false) => Some(0),
        _ => None,
    };
}

fn parse_vht_operation(data: &[u8], result: &mut IEData) {
    let channel_width = data[0];
    let segment_0 = i32::from(data[1]);
    let segment_1 = i32::from(data[2]);
    result.vht_channel_operation = match channel_width {
        0 => Some(0),
        1 if segment_0 == 0 || segment_1 == 0 => Some(1),
        1 => {
            let difference = (segment_1 - segment_0).abs();
            if difference == 8 {
                Some(2)
            } else if difference > 16 {
                Some(3)
            } else {
                Some(1)
            }
        }
        2 => Some(2),
        3 => Some(3),
        _ => None,
    };
}

fn valid_he_capabilities(data: &[u8]) -> bool {
    const FIXED_LENGTH: usize = 17;
    const BASE_MCS_NSS_LENGTH: usize = 4;

    if data.len() < FIXED_LENGTH {
        return false;
    }

    let phy_capabilities_byte_0 = data[6];
    let mut required_length = FIXED_LENGTH + BASE_MCS_NSS_LENGTH;
    if phy_capabilities_byte_0 & 0x08 != 0 {
        required_length += 4;
    }
    if phy_capabilities_byte_0 & 0x10 != 0 {
        required_length += 4;
    }
    if data.len() < required_length {
        return false;
    }

    let phy_capabilities_byte_6 = data[12];
    if phy_capabilities_byte_6 & 0x80 == 0 {
        return true;
    }
    if data.len() == required_length {
        return false;
    }

    let ppe_header = data[required_length];
    let ru_count = (ppe_header & 0x78).count_ones() as usize;
    let nss_count = usize::from(ppe_header & 0x07) + 1;
    let ppe_bits = 7 + ru_count * nss_count * 6;
    let ppe_length = ppe_bits.div_ceil(8);
    data.len() >= required_length + ppe_length
}

fn cipher_suite_name(suite: &[u8]) -> &'static str {
    if suite[..3] != RSN_OUI {
        return "Unknown";
    }
    match suite[3] {
        0x00 => "None",
        0x01 => "WEP-40",
        0x02 => "TKIP",
        0x04 => "CCMP (AES)",
        0x05 => "WEP-104",
        0x06 => "BIP-CMAC-128",
        0x07 => "No Group Addressed",
        0x08 => "GCMP-128",
        0x09 => "GCMP-256",
        0x0A => "CCMP-256",
        0x0B => "BIP-GMAC-128",
        0x0C => "BIP-GMAC-256",
        0x0D => "BIP-CMAC-256",
        _ => "Unknown",
    }
}

fn akm_suite_name(suite: &[u8]) -> &'static str {
    if suite[..3] != RSN_OUI {
        return "Unknown";
    }
    match suite[3] {
        0x01 => "802.1X",
        0x02 => "PSK",
        0x03 => "FT/802.1X",
        0x04 => "FT/PSK",
        0x05 => "802.1X-SHA256",
        0x06 => "PSK-SHA256",
        0x07 => "TDLS",
        0x08 => "SAE",
        0x09 => "FT-SAE",
        0x0A => "AP PeerKey",
        0x0B => "802.1X-Suite-B",
        0x0C => "802.1X-Suite-B-192",
        0x0D => "FT/802.1X-SHA384",
        0x0E => "FILS-SHA256",
        0x0F => "FILS-SHA384",
        0x10 => "FT-FILS-SHA256",
        0x11 => "FT-FILS-SHA384",
        0x12 => "OWE",
        _ => "Unknown",
    }
}

fn append_unique(values: &mut Vec<&'static str>, value: &'static str) {
    if !values.contains(&value) {
        values.push(value);
    }
}

fn parse_rsn(data: &[u8], result: &mut IEData) {
    if data.len() < 2 {
        return;
    }
    let mut position = 2;
    if data.len() - position < 4 {
        return;
    }
    let group_cipher = cipher_suite_name(&data[position..position + 4]);
    position += 4;

    if data.len() - position < 2 {
        return;
    }
    let pairwise_count = usize::from(u16::from_le_bytes([data[position], data[position + 1]]));
    position += 2;
    if pairwise_count == 0 || pairwise_count > (data.len() - position) / 4 {
        return;
    }

    let mut pairwise_ciphers = Vec::new();
    for suite in data[position..position + pairwise_count * 4].chunks_exact(4) {
        append_unique(&mut pairwise_ciphers, cipher_suite_name(suite));
    }
    position += pairwise_count * 4;

    if data.len() - position < 2 {
        return;
    }
    let akm_count = usize::from(u16::from_le_bytes([data[position], data[position + 1]]));
    position += 2;
    if akm_count == 0 || akm_count > (data.len() - position) / 4 {
        return;
    }

    let mut akm_suites = Vec::new();
    let mut supports_wpa3 = false;
    let mut supports_80211r = false;
    for suite in data[position..position + akm_count * 4].chunks_exact(4) {
        append_unique(&mut akm_suites, akm_suite_name(suite));
        if suite[..3] == RSN_OUI {
            supports_wpa3 |= matches!(suite[3], 0x08 | 0x09 | 0x0C);
            supports_80211r |= matches!(suite[3], 0x03 | 0x04 | 0x09 | 0x0D | 0x10 | 0x11);
        }
    }
    position += akm_count * 4;

    let supports_80211w = if data.len() - position >= 2 {
        Some(u16::from_le_bytes([data[position], data[position + 1]]) & (1 << 7) != 0)
    } else {
        None
    };

    result.group_cipher = Some(group_cipher);
    for cipher in pairwise_ciphers {
        append_unique(&mut result.pairwise_ciphers, cipher);
    }
    for suite in akm_suites {
        append_unique(&mut result.akm_suites, suite);
    }
    result.supports_wpa3 |= supports_wpa3;
    result.supports_80211r |= supports_80211r;
    if let Some(supports_80211w) = supports_80211w {
        result.supports_80211w = supports_80211w;
    }
}

pub fn parse(data: &[u8]) -> IEData {
    const TAG_SSID: u8 = 0;
    const TAG_COUNTRY: u8 = 7;
    const TAG_HT_CAPABILITIES: u8 = 45;
    const TAG_RSN: u8 = 48;
    const TAG_MOBILITY_DOMAIN: u8 = 54;
    const TAG_HT_OPERATION: u8 = 61;
    const TAG_RM_ENABLED: u8 = 70;
    const TAG_EXTENDED_CAPABILITIES: u8 = 127;
    const TAG_VHT_CAPABILITIES: u8 = 191;
    const TAG_VHT_OPERATION: u8 = 192;
    const TAG_EXTENSION: u8 = 255;
    const EXTENSION_HE_CAPABILITIES: u8 = 35;

    let mut result = IEData::default();
    let mut offset = 0;
    while data.len() - offset >= 2 {
        let tag = data[offset];
        let length = usize::from(data[offset + 1]);
        offset += 2;
        if length > data.len() - offset {
            break;
        }
        let element = &data[offset..offset + length];

        match tag {
            TAG_SSID => result.is_hidden_ssid = length == 0,
            TAG_COUNTRY if length >= 3 && element[..3].is_ascii() => {
                result.country_code = Some([element[0], element[1], element[2]])
            }
            TAG_HT_CAPABILITIES if length >= 26 => {
                result.ht_supported = true;
                parse_ht_capabilities(element, &mut result);
            }
            TAG_VHT_CAPABILITIES if length >= 12 => result.vht_supported = true,
            TAG_HT_OPERATION if length >= 22 => parse_ht_operation(element, &mut result),
            TAG_VHT_OPERATION if length >= 5 => parse_vht_operation(element, &mut result),
            TAG_RSN => parse_rsn(element, &mut result),
            TAG_EXTENDED_CAPABILITIES => {
                let transition_bit = 19;
                let byte_index = transition_bit / 8;
                result.supports_80211v = byte_index < element.len()
                    && element[byte_index] & (1 << (transition_bit % 8)) != 0;
            }
            TAG_RM_ENABLED if length >= 5 => result.supports_80211k = true,
            TAG_MOBILITY_DOMAIN if length >= 3 => result.supports_80211r = true,
            TAG_EXTENSION if element.first() == Some(&EXTENSION_HE_CAPABILITIES) => {
                result.he_supported |= valid_he_capabilities(&element[1..]);
            }
            _ => {}
        }

        offset += length;
    }

    result
}

fn encode_result(
    parsed: &IEData,
    group_cipher_range: Option<WiFiLensIEStringRange>,
) -> WiFiLensIEParseResult {
    let mut flags = 0;
    flags |= u32::from(parsed.supports_80211k) * FLAG_SUPPORTS_80211K;
    flags |= u32::from(parsed.supports_80211r) * FLAG_SUPPORTS_80211R;
    flags |= u32::from(parsed.supports_80211v) * FLAG_SUPPORTS_80211V;
    flags |= u32::from(parsed.supports_80211w) * FLAG_SUPPORTS_80211W;
    flags |= u32::from(parsed.supports_wpa3) * FLAG_SUPPORTS_WPA3;
    flags |= u32::from(parsed.ht_supported) * FLAG_HT_SUPPORTED;
    flags |= u32::from(parsed.vht_supported) * FLAG_VHT_SUPPORTED;
    flags |= u32::from(parsed.he_supported) * FLAG_HE_SUPPORTED;
    flags |= u32::from(parsed.eht_supported) * FLAG_EHT_SUPPORTED;
    flags |= u32::from(parsed.supports_40_mhz) * FLAG_SUPPORTS_40_MHZ;
    flags |= u32::from(parsed.is_hidden_ssid) * FLAG_HIDDEN_SSID;
    flags |= u32::from(parsed.country_code.is_some()) * FLAG_HAS_COUNTRY_CODE;
    flags |= u32::from(parsed.group_cipher.is_some()) * FLAG_HAS_GROUP_CIPHER;
    let country_code = parsed.country_code.map_or(0, |country| {
        u32::from(country[0]) << 16 | u32::from(country[1]) << 8 | u32::from(country[2])
    });

    WiFiLensIEParseResult {
        flags,
        country_code,
        ht_channel_operation: parsed.ht_channel_operation.unwrap_or(-1),
        vht_channel_operation: parsed.vht_channel_operation.unwrap_or(-1),
        max_mcs_index: parsed.max_mcs_index.unwrap_or(-1),
        spatial_streams: parsed.spatial_streams.unwrap_or(-1),
        group_cipher_offset: group_cipher_range.map_or(0, |range| range.offset),
        group_cipher_length: group_cipher_range.map_or(0, |range| range.length),
    }
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct WiFiLensIEStringRange {
    pub offset: usize,
    pub length: usize,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
pub struct WiFiLensIEParseResult {
    pub flags: u32,
    pub country_code: u32,
    pub ht_channel_operation: i32,
    pub vht_channel_operation: i32,
    pub max_mcs_index: i32,
    pub spatial_streams: i32,
    pub group_cipher_offset: usize,
    pub group_cipher_length: usize,
}

/// C ABI entry point for [`parse`]. All buffers are caller-owned.
///
/// # Safety
///
/// Each non-null pointer must remain valid and correctly aligned for the
/// duration of the call. Input bytes, the result record, count values, and
/// output buffers must not overlap. Null pointers are accepted
/// only for buffers whose corresponding length or capacity is zero.
#[no_mangle]
pub unsafe extern "C" fn wifi_lens_parse_information_elements(
    data: *const u8,
    data_length: usize,
    result: *mut WiFiLensIEParseResult,
    akm_suites: *mut WiFiLensIEStringRange,
    akm_capacity: usize,
    akm_count: *mut usize,
    pairwise_ciphers: *mut WiFiLensIEStringRange,
    pairwise_capacity: usize,
    pairwise_count: *mut usize,
    text: *mut u8,
    text_capacity: usize,
    text_length: *mut usize,
) -> i32 {
    if result.is_null()
        || akm_count.is_null()
        || pairwise_count.is_null()
        || text_length.is_null()
        || (data_length > 0 && data.is_null())
        || (akm_capacity > 0 && akm_suites.is_null())
        || (pairwise_capacity > 0 && pairwise_ciphers.is_null())
        || (text_capacity > 0 && text.is_null())
    {
        return WIFI_LENS_STATUS_INVALID_POINTER;
    }
    unsafe {
        *akm_count = 0;
        *pairwise_count = 0;
        *text_length = 0;
    }

    match std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let input = if data_length == 0 {
            &[]
        } else {
            unsafe { std::slice::from_raw_parts(data, data_length) }
        };
        let parsed = parse(input);
        let required_text_length = parsed.group_cipher.map_or(0, str::len)
            + parsed
                .pairwise_ciphers
                .iter()
                .map(|name| name.len())
                .sum::<usize>()
            + parsed
                .akm_suites
                .iter()
                .map(|name| name.len())
                .sum::<usize>();
        unsafe {
            *akm_count = parsed.akm_suites.len();
            *pairwise_count = parsed.pairwise_ciphers.len();
            *text_length = required_text_length;
        }
        if parsed.akm_suites.len() > akm_capacity
            || parsed.pairwise_ciphers.len() > pairwise_capacity
            || required_text_length > text_capacity
        {
            return Err(WIFI_LENS_STATUS_OUTPUT_TOO_SMALL);
        }

        let mut text_bytes = Vec::with_capacity(required_text_length);
        let group_cipher_range = parsed.group_cipher.map(|name| {
            let range = WiFiLensIEStringRange {
                offset: text_bytes.len(),
                length: name.len(),
            };
            text_bytes.extend_from_slice(name.as_bytes());
            range
        });
        let mut pairwise_ranges = Vec::with_capacity(parsed.pairwise_ciphers.len());
        for name in &parsed.pairwise_ciphers {
            pairwise_ranges.push(WiFiLensIEStringRange {
                offset: text_bytes.len(),
                length: name.len(),
            });
            text_bytes.extend_from_slice(name.as_bytes());
        }
        let mut akm_ranges = Vec::with_capacity(parsed.akm_suites.len());
        for name in &parsed.akm_suites {
            akm_ranges.push(WiFiLensIEStringRange {
                offset: text_bytes.len(),
                length: name.len(),
            });
            text_bytes.extend_from_slice(name.as_bytes());
        }

        unsafe {
            if !text_bytes.is_empty() {
                std::ptr::copy_nonoverlapping(text_bytes.as_ptr(), text, text_bytes.len());
            }
            if !pairwise_ranges.is_empty() {
                std::ptr::copy_nonoverlapping(
                    pairwise_ranges.as_ptr(),
                    pairwise_ciphers,
                    pairwise_ranges.len(),
                );
            }
            if !akm_ranges.is_empty() {
                std::ptr::copy_nonoverlapping(akm_ranges.as_ptr(), akm_suites, akm_ranges.len());
            }
            *result = encode_result(&parsed, group_cipher_range);
        }
        Ok(())
    })) {
        Ok(Ok(())) => crate::WIFI_LENS_STATUS_OK,
        Ok(Err(status)) => status,
        Err(_) => WIFI_LENS_STATUS_PANIC,
    }
}

#[cfg(test)]
mod tests {
    use super::{parse, IEData};

    fn ie(tag: u8, data: &[u8]) -> Vec<u8> {
        let mut result = vec![tag, data.len() as u8];
        result.extend_from_slice(data);
        result
    }

    #[test]
    fn preserves_incomplete_elements_and_unknown_rsn_suites() {
        let mut bytes = ie(0, &[]);
        bytes.extend(ie(7, b"US "));
        bytes.extend(ie(
            48,
            &[
                1, 0, 9, 9, 9, 9, 1, 0, 0, 0x0f, 0xac, 4, 1, 0, 0, 0x0f, 0xac, 0xff,
            ],
        ));
        bytes.extend([45, 26, 0x02]);

        let parsed = parse(&bytes);
        assert!(parsed.is_hidden_ssid);
        assert_eq!(parsed.country_code, Some(*b"US "));
        assert_eq!(parsed.group_cipher, Some("Unknown"));
        assert_eq!(parsed.pairwise_ciphers, ["CCMP (AES)"]);
        assert_eq!(parsed.akm_suites, ["Unknown"]);
        assert!(!parsed.ht_supported);
    }

    #[test]
    fn malformed_rsn_does_not_leave_partial_security_fields() {
        let parsed = parse(&ie(48, &[1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0x0f, 0xac, 4]));
        assert_eq!(parsed, IEData::default());
    }

    #[test]
    fn vht_operation_preserves_unknown_and_non_contiguous_widths() {
        let mut bytes = ie(192, &[1, 42, 58, 0, 0]);
        bytes.extend(ie(192, &[7, 0, 0, 0, 0]));
        let parsed = parse(&bytes);
        assert_eq!(parsed.vht_channel_operation, None);
    }

    #[test]
    fn c_abi_writes_canonical_labels_into_caller_owned_buffers() {
        let mut bytes = ie(0, &[]);
        bytes.extend(ie(
            48,
            &[
                1, 0, 9, 9, 9, 9, 1, 0, 0, 0x0f, 0xac, 4, 1, 0, 0, 0x0f, 0xac, 0xff,
            ],
        ));
        let mut result = super::WiFiLensIEParseResult::default();
        let mut akm_suites = [super::WiFiLensIEStringRange::default(); 256];
        let mut pairwise_ciphers = [super::WiFiLensIEStringRange::default(); 256];
        let mut text = [0u8; crate::WIFI_LENS_IE_MAX_TEXT_BYTES];
        let mut akm_count = 0;
        let mut pairwise_count = 0;
        let mut text_length = 0;
        let status = unsafe {
            super::wifi_lens_parse_information_elements(
                bytes.as_ptr(),
                bytes.len(),
                &mut result,
                akm_suites.as_mut_ptr(),
                akm_suites.len(),
                &mut akm_count,
                pairwise_ciphers.as_mut_ptr(),
                pairwise_ciphers.len(),
                &mut pairwise_count,
                text.as_mut_ptr(),
                text.len(),
                &mut text_length,
            )
        };
        assert_eq!(status, crate::WIFI_LENS_STATUS_OK);
        assert_eq!(akm_count, 1);
        assert_eq!(pairwise_count, 1);
        assert_eq!(
            std::str::from_utf8(
                &text[result.group_cipher_offset
                    ..result.group_cipher_offset + result.group_cipher_length]
            )
            .unwrap(),
            "Unknown"
        );
        let pairwise = pairwise_ciphers[0];
        assert_eq!(
            std::str::from_utf8(&text[pairwise.offset..pairwise.offset + pairwise.length]).unwrap(),
            "CCMP (AES)"
        );
        let akm = akm_suites[0];
        assert_eq!(
            std::str::from_utf8(&text[akm.offset..akm.offset + akm.length]).unwrap(),
            "Unknown"
        );
        assert_eq!(text_length, 24);

        let mut small_result = super::WiFiLensIEParseResult {
            flags: 123,
            ..super::WiFiLensIEParseResult::default()
        };
        let status = unsafe {
            super::wifi_lens_parse_information_elements(
                bytes.as_ptr(),
                bytes.len(),
                &mut small_result,
                std::ptr::null_mut(),
                0,
                &mut akm_count,
                std::ptr::null_mut(),
                0,
                &mut pairwise_count,
                std::ptr::null_mut(),
                0,
                &mut text_length,
            )
        };
        assert_eq!(status, crate::WIFI_LENS_STATUS_OUTPUT_TOO_SMALL);
        assert_eq!((akm_count, pairwise_count, text_length), (1, 1, 24));
        assert_eq!(small_result.flags, 123);

        let status = unsafe {
            super::wifi_lens_parse_information_elements(
                std::ptr::null(),
                1,
                &mut result,
                akm_suites.as_mut_ptr(),
                akm_suites.len(),
                &mut akm_count,
                pairwise_ciphers.as_mut_ptr(),
                pairwise_ciphers.len(),
                &mut pairwise_count,
                text.as_mut_ptr(),
                text.len(),
                &mut text_length,
            )
        };
        assert_eq!(status, crate::WIFI_LENS_STATUS_INVALID_POINTER);
    }
}
