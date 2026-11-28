use crate::{
    WIFI_LENS_STATUS_INVALID_NETWORK_DIAGNOSTIC_INPUT, WIFI_LENS_STATUS_INVALID_POINTER,
    WIFI_LENS_STATUS_OK, WIFI_LENS_STATUS_PANIC,
};
use std::panic::catch_unwind;

pub const WIFI_LENS_DIAGNOSTIC_STAGE_INTERNET_HTTPS_AVAILABLE: u32 = 1 << 0;
pub const WIFI_LENS_DIAGNOSTIC_STAGE_GATEWAY_NO_RESPONSE: u32 = 1 << 1;
pub const WIFI_LENS_DIAGNOSTIC_STAGE_PROXY_EXPLICIT_DIRECT_ROUTE: u32 = 1 << 2;
pub const WIFI_LENS_DIAGNOSTIC_STAGE_PROXY_RESOLUTION_EVIDENCE: u32 = 1 << 3;

const KNOWN_FLAGS: u32 = WIFI_LENS_DIAGNOSTIC_STAGE_INTERNET_HTTPS_AVAILABLE
    | WIFI_LENS_DIAGNOSTIC_STAGE_GATEWAY_NO_RESPONSE
    | WIFI_LENS_DIAGNOSTIC_STAGE_PROXY_EXPLICIT_DIRECT_ROUTE
    | WIFI_LENS_DIAGNOSTIC_STAGE_PROXY_RESOLUTION_EVIDENCE;

pub const WIFI_LENS_DIAGNOSTIC_STAGE_STATUS_MISSING: i32 = 0;
pub const WIFI_LENS_DIAGNOSTIC_STAGE_STATUS_NORMAL: i32 = 1;
pub const WIFI_LENS_DIAGNOSTIC_STAGE_STATUS_ABNORMAL: i32 = 2;
pub const WIFI_LENS_DIAGNOSTIC_STAGE_STATUS_INDETERMINATE: i32 = 3;
pub const WIFI_LENS_DIAGNOSTIC_STAGE_STATUS_BLOCKED: i32 = 4;
pub const WIFI_LENS_DIAGNOSTIC_STAGE_STATUS_SKIPPED: i32 = 5;

pub const WIFI_LENS_DIAGNOSTIC_STAGE_PROXY_FACTS_MISSING: i32 = 0;
pub const WIFI_LENS_DIAGNOSTIC_STAGE_PROXY_AVAILABLE: i32 = 1;
pub const WIFI_LENS_DIAGNOSTIC_STAGE_PROXY_UNAVAILABLE: i32 = 2;
pub const WIFI_LENS_DIAGNOSTIC_STAGE_PROXY_AUTHENTICATION_REQUIRED: i32 = 3;
pub const WIFI_LENS_DIAGNOSTIC_STAGE_PROXY_UNVERIFIED: i32 = 4;

pub const WIFI_LENS_DIAGNOSTIC_STAGE_QUALIFICATION_NONE: i32 = 0;
pub const WIFI_LENS_DIAGNOSTIC_STAGE_QUALIFICATION_PROXY_DIRECT_UNVERIFIED: i32 = 1;
pub const WIFI_LENS_DIAGNOSTIC_STAGE_QUALIFICATION_GATEWAY_UNVERIFIED: i32 = 2;

/// Result status from one completed diagnostic check. `None` is carried separately
/// so an absent result cannot be confused with an indeterminate result.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum DiagnosticStatus {
    Normal,
    Abnormal,
    Indeterminate,
    Blocked,
    Skipped,
}

/// Normalized HTTP or HTTPS proxy availability supplied by the Swift adapter.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ProxyAvailability {
    Available,
    Unavailable,
    AuthenticationRequired,
    Unverified,
}

/// One stage displayed by the network diagnostic pipeline.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum DiagnosticStage {
    ThisMac,
    Lan,
    Internet,
}

/// A qualification that explains a stage's interpreted state.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum StageQualification {
    ProxyDirectUnverified,
    GatewayUnverified,
}

