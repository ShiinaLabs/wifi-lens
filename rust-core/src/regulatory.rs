//! Portable regulatory-domain inference, channel rules, and recommendation decisions.

use std::collections::{HashMap, HashSet};

use crate::{
    WIFI_LENS_STATUS_INVALID_INPUT_SLICE, WIFI_LENS_STATUS_INVALID_POINTER,
    WIFI_LENS_STATUS_INVALID_REGULATORY_INPUT, WIFI_LENS_STATUS_INVALID_UTF8,
    WIFI_LENS_STATUS_OUTPUT_TOO_SMALL, WIFI_LENS_STATUS_PANIC,
};

pub const REGULATORY_DOMAIN_UNKNOWN: i32 = 0;
pub const REGULATORY_DOMAIN_US: i32 = 1;
pub const REGULATORY_DOMAIN_JP: i32 = 2;
pub const REGULATORY_DOMAIN_CN: i32 = 3;
pub const REGULATORY_DOMAIN_EU: i32 = 4;

pub const REGULATORY_BAND_24_GHZ: i32 = 1;
pub const REGULATORY_BAND_5_GHZ: i32 = 2;
pub const REGULATORY_BAND_6_GHZ: i32 = 3;

pub const INFERENCE_CONFIDENCE_LOW: i32 = 0;
pub const INFERENCE_CONFIDENCE_MEDIUM: i32 = 1;
pub const INFERENCE_CONFIDENCE_HIGH: i32 = 2;

const CONFLICT_CHANNELS_DISAGREE_WITH_AP: i32 = 1;

const CLASSIFICATION_RECOMMENDED: i32 = 1;
const CLASSIFICATION_ADVANCED: i32 = 2;
const CLASSIFICATION_RESTRICTED: i32 = 3;

const FILTER_HAS_SUPPORTED_CHANNELS: u32 = 1 << 0;
const CAPABILITY_SUPPORTS_N: u32 = 1 << 0;
const CAPABILITY_SUPPORTS_AC: u32 = 1 << 1;
const CAPABILITY_SUPPORTS_AX: u32 = 1 << 2;
const CAPABILITY_SUPPORTS_BE: u32 = 1 << 3;
const CAPABILITY_SUPPORTS_6_GHZ: u32 = 1 << 4;
const CAPABILITY_SUPPORTS_DFS: u32 = 1 << 5;
const CAPABILITY_SUPPORTS_160_MHZ: u32 = 1 << 6;
const CAPABILITY_KNOWN_FLAGS: u32 = (1 << 7) - 1;

const META_IS_DFS: u32 = 1 << 0;
const META_IS_RADAR_SENSITIVE: u32 = 1 << 1;
const META_REQUIRES_CAC: u32 = 1 << 2;
const META_FORCED_SWITCH_RISK: u32 = 1 << 3;
const META_IS_INDOOR_ONLY: u32 = 1 << 4;
const META_REQUIRES_AFC: u32 = 1 << 5;
const META_WIFI_6E_AVAILABLE: u32 = 1 << 6;
const META_WIFI_7_AVAILABLE: u32 = 1 << 7;
const META_KNOWN_FLAGS: u32 = (1 << 8) - 1;

const REASON_REGION_UNKNOWN: i32 = 1;
const REASON_REGION_BLOCKED: i32 = 2;
const REASON_DFS: i32 = 3;
const REASON_RADAR_SENSITIVE: i32 = 4;
const REASON_CAC_REQUIRED: i32 = 5;
const REASON_INDOOR_ONLY: i32 = 6;
const REASON_AFC_REQUIRED: i32 = 7;
const REASON_REGION_LOW_CONFIDENCE: i32 = 8;
const REASON_DEVICE_INCOMPATIBLE: i32 = 9;
const REASON_USER_OVERRIDE: i32 = 10;
const MAX_FILTER_REASONS: usize = 10;

const DEVICE_REASON_NONE: i32 = 0;
const DEVICE_REASON_CHANNEL_UNSUPPORTED: i32 = 1;
const DEVICE_REASON_6_GHZ_UNSUPPORTED: i32 = 2;
const DEVICE_REASON_AFC_UNSUPPORTED: i32 = 3;
const DEVICE_REASON_DFS_UNSUPPORTED: i32 = 4;

const RECOMMENDATION_REASON_CURRENT_CHANNEL: i32 = 1;
const RECOMMENDATION_REASON_CURRENTLY_OPTIMAL: i32 = 2;
const RECOMMENDATION_REASON_CLEAR_SPECTRUM: i32 = 3;
const RECOMMENDATION_REASON_LOW_CONGESTION: i32 = 4;
const RECOMMENDATION_REASON_CONGESTED: i32 = 5;
const RECOMMENDATION_REASON_LOW_OVERLAP: i32 = 6;
const RECOMMENDATION_REASON_HIGH_OVERLAP: i32 = 7;
const RECOMMENDATION_REASON_LOW_INTERFERENCE: i32 = 8;
const RECOMMENDATION_REASON_HIGH_INTERFERENCE: i32 = 9;
const RECOMMENDATION_REASON_LESS_CROWDED_BAND: i32 = 10;
const RECOMMENDATION_REASON_DFS_REQUIRED: i32 = 11;
const RECOMMENDATION_REASON_INDOOR_ONLY: i32 = 12;
const RECOMMENDATION_REASON_CAC_REQUIRED: i32 = 13;
const RECOMMENDATION_REASON_RADAR_SENSITIVE: i32 = 14;
const RECOMMENDATION_REASON_MAX: usize = 14;

const RESTRICTION_HAS_DFS: u32 = 1 << 0;
const RESTRICTION_HAS_INDOOR_ONLY: u32 = 1 << 1;
const RESTRICTION_HAS_CAC_REQUIRED: u32 = 1 << 2;
const RESTRICTION_HAS_RADAR_SENSITIVE: u32 = 1 << 3;
const RESTRICTION_KNOWN_FLAGS: u32 = (1 << 4) - 1;

#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub enum RegulatoryDomain {
    Unknown,
    Us,
    Jp,
    Cn,
    Eu,
}

impl RegulatoryDomain {
    fn code(self) -> i32 {
        match self {
            Self::Unknown => REGULATORY_DOMAIN_UNKNOWN,
            Self::Us => REGULATORY_DOMAIN_US,
            Self::Jp => REGULATORY_DOMAIN_JP,
            Self::Cn => REGULATORY_DOMAIN_CN,
            Self::Eu => REGULATORY_DOMAIN_EU,
        }
    }

