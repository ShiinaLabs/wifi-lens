use wifi_lens_core::network_diagnostic_stages::{
    assess_network_diagnostic_stages, wifi_lens_diagnostic_stage_assess, DiagnosticStage,
    DiagnosticStageAssessment, DiagnosticStatus, NetworkDiagnosticStageInput, ProxyAvailability,
    StageQualification, WiFiLensDiagnosticStageInput, WiFiLensDiagnosticStageResult,
    WIFI_LENS_DIAGNOSTIC_STAGE_GATEWAY_NO_RESPONSE,
    WIFI_LENS_DIAGNOSTIC_STAGE_INTERNET_HTTPS_AVAILABLE,
    WIFI_LENS_DIAGNOSTIC_STAGE_PROXY_AUTHENTICATION_REQUIRED,
    WIFI_LENS_DIAGNOSTIC_STAGE_PROXY_AVAILABLE,
    WIFI_LENS_DIAGNOSTIC_STAGE_PROXY_EXPLICIT_DIRECT_ROUTE,
    WIFI_LENS_DIAGNOSTIC_STAGE_PROXY_FACTS_MISSING,
    WIFI_LENS_DIAGNOSTIC_STAGE_PROXY_RESOLUTION_EVIDENCE,
    WIFI_LENS_DIAGNOSTIC_STAGE_PROXY_UNAVAILABLE, WIFI_LENS_DIAGNOSTIC_STAGE_PROXY_UNVERIFIED,
    WIFI_LENS_DIAGNOSTIC_STAGE_QUALIFICATION_GATEWAY_UNVERIFIED,
    WIFI_LENS_DIAGNOSTIC_STAGE_QUALIFICATION_NONE,
    WIFI_LENS_DIAGNOSTIC_STAGE_QUALIFICATION_PROXY_DIRECT_UNVERIFIED,
    WIFI_LENS_DIAGNOSTIC_STAGE_STATUS_ABNORMAL, WIFI_LENS_DIAGNOSTIC_STAGE_STATUS_BLOCKED,
    WIFI_LENS_DIAGNOSTIC_STAGE_STATUS_INDETERMINATE, WIFI_LENS_DIAGNOSTIC_STAGE_STATUS_MISSING,
    WIFI_LENS_DIAGNOSTIC_STAGE_STATUS_NORMAL, WIFI_LENS_DIAGNOSTIC_STAGE_STATUS_SKIPPED,
};
use wifi_lens_core::{
    WIFI_LENS_STATUS_INVALID_NETWORK_DIAGNOSTIC_INPUT, WIFI_LENS_STATUS_INVALID_POINTER,
    WIFI_LENS_STATUS_OK,
};

fn parse_status(value: &str) -> Option<DiagnosticStatus> {
    match value {
        "missing" => None,
        "normal" => Some(DiagnosticStatus::Normal),
        "abnormal" => Some(DiagnosticStatus::Abnormal),
        "indeterminate" => Some(DiagnosticStatus::Indeterminate),
        "blocked" => Some(DiagnosticStatus::Blocked),
        "skipped" => Some(DiagnosticStatus::Skipped),
        value => panic!("invalid status {value}"),
    }
}

fn parse_proxy(value: &str) -> Option<ProxyAvailability> {
    match value {
        "missing" => None,
        "available" => Some(ProxyAvailability::Available),
        "unavailable" => Some(ProxyAvailability::Unavailable),
        "auth" => Some(ProxyAvailability::AuthenticationRequired),
        "unverified" => Some(ProxyAvailability::Unverified),
        value => panic!("invalid proxy availability {value}"),
    }
}

fn parse_qualification(value: &str) -> Option<StageQualification> {
    match value {
        "none" => None,
        "proxy-direct-unverified" => Some(StageQualification::ProxyDirectUnverified),
        "gateway-unverified" => Some(StageQualification::GatewayUnverified),
        value => panic!("invalid qualification {value}"),
    }
}

fn parse_bool(value: &str) -> bool {
    match value {
        "0" => false,
        "1" => true,
        value => panic!("invalid boolean {value}"),
    }
}