/// Normalized facts needed to aggregate network diagnostic stages.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct NetworkDiagnosticStageInput {
    pub path: Option<DiagnosticStatus>,
    pub gateway_reachability: Option<DiagnosticStatus>,
    pub gateway_tcp_reachability: Option<DiagnosticStatus>,
    pub dns: Option<DiagnosticStatus>,
    pub internet: Option<DiagnosticStatus>,
    pub proxy: Option<DiagnosticStatus>,
    pub proxy_http: Option<ProxyAvailability>,
    pub proxy_https: Option<ProxyAvailability>,
    pub internet_https_available: bool,
    pub gateway_no_response: bool,
    pub proxy_has_explicit_direct_route: bool,
    pub proxy_has_resolution_evidence: bool,
}

/// Status and optional qualification for one network diagnostic stage.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct DiagnosticStageAssessment {
    pub stage: DiagnosticStage,
    pub status: Option<DiagnosticStatus>,
    pub qualification: Option<StageQualification>,
}

/// Stage results and context facts shared with the overall Swift assessment.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct NetworkDiagnosticStageResolution {
    pub stages: [DiagnosticStageAssessment; 3],
    pub external_success: bool,
    pub neutral_direct_proxy: bool,
    pub neutral_gateway: bool,
}

/// Aggregate completed check results into the established diagnostic stages.
pub fn assess_network_diagnostic_stages(
    input: NetworkDiagnosticStageInput,
) -> NetworkDiagnosticStageResolution {
    let external_success =
        input.internet_https_available || input.proxy_https == Some(ProxyAvailability::Available);
    let neutral_direct_proxy = input.proxy == Some(DiagnosticStatus::Indeterminate)
        && input.internet == Some(DiagnosticStatus::Normal)
        && input.proxy_http == Some(ProxyAvailability::Unverified)
        && input.proxy_https == Some(ProxyAvailability::Unverified)
        && input.proxy_has_explicit_direct_route
        && !input.proxy_has_resolution_evidence;
    let neutral_gateway = external_success
        && input.gateway_reachability == Some(DiagnosticStatus::Indeterminate)
        && input.gateway_no_response;

    let this_mac_qualification = (neutral_direct_proxy
        && input.path == Some(DiagnosticStatus::Normal)
        && input.dns == Some(DiagnosticStatus::Normal))
    .then_some(StageQualification::ProxyDirectUnverified);
    let lan_qualification = neutral_gateway.then_some(StageQualification::GatewayUnverified);
    let stages = [
        aggregate_stage(
            DiagnosticStage::ThisMac,
            &[input.path, input.dns, input.proxy],
            this_mac_qualification,
        ),
        aggregate_stage(
            DiagnosticStage::Lan,
            &[input.gateway_reachability, input.gateway_tcp_reachability],
            lan_qualification,
        ),
        aggregate_stage(DiagnosticStage::Internet, &[input.internet], None),
    ];

    NetworkDiagnosticStageResolution {
        stages,
        external_success,
        neutral_direct_proxy,
        neutral_gateway,
    }
}

