use crate::{
    WIFI_LENS_STATUS_INVALID_OBSERVATION_INPUT, WIFI_LENS_STATUS_INVALID_POINTER,
    WIFI_LENS_STATUS_OK, WIFI_LENS_STATUS_PANIC,
};
use std::panic::catch_unwind;

pub const WIFI_LENS_QUALITY_ELIGIBLE: u32 = 1 << 0;
pub const WIFI_LENS_QUALITY_HAS_RSSI: u32 = 1 << 1;
pub const WIFI_LENS_QUALITY_HAS_LATENCY: u32 = 1 << 2;
const QUALITY_KNOWN_FLAGS: u32 =
    WIFI_LENS_QUALITY_ELIGIBLE | WIFI_LENS_QUALITY_HAS_RSSI | WIFI_LENS_QUALITY_HAS_LATENCY;

pub const WIFI_LENS_DIAGNOSTIC_ASSOCIATED: u32 = 1 << 0;
pub const WIFI_LENS_DIAGNOSTIC_METRICS_VERIFIED: u32 = 1 << 1;
pub const WIFI_LENS_DIAGNOSTIC_HAS_RSSI: u32 = 1 << 2;
pub const WIFI_LENS_DIAGNOSTIC_HAS_CHANNEL_SCORE: u32 = 1 << 3;
pub const WIFI_LENS_DIAGNOSTIC_SECURITY_HAS_WPA3: u32 = 1 << 4;
pub const WIFI_LENS_DIAGNOSTIC_SECURITY_KNOWN: u32 = 1 << 5;
const DIAGNOSTIC_KNOWN_FLAGS: u32 = WIFI_LENS_DIAGNOSTIC_ASSOCIATED
    | WIFI_LENS_DIAGNOSTIC_METRICS_VERIFIED
    | WIFI_LENS_DIAGNOSTIC_HAS_RSSI
    | WIFI_LENS_DIAGNOSTIC_HAS_CHANNEL_SCORE
    | WIFI_LENS_DIAGNOSTIC_SECURITY_HAS_WPA3
    | WIFI_LENS_DIAGNOSTIC_SECURITY_KNOWN;

pub const WIFI_LENS_QUALITY_LEVEL_UNKNOWN: i32 = 0;
pub const WIFI_LENS_QUALITY_LEVEL_GOOD: i32 = 1;
pub const WIFI_LENS_QUALITY_LEVEL_FAIR: i32 = 2;
pub const WIFI_LENS_QUALITY_LEVEL_POOR: i32 = 3;

pub const WIFI_LENS_SIGNAL_BAND_UNKNOWN: i32 = 0;
pub const WIFI_LENS_SIGNAL_BAND_STRONG: i32 = 1;
pub const WIFI_LENS_SIGNAL_BAND_GOOD: i32 = 2;
pub const WIFI_LENS_SIGNAL_BAND_MODERATE: i32 = 3;
pub const WIFI_LENS_SIGNAL_BAND_WEAK: i32 = 4;

pub const WIFI_LENS_LATENCY_BAND_UNAVAILABLE: i32 = 0;
pub const WIFI_LENS_LATENCY_BAND_NORMAL: i32 = 1;
pub const WIFI_LENS_LATENCY_BAND_ELEVATED: i32 = 2;
pub const WIFI_LENS_LATENCY_BAND_HIGH: i32 = 3;

pub const WIFI_LENS_PHY_OTHER: i32 = 0;
pub const WIFI_LENS_PHY_11N: i32 = 1;
pub const WIFI_LENS_PHY_11AC: i32 = 2;

pub const WIFI_LENS_DIAGNOSTIC_UNKNOWN: i32 = 0;
pub const WIFI_LENS_DIAGNOSTIC_EXCELLENT: i32 = 1;
pub const WIFI_LENS_DIAGNOSTIC_WEAK_SIGNAL: i32 = 2;
pub const WIFI_LENS_DIAGNOSTIC_CONGESTED: i32 = 3;
pub const WIFI_LENS_DIAGNOSTIC_MEDIOCRE: i32 = 4;
pub const WIFI_LENS_DIAGNOSTIC_WEAK_SECURITY: i32 = 5;
pub const WIFI_LENS_DIAGNOSTIC_OLD_PHY_11N: i32 = 6;
pub const WIFI_LENS_DIAGNOSTIC_OLD_PHY_11AC: i32 = 7;
pub const WIFI_LENS_DIAGNOSTIC_OK: i32 = 8;

