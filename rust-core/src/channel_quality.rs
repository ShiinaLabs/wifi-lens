use crate::{channel_block, ChannelBand};

const BAND_24: i32 = 1;
const BAND_5: i32 = 2;
const BAND_6: i32 = 3;
const WIDTH_80_PLUS_80: i32 = 8080;
const QUALITY_HAS_CURRENT_CHANNEL: u32 = 1 << 0;
const QUALITY_HAS_TARGET_BSSID: u32 = 1 << 1;
const QUALITY_HAS_TARGET_SSID: u32 = 1 << 2;
const QUALITY_HAS_TARGET_CHANNEL: u32 = 1 << 3;
const QUALITY_KNOWN_FLAGS: u32 = QUALITY_HAS_CURRENT_CHANNEL
    | QUALITY_HAS_TARGET_BSSID
    | QUALITY_HAS_TARGET_SSID
    | QUALITY_HAS_TARGET_CHANNEL;

const BAND_24_MASK: u32 = 1 << 0;
const BAND_5_MASK: u32 = 1 << 1;
const BAND_6_MASK: u32 = 1 << 2;
const BAND_KNOWN_MASK: u32 = BAND_24_MASK | BAND_5_MASK | BAND_6_MASK;

const CONFIDENCE_UNKNOWN: i32 = 0;
const CONFIDENCE_EXACT: i32 = 1;
const CONFIDENCE_SSID_FALLBACK: i32 = 2;

const STATE_RECOMMENDED: i32 = 0;
const STATE_CURRENT_GOOD_ENOUGH: i32 = 1;
const STATE_INSUFFICIENT_IMPROVEMENT: i32 = 2;
const STATE_NOT_CANDIDATE: i32 = 3;
const STATE_TARGET_UNKNOWN: i32 = 4;

const CURRENT_GOOD_ENOUGH_SCORE: i32 = 80;
const MINIMUM_RECOMMENDED_SCORE: i32 = 70;
const MINIMUM_IMPROVEMENT: i32 = 10;
const MAX_RECOMMENDATIONS_PER_BAND: usize = 2;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ChannelWidth {
    Twenty,
    Forty,
    Eighty,
    OneSixty,
    EightyPlusEighty,
}

impl ChannelWidth {
    fn from_mhz(width_mhz: i32) -> Result<Self, i32> {
        match width_mhz {
            20 => Ok(Self::Twenty),
            40 => Ok(Self::Forty),
            80 => Ok(Self::Eighty),
            160 => Ok(Self::OneSixty),
            WIDTH_80_PLUS_80 => Ok(Self::EightyPlusEighty),
            _ => Err(crate::WIFI_LENS_STATUS_INVALID_WIDTH),
        }
    }

    fn interference_multiplier(self) -> f64 {
        match self {
            Self::OneSixty => 2.0,
            Self::Eighty | Self::EightyPlusEighty => 1.5,
            Self::Forty => 1.2,
            Self::Twenty => 1.0,
        }
    }

    fn scalar_span_width(self) -> i64 {
        match self {
            Self::OneSixty => 160,
            Self::Eighty | Self::EightyPlusEighty => 80,
            Self::Forty => 40,
            Self::Twenty => 20,
        }
    }
}

#[derive(Clone, Copy, Debug)]
pub struct AccessPoint<'a> {
    pub channel: i64,
    pub rssi: i64,
    pub channel_width: ChannelWidth,
    pub band: ChannelBand,
    pub bssid: Option<&'a [u8]>,
    pub ssid: Option<&'a [u8]>,
}

#[derive(Clone, Copy, Debug)]
pub struct TargetAccessPoint<'a> {
    pub bssid: Option<&'a [u8]>,
    pub ssid: Option<&'a [u8]>,
    pub channel: Option<i64>,
}