fn aggregate_stage(
    stage: DiagnosticStage,
    contributors: &[Option<DiagnosticStatus>],
    indeterminate_qualification: Option<StageQualification>,
) -> DiagnosticStageAssessment {
    let result = |status, qualification| DiagnosticStageAssessment {
        stage,
        status,
        qualification,
    };

    if contributors.iter().any(Option::is_none) {
        return result(None, None);
    }
    if contributors
        .iter()
        .all(|status| *status == Some(DiagnosticStatus::Skipped))
    {
        return result(Some(DiagnosticStatus::Skipped), None);
    }
    if contributors.contains(&Some(DiagnosticStatus::Abnormal)) {
        return result(Some(DiagnosticStatus::Abnormal), None);
    }
    if contributors.contains(&Some(DiagnosticStatus::Blocked)) {
        return result(Some(DiagnosticStatus::Blocked), None);
    }
    if stage == DiagnosticStage::Lan && contributors.contains(&Some(DiagnosticStatus::Normal)) {
        return result(Some(DiagnosticStatus::Normal), None);
    }
    if contributors.contains(&Some(DiagnosticStatus::Indeterminate)) {
        return match (stage, indeterminate_qualification) {
            (DiagnosticStage::ThisMac, Some(StageQualification::ProxyDirectUnverified)) => result(
                Some(DiagnosticStatus::Normal),
                Some(StageQualification::ProxyDirectUnverified),
            ),
            (DiagnosticStage::Lan, Some(StageQualification::GatewayUnverified)) => result(
                Some(DiagnosticStatus::Indeterminate),
                Some(StageQualification::GatewayUnverified),
            ),
            _ => result(Some(DiagnosticStatus::Indeterminate), None),
        };
    }
    result(Some(DiagnosticStatus::Normal), None)
}

/// C-compatible normalized input for [`wifi_lens_diagnostic_stage_assess`].
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct WiFiLensDiagnosticStageInput {
    pub path_status: i32,
    pub gateway_reachability_status: i32,
    pub gateway_tcp_reachability_status: i32,
    pub dns_status: i32,
    pub internet_status: i32,
    pub proxy_status: i32,
    pub proxy_http_availability: i32,
    pub proxy_https_availability: i32,
    pub flags: u32,
}

/// C-compatible stage statuses and context facts returned by the Rust adapter.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct WiFiLensDiagnosticStageResult {
    pub this_mac_status: i32,
    pub this_mac_qualification: i32,
    pub lan_status: i32,
    pub lan_qualification: i32,
    pub internet_status: i32,
    pub internet_qualification: i32,
    pub external_success: i32,
    pub neutral_direct_proxy: i32,
    pub neutral_gateway: i32,
}

fn decode_status(value: i32) -> Result<Option<DiagnosticStatus>, i32> {
    match value {
        WIFI_LENS_DIAGNOSTIC_STAGE_STATUS_MISSING => Ok(None),
        WIFI_LENS_DIAGNOSTIC_STAGE_STATUS_NORMAL => Ok(Some(DiagnosticStatus::Normal)),
        WIFI_LENS_DIAGNOSTIC_STAGE_STATUS_ABNORMAL => Ok(Some(DiagnosticStatus::Abnormal)),
        WIFI_LENS_DIAGNOSTIC_STAGE_STATUS_INDETERMINATE => {
            Ok(Some(DiagnosticStatus::Indeterminate))
        }
        WIFI_LENS_DIAGNOSTIC_STAGE_STATUS_BLOCKED => Ok(Some(DiagnosticStatus::Blocked)),
        WIFI_LENS_DIAGNOSTIC_STAGE_STATUS_SKIPPED => Ok(Some(DiagnosticStatus::Skipped)),
        _ => Err(WIFI_LENS_STATUS_INVALID_NETWORK_DIAGNOSTIC_INPUT),
    }
}

fn decode_proxy_availability(value: i32) -> Result<Option<ProxyAvailability>, i32> {
    match value {
        WIFI_LENS_DIAGNOSTIC_STAGE_PROXY_FACTS_MISSING => Ok(None),
        WIFI_LENS_DIAGNOSTIC_STAGE_PROXY_AVAILABLE => Ok(Some(ProxyAvailability::Available)),
        WIFI_LENS_DIAGNOSTIC_STAGE_PROXY_UNAVAILABLE => Ok(Some(ProxyAvailability::Unavailable)),
        WIFI_LENS_DIAGNOSTIC_STAGE_PROXY_AUTHENTICATION_REQUIRED => {
            Ok(Some(ProxyAvailability::AuthenticationRequired))
        }
        WIFI_LENS_DIAGNOSTIC_STAGE_PROXY_UNVERIFIED => Ok(Some(ProxyAvailability::Unverified)),
        _ => Err(WIFI_LENS_STATUS_INVALID_NETWORK_DIAGNOSTIC_INPUT),
    }
}