const CHANNEL_QUALITY_SCORE_MIN: i32 = 0;
const CHANNEL_QUALITY_SCORE_MAX: i32 = 100;

/// Quality level derived from verified signal and latency facts.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum QualityLevel {
    Unknown,
    Good,
    Fair,
    Poor,
}

/// Signal-strength band used by the localized signal label.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum SignalBand {
    Unknown,
    Strong,
    Good,
    Moderate,
    Weak,
}

/// Latency band used by the localized latency label.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum LatencyBand {
    Unavailable,
    Normal,
    Elevated,
    High,
}

/// Normalized connection-quality input.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct QualityInput {
    /// Association and metric attribution are verified by the native adapter.
    pub eligible: bool,
    pub rssi: Option<i64>,
    pub latency_ms: Option<f64>,
}

/// Level and label bands derived from normalized quality facts.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct QualityAssessment {
    pub level: QualityLevel,
    pub signal_band: SignalBand,
    pub latency_band: LatencyBand,
}

/// Generation of the current PHY, as normalized by the native adapter.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum PhyGeneration {
    Other,
    N,
    AC,
}

/// Diagnostic category selected from verified connection facts.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum DiagnosticKind {
    Unknown,
    Excellent,
    WeakSignal,
    Congested,
    Mediocre,
    WeakSecurity,
    OldPhy11N,
    OldPhy11AC,
    Ok,
}

/// Normalized observation facts for the diagnostic decision.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct DiagnosticInput {
    pub associated: bool,
    pub metrics_verified: bool,
    pub rssi: Option<i64>,
    pub channel_quality_score: Option<i32>,
    pub security_has_wpa3: bool,
    pub security_known_nonempty: bool,
    pub phy: PhyGeneration,
}

/// Evaluate the connection quality level and display bands without localization.
pub fn assess_quality(input: QualityInput) -> QualityAssessment {
    if !input.eligible {
        return QualityAssessment {
            level: QualityLevel::Unknown,
            signal_band: SignalBand::Unknown,
            latency_band: LatencyBand::Unavailable,
        };
    }
    let Some(rssi) = input.rssi else {
        return QualityAssessment {
            level: QualityLevel::Unknown,
            signal_band: SignalBand::Unknown,
            latency_band: LatencyBand::Unavailable,
        };
    };

    let level = if rssi >= -55 {
        match input.latency_ms {
            Some(ms) if ms < 50.0 => QualityLevel::Good,
            None => QualityLevel::Good,
            Some(_) => QualityLevel::Fair,
        }
    } else if rssi >= -70 {
        match input.latency_ms {
            Some(ms) if ms < 100.0 => QualityLevel::Fair,
            _ => QualityLevel::Poor,
        }
    } else {
        QualityLevel::Poor
    };
    let signal_band = if rssi >= -55 {
        SignalBand::Strong
    } else if rssi >= -70 {
        SignalBand::Good
    } else if rssi >= -85 {
        SignalBand::Moderate
    } else {
        SignalBand::Weak
    };
    let latency_band = match input.latency_ms {
        None => LatencyBand::Unavailable,
        Some(ms) if ms < 50.0 => LatencyBand::Normal,
        Some(ms) if ms < 100.0 => LatencyBand::Elevated,
        Some(_) => LatencyBand::High,
    };

    QualityAssessment {
        level,
        signal_band,
        latency_band,
    }
}

/// Select the diagnostic category from normalized observation facts.
pub fn assess_diagnosis(input: DiagnosticInput) -> DiagnosticKind {
    if !input.associated {
        return DiagnosticKind::Unknown;
    }

    let (rssi, channel_score, security_has_wpa3, security_known, phy) = if input.metrics_verified {
        (
            input.rssi,
            input.channel_quality_score,
            input.security_has_wpa3,
            input.security_known_nonempty,
            input.phy,
        )
    } else {
        (None, None, false, false, PhyGeneration::Other)
    };

    if rssi.is_none() && channel_score.is_none() {
        return DiagnosticKind::Unknown;
    }
    if let (Some(rssi), Some(channel_score)) = (rssi, channel_score) {
        if rssi >= -55 && channel_score >= 70 && security_has_wpa3 {
            return DiagnosticKind::Excellent;
        }
    }
    if rssi.is_some_and(|rssi| rssi < -75) {
        return DiagnosticKind::WeakSignal;
    }
    if channel_score.is_some_and(|score| score < 50) {
        return DiagnosticKind::Congested;
    }
    if channel_score.is_some_and(|score| score < 70) {
        return DiagnosticKind::Mediocre;
    }
    if security_known && !security_has_wpa3 {
        return DiagnosticKind::WeakSecurity;
    }
    match phy {
        PhyGeneration::N => DiagnosticKind::OldPhy11N,
        PhyGeneration::AC => DiagnosticKind::OldPhy11AC,
        PhyGeneration::Other => DiagnosticKind::Ok,
    }
}