#[derive(Clone, Copy, Debug)]
pub struct AnalysisConfiguration<'a> {
    pub current_channel: Option<i64>,
    pub current_band: Option<ChannelBand>,
    pub supported_band_mask: u32,
    pub target: Option<TargetAccessPoint<'a>>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct ChannelQuality {
    pub channel: i64,
    pub band: ChannelBand,
    pub quality_score: i32,
    pub ap_count: i32,
    pub co_channel_count: i32,
    pub adjacent_count: i32,
    pub interference_score: i32,
    pub strongest_neighbor_rssi: i32,
    pub recommendation_score: i32,
    pub recommendation_confidence: i32,
    pub recommendation_state: i32,
    pub is_recommended: bool,
    pub is_current_channel: bool,
    pub show_in_simple_view: bool,
}

#[derive(Clone, Copy)]
struct ScoreResult {
    score: i32,
    interference: i32,
}

#[derive(Clone, Copy)]
struct TargetResolution<'a> {
    confidence: i32,
    matcher: TargetMatcher<'a>,
}

#[derive(Clone, Copy)]
enum TargetMatcher<'a> {
    None,
    Bssid(&'a [u8]),
    Ssid(&'a [u8], Option<i64>),
}

impl TargetMatcher<'_> {
    fn matches(self, ap: &AccessPoint<'_>) -> bool {
        match self {
            Self::None => false,
            Self::Bssid(bssid) => ap
                .bssid
                .is_some_and(|candidate| candidate.eq_ignore_ascii_case(bssid)),
            Self::Ssid(ssid, channel) => {
                ap.ssid == Some(ssid) && channel.is_none_or(|channel| ap.channel == channel)
            }
        }
    }
}

impl ChannelBand {
    fn code(self) -> i32 {
        match self {
            Self::Band2_4Ghz => BAND_24,
            Self::Band5Ghz => BAND_5,
            Self::Band6Ghz => BAND_6,
        }
    }

    fn from_code(code: i32) -> Result<Self, i32> {
        match code {
            BAND_24 => Ok(Self::Band2_4Ghz),
            BAND_5 => Ok(Self::Band5Ghz),
            BAND_6 => Ok(Self::Band6Ghz),
            _ => Err(crate::WIFI_LENS_STATUS_INVALID_BAND),
        }
    }

    fn mask(self) -> u32 {
        match self {
            Self::Band2_4Ghz => BAND_24_MASK,
            Self::Band5Ghz => BAND_5_MASK,
            Self::Band6Ghz => BAND_6_MASK,
        }
    }

    fn channels(self) -> Vec<i64> {
        match self {
            Self::Band2_4Ghz => (1..=13).collect(),
            Self::Band5Ghz => (36..=144)
                .step_by(4)
                .chain((149..=165).step_by(4))
                .collect(),
            Self::Band6Ghz => (1..=233).step_by(4).collect(),
        }
    }
}

fn overlap_factor(channel: i64, other: &AccessPoint<'_>, band: ChannelBand) -> f64 {
    if other.channel == channel {
        return 1.0;
    }

    if band == ChannelBand::Band2_4Ghz {
        return match (channel - other.channel).abs() {
            1 => 0.8,
            2 => 0.55,
            3 => 0.3,
            4 => 0.15,
            _ => 0.0,
        };
    }

    let candidate_span = channel_block(channel, 20, band, None).expect("20 MHz channel block");
    let ap_span = channel_block(
        other.channel,
        other.channel_width.scalar_span_width(),
        band,
        None,
    )
    .expect("supported AP channel width");
    let overlap =
        (ap_span.right.min(candidate_span.right) - ap_span.left.max(candidate_span.left)).max(0);
    let ap_span_length = (ap_span.right - ap_span.left).max(1);
    (overlap as f64 / ap_span_length as f64).min(1.0)
}