fn parse_input(fields: &[&str]) -> NetworkDiagnosticStageInput {
    let flags = fields[9].parse::<u32>().unwrap();
    NetworkDiagnosticStageInput {
        path: parse_status(fields[1]),
        gateway_reachability: parse_status(fields[2]),
        gateway_tcp_reachability: parse_status(fields[3]),
        dns: parse_status(fields[4]),
        internet: parse_status(fields[5]),
        proxy: parse_status(fields[6]),
        proxy_http: parse_proxy(fields[7]),
        proxy_https: parse_proxy(fields[8]),
        internet_https_available: flags & WIFI_LENS_DIAGNOSTIC_STAGE_INTERNET_HTTPS_AVAILABLE != 0,
        gateway_no_response: flags & WIFI_LENS_DIAGNOSTIC_STAGE_GATEWAY_NO_RESPONSE != 0,
        proxy_has_explicit_direct_route: flags
            & WIFI_LENS_DIAGNOSTIC_STAGE_PROXY_EXPLICIT_DIRECT_ROUTE
            != 0,
        proxy_has_resolution_evidence: flags & WIFI_LENS_DIAGNOSTIC_STAGE_PROXY_RESOLUTION_EVIDENCE
            != 0,
    }
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

fn proxy_code(availability: Option<ProxyAvailability>) -> i32 {
    match availability {
        None => WIFI_LENS_DIAGNOSTIC_STAGE_PROXY_FACTS_MISSING,
        Some(ProxyAvailability::Available) => WIFI_LENS_DIAGNOSTIC_STAGE_PROXY_AVAILABLE,
        Some(ProxyAvailability::Unavailable) => WIFI_LENS_DIAGNOSTIC_STAGE_PROXY_UNAVAILABLE,
        Some(ProxyAvailability::AuthenticationRequired) => {
            WIFI_LENS_DIAGNOSTIC_STAGE_PROXY_AUTHENTICATION_REQUIRED
        }
        Some(ProxyAvailability::Unverified) => WIFI_LENS_DIAGNOSTIC_STAGE_PROXY_UNVERIFIED,
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

fn ffi_input(fields: &[&str]) -> WiFiLensDiagnosticStageInput {
    let input = parse_input(fields);
    WiFiLensDiagnosticStageInput {
        path_status: status_code(input.path),
        gateway_reachability_status: status_code(input.gateway_reachability),
        gateway_tcp_reachability_status: status_code(input.gateway_tcp_reachability),
        dns_status: status_code(input.dns),
        internet_status: status_code(input.internet),
        proxy_status: status_code(input.proxy),
        proxy_http_availability: proxy_code(input.proxy_http),
        proxy_https_availability: proxy_code(input.proxy_https),
        flags: fields[9].parse::<u32>().unwrap(),
    }
}

fn expected_stage(
    stage: DiagnosticStage,
    status: Option<DiagnosticStatus>,
    qualification: Option<StageQualification>,
) -> DiagnosticStageAssessment {
    DiagnosticStageAssessment {
        stage,
        status,
        qualification,
    }
}

#[test]
fn fixtures_match_typed_and_c_abis() {
    let mut case_count = 0;
    for (line_index, line) in include_str!("fixtures/network-diagnostic-stage-cases.tsv")
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
            18,
            "invalid fixture on line {}",
            line_index + 1
        );

        let expected = [
            expected_stage(
                DiagnosticStage::ThisMac,
                parse_status(fields[10]),
                parse_qualification(fields[13]),
            ),
            expected_stage(
                DiagnosticStage::Lan,
                parse_status(fields[11]),
                parse_qualification(fields[14]),
            ),
            expected_stage(DiagnosticStage::Internet, parse_status(fields[12]), None),
        ];
        let expected_external = parse_bool(fields[15]);
        let expected_neutral_direct = parse_bool(fields[16]);
        let expected_neutral_gateway = parse_bool(fields[17]);

        let resolution = assess_network_diagnostic_stages(parse_input(&fields));
        assert_eq!(resolution.stages, expected, "fixture {}", fields[0]);
        assert_eq!(
            resolution.stages[2].qualification, expected[2].qualification,
            "typed internet qualification fixture {}",
            fields[0]
        );
        assert_eq!(
            resolution.external_success, expected_external,
            "external success fixture {}",
            fields[0]
        );
        assert_eq!(
            resolution.neutral_direct_proxy, expected_neutral_direct,
            "neutral direct proxy fixture {}",
            fields[0]
        );
        assert_eq!(
            resolution.neutral_gateway, expected_neutral_gateway,
            "neutral gateway fixture {}",
            fields[0]
        );

        let input = ffi_input(&fields);
        let mut output = WiFiLensDiagnosticStageResult::default();
        let status = unsafe {
            wifi_lens_diagnostic_stage_assess(
                std::ptr::from_ref(&input),
                std::ptr::from_mut(&mut output),
            )
        };
        assert_eq!(status, WIFI_LENS_STATUS_OK, "fixture {}", fields[0]);
        assert_eq!(
            output.this_mac_status,
            status_code(expected[0].status),
            "C ABI this mac fixture {}",
            fields[0]
        );
        assert_eq!(
            output.this_mac_qualification,
            qualification_code(expected[0].qualification),
            "C ABI this mac qualification fixture {}",
            fields[0]
        );
        assert_eq!(
            output.lan_status,
            status_code(expected[1].status),
            "C ABI lan fixture {}",
            fields[0]
        );
        assert_eq!(
            output.lan_qualification,
            qualification_code(expected[1].qualification),
            "C ABI lan qualification fixture {}",
            fields[0]
        );
        assert_eq!(
            output.internet_status,
            status_code(expected[2].status),
            "C ABI internet fixture {}",
            fields[0]
        );
        assert_eq!(
            output.internet_qualification,
            qualification_code(expected[2].qualification),
            "C ABI internet qualification fixture {}",
            fields[0]
        );
        assert_eq!(
            output.external_success,
            i32::from(expected_external),
            "C ABI external fixture {}",
            fields[0]
        );
        assert_eq!(
            output.neutral_direct_proxy,
            i32::from(expected_neutral_direct),
            "C ABI neutral direct fixture {}",
            fields[0]
        );
        assert_eq!(
            output.neutral_gateway,
            i32::from(expected_neutral_gateway),
            "C ABI neutral gateway fixture {}",
            fields[0]
        );
        case_count += 1;
    }
    assert_eq!(case_count, 31);
}

#[test]
fn c_abi_rejects_every_invalid_status_proxy_and_flag_without_partial_output() {
    let input = WiFiLensDiagnosticStageInput {
        path_status: WIFI_LENS_DIAGNOSTIC_STAGE_STATUS_NORMAL,
        gateway_reachability_status: WIFI_LENS_DIAGNOSTIC_STAGE_STATUS_NORMAL,
        gateway_tcp_reachability_status: WIFI_LENS_DIAGNOSTIC_STAGE_STATUS_NORMAL,
        dns_status: WIFI_LENS_DIAGNOSTIC_STAGE_STATUS_NORMAL,
        internet_status: WIFI_LENS_DIAGNOSTIC_STAGE_STATUS_NORMAL,
        proxy_status: WIFI_LENS_DIAGNOSTIC_STAGE_STATUS_NORMAL,
        ..WiFiLensDiagnosticStageInput::default()
    };
    let sentinel = WiFiLensDiagnosticStageResult {
        this_mac_status: -1,
        lan_status: -2,
        internet_status: -3,
        ..WiFiLensDiagnosticStageResult::default()
    };
    let mut output = sentinel;

    for invalid_input in [
        WiFiLensDiagnosticStageInput {
            path_status: 6,
            ..input
        },
        WiFiLensDiagnosticStageInput {
            gateway_reachability_status: i32::MIN,
            ..input
        },
        WiFiLensDiagnosticStageInput {
            gateway_tcp_reachability_status: i32::MAX,
            ..input
        },
        WiFiLensDiagnosticStageInput {
            dns_status: -1,
            ..input
        },
        WiFiLensDiagnosticStageInput {
            internet_status: 99,
            ..input
        },
        WiFiLensDiagnosticStageInput {
            proxy_status: 6,
            ..input
        },
        WiFiLensDiagnosticStageInput {
            proxy_http_availability: 5,
            ..input
        },
        WiFiLensDiagnosticStageInput {
            proxy_https_availability: -1,
            ..input
        },
        WiFiLensDiagnosticStageInput {
            flags: 1 << 4,
            ..input
        },
    ] {
        assert_eq!(
            unsafe {
                wifi_lens_diagnostic_stage_assess(
                    std::ptr::from_ref(&invalid_input),
                    std::ptr::from_mut(&mut output),
                )
            },
            WIFI_LENS_STATUS_INVALID_NETWORK_DIAGNOSTIC_INPUT
        );
        assert_eq!(output, sentinel);
    }
}

#[test]
fn c_abi_rejects_null_pointers() {
    let input = WiFiLensDiagnosticStageInput::default();
    let mut output = WiFiLensDiagnosticStageResult::default();
    assert_eq!(
        unsafe { wifi_lens_diagnostic_stage_assess(std::ptr::null(), &mut output) },
        WIFI_LENS_STATUS_INVALID_POINTER
    );
    assert_eq!(
        unsafe { wifi_lens_diagnostic_stage_assess(&input, std::ptr::null_mut()) },
        WIFI_LENS_STATUS_INVALID_POINTER
    );
}