/// C-compatible connection-quality input.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct WiFiLensQualityInput {
    pub flags: u32,
    pub rssi: i64,
    pub latency_ms: f64,
}

/// C-compatible quality level and display bands.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct WiFiLensQualityResult {
    pub level: i32,
    pub signal_band: i32,
    pub latency_band: i32,
}

/// C-compatible normalized diagnostic input.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct WiFiLensDiagnosticInput {
    pub flags: u32,
    pub rssi: i64,
    pub channel_quality_score: i32,
    pub phy_generation: i32,
}

/// C-compatible diagnostic category.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct WiFiLensDiagnosticResult {
    pub kind: i32,
}

fn quality_level_code(level: QualityLevel) -> i32 {
    match level {
        QualityLevel::Unknown => WIFI_LENS_QUALITY_LEVEL_UNKNOWN,
        QualityLevel::Good => WIFI_LENS_QUALITY_LEVEL_GOOD,
        QualityLevel::Fair => WIFI_LENS_QUALITY_LEVEL_FAIR,
        QualityLevel::Poor => WIFI_LENS_QUALITY_LEVEL_POOR,
    }
}

fn signal_band_code(band: SignalBand) -> i32 {
    match band {
        SignalBand::Unknown => WIFI_LENS_SIGNAL_BAND_UNKNOWN,
        SignalBand::Strong => WIFI_LENS_SIGNAL_BAND_STRONG,
        SignalBand::Good => WIFI_LENS_SIGNAL_BAND_GOOD,
        SignalBand::Moderate => WIFI_LENS_SIGNAL_BAND_MODERATE,
        SignalBand::Weak => WIFI_LENS_SIGNAL_BAND_WEAK,
    }
}

fn latency_band_code(band: LatencyBand) -> i32 {
    match band {
        LatencyBand::Unavailable => WIFI_LENS_LATENCY_BAND_UNAVAILABLE,
        LatencyBand::Normal => WIFI_LENS_LATENCY_BAND_NORMAL,
        LatencyBand::Elevated => WIFI_LENS_LATENCY_BAND_ELEVATED,
        LatencyBand::High => WIFI_LENS_LATENCY_BAND_HIGH,
    }
}

fn diagnostic_kind_code(kind: DiagnosticKind) -> i32 {
    match kind {
        DiagnosticKind::Unknown => WIFI_LENS_DIAGNOSTIC_UNKNOWN,
        DiagnosticKind::Excellent => WIFI_LENS_DIAGNOSTIC_EXCELLENT,
        DiagnosticKind::WeakSignal => WIFI_LENS_DIAGNOSTIC_WEAK_SIGNAL,
        DiagnosticKind::Congested => WIFI_LENS_DIAGNOSTIC_CONGESTED,
        DiagnosticKind::Mediocre => WIFI_LENS_DIAGNOSTIC_MEDIOCRE,
        DiagnosticKind::WeakSecurity => WIFI_LENS_DIAGNOSTIC_WEAK_SECURITY,
        DiagnosticKind::OldPhy11N => WIFI_LENS_DIAGNOSTIC_OLD_PHY_11N,
        DiagnosticKind::OldPhy11AC => WIFI_LENS_DIAGNOSTIC_OLD_PHY_11AC,
        DiagnosticKind::Ok => WIFI_LENS_DIAGNOSTIC_OK,
    }
}

impl From<QualityAssessment> for WiFiLensQualityResult {
    fn from(assessment: QualityAssessment) -> Self {
        Self {
            level: quality_level_code(assessment.level),
            signal_band: signal_band_code(assessment.signal_band),
            latency_band: latency_band_code(assessment.latency_band),
        }
    }
}

fn decode_quality_input(raw: WiFiLensQualityInput) -> Result<QualityInput, i32> {
    if raw.flags & !QUALITY_KNOWN_FLAGS != 0 {
        return Err(WIFI_LENS_STATUS_INVALID_OBSERVATION_INPUT);
    }
    let has_rssi = raw.flags & WIFI_LENS_QUALITY_HAS_RSSI != 0;
    let has_latency = raw.flags & WIFI_LENS_QUALITY_HAS_LATENCY != 0;
    if has_latency && (!raw.latency_ms.is_finite() || raw.latency_ms < 0.0) {
        return Err(WIFI_LENS_STATUS_INVALID_OBSERVATION_INPUT);
    }
    Ok(QualityInput {
        eligible: raw.flags & WIFI_LENS_QUALITY_ELIGIBLE != 0,
        rssi: has_rssi.then_some(raw.rssi),
        latency_ms: has_latency.then_some(raw.latency_ms),
    })
}