fn score(channel: i64, band: ChannelBand, aps: &[AccessPoint<'_>]) -> ScoreResult {
    let mut penalty = 0.0;
    for ap in aps {
        let factor = overlap_factor(channel, ap, band);
        if factor <= 0.0 {
            continue;
        }

        let rssi_weight = ((ap.rssi + 100) as f64 / 70.0).clamp(0.0, 1.0);
        let band_multiplier = if band == ChannelBand::Band2_4Ghz {
            1.8
        } else {
            1.0
        };
        penalty += factor
            * rssi_weight
            * ap.channel_width.interference_multiplier()
            * band_multiplier
            * 18.0;
    }

    let interference = penalty.round() as i32;
    ScoreResult {
        score: (100 - interference).clamp(0, 100),
        interference,
    }
}

fn resolve_target<'a>(
    target: Option<TargetAccessPoint<'a>>,
    aps: &[AccessPoint<'_>],
) -> TargetResolution<'a> {
    let Some(target) = target else {
        return TargetResolution {
            confidence: CONFIDENCE_UNKNOWN,
            matcher: TargetMatcher::None,
        };
    };

    if let Some(bssid) = target.bssid {
        return TargetResolution {
            confidence: CONFIDENCE_EXACT,
            matcher: TargetMatcher::Bssid(bssid),
        };
    }

    if let Some(ssid) = target.ssid {
        let mut matching_count = 0;
        for ap in aps {
            if ap.ssid == Some(ssid) && target.channel.is_none_or(|channel| ap.channel == channel) {
                matching_count += 1;
            }
        }
        if matching_count == 1 {
            return TargetResolution {
                confidence: CONFIDENCE_SSID_FALLBACK,
                matcher: TargetMatcher::Ssid(ssid, target.channel),
            };
        }
    }

    TargetResolution {
        confidence: CONFIDENCE_UNKNOWN,
        matcher: TargetMatcher::None,
    }
}

fn initially_visible(result: &ChannelQuality) -> bool {
    result.is_current_channel || result.is_recommended || result.ap_count > 0
}

fn apply_counterfactual_selection(results: &mut [ChannelQuality], current_channel: Option<i64>) {
    let confidence = results.first().map_or(CONFIDENCE_UNKNOWN, |result| {
        result.recommendation_confidence
    });
    let Some(current_channel) = current_channel.filter(|_| confidence != CONFIDENCE_UNKNOWN) else {
        for result in results {
            result.show_in_simple_view = initially_visible(result);
        }
        return;
    };

    let Some(current) = results
        .iter()
        .find(|result| result.channel == current_channel)
    else {
        for result in results {
            result.show_in_simple_view = initially_visible(result);
        }
        return;
    };

    if current.recommendation_score >= CURRENT_GOOD_ENOUGH_SCORE {
        for result in results {
            if result.channel == current_channel {
                result.recommendation_state = STATE_CURRENT_GOOD_ENOUGH;
            }
            result.show_in_simple_view = initially_visible(result);
        }
        return;
    }

    let mut candidates = results
        .iter()
        .filter(|candidate| {
            candidate.channel != current_channel
                && candidate.recommendation_score >= MINIMUM_RECOMMENDED_SCORE
                && candidate.recommendation_score - current.recommendation_score
                    >= MINIMUM_IMPROVEMENT
        })
        .copied()
        .collect::<Vec<_>>();
    candidates.sort_by(|a, b| {
        b.recommendation_score
            .cmp(&a.recommendation_score)
            .then_with(|| b.quality_score.cmp(&a.quality_score))
            .then_with(|| a.channel.cmp(&b.channel))
    });
    let selected_channels = candidates
        .iter()
        .take(MAX_RECOMMENDATIONS_PER_BAND)
        .map(|candidate| candidate.channel)
        .collect::<Vec<_>>();

    for result in results {
        if selected_channels.contains(&result.channel) {
            result.is_recommended = true;
            result.recommendation_state = STATE_RECOMMENDED;
        } else if result.channel != current_channel {
            result.recommendation_state = STATE_INSUFFICIENT_IMPROVEMENT;
        }
        result.show_in_simple_view = initially_visible(result);
    }
}