fn decode_input(input: WiFiLensDiagnosticStageInput) -> Result<NetworkDiagnosticStageInput, i32> {
    if input.flags & !KNOWN_FLAGS != 0 {
        return Err(WIFI_LENS_STATUS_INVALID_NETWORK_DIAGNOSTIC_INPUT);
    }

    Ok(NetworkDiagnosticStageInput {
        path: decode_status(input.path_status)?,
        gateway_reachability: decode_status(input.gateway_reachability_status)?,
        gateway_tcp_reachability: decode_status(input.gateway_tcp_reachability_status)?,
        dns: decode_status(input.dns_status)?,
        internet: decode_status(input.internet_status)?,
        proxy: decode_status(input.proxy_status)?,
        proxy_http: decode_proxy_availability(input.proxy_http_availability)?,
        proxy_https: decode_proxy_availability(input.proxy_https_availability)?,
        internet_https_available: input.flags & WIFI_LENS_DIAGNOSTIC_STAGE_INTERNET_HTTPS_AVAILABLE
            != 0,
        gateway_no_response: input.flags & WIFI_LENS_DIAGNOSTIC_STAGE_GATEWAY_NO_RESPONSE != 0,
        proxy_has_explicit_direct_route: input.flags
            & WIFI_LENS_DIAGNOSTIC_STAGE_PROXY_EXPLICIT_DIRECT_ROUTE
            != 0,
        proxy_has_resolution_evidence: input.flags
            & WIFI_LENS_DIAGNOSTIC_STAGE_PROXY_RESOLUTION_EVIDENCE
            != 0,
    })
}

fn status_code(status: Option<DiagnosticStatus>) -> i32 {
    match status {
        None => WIFI_LENS_DIAGNOSTIC_STAGE_STATUS_MISSING,
        Some(DiagnosticStatus::Normal) => WIFI_LENS_DIAGNOSTIC_STAGE_STATUS_NORMAL,
        Some(DiagnosticStatus::Abnormal) => WIFI_LENS_DIAGNOSTIC_STAGE_STATUS_ABNORMAL,
        Some(DiagnosticStatus::Indeterminate) => WIFI_LENS_DIAGNOSTIC_STAGE_STATUS_INDETERMINATE,
        Some(DiagnosticStatus::Blocked) => WIFI_LENS_DIAGNOSTIC_STAGE_STATUS_BLOCKED,
        Some(DiagnosticStatus::Skipped) => WIFI_LENS_DIAGNOSTIC_STAGE_STATUS_SKIPPED,
    }
}

fn qualification_code(qualification: Option<StageQualification>) -> i32 {
    match qualification {
        None => WIFI_LENS_DIAGNOSTIC_STAGE_QUALIFICATION_NONE,
        Some(StageQualification::ProxyDirectUnverified) => {
            WIFI_LENS_DIAGNOSTIC_STAGE_QUALIFICATION_PROXY_DIRECT_UNVERIFIED
        }
        Some(StageQualification::GatewayUnverified) => {
            WIFI_LENS_DIAGNOSTIC_STAGE_QUALIFICATION_GATEWAY_UNVERIFIED
        }
    }
}

impl From<NetworkDiagnosticStageResolution> for WiFiLensDiagnosticStageResult {
    fn from(resolution: NetworkDiagnosticStageResolution) -> Self {
        let [this_mac, lan, internet] = resolution.stages;
        Self {
            this_mac_status: status_code(this_mac.status),
            this_mac_qualification: qualification_code(this_mac.qualification),
            lan_status: status_code(lan.status),
            lan_qualification: qualification_code(lan.qualification),
            internet_status: status_code(internet.status),
            internet_qualification: qualification_code(internet.qualification),
            external_success: i32::from(resolution.external_success),
            neutral_direct_proxy: i32::from(resolution.neutral_direct_proxy),
            neutral_gateway: i32::from(resolution.neutral_gateway),
        }
    }
}