fn decode_phy(value: i32) -> Result<PhyGeneration, i32> {
    match value {
        WIFI_LENS_PHY_OTHER => Ok(PhyGeneration::Other),
        WIFI_LENS_PHY_11N => Ok(PhyGeneration::N),
        WIFI_LENS_PHY_11AC => Ok(PhyGeneration::AC),
        _ => Err(WIFI_LENS_STATUS_INVALID_OBSERVATION_INPUT),
    }
}

fn decode_diagnostic_input(raw: WiFiLensDiagnosticInput) -> Result<DiagnosticInput, i32> {
    if raw.flags & !DIAGNOSTIC_KNOWN_FLAGS != 0 {
        return Err(WIFI_LENS_STATUS_INVALID_OBSERVATION_INPUT);
    }
    let metrics_verified = raw.flags & WIFI_LENS_DIAGNOSTIC_METRICS_VERIFIED != 0;
    let has_rssi = raw.flags & WIFI_LENS_DIAGNOSTIC_HAS_RSSI != 0;
    let has_channel_score = raw.flags & WIFI_LENS_DIAGNOSTIC_HAS_CHANNEL_SCORE != 0;
    let security_has_wpa3 = raw.flags & WIFI_LENS_DIAGNOSTIC_SECURITY_HAS_WPA3 != 0;
    let security_known_nonempty = raw.flags & WIFI_LENS_DIAGNOSTIC_SECURITY_KNOWN != 0;
    if (!metrics_verified
        && (has_rssi
            || has_channel_score
            || security_has_wpa3
            || security_known_nonempty
            || raw.phy_generation != WIFI_LENS_PHY_OTHER))
        || (security_has_wpa3 && !security_known_nonempty)
        || (has_channel_score
            && !(CHANNEL_QUALITY_SCORE_MIN..=CHANNEL_QUALITY_SCORE_MAX)
                .contains(&raw.channel_quality_score))
    {
        return Err(WIFI_LENS_STATUS_INVALID_OBSERVATION_INPUT);
    }
    Ok(DiagnosticInput {
        associated: raw.flags & WIFI_LENS_DIAGNOSTIC_ASSOCIATED != 0,
        metrics_verified,
        rssi: has_rssi.then_some(raw.rssi),
        channel_quality_score: has_channel_score.then_some(raw.channel_quality_score),
        security_has_wpa3,
        security_known_nonempty,
        phy: decode_phy(raw.phy_generation)?,
    })
}

fn guarded<T>(
    operation: impl FnOnce() -> Result<T, i32> + std::panic::UnwindSafe,
) -> Result<T, i32> {
    match catch_unwind(operation) {
        Ok(result) => result,
        Err(_) => Err(WIFI_LENS_STATUS_PANIC),
    }
}

/// Evaluate normalized connection quality through the stable C ABI.
///
/// # Safety
///
/// `input` and `output` must be non-null, correctly aligned, and valid for one
/// read or write respectively. They must not overlap.
#[no_mangle]
pub unsafe extern "C" fn wifi_lens_evaluate_quality(
    input: *const WiFiLensQualityInput,
    output: *mut WiFiLensQualityResult,
) -> i32 {
    if input.is_null() || output.is_null() {
        return WIFI_LENS_STATUS_INVALID_POINTER;
    }
    let raw = unsafe { *input };
    match guarded(|| {
        #[cfg(test)]
        if raw.flags == u32::MAX {
            panic!("test-only panic path");
        }
        decode_quality_input(raw)
            .map(assess_quality)
            .map(Into::into)
    }) {
        Ok(result) => {
            unsafe { *output = result };
            WIFI_LENS_STATUS_OK
        }
        Err(status) => status,
    }
}