pub fn analyze(
    aps: &[AccessPoint<'_>],
    configuration: AnalysisConfiguration<'_>,
) -> Vec<ChannelQuality> {
    let mut results = Vec::new();

    for band in [
        ChannelBand::Band2_4Ghz,
        ChannelBand::Band5Ghz,
        ChannelBand::Band6Ghz,
    ] {
        if configuration.supported_band_mask & band.mask() == 0 {
            continue;
        }

        let band_aps = aps
            .iter()
            .copied()
            .filter(|ap| ap.band == band)
            .collect::<Vec<_>>();
        let band_current_channel =
            if configuration.current_band.is_none() || configuration.current_band == Some(band) {
                configuration.current_channel
            } else {
                None
            };
        let target = resolve_target(configuration.target, &band_aps);
        let recommendation_aps = band_aps
            .iter()
            .copied()
            .filter(|ap| target.confidence == CONFIDENCE_UNKNOWN || !target.matcher.matches(ap))
            .collect::<Vec<_>>();

        let mut band_results = band
            .channels()
            .into_iter()
            .map(|channel| {
                let observed = score(channel, band, &band_aps);
                let recommendation = score(channel, band, &recommendation_aps);
                let overlapping = band_aps
                    .iter()
                    .filter(|ap| overlap_factor(channel, ap, band) > 0.0)
                    .collect::<Vec<_>>();
                let ap_count = overlapping.len() as i32;
                let co_channel_count =
                    band_aps.iter().filter(|ap| ap.channel == channel).count() as i32;
                let adjacent_count = ap_count - co_channel_count;
                let strongest_neighbor_rssi =
                    overlapping.iter().map(|ap| ap.rssi).max().unwrap_or(-100) as i32;
                let recommendation_state = if target.confidence == CONFIDENCE_UNKNOWN {
                    STATE_TARGET_UNKNOWN
                } else {
                    STATE_NOT_CANDIDATE
                };

                ChannelQuality {
                    channel,
                    band,
                    quality_score: observed.score,
                    ap_count,
                    co_channel_count,
                    adjacent_count,
                    interference_score: observed.interference,
                    strongest_neighbor_rssi,
                    recommendation_score: recommendation.score,
                    recommendation_confidence: target.confidence,
                    recommendation_state,
                    is_recommended: false,
                    is_current_channel: Some(channel) == band_current_channel,
                    show_in_simple_view: false,
                }
            })
            .collect::<Vec<_>>();

        apply_counterfactual_selection(&mut band_results, band_current_channel);
        results.extend(band_results);
    }

    results.sort_by(|a, b| {
        b.is_current_channel
            .cmp(&a.is_current_channel)
            .then_with(|| b.is_recommended.cmp(&a.is_recommended))
            .then_with(|| b.recommendation_score.cmp(&a.recommendation_score))
            .then_with(|| b.quality_score.cmp(&a.quality_score))
            .then_with(|| a.band.code().cmp(&b.band.code()))
            .then_with(|| a.channel.cmp(&b.channel))
    });
    results
}

fn read_string_slice<'a>(strings: &'a [u8], offset: usize, length: usize) -> Result<&'a [u8], i32> {
    let end = offset
        .checked_add(length)
        .ok_or(crate::WIFI_LENS_STATUS_INVALID_INPUT_SLICE)?;
    strings
        .get(offset..end)
        .ok_or(crate::WIFI_LENS_STATUS_INVALID_INPUT_SLICE)
}