fn guarded_assessment(
    operation: impl FnOnce() -> Result<WiFiLensDiagnosticStageResult, i32> + std::panic::UnwindSafe,
) -> Result<WiFiLensDiagnosticStageResult, i32> {
    match catch_unwind(operation) {
        Ok(result) => result,
        Err(_) => Err(WIFI_LENS_STATUS_PANIC),
    }
}

/// Assess normalized network diagnostic results through the stable C ABI.
///
/// # Safety
///
/// `input` and `output` must be non-null, correctly aligned, and valid for one
/// read or write respectively. They must not overlap.
#[no_mangle]
pub unsafe extern "C" fn wifi_lens_diagnostic_stage_assess(
    input: *const WiFiLensDiagnosticStageInput,
    output: *mut WiFiLensDiagnosticStageResult,
) -> i32 {
    if input.is_null() || output.is_null() {
        return WIFI_LENS_STATUS_INVALID_POINTER;
    }

    let raw_input = unsafe { *input };
    match guarded_assessment(|| {
        #[cfg(test)]
        if raw_input.flags == u32::MAX {
            panic!("test-only panic path");
        }
        decode_input(raw_input)
            .map(assess_network_diagnostic_stages)
            .map(Into::into)
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

    fn base_input() -> NetworkDiagnosticStageInput {
        NetworkDiagnosticStageInput {
            path: Some(DiagnosticStatus::Normal),
            gateway_reachability: Some(DiagnosticStatus::Normal),
            gateway_tcp_reachability: Some(DiagnosticStatus::Normal),
            dns: Some(DiagnosticStatus::Normal),
            internet: Some(DiagnosticStatus::Normal),
            proxy: Some(DiagnosticStatus::Normal),
            ..NetworkDiagnosticStageInput::default()
        }
    }

    fn stage(
        resolution: NetworkDiagnosticStageResolution,
        stage: DiagnosticStage,
    ) -> DiagnosticStageAssessment {
        resolution
            .stages
            .into_iter()
            .find(|assessment| assessment.stage == stage)
            .unwrap()
    }

    #[test]
    fn missing_and_skipped_results_remain_distinct() {
        let mut input = base_input();
        input.dns = None;
        input.gateway_reachability = Some(DiagnosticStatus::Skipped);
        input.gateway_tcp_reachability = Some(DiagnosticStatus::Skipped);
        input.internet = Some(DiagnosticStatus::Skipped);

        let resolution = assess_network_diagnostic_stages(input);
        assert_eq!(stage(resolution, DiagnosticStage::ThisMac).status, None);
        assert_eq!(
            stage(resolution, DiagnosticStage::ThisMac).qualification,
            None
        );
        assert_eq!(
            stage(resolution, DiagnosticStage::Lan).status,
            Some(DiagnosticStatus::Skipped)
        );
        assert_eq!(
            stage(resolution, DiagnosticStage::Internet).status,
            Some(DiagnosticStatus::Skipped)
        );
    }

    #[test]
    fn stage_status_precedence_matches_the_existing_aggregation() {
        let mut input = base_input();
        input.path = Some(DiagnosticStatus::Abnormal);
        input.dns = Some(DiagnosticStatus::Blocked);
        input.proxy = Some(DiagnosticStatus::Indeterminate);
        input.gateway_reachability = Some(DiagnosticStatus::Blocked);
        input.gateway_tcp_reachability = Some(DiagnosticStatus::Indeterminate);
        input.internet = Some(DiagnosticStatus::Indeterminate);

        let resolution = assess_network_diagnostic_stages(input);
        assert_eq!(
            stage(resolution, DiagnosticStage::ThisMac).status,
            Some(DiagnosticStatus::Abnormal)
        );
        assert_eq!(
            stage(resolution, DiagnosticStage::Lan).status,
            Some(DiagnosticStatus::Blocked)
        );
        assert_eq!(
            stage(resolution, DiagnosticStage::Internet).status,
            Some(DiagnosticStatus::Indeterminate)
        );

        input.path = Some(DiagnosticStatus::Skipped);
        input.dns = Some(DiagnosticStatus::Normal);
        input.proxy = Some(DiagnosticStatus::Skipped);
        let mixed_skip = stage(
            assess_network_diagnostic_stages(input),
            DiagnosticStage::ThisMac,
        );
        assert_eq!(mixed_skip.status, Some(DiagnosticStatus::Normal));
        assert_eq!(mixed_skip.qualification, None);
    }

    #[test]
    fn lan_success_precedes_indeterminate_and_direct_proxy_needs_explicit_facts() {
        let mut input = base_input();
        input.gateway_reachability = Some(DiagnosticStatus::Indeterminate);
        input.gateway_tcp_reachability = Some(DiagnosticStatus::Normal);
        let lan = stage(
            assess_network_diagnostic_stages(input),
            DiagnosticStage::Lan,
        );
        assert_eq!(lan.status, Some(DiagnosticStatus::Normal));
        assert_eq!(lan.qualification, None);

        input.path = Some(DiagnosticStatus::Normal);
        input.dns = Some(DiagnosticStatus::Normal);
        input.internet = Some(DiagnosticStatus::Normal);
        input.proxy = Some(DiagnosticStatus::Indeterminate);
        input.proxy_http = Some(ProxyAvailability::Unverified);
        input.proxy_https = Some(ProxyAvailability::Unverified);
        input.proxy_has_explicit_direct_route = true;
        let direct = assess_network_diagnostic_stages(input);
        assert!(direct.neutral_direct_proxy);
        let this_mac = stage(direct, DiagnosticStage::ThisMac);
        assert_eq!(this_mac.status, Some(DiagnosticStatus::Normal));
        assert_eq!(
            this_mac.qualification,
            Some(StageQualification::ProxyDirectUnverified)
        );

        input.proxy_has_resolution_evidence = true;
        let unresolved = assess_network_diagnostic_stages(input);
        assert!(!unresolved.neutral_direct_proxy);
        assert_eq!(
            stage(unresolved, DiagnosticStage::ThisMac).status,
            Some(DiagnosticStatus::Indeterminate)
        );
        assert_eq!(
            stage(unresolved, DiagnosticStage::ThisMac).qualification,
            None
        );
    }

    #[test]
    fn gateway_unverified_requires_no_response_and_external_success() {
        let mut input = base_input();
        input.gateway_reachability = Some(DiagnosticStatus::Indeterminate);
        input.gateway_tcp_reachability = Some(DiagnosticStatus::Indeterminate);
        input.gateway_no_response = true;
        input.internet_https_available = true;
        let resolution = assess_network_diagnostic_stages(input);
        assert!(resolution.external_success);
        assert!(resolution.neutral_gateway);
        let lan = stage(resolution, DiagnosticStage::Lan);
        assert_eq!(lan.status, Some(DiagnosticStatus::Indeterminate));
        assert_eq!(
            lan.qualification,
            Some(StageQualification::GatewayUnverified)
        );

        input.internet_https_available = false;
        let without_external_success = assess_network_diagnostic_stages(input);
        assert!(!without_external_success.external_success);
        assert!(!without_external_success.neutral_gateway);
        assert_eq!(
            stage(without_external_success, DiagnosticStage::Lan).qualification,
            None
        );

        input.proxy_https = Some(ProxyAvailability::Available);
        let via_proxy = assess_network_diagnostic_stages(input);
        assert!(via_proxy.external_success);
        assert!(via_proxy.neutral_gateway);
    }

    #[test]
    fn c_abi_rejects_unknown_codes_without_partially_writing_output() {
        let input = WiFiLensDiagnosticStageInput {
            path_status: 99,
            ..WiFiLensDiagnosticStageInput::default()
        };
        let mut output = WiFiLensDiagnosticStageResult {
            this_mac_status: 77,
            ..WiFiLensDiagnosticStageResult::default()
        };
        let initial = output;
        assert_eq!(
            unsafe { wifi_lens_diagnostic_stage_assess(&input, &mut output) },
            WIFI_LENS_STATUS_INVALID_NETWORK_DIAGNOSTIC_INPUT
        );
        assert_eq!(output, initial);

        let input = WiFiLensDiagnosticStageInput {
            flags: 1 << 20,
            ..WiFiLensDiagnosticStageInput::default()
        };
        assert_eq!(
            unsafe { wifi_lens_diagnostic_stage_assess(&input, &mut output) },
            WIFI_LENS_STATUS_INVALID_NETWORK_DIAGNOSTIC_INPUT
        );
        assert_eq!(output, initial);
    }

    #[test]
    fn panic_at_the_public_ffi_entry_is_converted_to_a_status() {
        let input = WiFiLensDiagnosticStageInput {
            flags: u32::MAX,
            ..WiFiLensDiagnosticStageInput::default()
        };
        let sentinel = WiFiLensDiagnosticStageResult {
            this_mac_status: -1,
            ..WiFiLensDiagnosticStageResult::default()
        };
        let mut output = sentinel;
        assert_eq!(
            unsafe { wifi_lens_diagnostic_stage_assess(&input, &mut output) },
            WIFI_LENS_STATUS_PANIC
        );
        assert_eq!(output, sentinel);
    }

    #[test]
    fn c_abi_rejects_null_pointers() {
        let mut output = WiFiLensDiagnosticStageResult::default();
        assert_eq!(
            unsafe { wifi_lens_diagnostic_stage_assess(std::ptr::null(), &mut output) },
            WIFI_LENS_STATUS_INVALID_POINTER
        );
        let input = WiFiLensDiagnosticStageInput::default();
        assert_eq!(
            unsafe { wifi_lens_diagnostic_stage_assess(&input, std::ptr::null_mut()) },
            WIFI_LENS_STATUS_INVALID_POINTER
        );
    }

    #[test]
    fn c_abi_maps_normalized_stage_results() {
        let input = WiFiLensDiagnosticStageInput {
            path_status: WIFI_LENS_DIAGNOSTIC_STAGE_STATUS_NORMAL,
            gateway_reachability_status: WIFI_LENS_DIAGNOSTIC_STAGE_STATUS_INDETERMINATE,
            gateway_tcp_reachability_status: WIFI_LENS_DIAGNOSTIC_STAGE_STATUS_INDETERMINATE,
            dns_status: WIFI_LENS_DIAGNOSTIC_STAGE_STATUS_NORMAL,
            internet_status: WIFI_LENS_DIAGNOSTIC_STAGE_STATUS_NORMAL,
            proxy_status: WIFI_LENS_DIAGNOSTIC_STAGE_STATUS_NORMAL,
            flags: WIFI_LENS_DIAGNOSTIC_STAGE_INTERNET_HTTPS_AVAILABLE
                | WIFI_LENS_DIAGNOSTIC_STAGE_GATEWAY_NO_RESPONSE,
            ..WiFiLensDiagnosticStageInput::default()
        };
        let mut output = WiFiLensDiagnosticStageResult::default();
        assert_eq!(
            unsafe { wifi_lens_diagnostic_stage_assess(&input, &mut output) },
            WIFI_LENS_STATUS_OK
        );
        assert_eq!(
            output.this_mac_status,
            WIFI_LENS_DIAGNOSTIC_STAGE_STATUS_NORMAL
        );
        assert_eq!(
            output.lan_status,
            WIFI_LENS_DIAGNOSTIC_STAGE_STATUS_INDETERMINATE
        );
        assert_eq!(
            output.lan_qualification,
            WIFI_LENS_DIAGNOSTIC_STAGE_QUALIFICATION_GATEWAY_UNVERIFIED
        );
        assert_eq!(
            output.internet_status,
            WIFI_LENS_DIAGNOSTIC_STAGE_STATUS_NORMAL
        );
        assert_eq!(output.external_success, 1);
        assert_eq!(output.neutral_gateway, 1);
    }
}