/// Select a normalized diagnostic category through the stable C ABI.
///
/// # Safety
///
/// `input` and `output` must be non-null, correctly aligned, and valid for one
/// read or write respectively. They must not overlap.
#[no_mangle]
pub unsafe extern "C" fn wifi_lens_evaluate_diagnosis(
    input: *const WiFiLensDiagnosticInput,
    output: *mut WiFiLensDiagnosticResult,
) -> i32 {
    if input.is_null() || output.is_null() {
        return WIFI_LENS_STATUS_INVALID_POINTER;
    }
    let raw = unsafe { *input };
    match guarded(|| {
        #[cfg(test)]
        if raw.flags == u32::MAX {
            panic!("test-only panic path");
        }
        decode_diagnostic_input(raw).map(|decoded| WiFiLensDiagnosticResult {
            kind: diagnostic_kind_code(assess_diagnosis(decoded)),
        })
    }) {
        Ok(result) => {
            unsafe { *output = result };
            WIFI_LENS_STATUS_OK
        }
        Err(status) => status,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{WIFI_LENS_STATUS_INVALID_OBSERVATION_INPUT, WIFI_LENS_STATUS_PANIC};

    #[test]
    fn quality_thresholds_missing_values_and_display_bands_are_preserved() {
        let cases = [
            (
                QualityInput {
                    eligible: false,
                    rssi: Some(-40),
                    latency_ms: Some(10.0),
                },
                QualityAssessment {
                    level: QualityLevel::Unknown,
                    signal_band: SignalBand::Unknown,
                    latency_band: LatencyBand::Unavailable,
                },
            ),
            (
                QualityInput {
                    eligible: true,
                    rssi: None,
                    latency_ms: None,
                },
                QualityAssessment {
                    level: QualityLevel::Unknown,
                    signal_band: SignalBand::Unknown,
                    latency_band: LatencyBand::Unavailable,
                },
            ),
            (
                QualityInput {
                    eligible: true,
                    rssi: Some(-55),
                    latency_ms: None,
                },
                QualityAssessment {
                    level: QualityLevel::Good,
                    signal_band: SignalBand::Strong,
                    latency_band: LatencyBand::Unavailable,
                },
            ),
            (
                QualityInput {
                    eligible: true,
                    rssi: Some(-55),
                    latency_ms: Some(49.999),
                },
                QualityAssessment {
                    level: QualityLevel::Good,
                    signal_band: SignalBand::Strong,
                    latency_band: LatencyBand::Normal,
                },
            ),
            (
                QualityInput {
                    eligible: true,
                    rssi: Some(-55),
                    latency_ms: Some(50.0),
                },
                QualityAssessment {
                    level: QualityLevel::Fair,
                    signal_band: SignalBand::Strong,
                    latency_band: LatencyBand::Elevated,
                },
            ),
            (
                QualityInput {
                    eligible: true,
                    rssi: Some(-56),
                    latency_ms: Some(99.999),
                },
                QualityAssessment {
                    level: QualityLevel::Fair,
                    signal_band: SignalBand::Good,
                    latency_band: LatencyBand::Elevated,
                },
            ),
            (
                QualityInput {
                    eligible: true,
                    rssi: Some(-56),
                    latency_ms: Some(100.0),
                },
                QualityAssessment {
                    level: QualityLevel::Poor,
                    signal_band: SignalBand::Good,
                    latency_band: LatencyBand::High,
                },
            ),
            (
                QualityInput {
                    eligible: true,
                    rssi: Some(-70),
                    latency_ms: Some(99.999),
                },
                QualityAssessment {
                    level: QualityLevel::Fair,
                    signal_band: SignalBand::Good,
                    latency_band: LatencyBand::Elevated,
                },
            ),
            (
                QualityInput {
                    eligible: true,
                    rssi: Some(-70),
                    latency_ms: Some(100.0),
                },
                QualityAssessment {
                    level: QualityLevel::Poor,
                    signal_band: SignalBand::Good,
                    latency_band: LatencyBand::High,
                },
            ),
            (
                QualityInput {
                    eligible: true,
                    rssi: Some(-71),
                    latency_ms: None,
                },
                QualityAssessment {
                    level: QualityLevel::Poor,
                    signal_band: SignalBand::Moderate,
                    latency_band: LatencyBand::Unavailable,
                },
            ),
            (
                QualityInput {
                    eligible: true,
                    rssi: Some(-85),
                    latency_ms: None,
                },
                QualityAssessment {
                    level: QualityLevel::Poor,
                    signal_band: SignalBand::Moderate,
                    latency_band: LatencyBand::Unavailable,
                },
            ),
            (
                QualityInput {
                    eligible: true,
                    rssi: Some(-86),
                    latency_ms: None,
                },
                QualityAssessment {
                    level: QualityLevel::Poor,
                    signal_band: SignalBand::Weak,
                    latency_band: LatencyBand::Unavailable,
                },
            ),
        ];

        for (input, expected) in cases {
            assert_eq!(assess_quality(input), expected, "input {input:?}");
        }
    }

    #[test]
    fn diagnosis_thresholds_precedence_and_unknown_states_are_preserved() {
        let base = DiagnosticInput {
            associated: true,
            metrics_verified: true,
            rssi: Some(-55),
            channel_quality_score: Some(70),
            security_has_wpa3: true,
            security_known_nonempty: true,
            phy: PhyGeneration::Other,
        };
        assert_eq!(assess_diagnosis(base), DiagnosticKind::Excellent);
        assert_eq!(
            assess_diagnosis(DiagnosticInput {
                channel_quality_score: Some(0),
                ..base
            }),
            DiagnosticKind::Congested,
            "the minimum channel score is valid and congested"
        );
        assert_eq!(
            assess_diagnosis(DiagnosticInput {
                channel_quality_score: Some(100),
                ..base
            }),
            DiagnosticKind::Excellent,
            "the maximum channel score is valid"
        );
        assert_eq!(
            assess_diagnosis(DiagnosticInput {
                rssi: Some(-56),
                ..base
            }),
            DiagnosticKind::Ok,
            "strong-signal excellent threshold is inclusive at -55 dBm"
        );
        assert_eq!(
            assess_diagnosis(DiagnosticInput {
                associated: false,
                ..base
            }),
            DiagnosticKind::Unknown
        );
        assert_eq!(
            assess_diagnosis(DiagnosticInput {
                metrics_verified: false,
                ..base
            }),
            DiagnosticKind::Unknown
        );
        assert_eq!(
            assess_diagnosis(DiagnosticInput {
                rssi: None,
                channel_quality_score: None,
                ..base
            }),
            DiagnosticKind::Unknown
        );
        assert_eq!(
            assess_diagnosis(DiagnosticInput {
                rssi: Some(-75),
                channel_quality_score: Some(85),
                ..base
            }),
            DiagnosticKind::Ok,
            "weak-signal threshold is exclusive below -75 dBm"
        );
        assert_eq!(
            assess_diagnosis(DiagnosticInput {
                rssi: Some(-76),
                channel_quality_score: Some(49),
                ..base
            }),
            DiagnosticKind::WeakSignal,
            "weak signal takes precedence over channel congestion"
        );
        assert_eq!(
            assess_diagnosis(DiagnosticInput {
                channel_quality_score: Some(50),
                ..base
            }),
            DiagnosticKind::Mediocre,
            "congestion threshold is exclusive below 50"
        );
        assert_eq!(
            assess_diagnosis(DiagnosticInput {
                channel_quality_score: Some(49),
                ..base
            }),
            DiagnosticKind::Congested
        );
        assert_eq!(
            assess_diagnosis(DiagnosticInput {
                channel_quality_score: Some(69),
                ..base
            }),
            DiagnosticKind::Mediocre
        );
        assert_eq!(
            assess_diagnosis(DiagnosticInput {
                channel_quality_score: Some(70),
                security_has_wpa3: false,
                security_known_nonempty: true,
                ..base
            }),
            DiagnosticKind::WeakSecurity,
            "security assessment follows signal and channel assessments"
        );
        assert_eq!(
            assess_diagnosis(DiagnosticInput {
                security_has_wpa3: false,
                security_known_nonempty: false,
                phy: PhyGeneration::N,
                ..base
            }),
            DiagnosticKind::OldPhy11N
        );
        assert_eq!(
            assess_diagnosis(DiagnosticInput {
                security_has_wpa3: false,
                security_known_nonempty: false,
                phy: PhyGeneration::AC,
                ..base
            }),
            DiagnosticKind::OldPhy11AC
        );
    }

    #[test]
    fn c_abi_maps_valid_results_and_preserves_missing_values() {
        let quality_input = WiFiLensQualityInput {
            flags: WIFI_LENS_QUALITY_ELIGIBLE
                | WIFI_LENS_QUALITY_HAS_RSSI
                | WIFI_LENS_QUALITY_HAS_LATENCY,
            rssi: -55,
            latency_ms: 49.999,
        };
        let mut quality_output = WiFiLensQualityResult::default();
        assert_eq!(
            unsafe { wifi_lens_evaluate_quality(&quality_input, &mut quality_output) },
            WIFI_LENS_STATUS_OK
        );
        assert_eq!(
            quality_output,
            WiFiLensQualityResult {
                level: WIFI_LENS_QUALITY_LEVEL_GOOD,
                signal_band: WIFI_LENS_SIGNAL_BAND_STRONG,
                latency_band: WIFI_LENS_LATENCY_BAND_NORMAL,
            }
        );

        let missing_quality_input = WiFiLensQualityInput {
            rssi: -35,
            latency_ms: f64::NAN,
            ..WiFiLensQualityInput::default()
        };
        assert_eq!(
            unsafe { wifi_lens_evaluate_quality(&missing_quality_input, &mut quality_output) },
            WIFI_LENS_STATUS_OK,
            "unflagged fields are absent facts and their storage is ignored"
        );
        assert_eq!(
            quality_output,
            WiFiLensQualityResult {
                level: WIFI_LENS_QUALITY_LEVEL_UNKNOWN,
                signal_band: WIFI_LENS_SIGNAL_BAND_UNKNOWN,
                latency_band: WIFI_LENS_LATENCY_BAND_UNAVAILABLE,
            }
        );

        let diagnostic_input = WiFiLensDiagnosticInput {
            flags: WIFI_LENS_DIAGNOSTIC_ASSOCIATED
                | WIFI_LENS_DIAGNOSTIC_METRICS_VERIFIED
                | WIFI_LENS_DIAGNOSTIC_HAS_RSSI
                | WIFI_LENS_DIAGNOSTIC_HAS_CHANNEL_SCORE
                | WIFI_LENS_DIAGNOSTIC_SECURITY_HAS_WPA3
                | WIFI_LENS_DIAGNOSTIC_SECURITY_KNOWN,
            rssi: -55,
            channel_quality_score: 70,
            phy_generation: WIFI_LENS_PHY_OTHER,
        };
        let mut diagnostic_output = WiFiLensDiagnosticResult::default();
        assert_eq!(
            unsafe { wifi_lens_evaluate_diagnosis(&diagnostic_input, &mut diagnostic_output) },
            WIFI_LENS_STATUS_OK
        );
        assert_eq!(
            diagnostic_output,
            WiFiLensDiagnosticResult {
                kind: WIFI_LENS_DIAGNOSTIC_EXCELLENT,
            }
        );

        let missing_diagnostic_input = WiFiLensDiagnosticInput {
            flags: WIFI_LENS_DIAGNOSTIC_ASSOCIATED | WIFI_LENS_DIAGNOSTIC_METRICS_VERIFIED,
            rssi: -35,
            channel_quality_score: 100,
            ..diagnostic_input
        };
        assert_eq!(
            unsafe {
                wifi_lens_evaluate_diagnosis(&missing_diagnostic_input, &mut diagnostic_output)
            },
            WIFI_LENS_STATUS_OK
        );
        assert_eq!(
            diagnostic_output,
            WiFiLensDiagnosticResult {
                kind: WIFI_LENS_DIAGNOSTIC_UNKNOWN,
            }
        );
    }

    #[test]
    fn c_abi_rejects_invalid_encodings_without_partial_output() {
        let quality_base = WiFiLensQualityInput {
            flags: WIFI_LENS_QUALITY_ELIGIBLE | WIFI_LENS_QUALITY_HAS_RSSI,
            rssi: -50,
            latency_ms: 0.0,
        };
        let quality_sentinel = WiFiLensQualityResult {
            level: -1,
            signal_band: -2,
            latency_band: -3,
        };
        let mut quality_output = quality_sentinel;
        for input in [
            WiFiLensQualityInput {
                flags: quality_base.flags | (1 << 7),
                ..quality_base
            },
            WiFiLensQualityInput {
                flags: quality_base.flags | WIFI_LENS_QUALITY_HAS_LATENCY,
                latency_ms: f64::NAN,
                ..quality_base
            },
            WiFiLensQualityInput {
                flags: quality_base.flags | WIFI_LENS_QUALITY_HAS_LATENCY,
                latency_ms: f64::INFINITY,
                ..quality_base
            },
            WiFiLensQualityInput {
                flags: quality_base.flags | WIFI_LENS_QUALITY_HAS_LATENCY,
                latency_ms: f64::NEG_INFINITY,
                ..quality_base
            },
            WiFiLensQualityInput {
                flags: quality_base.flags | WIFI_LENS_QUALITY_HAS_LATENCY,
                latency_ms: -0.001,
                ..quality_base
            },
        ] {
            assert_eq!(
                unsafe { wifi_lens_evaluate_quality(&input, &mut quality_output) },
                WIFI_LENS_STATUS_INVALID_OBSERVATION_INPUT,
                "input {input:?}"
            );
            assert_eq!(quality_output, quality_sentinel);
        }

        let diagnostic_base = WiFiLensDiagnosticInput {
            flags: WIFI_LENS_DIAGNOSTIC_ASSOCIATED | WIFI_LENS_DIAGNOSTIC_METRICS_VERIFIED,
            ..WiFiLensDiagnosticInput::default()
        };
        let diagnostic_sentinel = WiFiLensDiagnosticResult { kind: -1 };
        let mut diagnostic_output = diagnostic_sentinel;
        for input in [
            WiFiLensDiagnosticInput {
                flags: diagnostic_base.flags | (1 << 7),
                ..diagnostic_base
            },
            WiFiLensDiagnosticInput {
                flags: WIFI_LENS_DIAGNOSTIC_ASSOCIATED | WIFI_LENS_DIAGNOSTIC_HAS_RSSI,
                rssi: -50,
                ..diagnostic_base
            },
            WiFiLensDiagnosticInput {
                flags: diagnostic_base.flags | WIFI_LENS_DIAGNOSTIC_SECURITY_HAS_WPA3,
                ..diagnostic_base
            },
            WiFiLensDiagnosticInput {
                flags: diagnostic_base.flags | WIFI_LENS_DIAGNOSTIC_HAS_CHANNEL_SCORE,
                channel_quality_score: -1,
                ..diagnostic_base
            },
            WiFiLensDiagnosticInput {
                flags: diagnostic_base.flags | WIFI_LENS_DIAGNOSTIC_HAS_CHANNEL_SCORE,
                channel_quality_score: 101,
                ..diagnostic_base
            },
            WiFiLensDiagnosticInput {
                phy_generation: 3,
                ..diagnostic_base
            },
            WiFiLensDiagnosticInput {
                flags: WIFI_LENS_DIAGNOSTIC_ASSOCIATED,
                phy_generation: WIFI_LENS_PHY_11N,
                ..diagnostic_base
            },
        ] {
            assert_eq!(
                unsafe { wifi_lens_evaluate_diagnosis(&input, &mut diagnostic_output) },
                WIFI_LENS_STATUS_INVALID_OBSERVATION_INPUT,
                "input {input:?}"
            );
            assert_eq!(diagnostic_output, diagnostic_sentinel);
        }
    }

    #[test]
    fn c_abi_rejects_null_pointers_and_catches_panics() {
        let quality_sentinel = WiFiLensQualityResult {
            level: -1,
            signal_band: -2,
            latency_band: -3,
        };
        let mut quality_output = quality_sentinel;
        assert_eq!(
            unsafe { wifi_lens_evaluate_quality(std::ptr::null(), &mut quality_output) },
            WIFI_LENS_STATUS_INVALID_POINTER
        );
        assert_eq!(quality_output, quality_sentinel);
        let quality = WiFiLensQualityInput::default();
        assert_eq!(
            unsafe { wifi_lens_evaluate_quality(&quality, std::ptr::null_mut()) },
            WIFI_LENS_STATUS_INVALID_POINTER
        );

        let diagnostic_sentinel = WiFiLensDiagnosticResult { kind: -1 };
        let mut diagnostic_output = diagnostic_sentinel;
        assert_eq!(
            unsafe { wifi_lens_evaluate_diagnosis(std::ptr::null(), &mut diagnostic_output) },
            WIFI_LENS_STATUS_INVALID_POINTER
        );
        assert_eq!(diagnostic_output, diagnostic_sentinel);
        let diagnostic = WiFiLensDiagnosticInput::default();
        assert_eq!(
            unsafe { wifi_lens_evaluate_diagnosis(&diagnostic, std::ptr::null_mut()) },
            WIFI_LENS_STATUS_INVALID_POINTER
        );

        let panic_input = WiFiLensQualityInput {
            flags: u32::MAX,
            ..WiFiLensQualityInput::default()
        };
        assert_eq!(
            unsafe { wifi_lens_evaluate_quality(&panic_input, &mut quality_output) },
            WIFI_LENS_STATUS_PANIC
        );
        assert_eq!(quality_output, quality_sentinel);
        let panic_diagnostic = WiFiLensDiagnosticInput {
            flags: u32::MAX,
            ..WiFiLensDiagnosticInput::default()
        };
        assert_eq!(
            unsafe { wifi_lens_evaluate_diagnosis(&panic_diagnostic, &mut diagnostic_output) },
            WIFI_LENS_STATUS_PANIC
        );
        assert_eq!(diagnostic_output, diagnostic_sentinel);
    }
}