fn parse_utf8_slice<'a>(strings: &'a [u8], offset: usize, length: usize) -> Result<&'a [u8], i32> {
    let value = read_string_slice(strings, offset, length)?;
    std::str::from_utf8(value).map_err(|_| crate::WIFI_LENS_STATUS_INVALID_UTF8)?;
    Ok(value)
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
pub struct WiFiLensAccessPointInput {
    pub channel: i64,
    pub rssi: i64,
    pub band: i32,
    pub channel_width_mhz: i32,
    pub bssid_offset: usize,
    pub bssid_length: usize,
    pub ssid_offset: usize,
    pub ssid_length: usize,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
pub struct WiFiLensChannelQualityConfig {
    pub flags: u32,
    pub current_channel: i64,
    pub target_channel: i64,
    pub current_band: i32,
    pub supported_band_mask: u32,
    pub target_bssid_offset: usize,
    pub target_bssid_length: usize,
    pub target_ssid_offset: usize,
    pub target_ssid_length: usize,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
pub struct WiFiLensChannelQualityResult {
    pub channel: i64,
    pub band: i32,
    pub quality_score: i32,
    pub ap_count: i32,
    pub co_channel_count: i32,
    pub adjacent_count: i32,
    pub interference_score: i32,
    pub strongest_neighbor_rssi: i32,
    pub recommendation_score: i32,
    pub recommendation_confidence: i32,
    pub recommendation_state: i32,
    pub is_recommended: u8,
    pub is_current_channel: u8,
    pub show_in_simple_view: u8,
}

impl From<ChannelQuality> for WiFiLensChannelQualityResult {
    fn from(result: ChannelQuality) -> Self {
        Self {
            channel: result.channel,
            band: result.band.code(),
            quality_score: result.quality_score,
            ap_count: result.ap_count,
            co_channel_count: result.co_channel_count,
            adjacent_count: result.adjacent_count,
            interference_score: result.interference_score,
            strongest_neighbor_rssi: result.strongest_neighbor_rssi,
            recommendation_score: result.recommendation_score,
            recommendation_confidence: result.recommendation_confidence,
            recommendation_state: result.recommendation_state,
            is_recommended: u8::from(result.is_recommended),
            is_current_channel: u8::from(result.is_current_channel),
            show_in_simple_view: u8::from(result.show_in_simple_view),
        }
    }
}

/// C ABI entry point for [`analyze`]. The caller retains ownership of every
/// input and output buffer; no pointer escapes the call.
///
/// # Safety
///
/// Each non-null pointer must remain valid and correctly aligned for the
/// duration of the call. Writable outputs must not overlap inputs, the
/// configuration, or another writable output. Null pointers are accepted only
/// for zero-length input buffers or a zero-capacity result buffer. The config
/// and result-count pointers must always be non-null.
#[no_mangle]
pub unsafe extern "C" fn wifi_lens_channel_quality_analyze(
    access_points: *const WiFiLensAccessPointInput,
    access_point_count: usize,
    strings: *const u8,
    strings_length: usize,
    config: *const WiFiLensChannelQualityConfig,
    results: *mut WiFiLensChannelQualityResult,
    result_capacity: usize,
    result_count: *mut usize,
) -> i32 {
    if config.is_null()
        || result_count.is_null()
        || (access_point_count > 0 && access_points.is_null())
        || (strings_length > 0 && strings.is_null())
        || (result_capacity > 0 && results.is_null())
    {
        return crate::WIFI_LENS_STATUS_INVALID_POINTER;
    }

    unsafe { *result_count = 0 };
    match std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let config = unsafe { *config };
        if config.flags & !QUALITY_KNOWN_FLAGS != 0
            || config.supported_band_mask & !BAND_KNOWN_MASK != 0
        {
            return Err(crate::WIFI_LENS_STATUS_INVALID_INPUT_SLICE);
        }

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
        for ap in raw_access_points {
            let band = ChannelBand::from_code(ap.band)?;
            let channel_width = ChannelWidth::from_mhz(ap.channel_width_mhz)?;
            let bssid = parse_utf8_slice(input_strings, ap.bssid_offset, ap.bssid_length)?;
            let ssid = parse_utf8_slice(input_strings, ap.ssid_offset, ap.ssid_length)?;
            parsed_access_points.push(AccessPoint {
                channel: ap.channel,
                rssi: ap.rssi,
                channel_width,
                band,
                bssid: (ap.bssid_length > 0).then_some(bssid),
                ssid: (ap.ssid_length > 0).then_some(ssid),
            });
        }

        let current_band = if config.current_band == 0 {
            None
        } else {
            Some(ChannelBand::from_code(config.current_band)?)
        };
        let target_bssid = parse_utf8_slice(
            input_strings,
            config.target_bssid_offset,
            config.target_bssid_length,
        )?;
        let target_ssid = parse_utf8_slice(
            input_strings,
            config.target_ssid_offset,
            config.target_ssid_length,
        )?;
        let target = config.flags
            & (QUALITY_HAS_TARGET_BSSID | QUALITY_HAS_TARGET_SSID | QUALITY_HAS_TARGET_CHANNEL)
            != 0;
        let analysis = analyze(
            &parsed_access_points,
            AnalysisConfiguration {
                current_channel: (config.flags & QUALITY_HAS_CURRENT_CHANNEL != 0)
                    .then_some(config.current_channel),
                current_band,
                supported_band_mask: config.supported_band_mask,
                target: target.then_some(TargetAccessPoint {
                    bssid: (config.flags & QUALITY_HAS_TARGET_BSSID != 0).then_some(target_bssid),
                    ssid: (config.flags & QUALITY_HAS_TARGET_SSID != 0).then_some(target_ssid),
                    channel: (config.flags & QUALITY_HAS_TARGET_CHANNEL != 0)
                        .then_some(config.target_channel),
                }),
            },
        );

        unsafe { *result_count = analysis.len() };
        if analysis.len() > result_capacity {
            return Err(crate::WIFI_LENS_STATUS_OUTPUT_TOO_SMALL);
        }

        if !analysis.is_empty() {
            let output = unsafe { std::slice::from_raw_parts_mut(results, result_capacity) };
            for (destination, source) in output.iter_mut().zip(analysis) {
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
    use super::{analyze, AccessPoint, AnalysisConfiguration, ChannelWidth, TargetAccessPoint};
    use crate::ChannelBand;

    fn ap(channel: i64, rssi: i64, width: ChannelWidth, band: ChannelBand) -> AccessPoint<'static> {
        AccessPoint {
            channel,
            rssi,
            channel_width: width,
            band,
            bssid: None,
            ssid: None,
        }
    }

    fn config(
        current_channel: Option<i64>,
        target: Option<TargetAccessPoint<'_>>,
        band: ChannelBand,
    ) -> AnalysisConfiguration<'_> {
        AnalysisConfiguration {
            current_channel,
            current_band: Some(band),
            supported_band_mask: band.mask(),
            target,
        }
    }

    #[test]
    fn preserves_observed_and_counterfactual_scores() {
        let aps = [AccessPoint {
            bssid: Some(b"aa:bb"),
            ssid: Some(b"home"),
            ..ap(44, -50, ChannelWidth::Twenty, ChannelBand::Band5Ghz)
        }];
        let results = analyze(
            &aps,
            config(
                Some(44),
                Some(TargetAccessPoint {
                    bssid: Some(b"AA:BB"),
                    ssid: None,
                    channel: Some(44),
                }),
                ChannelBand::Band5Ghz,
            ),
        );
        let current = results.iter().find(|result| result.channel == 44).unwrap();
        assert_eq!(current.quality_score, 87);
        assert_eq!(current.recommendation_score, 100);
        assert_eq!(current.recommendation_confidence, super::CONFIDENCE_EXACT);
    }

    #[test]
    fn preserves_ssid_fallback_ambiguity_and_score_thresholds() {
        let aps = [
            AccessPoint {
                ssid: Some(b"home"),
                ..ap(44, -50, ChannelWidth::Twenty, ChannelBand::Band5Ghz)
            },
            ap(36, -50, ChannelWidth::Twenty, ChannelBand::Band5Ghz),
        ];
        let unique = analyze(
            &aps,
            config(
                Some(44),
                Some(TargetAccessPoint {
                    bssid: None,
                    ssid: Some(b"home"),
                    channel: Some(44),
                }),
                ChannelBand::Band5Ghz,
            ),
        );
        assert_eq!(
            unique[0].recommendation_confidence,
            super::CONFIDENCE_SSID_FALLBACK
        );

        let ambiguous_aps = [
            AccessPoint {
                ssid: Some(b"home"),
                ..ap(44, -50, ChannelWidth::Twenty, ChannelBand::Band5Ghz)
            },
            AccessPoint {
                ssid: Some(b"home"),
                ..ap(36, -50, ChannelWidth::Twenty, ChannelBand::Band5Ghz)
            },
        ];
        let ambiguous = analyze(
            &ambiguous_aps,
            config(
                Some(44),
                Some(TargetAccessPoint {
                    bssid: None,
                    ssid: Some(b"home"),
                    channel: None,
                }),
                ChannelBand::Band5Ghz,
            ),
        );
        assert!(ambiguous
            .iter()
            .all(|result| result.recommendation_confidence == super::CONFIDENCE_UNKNOWN));
    }

    #[test]
    fn c_abi_uses_caller_owned_buffers_and_reports_required_capacity() {
        let access_point = super::WiFiLensAccessPointInput {
            channel: 44,
            rssi: -50,
            band: super::BAND_5,
            channel_width_mhz: 20,
            bssid_offset: 0,
            bssid_length: 5,
            ssid_offset: 5,
            ssid_length: 4,
        };
        let strings = b"aa:bbhomeAA:BB";
        let config = super::WiFiLensChannelQualityConfig {
            flags: super::QUALITY_HAS_CURRENT_CHANNEL
                | super::QUALITY_HAS_TARGET_BSSID
                | super::QUALITY_HAS_TARGET_CHANNEL,
            current_channel: 44,
            target_channel: 44,
            current_band: super::BAND_5,
            supported_band_mask: super::BAND_5_MASK,
            target_bssid_offset: 9,
            target_bssid_length: 5,
            target_ssid_offset: 0,
            target_ssid_length: 0,
        };
        let mut output = [super::WiFiLensChannelQualityResult::default();
            crate::WIFI_LENS_MAX_CHANNEL_QUALITIES];
        let mut output_count = 0;
        let status = unsafe {
            super::wifi_lens_channel_quality_analyze(
                &access_point,
                1,
                strings.as_ptr(),
                strings.len(),
                &config,
                output.as_mut_ptr(),
                output.len(),
                &mut output_count,
            )
        };
        assert_eq!(status, crate::WIFI_LENS_STATUS_OK);
        assert_eq!(output_count, 33);
        let current = output.iter().find(|result| result.channel == 44).unwrap();
        assert_eq!(current.quality_score, 87);
        assert_eq!(current.recommendation_score, 100);
        assert_eq!(current.recommendation_confidence, super::CONFIDENCE_EXACT);

        output_count = 0;
        let status = unsafe {
            super::wifi_lens_channel_quality_analyze(
                &access_point,
                1,
                strings.as_ptr(),
                strings.len(),
                &config,
                std::ptr::null_mut(),
                0,
                &mut output_count,
            )
        };
        assert_eq!(status, crate::WIFI_LENS_STATUS_OUTPUT_TOO_SMALL);
        assert_eq!(output_count, 33);

        let mut invalid_width = access_point;
        invalid_width.channel_width_mhz = 10;
        let status = unsafe {
            super::wifi_lens_channel_quality_analyze(
                &invalid_width,
                1,
                strings.as_ptr(),
                strings.len(),
                &config,
                output.as_mut_ptr(),
                output.len(),
                &mut output_count,
            )
        };
        assert_eq!(status, crate::WIFI_LENS_STATUS_INVALID_WIDTH);

        let mut invalid_slice = access_point;
        invalid_slice.bssid_offset = usize::MAX;
        let status = unsafe {
            super::wifi_lens_channel_quality_analyze(
                &invalid_slice,
                1,
                strings.as_ptr(),
                strings.len(),
                &config,
                output.as_mut_ptr(),
                output.len(),
                &mut output_count,
            )
        };
        assert_eq!(status, crate::WIFI_LENS_STATUS_INVALID_INPUT_SLICE);
    }
}