    fn from_code(code: i32) -> Result<Self, i32> {
        match code {
            REGULATORY_DOMAIN_UNKNOWN => Ok(Self::Unknown),
            REGULATORY_DOMAIN_US => Ok(Self::Us),
            REGULATORY_DOMAIN_JP => Ok(Self::Jp),
            REGULATORY_DOMAIN_CN => Ok(Self::Cn),
            REGULATORY_DOMAIN_EU => Ok(Self::Eu),
            _ => Err(WIFI_LENS_STATUS_INVALID_REGULATORY_INPUT),
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum RegulatoryBand {
    Band24Ghz,
    Band5Ghz,
    Band6Ghz,
}

impl RegulatoryBand {
    fn code(self) -> i32 {
        match self {
            Self::Band24Ghz => REGULATORY_BAND_24_GHZ,
            Self::Band5Ghz => REGULATORY_BAND_5_GHZ,
            Self::Band6Ghz => REGULATORY_BAND_6_GHZ,
        }
    }

    fn from_code(code: i32) -> Result<Self, i32> {
        match code {
            REGULATORY_BAND_24_GHZ => Ok(Self::Band24Ghz),
            REGULATORY_BAND_5_GHZ => Ok(Self::Band5Ghz),
            REGULATORY_BAND_6_GHZ => Ok(Self::Band6Ghz),
            _ => Err(WIFI_LENS_STATUS_INVALID_REGULATORY_INPUT),
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum InferenceConfidence {
    Low,
    Medium,
    High,
}

impl InferenceConfidence {
    fn code(self) -> i32 {
        match self {
            Self::Low => INFERENCE_CONFIDENCE_LOW,
            Self::Medium => INFERENCE_CONFIDENCE_MEDIUM,
            Self::High => INFERENCE_CONFIDENCE_HIGH,
        }
    }

    fn from_code(code: i32) -> Result<Self, i32> {
        match code {
            INFERENCE_CONFIDENCE_LOW => Ok(Self::Low),
            INFERENCE_CONFIDENCE_MEDIUM => Ok(Self::Medium),
            INFERENCE_CONFIDENCE_HIGH => Ok(Self::High),
            _ => Err(WIFI_LENS_STATUS_INVALID_REGULATORY_INPUT),
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct SupportedChannel {
    pub band: i32,
    pub channel: i32,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum RegionSourceKind {
    SystemLocale,
    SupportedChannels,
    ApBeaconCountry,
    UserOverride,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RegionContribution {
    pub kind: RegionSourceKind,
    pub domain: RegulatoryDomain,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum RegionConflictResolution {
    TrustSupportedChannels,
}

impl RegionConflictResolution {
    fn code(self) -> i32 {
        match self {
            Self::TrustSupportedChannels => CONFLICT_CHANNELS_DISAGREE_WITH_AP,
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RegionConflict {
    pub source_a_index: usize,
    pub source_b_index: usize,
    pub resolution: RegionConflictResolution,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct RegionInference {
    pub domain: RegulatoryDomain,
    pub confidence: InferenceConfidence,
    pub contributions: Vec<RegionContribution>,
    pub conflicts: Vec<RegionConflict>,
}

pub struct RegionInferenceInput<'a> {
    pub system_region_code: Option<&'a str>,
    pub supported_channels: &'a [SupportedChannel],
    pub ap_country_codes: &'a [&'a str],
    pub user_override: Option<RegulatoryDomain>,
}

pub fn domain_from_country_code(code: Option<&str>) -> RegulatoryDomain {
    let Some(code) = code else {
        return RegulatoryDomain::Unknown;
    };

    match code.to_ascii_uppercase().as_str() {
        "US" | "CA" | "MX" => RegulatoryDomain::Us,
        "JP" => RegulatoryDomain::Jp,
        "CN" => RegulatoryDomain::Cn,
        "GB" | "DE" | "FR" | "IT" | "ES" | "NL" | "BE" | "SE" | "DK" | "FI" | "PT" | "IE"
        | "AT" | "PL" | "CZ" | "SK" | "HU" | "RO" | "BG" | "HR" | "SI" | "LT" | "LV" | "EE"
        | "LU" | "MT" | "CY" | "GR" | "NO" | "CH" | "IS" | "LI" => RegulatoryDomain::Eu,
        _ => RegulatoryDomain::Unknown,
    }
}

pub fn infer_region(input: RegionInferenceInput<'_>) -> RegionInference {
    let locale_domain = domain_from_country_code(input.system_region_code);
    let ap_result = ap_consensus(input.ap_country_codes);
    let channel_domain = channel_fingerprint(input.supported_channels);
    let mut contributions = Vec::with_capacity(4);
    let mut conflicts = Vec::with_capacity(1);

    if let Some(user_override) = input
        .user_override
        .filter(|domain| *domain != RegulatoryDomain::Unknown)
    {
        contributions.push(RegionContribution {
            kind: RegionSourceKind::UserOverride,
            domain: user_override,
        });
        contributions.push(RegionContribution {
            kind: RegionSourceKind::SystemLocale,
            domain: locale_domain,
        });
        if !input.ap_country_codes.is_empty() {
            contributions.push(RegionContribution {
                kind: RegionSourceKind::ApBeaconCountry,
                domain: ap_result.domain,
            });
        }
        contributions.push(RegionContribution {
            kind: RegionSourceKind::SupportedChannels,
            domain: channel_domain,
        });
        return RegionInference {
            domain: user_override,
            confidence: InferenceConfidence::High,
            contributions,
            conflicts,
        };
    }

    contributions.push(RegionContribution {
        kind: RegionSourceKind::SystemLocale,
        domain: locale_domain,
    });
    if !input.ap_country_codes.is_empty() {
        contributions.push(RegionContribution {
            kind: RegionSourceKind::ApBeaconCountry,
            domain: ap_result.domain,
        });
    }
    contributions.push(RegionContribution {
        kind: RegionSourceKind::SupportedChannels,
        domain: channel_domain,
    });

    let channel_valid = channel_domain != RegulatoryDomain::Unknown;
    let ap_valid =
        ap_result.domain != RegulatoryDomain::Unknown && !input.ap_country_codes.is_empty();
    let locale_valid = locale_domain != RegulatoryDomain::Unknown;

    if channel_valid && ap_valid && channel_domain == ap_result.domain {
        return RegionInference {
            domain: channel_domain,
            confidence: InferenceConfidence::High,
            contributions,
            conflicts,
        };
    }

    if channel_valid {
        if ap_valid && channel_domain != ap_result.domain {
            let source_a_index = contributions
                .iter()
                .position(|source| source.kind == RegionSourceKind::SupportedChannels)
                .unwrap();
            let source_b_index = contributions
                .iter()
                .position(|source| source.kind == RegionSourceKind::ApBeaconCountry)
                .unwrap();
            conflicts.push(RegionConflict {
                source_a_index,
                source_b_index,
                resolution: RegionConflictResolution::TrustSupportedChannels,
            });
        }
        return RegionInference {
            domain: channel_domain,
            confidence: InferenceConfidence::Medium,
            contributions,
            conflicts,
        };
    }

    if ap_valid {
        return RegionInference {
            domain: ap_result.domain,
            confidence: if ap_result.consensus {
                InferenceConfidence::Medium
            } else {
                InferenceConfidence::Low
            },
            contributions,
            conflicts,
        };
    }

    if locale_valid {
        return RegionInference {
            domain: locale_domain,
            confidence: InferenceConfidence::Low,
            contributions,
            conflicts,
        };
    }

    RegionInference {
        domain: RegulatoryDomain::Unknown,
        confidence: InferenceConfidence::Low,
        contributions,
        conflicts,
    }
}

struct ApConsensus {
    domain: RegulatoryDomain,
    consensus: bool,
}

fn ap_consensus(codes: &[&str]) -> ApConsensus {
    let domains: Vec<_> = codes
        .iter()
        .filter_map(|code| {
            let normalized: String = code.chars().take(2).collect();
            let domain = domain_from_country_code(Some(&normalized));
            (domain != RegulatoryDomain::Unknown).then_some(domain)
        })
        .collect();
    if domains.is_empty() {
        return ApConsensus {
            domain: RegulatoryDomain::Unknown,
            consensus: false,
        };
    }

    let mut counts = Vec::<(RegulatoryDomain, usize)>::new();
    for domain in &domains {
        if let Some((_, count)) = counts.iter_mut().find(|(candidate, _)| candidate == domain) {
            *count += 1;
        } else {
            counts.push((*domain, 1));
        }
    }
    let mut winner = counts[0];
    for candidate in counts.into_iter().skip(1) {
        if candidate.1 > winner.1 {
            winner = candidate;
        }
    }
    ApConsensus {
        domain: winner.0,
        consensus: winner.1 == domains.len(),
    }
}

fn channel_fingerprint(channels: &[SupportedChannel]) -> RegulatoryDomain {
    if channels.is_empty() {
        return RegulatoryDomain::Unknown;
    }

    let hardware_channels: HashSet<_> = channels
        .iter()
        .map(|channel| (channel.band, channel.channel))
        .collect();
    let mut best_domain = RegulatoryDomain::Unknown;
    let mut best_score = 0.0_f64;

    for domain in [
        RegulatoryDomain::Us,
        RegulatoryDomain::Jp,
        RegulatoryDomain::Cn,
        RegulatoryDomain::Eu,
    ] {
        let mut expected_channels = HashSet::new();
        for band in [
            RegulatoryBand::Band24Ghz,
            RegulatoryBand::Band5Ghz,
            RegulatoryBand::Band6Ghz,
        ] {
            if let Some(allowed) = allowed_channels(domain, band) {
                expected_channels.extend(allowed.into_iter().map(|channel| (band.code(), channel)));
            }
        }
        if expected_channels.is_empty() {
            continue;
        }

        let intersection_count = expected_channels.intersection(&hardware_channels).count();
        let score =
            intersection_count as f64 / expected_channels.len().min(hardware_channels.len()) as f64;

        if domain == RegulatoryDomain::Jp
            && hardware_channels.contains(&(REGULATORY_BAND_24_GHZ, 14))
        {
            best_score = score + 0.15;
            best_domain = domain;
        }
        if score > best_score {
            best_score = score;
            best_domain = domain;
        }
    }

    if best_domain != RegulatoryDomain::Cn {
        let has_dfs_channels = hardware_channels
            .iter()
            .any(|(_, channel)| (52..=64).contains(channel) || (100..=144).contains(channel));
        if !has_dfs_channels && best_score < 0.5 {
            let cn_expected: HashSet<_> = [
                RegulatoryBand::Band24Ghz,
                RegulatoryBand::Band5Ghz,
                RegulatoryBand::Band6Ghz,
            ]
            .into_iter()
            .flat_map(|band| {
                allowed_channels(RegulatoryDomain::Cn, band)
                    .unwrap_or_default()
                    .into_iter()
                    .map(move |channel| (band.code(), channel))
            })
            .collect();
            let cn_score = cn_expected.intersection(&hardware_channels).count() as f64
                / cn_expected.len().min(hardware_channels.len()) as f64;
            if cn_score > best_score {
                best_score = cn_score;
                best_domain = RegulatoryDomain::Cn;
            }
        }
    }

    if best_score > 0.3 {
        best_domain
    } else {
        RegulatoryDomain::Unknown
    }
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct RegulatoryChannelMetadata {
    pub is_dfs: bool,
    pub is_radar_sensitive: bool,
    pub requires_cac: bool,
    pub forced_switch_risk: bool,
    pub is_indoor_only: bool,
    pub max_eirp_dbm: Option<i32>,
    pub requires_afc: bool,
    pub wifi6e_available: bool,
    pub wifi7_available: bool,
    pub note_code: i32,
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct RegulatoryChannelRule {
    pub channel: i32,
    pub metadata: Option<RegulatoryChannelMetadata>,
}

pub fn regulatory_channel_rules(
    domain: RegulatoryDomain,
    band: RegulatoryBand,
) -> Option<Vec<RegulatoryChannelRule>> {
    let channels = allowed_channels(domain, band)?;
    Some(
        channels
            .into_iter()
            .map(|channel| RegulatoryChannelRule {
                channel,
                metadata: channel_metadata(domain, band, channel),
            })
            .collect(),
    )
}

fn allowed_channels(domain: RegulatoryDomain, band: RegulatoryBand) -> Option<Vec<i32>> {
    let channels = match (domain, band) {
        (RegulatoryDomain::Us, RegulatoryBand::Band24Ghz) => range(1, 11, 1),
        (RegulatoryDomain::Us, RegulatoryBand::Band5Ghz) => {
            let mut channels = range(36, 144, 4);
            channels.extend(range(149, 165, 4));
            channels
        }
        (RegulatoryDomain::Us, RegulatoryBand::Band6Ghz) => range(1, 233, 4),
        (RegulatoryDomain::Jp, RegulatoryBand::Band24Ghz) => range(1, 14, 1),
        (RegulatoryDomain::Jp, RegulatoryBand::Band5Ghz) => range(36, 144, 4),
        (RegulatoryDomain::Jp, RegulatoryBand::Band6Ghz) => range(1, 93, 4),
        (RegulatoryDomain::Cn, RegulatoryBand::Band24Ghz) => range(1, 13, 1),
        (RegulatoryDomain::Cn, RegulatoryBand::Band5Ghz) => {
            let mut channels = range(36, 48, 4);
            channels.extend(range(149, 165, 4));
            channels
        }
        (RegulatoryDomain::Cn, RegulatoryBand::Band6Ghz) => Vec::new(),
        (RegulatoryDomain::Eu, RegulatoryBand::Band24Ghz) => range(1, 13, 1),
        (RegulatoryDomain::Eu, RegulatoryBand::Band5Ghz) => range(36, 144, 4),
        (RegulatoryDomain::Eu, RegulatoryBand::Band6Ghz) => range(1, 93, 4),
        (RegulatoryDomain::Unknown, _) => return None,
    };
    Some(channels)
}

fn range(start: i32, end: i32, step: i32) -> Vec<i32> {
    (start..=end).step_by(step as usize).collect()
}

fn channel_metadata(
    domain: RegulatoryDomain,
    band: RegulatoryBand,
    channel: i32,
) -> Option<RegulatoryChannelMetadata> {
    match (domain, band) {
        (RegulatoryDomain::Us, RegulatoryBand::Band5Ghz) if is_us_dfs(channel) => {
            Some(RegulatoryChannelMetadata {
                is_dfs: true,
                is_radar_sensitive: is_radar_sensitive(channel),
                requires_cac: true,
                forced_switch_risk: true,
                wifi6e_available: true,
                wifi7_available: true,
                note_code: if channel <= 64 { 1 } else { 2 },
                ..RegulatoryChannelMetadata::default()
            })
        }
        (RegulatoryDomain::Jp, RegulatoryBand::Band24Ghz) if channel == 14 => {
            Some(RegulatoryChannelMetadata {
                wifi6e_available: false,
                wifi7_available: false,
                note_code: 5,
                ..RegulatoryChannelMetadata::default()
            })
        }
        (RegulatoryDomain::Jp, RegulatoryBand::Band5Ghz) if is_jp_eu_dfs(channel) => {
            Some(RegulatoryChannelMetadata {
                is_dfs: true,
                is_radar_sensitive: is_radar_sensitive(channel),
                requires_cac: true,
                forced_switch_risk: true,
                wifi6e_available: true,
                wifi7_available: true,
                note_code: if channel <= 64 { 3 } else { 4 },
                ..RegulatoryChannelMetadata::default()
            })
        }
        (RegulatoryDomain::Eu, RegulatoryBand::Band5Ghz) if is_jp_eu_dfs(channel) => {
            Some(RegulatoryChannelMetadata {
                is_dfs: true,
                is_radar_sensitive: is_radar_sensitive(channel),
                requires_cac: true,
                forced_switch_risk: true,
                wifi6e_available: true,
                wifi7_available: true,
                note_code: if channel <= 64 { 1 } else { 2 },
                ..RegulatoryChannelMetadata::default()
            })
        }
        _ => None,
    }
}

fn is_us_dfs(channel: i32) -> bool {
    (52..=64).contains(&channel) || (100..=144).contains(&channel)
}

fn is_jp_eu_dfs(channel: i32) -> bool {
    (52..=64).contains(&channel) || (100..=140).contains(&channel)
}

fn is_radar_sensitive(channel: i32) -> bool {
    (52..=64).contains(&channel) || (100..=128).contains(&channel)
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ChannelClassification {
    Recommended,
    Advanced,
    Restricted,
}

impl ChannelClassification {
    fn code(self) -> i32 {
        match self {
            Self::Recommended => CLASSIFICATION_RECOMMENDED,
            Self::Advanced => CLASSIFICATION_ADVANCED,
            Self::Restricted => CLASSIFICATION_RESTRICTED,
        }
    }

    fn from_code(code: i32) -> Result<Self, i32> {
        match code {
            CLASSIFICATION_RECOMMENDED => Ok(Self::Recommended),
            CLASSIFICATION_ADVANCED => Ok(Self::Advanced),
            CLASSIFICATION_RESTRICTED => Ok(Self::Restricted),
            _ => Err(WIFI_LENS_STATUS_INVALID_REGULATORY_INPUT),
        }
    }

    fn order(self) -> i32 {
        match self {
            Self::Recommended => 2,
            Self::Advanced => 1,
            Self::Restricted => 0,
        }
    }
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct DeviceCapabilities {
    pub supports_n: bool,
    pub supports_ac: bool,
    pub supports_ax: bool,
    pub supports_be: bool,
    pub supports_6ghz: bool,
    pub supports_dfs: bool,
    pub supports_160mhz: bool,
}

impl DeviceCapabilities {
    fn from_flags(flags: u32) -> Result<Self, i32> {
        if flags & !CAPABILITY_KNOWN_FLAGS != 0 {
            return Err(WIFI_LENS_STATUS_INVALID_REGULATORY_INPUT);
        }
        Ok(Self {
            supports_n: flags & CAPABILITY_SUPPORTS_N != 0,
            supports_ac: flags & CAPABILITY_SUPPORTS_AC != 0,
            supports_ax: flags & CAPABILITY_SUPPORTS_AX != 0,
            supports_be: flags & CAPABILITY_SUPPORTS_BE != 0,
            supports_6ghz: flags & CAPABILITY_SUPPORTS_6_GHZ != 0,
            supports_dfs: flags & CAPABILITY_SUPPORTS_DFS != 0,
            supports_160mhz: flags & CAPABILITY_SUPPORTS_160_MHZ != 0,
        })
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum DeviceCompatibilityReason {
    ChannelNotSupported,
    SixGhzUnsupported,
    AfcUnsupported,
    DfsUnsupported,
}

impl DeviceCompatibilityReason {
    fn code(self) -> i32 {
        match self {
            Self::ChannelNotSupported => DEVICE_REASON_CHANNEL_UNSUPPORTED,
            Self::SixGhzUnsupported => DEVICE_REASON_6_GHZ_UNSUPPORTED,
            Self::AfcUnsupported => DEVICE_REASON_AFC_UNSUPPORTED,
            Self::DfsUnsupported => DEVICE_REASON_DFS_UNSUPPORTED,
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct DeviceCompatibility {
    pub compatible: bool,
    pub reason: Option<DeviceCompatibilityReason>,
}

pub struct DeviceCompatibilityInput<'a> {
    pub channel: i32,
    pub band: &'a str,
    pub capabilities: DeviceCapabilities,
    pub has_supported_channels: bool,
    pub supported_channels: &'a [SupportedChannel],
    pub metadata: Option<RegulatoryChannelMetadata>,
}

pub fn check_device_compatibility(input: DeviceCompatibilityInput<'_>) -> DeviceCompatibility {
    let band_raw = band_to_raw(input.band);
    if input.has_supported_channels
        && !input
            .supported_channels
            .iter()
            .any(|supported| supported.band == band_raw && supported.channel == input.channel)
    {
        return incompatible(DeviceCompatibilityReason::ChannelNotSupported);
    }

    match input.band {
        "6" => {
            if !input.capabilities.supports_6ghz {
                return incompatible(DeviceCompatibilityReason::SixGhzUnsupported);
            }
            if input.metadata.is_some_and(|metadata| metadata.requires_afc) {
                return incompatible(DeviceCompatibilityReason::AfcUnsupported);
            }
        }
        "5" => {
            if input.metadata.is_some_and(|metadata| metadata.is_dfs)
                && !input.capabilities.supports_dfs
            {
                return incompatible(DeviceCompatibilityReason::DfsUnsupported);
            }
        }
        _ => {}
    }

    DeviceCompatibility {
        compatible: true,
        reason: None,
    }
}

fn incompatible(reason: DeviceCompatibilityReason) -> DeviceCompatibility {
    DeviceCompatibility {
        compatible: false,
        reason: Some(reason),
    }
}

fn band_to_raw(band: &str) -> i32 {
    match band {
        "24" => REGULATORY_BAND_24_GHZ,
        "5" => REGULATORY_BAND_5_GHZ,
        "6" => REGULATORY_BAND_6_GHZ,
        _ => 0,
    }
}

fn regulatory_band(band: &str) -> Option<RegulatoryBand> {
    match band {
        "24" => Some(RegulatoryBand::Band24Ghz),
        "5" => Some(RegulatoryBand::Band5Ghz),
        "6" => Some(RegulatoryBand::Band6Ghz),
        _ => None,
    }
}

pub struct RegulatoryFilterCandidate<'a> {
    pub band: &'a str,
    pub channel: i32,
    pub rf_score: i32,
    pub score_selected: bool,
    pub recommendation_score: i32,
    pub is_current_channel: bool,
    pub show_in_simple_view: bool,
    pub user_classification_override: Option<ChannelClassification>,
}

pub struct RegulatoryFilterInput<'a> {
    pub domain: RegulatoryDomain,
    pub confidence: InferenceConfidence,
    pub candidates: &'a [RegulatoryFilterCandidate<'a>],
    pub has_supported_channels: bool,
    pub supported_channels: &'a [SupportedChannel],
    pub device_capabilities: DeviceCapabilities,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct RegulatoryFilterResult {
    pub original_index: usize,
    pub classification: ChannelClassification,
    pub restriction_reason_codes: Vec<i32>,
    pub device_compatible: bool,
    pub device_reason: Option<DeviceCompatibilityReason>,
    pub show_in_simple_view: bool,
}

pub fn apply_regulatory_filter(input: RegulatoryFilterInput<'_>) -> Vec<RegulatoryFilterResult> {
    let mut results = input
        .candidates
        .iter()
        .enumerate()
        .map(|(index, candidate)| {
            let rules = if input.domain == RegulatoryDomain::Unknown {
                None
            } else {
                regulatory_band(candidate.band).and_then(|band| {
                    allowed_channels(input.domain, band).map(|channels| (band, channels))
                })
            };
            let mut classification = ChannelClassification::Recommended;
            let mut reasons = Vec::with_capacity(MAX_FILTER_REASONS);
            let mut metadata = None;

            match rules {
                None => {
                    classification = ChannelClassification::Restricted;
                    reasons.push(REASON_REGION_UNKNOWN);
                }
                Some((_, channels)) if !channels.contains(&candidate.channel) => {
                    classification = ChannelClassification::Restricted;
                    reasons.push(REASON_REGION_BLOCKED);
                }
                Some((band, _)) => {
                    metadata = channel_metadata(input.domain, band, candidate.channel);
                    if let Some(metadata) = metadata {
                        if metadata.is_dfs {
                            classification = ChannelClassification::Advanced;
                            reasons.push(REASON_DFS);
                        }
                        if metadata.is_radar_sensitive {
                            reasons.push(REASON_RADAR_SENSITIVE);
                        }
                        if metadata.requires_cac {
                            reasons.push(REASON_CAC_REQUIRED);
                        }
                        if metadata.is_indoor_only {
                            classification = lower_classification(
                                classification,
                                ChannelClassification::Advanced,
                            );
                            reasons.push(REASON_INDOOR_ONLY);
                        }
                        if metadata.requires_afc {
                            classification = ChannelClassification::Restricted;
                            reasons.push(REASON_AFC_REQUIRED);
                        }
                    }
                    if input.confidence == InferenceConfidence::Low {
                        reasons.push(REASON_REGION_LOW_CONFIDENCE);
                        if classification == ChannelClassification::Recommended {
                            classification = ChannelClassification::Advanced;
                        }
                    }
                }
            }

            let compatibility = check_device_compatibility(DeviceCompatibilityInput {
                channel: candidate.channel,
                band: candidate.band,
                capabilities: input.device_capabilities,
                has_supported_channels: input.has_supported_channels,
                supported_channels: &input.supported_channels,
                metadata,
            });
            if !compatibility.compatible {
                reasons.push(REASON_DEVICE_INCOMPATIBLE);
                if classification != ChannelClassification::Restricted {
                    classification = ChannelClassification::Restricted;
                }
            }
            if let Some(override_classification) = candidate.user_classification_override {
                classification = override_classification;
                reasons.push(REASON_USER_OVERRIDE);
            }

            RegulatoryFilterResult {
                original_index: index,
                classification,
                restriction_reason_codes: reasons,
                device_compatible: compatibility.compatible,
                device_reason: compatibility.reason,
                show_in_simple_view: candidate.show_in_simple_view
                    && classification != ChannelClassification::Restricted,
            }
        })
        .collect::<Vec<_>>();

    results.sort_by(|left, right| {
        let a = &input.candidates[left.original_index];
        let b = &input.candidates[right.original_index];
        b.is_current_channel
            .cmp(&a.is_current_channel)
            .then_with(|| {
                right
                    .classification
                    .order()
                    .cmp(&left.classification.order())
            })
            .then_with(|| b.score_selected.cmp(&a.score_selected))
            .then_with(|| b.recommendation_score.cmp(&a.recommendation_score))
            .then_with(|| b.rf_score.cmp(&a.rf_score))
            .then_with(|| a.band.cmp(b.band))
            .then_with(|| a.channel.cmp(&b.channel))
    });
    results
}

fn lower_classification(
    left: ChannelClassification,
    right: ChannelClassification,
) -> ChannelClassification {
    if left.order() < right.order() {
        left
    } else {
        right
    }
}

pub struct RecommendationReasonInput<'a> {
    pub band: &'a str,
    pub channel: i32,
    pub rf_score: i32,
    pub ap_count: i32,
    pub is_current_channel: bool,
    pub is_recommended: bool,
    pub adjacent_count: i32,
    pub interference_score: i32,
    /// 1 = low, 2 = moderate, 3 = high; the remaining values mean no overlap.
    pub overlap_level: i32,
    pub restriction_flags: u32,
}

pub fn recommendation_reasons(inputs: &[RecommendationReasonInput<'_>]) -> Vec<Vec<i32>> {
    let mut band_ap_counts = HashMap::<&str, i32>::new();
    for input in inputs {
        *band_ap_counts.entry(input.band).or_default() += input.ap_count;
    }

    inputs
        .iter()
        .map(|input| {
            let mut reasons = Vec::with_capacity(RECOMMENDATION_REASON_MAX);
            if input.is_current_channel {
                reasons.push(RECOMMENDATION_REASON_CURRENT_CHANNEL);
            }
            if input.is_current_channel && input.rf_score >= 90 {
                reasons.push(RECOMMENDATION_REASON_CURRENTLY_OPTIMAL);
            }
            match input.ap_count {
                0 => reasons.push(RECOMMENDATION_REASON_CLEAR_SPECTRUM),
                1..=2 => reasons.push(RECOMMENDATION_REASON_LOW_CONGESTION),
                6.. if !input.is_recommended => reasons.push(RECOMMENDATION_REASON_CONGESTED),
                _ => {}
            }
            match input.overlap_level {
                1 if input.adjacent_count <= 1 => reasons.push(RECOMMENDATION_REASON_LOW_OVERLAP),
                3 if !input.is_recommended => reasons.push(RECOMMENDATION_REASON_HIGH_OVERLAP),
                _ => {}
            }
            match input.interference_score {
                ..=15 => reasons.push(RECOMMENDATION_REASON_LOW_INTERFERENCE),
                40.. if !input.is_recommended => {
                    reasons.push(RECOMMENDATION_REASON_HIGH_INTERFERENCE)
                }
                _ => {}
            }
            if input.band != "24"
                && band_ap_counts.get("24").is_some_and(|band24_count| {
                    band_ap_counts
                        .get(input.band)
                        .is_some_and(|band_count| band24_count > band_count)
                })
            {
                reasons.push(RECOMMENDATION_REASON_LESS_CROWDED_BAND);
            }
            if input.restriction_flags & RESTRICTION_HAS_DFS != 0 {
                reasons.push(RECOMMENDATION_REASON_DFS_REQUIRED);
            }
            if input.restriction_flags & RESTRICTION_HAS_INDOOR_ONLY != 0 {
                reasons.push(RECOMMENDATION_REASON_INDOOR_ONLY);
            }
            if input.restriction_flags & RESTRICTION_HAS_CAC_REQUIRED != 0 {
                reasons.push(RECOMMENDATION_REASON_CAC_REQUIRED);
            }
            if input.restriction_flags & RESTRICTION_HAS_RADAR_SENSITIVE != 0 {
                reasons.push(RECOMMENDATION_REASON_RADAR_SENSITIVE);
            }
            let mut deduplicated = Vec::with_capacity(reasons.len());
            for reason in reasons {
                if !deduplicated.contains(&reason) {
                    deduplicated.push(reason);
                }
            }
            deduplicated
        })
        .collect()
}

fn metadata_flags(metadata: RegulatoryChannelMetadata) -> u32 {
    u32::from(metadata.is_dfs) * META_IS_DFS
        | u32::from(metadata.is_radar_sensitive) * META_IS_RADAR_SENSITIVE
        | u32::from(metadata.requires_cac) * META_REQUIRES_CAC
        | u32::from(metadata.forced_switch_risk) * META_FORCED_SWITCH_RISK
        | u32::from(metadata.is_indoor_only) * META_IS_INDOOR_ONLY
        | u32::from(metadata.requires_afc) * META_REQUIRES_AFC
        | u32::from(metadata.wifi6e_available) * META_WIFI_6E_AVAILABLE
        | u32::from(metadata.wifi7_available) * META_WIFI_7_AVAILABLE
}

fn metadata_from_flags(
    flags: u32,
    max_eirp_dbm: i32,
    has_max_eirp: u8,
    note_code: i32,
) -> Result<RegulatoryChannelMetadata, i32> {
    if flags & !META_KNOWN_FLAGS != 0 || has_max_eirp > 1 {
        return Err(WIFI_LENS_STATUS_INVALID_REGULATORY_INPUT);
    }
    Ok(RegulatoryChannelMetadata {
        is_dfs: flags & META_IS_DFS != 0,
        is_radar_sensitive: flags & META_IS_RADAR_SENSITIVE != 0,
        requires_cac: flags & META_REQUIRES_CAC != 0,
        forced_switch_risk: flags & META_FORCED_SWITCH_RISK != 0,
        is_indoor_only: flags & META_IS_INDOOR_ONLY != 0,
        max_eirp_dbm: (has_max_eirp != 0).then_some(max_eirp_dbm),
        requires_afc: flags & META_REQUIRES_AFC != 0,
        wifi6e_available: flags & META_WIFI_6E_AVAILABLE != 0,
        wifi7_available: flags & META_WIFI_7_AVAILABLE != 0,
        note_code,
    })
}

fn read_string_slice(strings: &[u8], offset: usize, length: usize) -> Result<&[u8], i32> {
    let end = offset
        .checked_add(length)
        .ok_or(WIFI_LENS_STATUS_INVALID_INPUT_SLICE)?;
    strings
        .get(offset..end)
        .ok_or(WIFI_LENS_STATUS_INVALID_INPUT_SLICE)
}

fn parse_utf8_slice(strings: &[u8], offset: usize, length: usize) -> Result<&str, i32> {
    std::str::from_utf8(read_string_slice(strings, offset, length)?)
        .map_err(|_| WIFI_LENS_STATUS_INVALID_UTF8)
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
pub struct WiFiLensRegulatoryStringRange {
    pub offset: usize,
    pub length: usize,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
pub struct WiFiLensRegulatorySupportedChannel {
    pub band: i32,
    pub channel: i32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
pub struct WiFiLensRegulatoryInferenceInput {
    pub locale_region_offset: usize,
    pub locale_region_length: usize,
    pub user_override_domain: i32,
    pub ap_country_code_count: usize,
    pub ap_country_codes: *const WiFiLensRegulatoryStringRange,
    pub supported_channel_count: usize,
    pub supported_channels: *const WiFiLensRegulatorySupportedChannel,
    pub strings_length: usize,
    pub strings: *const u8,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
pub struct WiFiLensRegulatoryInferenceResult {
    pub domain: i32,
    pub confidence: i32,
    pub locale_domain: i32,
    pub ap_domain: i32,
    pub supported_channels_domain: i32,
    pub conflict_resolution: i32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
pub struct WiFiLensRegulatoryChannelRule {
    pub channel: i32,
    pub has_metadata: u8,
    pub metadata_flags: u32,
    pub max_eirp_dbm: i32,
    pub has_max_eirp: u8,
    pub note_code: i32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
pub struct WiFiLensRegulatoryFilterCandidate {
    pub band_offset: usize,
    pub band_length: usize,
    pub channel: i32,
    pub rf_score: i32,
    pub score_selected: u8,
    pub recommendation_score: i32,
    pub is_current_channel: u8,
    pub show_in_simple_view: u8,
    pub user_classification_override: i32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
pub struct WiFiLensRegulatoryFilterConfig {
    pub domain: i32,
    pub confidence: i32,
    pub flags: u32,
    pub capability_flags: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct WiFiLensRegulatoryFilterResult {
    pub original_index: usize,
    pub classification: i32,
    pub restriction_reason_flags: u32,
    pub device_compatible: u8,
    pub device_reason: i32,
    pub show_in_simple_view: u8,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
pub struct WiFiLensDeviceCompatibilityInput {
    pub band_code: i32,
    pub channel: i32,
    pub has_supported_channels: u8,
    pub capability_flags: u32,
    pub has_metadata: u8,
    pub metadata_flags: u32,
    pub max_eirp_dbm: i32,
    pub has_max_eirp: u8,
    pub note_code: i32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct WiFiLensDeviceCompatibilityResult {
    pub is_compatible: u8,
    pub reason: i32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
pub struct WiFiLensRecommendationReasonInput {
    pub band_offset: usize,
    pub band_length: usize,
    pub channel: i32,
    pub rf_score: i32,
    pub ap_count: i32,
    pub is_current_channel: u8,
    pub is_recommended: u8,
    pub adjacent_count: i32,
    pub interference_score: i32,
    pub overlap_level: i32,
    pub restriction_flags: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct WiFiLensRecommendationReasonResult {
    pub reason_flags: u32,
}

/// Map an ISO 3166-1 alpha-2 country code to its regulatory domain code.
///
/// Invalid UTF-8 and unknown codes return [`REGULATORY_DOMAIN_UNKNOWN`]. A
/// non-empty null input returns [`WIFI_LENS_STATUS_INVALID_POINTER`].
///
/// # Safety
///
/// When `country_code_length` is nonzero, `country_code` must point to that many
/// readable bytes for the duration of the call.
#[no_mangle]
pub unsafe extern "C" fn wifi_lens_regulatory_domain_from_country_code(
    country_code: *const u8,
    country_code_length: usize,
) -> i32 {
    if country_code_length > 0 && country_code.is_null() {
        return WIFI_LENS_STATUS_INVALID_POINTER;
    }
    let bytes = if country_code_length == 0 {
        &[]
    } else {
        unsafe { std::slice::from_raw_parts(country_code, country_code_length) }
    };
    let code = std::str::from_utf8(bytes).ok();
    domain_from_country_code(code).code()
}

/// Infer a region from caller-owned locale, AP country, channel, and override facts.
///
/// # Safety
///
/// `input` and `output` must point to aligned records valid for this call. Each
/// nonempty input array and string buffer must point to valid caller-owned
/// storage of the declared length; output must not overlap any input.
#[no_mangle]
pub unsafe extern "C" fn wifi_lens_regulatory_infer(
    input: *const WiFiLensRegulatoryInferenceInput,
    output: *mut WiFiLensRegulatoryInferenceResult,
) -> i32 {
    if input.is_null() || output.is_null() {
        return WIFI_LENS_STATUS_INVALID_POINTER;
    }
    let raw = unsafe { *input };
    if (raw.ap_country_code_count > 0 && raw.ap_country_codes.is_null())
        || (raw.supported_channel_count > 0 && raw.supported_channels.is_null())
        || (raw.strings_length > 0 && raw.strings.is_null())
    {
        return WIFI_LENS_STATUS_INVALID_POINTER;
    }

    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let user_override = match RegulatoryDomain::from_code(raw.user_override_domain)? {
            RegulatoryDomain::Unknown => None,
            domain => Some(domain),
        };
        let strings = if raw.strings_length == 0 {
            &[]
        } else {
            unsafe { std::slice::from_raw_parts(raw.strings, raw.strings_length) }
        };
        let locale_code = if raw.locale_region_length == 0 {
            None
        } else {
            Some(parse_utf8_slice(
                strings,
                raw.locale_region_offset,
                raw.locale_region_length,
            )?)
        };
        let raw_countries = if raw.ap_country_code_count == 0 {
            &[]
        } else {
            unsafe { std::slice::from_raw_parts(raw.ap_country_codes, raw.ap_country_code_count) }
        };
        let mut country_codes = Vec::with_capacity(raw.ap_country_code_count);
        for country in raw_countries {
            country_codes.push(parse_utf8_slice(strings, country.offset, country.length)?);
        }
        let raw_channels = if raw.supported_channel_count == 0 {
            &[]
        } else {
            unsafe {
                std::slice::from_raw_parts(raw.supported_channels, raw.supported_channel_count)
            }
        };
        let channels: Vec<_> = raw_channels
            .iter()
            .map(|channel| SupportedChannel {
                band: channel.band,
                channel: channel.channel,
            })
            .collect();
        Ok::<_, i32>(infer_region(RegionInferenceInput {
            system_region_code: locale_code,
            supported_channels: &channels,
            ap_country_codes: &country_codes,
            user_override,
        }))
    }));

    match result {
        Ok(Ok(inference)) => {
            let mut output_value = WiFiLensRegulatoryInferenceResult {
                domain: inference.domain.code(),
                confidence: inference.confidence.code(),
                ..WiFiLensRegulatoryInferenceResult::default()
            };
            for source in inference.contributions {
                match source.kind {
                    RegionSourceKind::SystemLocale => {
                        output_value.locale_domain = source.domain.code()
                    }
                    RegionSourceKind::SupportedChannels => {
                        output_value.supported_channels_domain = source.domain.code()
                    }
                    RegionSourceKind::ApBeaconCountry => {
                        output_value.ap_domain = source.domain.code()
                    }
                    RegionSourceKind::UserOverride => {}
                }
            }
            if let Some(conflict) = inference.conflicts.first() {
                output_value.conflict_resolution = conflict.resolution.code();
            }
            unsafe { *output = output_value };
            0
        }
        Ok(Err(status)) => status,
        Err(_) => WIFI_LENS_STATUS_PANIC,
    }
}

/// Write the allowed channels and metadata for one known domain and band.
///
/// # Safety
///
/// `output_count` must point to a writable `usize`. When `output_capacity` is
/// nonzero, `output` must point to that many writable, aligned records.
#[no_mangle]
pub unsafe extern "C" fn wifi_lens_regulatory_channel_rules(
    domain_code: i32,
    band_code: i32,
    output: *mut WiFiLensRegulatoryChannelRule,
    output_capacity: usize,
    output_count: *mut usize,
) -> i32 {
    if output_count.is_null() || (output_capacity > 0 && output.is_null()) {
        return WIFI_LENS_STATUS_INVALID_POINTER;
    }
    unsafe { *output_count = 0 };
    let rules = std::panic::catch_unwind(|| {
        let domain = RegulatoryDomain::from_code(domain_code)?;
        let band = RegulatoryBand::from_code(band_code)?;
        regulatory_channel_rules(domain, band).ok_or(WIFI_LENS_STATUS_INVALID_REGULATORY_INPUT)
    });
    match rules {
        Ok(Ok(rules)) => {
            unsafe { *output_count = rules.len() };
            if output_capacity < rules.len() {
                return WIFI_LENS_STATUS_OUTPUT_TOO_SMALL;
            }
            if !rules.is_empty() {
                let output_slice = unsafe { std::slice::from_raw_parts_mut(output, rules.len()) };
                for (target, rule) in output_slice.iter_mut().zip(rules) {
                    *target = WiFiLensRegulatoryChannelRule {
                        channel: rule.channel,
                        has_metadata: u8::from(rule.metadata.is_some()),
                        metadata_flags: rule.metadata.map(metadata_flags).unwrap_or_default(),
                        max_eirp_dbm: rule
                            .metadata
                            .and_then(|metadata| metadata.max_eirp_dbm)
                            .unwrap_or_default(),
                        has_max_eirp: u8::from(
                            rule.metadata
                                .is_some_and(|metadata| metadata.max_eirp_dbm.is_some()),
                        ),
                        note_code: rule
                            .metadata
                            .map(|metadata| metadata.note_code)
                            .unwrap_or_default(),
                    };
                }
            }
            0
        }
        Ok(Err(status)) => status,
        Err(_) => WIFI_LENS_STATUS_PANIC,
    }
}

/// Check device compatibility from normalized hardware facts and rule metadata.
///
/// # Safety
///
/// `input` and `output` must point to aligned, valid records. A nonzero channel
/// count requires a valid aligned input array of that length; the writable
/// output must not overlap either input.
#[no_mangle]
pub unsafe extern "C" fn wifi_lens_regulatory_device_compatibility(
    input: *const WiFiLensDeviceCompatibilityInput,
    supported_channels: *const WiFiLensRegulatorySupportedChannel,
    supported_channel_count: usize,
    output: *mut WiFiLensDeviceCompatibilityResult,
) -> i32 {
    if input.is_null()
        || output.is_null()
        || (supported_channel_count > 0 && supported_channels.is_null())
    {
        return WIFI_LENS_STATUS_INVALID_POINTER;
    }
    let raw = unsafe { *input };
    if raw.has_supported_channels > 1 || raw.has_metadata > 1 {
        return WIFI_LENS_STATUS_INVALID_REGULATORY_INPUT;
    }
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let band = band_string(raw.band_code)?;
        let capabilities = DeviceCapabilities::from_flags(raw.capability_flags)?;
        let metadata = if raw.has_metadata != 0 {
            Some(metadata_from_flags(
                raw.metadata_flags,
                raw.max_eirp_dbm,
                raw.has_max_eirp,
                raw.note_code,
            )?)
        } else {
            if raw.metadata_flags != 0 || raw.has_max_eirp != 0 || raw.note_code != 0 {
                return Err(WIFI_LENS_STATUS_INVALID_REGULATORY_INPUT);
            }
            None
        };
        let raw_supported = if supported_channel_count == 0 {
            &[]
        } else {
            unsafe { std::slice::from_raw_parts(supported_channels, supported_channel_count) }
        };
        let supported: Vec<_> = raw_supported
            .iter()
            .map(|channel| SupportedChannel {
                band: channel.band,
                channel: channel.channel,
            })
            .collect();
        Ok::<_, i32>(check_device_compatibility(DeviceCompatibilityInput {
            channel: raw.channel,
            band,
            capabilities,
            has_supported_channels: raw.has_supported_channels != 0,
            supported_channels: &supported,
            metadata,
        }))
    }));
    match result {
        Ok(Ok(result)) => {
            unsafe {
                *output = WiFiLensDeviceCompatibilityResult {
                    is_compatible: u8::from(result.compatible),
                    reason: result
                        .reason
                        .map(DeviceCompatibilityReason::code)
                        .unwrap_or(DEVICE_REASON_NONE),
                }
            };
            0
        }
        Ok(Err(status)) => status,
        Err(_) => WIFI_LENS_STATUS_PANIC,
    }
}

/// Apply region rules, device compatibility, user overrides, and recommendation order.
///
/// # Safety
///
/// Every nonempty input pointer must reference valid aligned storage for its
/// declared count or byte length. `output_count` must be writable, and `output`
/// must reference `output_capacity` writable aligned records when capacity is
/// nonzero. Writable output may not overlap input or configuration storage.
#[no_mangle]
pub unsafe extern "C" fn wifi_lens_regulatory_filter(
    candidates: *const WiFiLensRegulatoryFilterCandidate,
    candidate_count: usize,
    strings: *const u8,
    strings_length: usize,
    supported_channels: *const WiFiLensRegulatorySupportedChannel,
    supported_channel_count: usize,
    config: *const WiFiLensRegulatoryFilterConfig,
    output: *mut WiFiLensRegulatoryFilterResult,
    output_capacity: usize,
    output_count: *mut usize,
) -> i32 {
    if config.is_null()
        || output_count.is_null()
        || (candidate_count > 0 && candidates.is_null())
        || (strings_length > 0 && strings.is_null())
        || (supported_channel_count > 0 && supported_channels.is_null())
        || (output_capacity > 0 && output.is_null())
    {
        return WIFI_LENS_STATUS_INVALID_POINTER;
    }
    unsafe { *output_count = 0 };
    let raw_config = unsafe { *config };
    if raw_config.flags & !FILTER_HAS_SUPPORTED_CHANNELS != 0 {
        return WIFI_LENS_STATUS_INVALID_REGULATORY_INPUT;
    }

    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let domain = RegulatoryDomain::from_code(raw_config.domain)?;
        let confidence = InferenceConfidence::from_code(raw_config.confidence)?;
        let capabilities = DeviceCapabilities::from_flags(raw_config.capability_flags)?;
        let strings = if strings_length == 0 {
            &[]
        } else {
            unsafe { std::slice::from_raw_parts(strings, strings_length) }
        };
        let raw_candidates = if candidate_count == 0 {
            &[]
        } else {
            unsafe { std::slice::from_raw_parts(candidates, candidate_count) }
        };
        let mut parsed_candidates = Vec::with_capacity(candidate_count);
        for candidate in raw_candidates {
            if candidate.score_selected > 1
                || candidate.is_current_channel > 1
                || candidate.show_in_simple_view > 1
            {
                return Err(WIFI_LENS_STATUS_INVALID_REGULATORY_INPUT);
            }
            let override_classification = if candidate.user_classification_override == 0 {
                None
            } else {
                Some(ChannelClassification::from_code(
                    candidate.user_classification_override,
                )?)
            };
            parsed_candidates.push(RegulatoryFilterCandidate {
                band: parse_utf8_slice(strings, candidate.band_offset, candidate.band_length)?,
                channel: candidate.channel,
                rf_score: candidate.rf_score,
                score_selected: candidate.score_selected != 0,
                recommendation_score: candidate.recommendation_score,
                is_current_channel: candidate.is_current_channel != 0,
                show_in_simple_view: candidate.show_in_simple_view != 0,
                user_classification_override: override_classification,
            });
        }
        let raw_supported = if supported_channel_count == 0 {
            &[]
        } else {
            unsafe { std::slice::from_raw_parts(supported_channels, supported_channel_count) }
        };
        let parsed_supported: Vec<_> = raw_supported
            .iter()
            .map(|channel| SupportedChannel {
                band: channel.band,
                channel: channel.channel,
            })
            .collect();
        Ok::<_, i32>(apply_regulatory_filter(RegulatoryFilterInput {
            domain,
            confidence,
            candidates: &parsed_candidates,
            has_supported_channels: raw_config.flags & FILTER_HAS_SUPPORTED_CHANNELS != 0,
            supported_channels: &parsed_supported,
            device_capabilities: capabilities,
        }))
    }));

    match result {
        Ok(Ok(results)) => {
            unsafe { *output_count = results.len() };
            if output_capacity < results.len() {
                return WIFI_LENS_STATUS_OUTPUT_TOO_SMALL;
            }
            if !results.is_empty() {
                let output_slice = unsafe { std::slice::from_raw_parts_mut(output, results.len()) };
                for (target, result) in output_slice.iter_mut().zip(results) {
                    let restriction_reason_flags = result
                        .restriction_reason_codes
                        .iter()
                        .fold(0, |flags, reason| flags | (1 << (reason - 1)));
                    *target = WiFiLensRegulatoryFilterResult {
                        original_index: result.original_index,
                        classification: result.classification.code(),
                        restriction_reason_flags,
                        device_compatible: u8::from(result.device_compatible),
                        device_reason: result
                            .device_reason
                            .map(DeviceCompatibilityReason::code)
                            .unwrap_or(DEVICE_REASON_NONE),
                        show_in_simple_view: u8::from(result.show_in_simple_view),
                    };
                }
            }
            0
        }
        Ok(Err(status)) => status,
        Err(_) => WIFI_LENS_STATUS_PANIC,
    }
}

/// Compute stable recommendation reason flags for a caller-owned candidate array.
///
/// # Safety
///
/// `output_count` must point to a writable `usize`; all nonempty input arrays and
/// string bytes must be valid and aligned for their declared lengths. A nonzero
/// output capacity requires a writable output array that does not overlap inputs.
#[no_mangle]
pub unsafe extern "C" fn wifi_lens_recommendation_reasons(
    inputs: *const WiFiLensRecommendationReasonInput,
    input_count: usize,
    strings: *const u8,
    strings_length: usize,
    outputs: *mut WiFiLensRecommendationReasonResult,
    output_capacity: usize,
    output_count: *mut usize,
) -> i32 {
    if output_count.is_null()
        || (input_count > 0 && inputs.is_null())
        || (strings_length > 0 && strings.is_null())
        || (output_capacity > 0 && outputs.is_null())
    {
        return WIFI_LENS_STATUS_INVALID_POINTER;
    }
    unsafe { *output_count = 0 };
    if output_capacity < input_count {
        unsafe { *output_count = input_count };
        return WIFI_LENS_STATUS_OUTPUT_TOO_SMALL;
    }

    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let strings = if strings_length == 0 {
            &[]
        } else {
            unsafe { std::slice::from_raw_parts(strings, strings_length) }
        };
        let raw_inputs = if input_count == 0 {
            &[]
        } else {
            unsafe { std::slice::from_raw_parts(inputs, input_count) }
        };
        let mut parsed = Vec::with_capacity(input_count);
        for input in raw_inputs {
            if input.is_current_channel > 1
                || input.is_recommended > 1
                || input.restriction_flags & !RESTRICTION_KNOWN_FLAGS != 0
                || !(0..=3).contains(&input.overlap_level)
            {
                return Err(WIFI_LENS_STATUS_INVALID_REGULATORY_INPUT);
            }
            parsed.push(RecommendationReasonInput {
                band: parse_utf8_slice(strings, input.band_offset, input.band_length)?,
                channel: input.channel,
                rf_score: input.rf_score,
                ap_count: input.ap_count,
                is_current_channel: input.is_current_channel != 0,
                is_recommended: input.is_recommended != 0,
                adjacent_count: input.adjacent_count,
                interference_score: input.interference_score,
                overlap_level: input.overlap_level,
                restriction_flags: input.restriction_flags,
            });
        }
        Ok::<_, i32>(recommendation_reasons(&parsed))
    }));

    match result {
        Ok(Ok(reasons)) => {
            unsafe { *output_count = reasons.len() };
            if !reasons.is_empty() {
                let output_slice =
                    unsafe { std::slice::from_raw_parts_mut(outputs, reasons.len()) };
                for (target, codes) in output_slice.iter_mut().zip(reasons) {
                    let reason_flags = codes
                        .iter()
                        .fold(0, |flags, code| flags | (1 << (code - 1)));
                    *target = WiFiLensRecommendationReasonResult { reason_flags };
                }
            }
            0
        }
        Ok(Err(status)) => status,
        Err(_) => WIFI_LENS_STATUS_PANIC,
    }
}

fn band_string(code: i32) -> Result<&'static str, i32> {
    match code {
        0 => Ok("unknown"),
        REGULATORY_BAND_24_GHZ => Ok("24"),
        REGULATORY_BAND_5_GHZ => Ok("5"),
        REGULATORY_BAND_6_GHZ => Ok("6"),
        _ => Err(WIFI_LENS_STATUS_INVALID_REGULATORY_INPUT),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn supported(pairs: &[(i32, i32)]) -> Vec<SupportedChannel> {
        pairs
            .iter()
            .map(|(band, channel)| SupportedChannel {
                band: *band,
                channel: *channel,
            })
            .collect()
    }

    #[test]
    fn country_code_c_abi_rejects_a_null_nonempty_slice() {
        let status = unsafe { wifi_lens_regulatory_domain_from_country_code(std::ptr::null(), 1) };
        assert_eq!(status, WIFI_LENS_STATUS_INVALID_POINTER);
        assert_eq!(
            unsafe { wifi_lens_regulatory_domain_from_country_code(std::ptr::null(), 0) },
            REGULATORY_DOMAIN_UNKNOWN
        );
    }

    #[test]
    fn country_mapping_and_region_precedence_match_the_swift_contract() {
        assert_eq!(domain_from_country_code(Some("ca")), RegulatoryDomain::Us);
        assert_eq!(domain_from_country_code(Some("gb")), RegulatoryDomain::Eu);
        assert_eq!(domain_from_country_code(Some("JP")), RegulatoryDomain::Jp);
        assert_eq!(
            domain_from_country_code(Some("ZZ")),
            RegulatoryDomain::Unknown
        );
        assert_eq!(domain_from_country_code(None), RegulatoryDomain::Unknown);

        let result = infer_region(RegionInferenceInput {
            system_region_code: Some("JP"),
            supported_channels: &[],
            ap_country_codes: &["US", "US"],
            user_override: Some(RegulatoryDomain::Cn),
        });
        assert_eq!(result.domain, RegulatoryDomain::Cn);
        assert_eq!(result.confidence, InferenceConfidence::High);
        assert_eq!(result.contributions.len(), 4);
        assert_eq!(result.contributions[0].kind, RegionSourceKind::UserOverride);
        assert_eq!(result.contributions[1].kind, RegionSourceKind::SystemLocale);
        assert_eq!(
            result.contributions[2].kind,
            RegionSourceKind::ApBeaconCountry
        );
        assert_eq!(
            result.contributions[3].kind,
            RegionSourceKind::SupportedChannels
        );
    }

    #[test]
    fn region_inference_preserves_channel_priority_ap_confidence_and_unknown() {
        let us_channels = supported(&[(1, 1), (1, 6), (1, 11), (2, 36), (2, 40), (2, 44)]);
        let matched = infer_region(RegionInferenceInput {
            system_region_code: Some("DE"),
            supported_channels: &us_channels,
            ap_country_codes: &["US"],
            user_override: None,
        });
        assert_eq!(matched.domain, RegulatoryDomain::Us);
        assert_eq!(matched.confidence, InferenceConfidence::High);

        let conflict = infer_region(RegionInferenceInput {
            system_region_code: Some("US"),
            supported_channels: &us_channels,
            ap_country_codes: &["JP"],
            user_override: None,
        });
        assert_eq!(conflict.domain, RegulatoryDomain::Us);
        assert_eq!(conflict.confidence, InferenceConfidence::Medium);
        assert_eq!(conflict.conflicts.len(), 1);
        assert_eq!(
            conflict.conflicts[0].resolution,
            RegionConflictResolution::TrustSupportedChannels
        );

        let ap_tie = infer_region(RegionInferenceInput {
            system_region_code: Some("ZZ"),
            supported_channels: &[],
            ap_country_codes: &["US", "DE"],
            user_override: None,
        });
        assert_eq!(ap_tie.domain, RegulatoryDomain::Us);
        assert_eq!(ap_tie.confidence, InferenceConfidence::Low);

        let ap_only = infer_region(RegionInferenceInput {
            system_region_code: Some("ZZ"),
            supported_channels: &[],
            ap_country_codes: &["US", "DE", "US"],
            user_override: None,
        });
        assert_eq!(ap_only.domain, RegulatoryDomain::Us);
        assert_eq!(ap_only.confidence, InferenceConfidence::Low);

        let unknown = infer_region(RegionInferenceInput {
            system_region_code: Some("ZZ"),
            supported_channels: &[],
            ap_country_codes: &["ZZ", "??"],
            user_override: None,
        });
        assert_eq!(unknown.domain, RegulatoryDomain::Unknown);
        assert_eq!(unknown.confidence, InferenceConfidence::Low);
    }

    #[test]
    fn channel_fingerprint_preserves_japan_bonus_and_first_region_tie() {
        assert_eq!(
            channel_fingerprint(&supported(&[(1, 1), (1, 6), (1, 11), (1, 14)])),
            RegulatoryDomain::Jp
        );
        assert_eq!(
            channel_fingerprint(&supported(&[
                (1, 1),
                (1, 6),
                (1, 11),
                (2, 36),
                (2, 40),
                (2, 44)
            ])),
            RegulatoryDomain::Us
        );
        assert_eq!(
            channel_fingerprint(&supported(&[
                (1, 1),
                (1, 6),
                (1, 11),
                (2, 149),
                (2, 153),
                (2, 157)
            ])),
            RegulatoryDomain::Us
        );
    }

    #[test]
    fn regulatory_database_preserves_region_channel_sets_and_metadata() {
        assert_eq!(
            allowed_channels(RegulatoryDomain::Us, RegulatoryBand::Band24Ghz).unwrap(),
            range(1, 11, 1)
        );
        assert_eq!(
            allowed_channels(RegulatoryDomain::Jp, RegulatoryBand::Band24Ghz).unwrap(),
            range(1, 14, 1)
        );
        assert_eq!(
            allowed_channels(RegulatoryDomain::Cn, RegulatoryBand::Band6Ghz).unwrap(),
            Vec::<i32>::new()
        );
        assert_eq!(
            allowed_channels(RegulatoryDomain::Eu, RegulatoryBand::Band6Ghz).unwrap(),
            range(1, 93, 4)
        );
        let us_dfs = channel_metadata(RegulatoryDomain::Us, RegulatoryBand::Band5Ghz, 52).unwrap();
        assert!(
            us_dfs.is_dfs
                && us_dfs.is_radar_sensitive
                && us_dfs.requires_cac
                && us_dfs.forced_switch_risk
        );
        assert_eq!(us_dfs.note_code, 1);
        let japan_channel_14 =
            channel_metadata(RegulatoryDomain::Jp, RegulatoryBand::Band24Ghz, 14).unwrap();
        assert!(!japan_channel_14.wifi6e_available && !japan_channel_14.wifi7_available);
        assert_eq!(japan_channel_14.note_code, 5);
        assert!(channel_metadata(RegulatoryDomain::Eu, RegulatoryBand::Band5Ghz, 144).is_none());
    }

    #[test]
    fn filtering_preserves_rule_reasons_device_override_order_and_sorting() {
        let candidates = [
            RegulatoryFilterCandidate {
                band: "5",
                channel: 36,
                rf_score: 80,
                score_selected: false,
                recommendation_score: 50,
                is_current_channel: false,
                show_in_simple_view: true,
                user_classification_override: None,
            },
            RegulatoryFilterCandidate {
                band: "5",
                channel: 52,
                rf_score: 100,
                score_selected: true,
                recommendation_score: 100,
                is_current_channel: false,
                show_in_simple_view: true,
                user_classification_override: None,
            },
            RegulatoryFilterCandidate {
                band: "24",
                channel: 14,
                rf_score: 95,
                score_selected: true,
                recommendation_score: 95,
                is_current_channel: true,
                show_in_simple_view: true,
                user_classification_override: Some(ChannelClassification::Recommended),
            },
        ];
        let supported_channels = supported(&[(2, 36), (2, 52), (1, 14)]);
        let result = apply_regulatory_filter(RegulatoryFilterInput {
            domain: RegulatoryDomain::Us,
            confidence: InferenceConfidence::Low,
            candidates: &candidates,
            has_supported_channels: true,
            supported_channels: &supported_channels,
            device_capabilities: DeviceCapabilities {
                supports_dfs: true,
                ..DeviceCapabilities::default()
            },
        });
        assert_eq!(
            result
                .iter()
                .map(|result| result.original_index)
                .collect::<Vec<_>>(),
            [2, 1, 0]
        );
        assert_eq!(result[0].classification, ChannelClassification::Recommended);
        assert_eq!(
            result[0].restriction_reason_codes,
            [REASON_REGION_BLOCKED, REASON_USER_OVERRIDE]
        );
        assert_eq!(result[1].classification, ChannelClassification::Advanced);
        assert_eq!(
            result[1].restriction_reason_codes,
            [
                REASON_DFS,
                REASON_RADAR_SENSITIVE,
                REASON_CAC_REQUIRED,
                REASON_REGION_LOW_CONFIDENCE,
            ]
        );
        assert_eq!(result[2].classification, ChannelClassification::Advanced);
        assert!(result[2].show_in_simple_view);

        let unknown = apply_regulatory_filter(RegulatoryFilterInput {
            domain: RegulatoryDomain::Unknown,
            confidence: InferenceConfidence::Low,
            candidates: &candidates[..1],
            has_supported_channels: true,
            supported_channels: &[],
            device_capabilities: DeviceCapabilities::default(),
        });
        assert_eq!(unknown[0].classification, ChannelClassification::Restricted);
        assert_eq!(
            unknown[0].restriction_reason_codes,
            [REASON_REGION_UNKNOWN, REASON_DEVICE_INCOMPATIBLE]
        );
        assert!(!unknown[0].device_compatible);
        assert!(!unknown[0].show_in_simple_view);
    }

    #[test]
    fn device_compatibility_preserves_unknown_supported_channels_and_phy_rules() {
        let supported_channels = supported(&[(2, 52), (3, 5)]);
        let dfs = check_device_compatibility(DeviceCompatibilityInput {
            channel: 52,
            band: "5",
            capabilities: DeviceCapabilities::default(),
            has_supported_channels: true,
            supported_channels: &supported_channels,
            metadata: channel_metadata(RegulatoryDomain::Us, RegulatoryBand::Band5Ghz, 52),
        });
        assert_eq!(dfs.reason, Some(DeviceCompatibilityReason::DfsUnsupported));

        let six_ghz = check_device_compatibility(DeviceCompatibilityInput {
            channel: 5,
            band: "6",
            capabilities: DeviceCapabilities::default(),
            has_supported_channels: true,
            supported_channels: &supported_channels,
            metadata: None,
        });
        assert_eq!(
            six_ghz.reason,
            Some(DeviceCompatibilityReason::SixGhzUnsupported)
        );

        let no_facts = check_device_compatibility(DeviceCompatibilityInput {
            channel: 36,
            band: "5",
            capabilities: DeviceCapabilities::default(),
            has_supported_channels: false,
            supported_channels: &[],
            metadata: None,
        });
        assert!(no_facts.compatible);
    }

    #[test]
    fn recommendation_reasons_keep_existing_thresholds_and_order() {
        let inputs = [
            RecommendationReasonInput {
                band: "24",
                channel: 6,
                rf_score: 95,
                ap_count: 0,
                is_current_channel: true,
                is_recommended: true,
                adjacent_count: 0,
                interference_score: 10,
                overlap_level: 1,
                restriction_flags: RESTRICTION_HAS_DFS | RESTRICTION_HAS_CAC_REQUIRED,
            },
            RecommendationReasonInput {
                band: "5",
                channel: 36,
                rf_score: 70,
                ap_count: 1,
                is_current_channel: false,
                is_recommended: false,
                adjacent_count: 1,
                interference_score: 15,
                overlap_level: 1,
                restriction_flags: 0,
            },
        ];
        let reasons = recommendation_reasons(&inputs);
        assert_eq!(
            reasons[0],
            [
                RECOMMENDATION_REASON_CURRENT_CHANNEL,
                RECOMMENDATION_REASON_CURRENTLY_OPTIMAL,
                RECOMMENDATION_REASON_CLEAR_SPECTRUM,
                RECOMMENDATION_REASON_LOW_OVERLAP,
                RECOMMENDATION_REASON_LOW_INTERFERENCE,
                RECOMMENDATION_REASON_DFS_REQUIRED,
                RECOMMENDATION_REASON_CAC_REQUIRED,
            ]
        );
        assert_eq!(
            reasons[1],
            [
                RECOMMENDATION_REASON_LOW_CONGESTION,
                RECOMMENDATION_REASON_LOW_OVERLAP,
                RECOMMENDATION_REASON_LOW_INTERFERENCE,
            ]
        );
    }

    #[test]
    fn c_abi_rejects_invalid_codes_without_writing_output() {
        let config = WiFiLensRegulatoryFilterConfig {
            domain: 99,
            confidence: INFERENCE_CONFIDENCE_LOW,
            ..WiFiLensRegulatoryFilterConfig::default()
        };
        let mut output = [WiFiLensRegulatoryFilterResult {
            original_index: 999,
            ..WiFiLensRegulatoryFilterResult::default()
        }];
        let before = output;
        let mut output_count = usize::MAX;
        let status = unsafe {
            wifi_lens_regulatory_filter(
                std::ptr::null(),
                0,
                std::ptr::null(),
                0,
                std::ptr::null(),
                0,
                &config,
                output.as_mut_ptr(),
                output.len(),
                &mut output_count,
            )
        };
        assert_eq!(status, WIFI_LENS_STATUS_INVALID_REGULATORY_INPUT);
        assert_eq!(output, before);
    }

    #[test]
    fn c_abi_outputs_typed_region_and_filter_results() {
        let strings = b"USJP";
        let country_ranges = [WiFiLensRegulatoryStringRange {
            offset: 2,
            length: 2,
        }];
        let supported = [
            WiFiLensRegulatorySupportedChannel {
                band: 1,
                channel: 1,
            },
            WiFiLensRegulatorySupportedChannel {
                band: 1,
                channel: 6,
            },
            WiFiLensRegulatorySupportedChannel {
                band: 1,
                channel: 11,
            },
            WiFiLensRegulatorySupportedChannel {
                band: 2,
                channel: 36,
            },
            WiFiLensRegulatorySupportedChannel {
                band: 2,
                channel: 40,
            },
            WiFiLensRegulatorySupportedChannel {
                band: 2,
                channel: 44,
            },
        ];
        let input = WiFiLensRegulatoryInferenceInput {
            locale_region_offset: 0,
            locale_region_length: 2,
            user_override_domain: REGULATORY_DOMAIN_UNKNOWN,
            ap_country_code_count: country_ranges.len(),
            ap_country_codes: country_ranges.as_ptr(),
            supported_channel_count: supported.len(),
            supported_channels: supported.as_ptr(),
            strings_length: strings.len(),
            strings: strings.as_ptr(),
        };
        let mut inference = WiFiLensRegulatoryInferenceResult::default();
        let status = unsafe { wifi_lens_regulatory_infer(&input, &mut inference) };
        assert_eq!(status, 0);
        assert_eq!(inference.domain, REGULATORY_DOMAIN_US);
        assert_eq!(inference.confidence, INFERENCE_CONFIDENCE_MEDIUM);
        assert_eq!(inference.locale_domain, REGULATORY_DOMAIN_US);
        assert_eq!(inference.ap_domain, REGULATORY_DOMAIN_JP);
        assert_eq!(inference.supported_channels_domain, REGULATORY_DOMAIN_US);
        assert_eq!(
            inference.conflict_resolution,
            CONFLICT_CHANNELS_DISAGREE_WITH_AP
        );

        let band_strings = b"5";
        let candidate = WiFiLensRegulatoryFilterCandidate {
            band_offset: 0,
            band_length: 1,
            channel: 52,
            rf_score: 100,
            score_selected: 1,
            recommendation_score: 100,
            is_current_channel: 0,
            show_in_simple_view: 1,
            user_classification_override: 0,
        };
        let filter_config = WiFiLensRegulatoryFilterConfig {
            domain: REGULATORY_DOMAIN_US,
            confidence: INFERENCE_CONFIDENCE_HIGH,
            capability_flags: CAPABILITY_SUPPORTS_DFS,
            ..WiFiLensRegulatoryFilterConfig::default()
        };
        let mut filter_result = [WiFiLensRegulatoryFilterResult::default()];
        let mut filter_count = 0;
        let status = unsafe {
            wifi_lens_regulatory_filter(
                &candidate,
                1,
                band_strings.as_ptr(),
                band_strings.len(),
                std::ptr::null(),
                0,
                &filter_config,
                filter_result.as_mut_ptr(),
                1,
                &mut filter_count,
            )
        };
        assert_eq!(status, 0);
        assert_eq!(filter_count, 1);
        assert_eq!(filter_result[0].classification, CLASSIFICATION_ADVANCED);
        assert_eq!(
            filter_result[0].restriction_reason_flags,
            (1 << (REASON_DFS - 1))
                | (1 << (REASON_RADAR_SENSITIVE - 1))
                | (1 << (REASON_CAC_REQUIRED - 1))
        );
    }

    #[test]
    fn c_abi_returns_rule_records_and_device_results() {
        let mut records = [WiFiLensRegulatoryChannelRule::default(); 256];
        let mut count = 0;
        let status = unsafe {
            wifi_lens_regulatory_channel_rules(
                REGULATORY_DOMAIN_JP,
                REGULATORY_BAND_24_GHZ,
                records.as_mut_ptr(),
                records.len(),
                &mut count,
            )
        };
        assert_eq!(status, 0);
        assert_eq!(count, 14);
        assert_eq!(records[13].channel, 14);
        assert_ne!(records[13].has_metadata, 0);

        let input = WiFiLensDeviceCompatibilityInput {
            band_code: REGULATORY_BAND_5_GHZ,
            channel: 52,
            has_supported_channels: 1,
            capability_flags: 0,
            has_metadata: 1,
            metadata_flags: META_IS_DFS,
            ..WiFiLensDeviceCompatibilityInput::default()
        };
        let supported = [WiFiLensRegulatorySupportedChannel {
            band: REGULATORY_BAND_5_GHZ,
            channel: 52,
        }];
        let mut output = WiFiLensDeviceCompatibilityResult::default();
        let status = unsafe {
            wifi_lens_regulatory_device_compatibility(
                &input,
                supported.as_ptr(),
                supported.len(),
                &mut output,
            )
        };
        assert_eq!(status, 0);
        assert_eq!(output.is_compatible, 0);
        assert_eq!(output.reason, DEVICE_REASON_DFS_UNSUPPORTED);
    }

    #[test]
    fn c_abi_recommendation_reason_flags_match_the_typed_api() {
        let strings = b"24";
        let input = WiFiLensRecommendationReasonInput {
            band_offset: 0,
            band_length: 2,
            channel: 6,
            rf_score: 95,
            ap_count: 0,
            is_current_channel: 1,
            is_recommended: 1,
            adjacent_count: 0,
            interference_score: 10,
            overlap_level: 1,
            restriction_flags: RESTRICTION_HAS_DFS,
        };
        let mut output = [WiFiLensRecommendationReasonResult::default()];
        let mut count = 0;
        let status = unsafe {
            wifi_lens_recommendation_reasons(
                &input,
                1,
                strings.as_ptr(),
                strings.len(),
                output.as_mut_ptr(),
                output.len(),
                &mut count,
            )
        };
        assert_eq!(status, 0);
        assert_eq!(count, 1);
        assert_eq!(
            output[0].reason_flags,
            (1 << (RECOMMENDATION_REASON_CURRENT_CHANNEL - 1))
                | (1 << (RECOMMENDATION_REASON_CURRENTLY_OPTIMAL - 1))
                | (1 << (RECOMMENDATION_REASON_CLEAR_SPECTRUM - 1))
                | (1 << (RECOMMENDATION_REASON_LOW_OVERLAP - 1))
                | (1 << (RECOMMENDATION_REASON_LOW_INTERFERENCE - 1))
                | (1 << (RECOMMENDATION_REASON_DFS_REQUIRED - 1))
        );
    }
}
