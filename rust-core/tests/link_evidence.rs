use wifi_lens_core::{
    link_evidence::{
        interpret_link_evidence, wifi_lens_interpret_link_evidence, LinkEvidenceAssessment,
        LinkEvidenceInput, LinkEvidenceReason, LinkModeEvidence, LinkRadioEvidence, LinkState,
        WiFiLensLinkEvidenceInput, WiFiLensLinkEvidenceResult, WIFI_LENS_LINK_ACTIVE,
        WIFI_LENS_LINK_ACTIVE_UNAVAILABLE, WIFI_LENS_LINK_CANDIDATE_DISCONNECTED,
        WIFI_LENS_LINK_CAPTURE_WINDOW_VALID, WIFI_LENS_LINK_CYCLE_MATCHES,
        WIFI_LENS_LINK_EXPECTED_TIMESTAMP_MATCHES, WIFI_LENS_LINK_HAS_CORE_WLAN_MODE,
        WIFI_LENS_LINK_HAS_EVIDENCE, WIFI_LENS_LINK_HAS_RADIO_POWER_ON_RAW,
        WIFI_LENS_LINK_INACTIVE, WIFI_LENS_LINK_INTERFACE_NAME_NONEMPTY, WIFI_LENS_LINK_MODE_NONE,
        WIFI_LENS_LINK_MODE_NONE_OR_READ_FAILURE, WIFI_LENS_LINK_MODE_OTHER,
        WIFI_LENS_LINK_MODE_STATION, WIFI_LENS_LINK_MODE_UNAVAILABLE,
        WIFI_LENS_LINK_RADIO_POWER_ON_RAW, WIFI_LENS_LINK_RADIO_REPORTED_OFF,
        WIFI_LENS_LINK_RADIO_REPORTED_OFF_OR_READ_FAILURE, WIFI_LENS_LINK_RADIO_REPORTED_ON,
        WIFI_LENS_LINK_RADIO_UNAVAILABLE,
    },
    WIFI_LENS_STATUS_INVALID_LINK_EVIDENCE, WIFI_LENS_STATUS_INVALID_POINTER, WIFI_LENS_STATUS_OK,
};

fn parse_bool(value: &str) -> bool {
    match value {
        "0" => false,
        "1" => true,
        value => panic!("invalid boolean {value}"),
    }
}

fn parse_input(fields: &[&str]) -> LinkEvidenceInput {
    let mode_raw_value = fields[7].parse::<i64>().unwrap();
    let other_mode_raw_value = fields[8].parse::<i64>().unwrap();
    let mode = match fields[5].parse::<i32>().unwrap() {
        WIFI_LENS_LINK_MODE_UNAVAILABLE => LinkModeEvidence::Unavailable,
        WIFI_LENS_LINK_MODE_STATION => LinkModeEvidence::Station,
        WIFI_LENS_LINK_MODE_NONE => LinkModeEvidence::None,
        WIFI_LENS_LINK_MODE_NONE_OR_READ_FAILURE => LinkModeEvidence::NoneOrReadFailure,
        WIFI_LENS_LINK_MODE_OTHER => LinkModeEvidence::Other {
            raw_value: other_mode_raw_value,
        },
        value => panic!("invalid mode {value}"),
    };
    let radio = match fields[9].parse::<i32>().unwrap() {
        WIFI_LENS_LINK_RADIO_UNAVAILABLE => LinkRadioEvidence::Unavailable,
        WIFI_LENS_LINK_RADIO_REPORTED_ON => LinkRadioEvidence::ReportedOn,
        WIFI_LENS_LINK_RADIO_REPORTED_OFF => LinkRadioEvidence::ReportedOff,
        WIFI_LENS_LINK_RADIO_REPORTED_OFF_OR_READ_FAILURE => {
            LinkRadioEvidence::ReportedOffOrReadFailure
        }
        value => panic!("invalid radio {value}"),
    };
    let link_active = match fields[13].parse::<i32>().unwrap() {
        WIFI_LENS_LINK_ACTIVE_UNAVAILABLE => None,
        WIFI_LENS_LINK_ACTIVE => Some(true),
        WIFI_LENS_LINK_INACTIVE => Some(false),
        value => panic!("invalid link state {value}"),
    };

    LinkEvidenceInput {
        evidence_present: parse_bool(fields[1]),
        cycle_matches: parse_bool(fields[2]),
        expected_timestamp_matches: fields[3] != "0",
        capture_window_valid: parse_bool(fields[4]),
        mode,
        core_wlan_mode_raw_value: parse_bool(fields[6]).then_some(mode_raw_value),
        radio,
        radio_power_on_raw: parse_bool(fields[10]).then(|| parse_bool(fields[11])),
        interface_name_nonempty: parse_bool(fields[12]),
        link_active,
    }
}

fn parse_expected(fields: &[&str]) -> LinkEvidenceAssessment {
    let state = match fields[14].parse::<i32>().unwrap() {
        0 => LinkState::Unknown,
        1 => LinkState::Associated,
        2 => LinkState::Disconnected,
        value => panic!("invalid expected state {value}"),
    };
    let reason = match fields[15].parse::<i32>().unwrap() {
        1 => LinkEvidenceReason::StationMode,
        2 => LinkEvidenceReason::CycleMismatch,
        3 => LinkEvidenceReason::RadioUnavailable,
        4 => LinkEvidenceReason::ModeUnavailable,
        5 => LinkEvidenceReason::UnsupportedMode,
        6 => LinkEvidenceReason::CaptureTimestampMismatch,
        7 => LinkEvidenceReason::LinkStateUnavailable,
        8 => LinkEvidenceReason::ConflictingLinkEvidence,
        9 => LinkEvidenceReason::DisconnectCandidate,
        value => panic!("invalid expected reason {value}"),
    };
    let candidate_state = match fields[16].parse::<i32>().unwrap() {
        0 => None,
        WIFI_LENS_LINK_CANDIDATE_DISCONNECTED => Some(LinkState::Disconnected),
        value => panic!("invalid expected candidate {value}"),
    };
    LinkEvidenceAssessment {
        state,
        reason,
        candidate_state,
    }
}

fn parse_ffi_input(fields: &[&str]) -> WiFiLensLinkEvidenceInput {
    let mut flags = 0;
    for (enabled, flag) in [
        (parse_bool(fields[1]), WIFI_LENS_LINK_HAS_EVIDENCE),
        (parse_bool(fields[2]), WIFI_LENS_LINK_CYCLE_MATCHES),
        (fields[3] != "0", WIFI_LENS_LINK_EXPECTED_TIMESTAMP_MATCHES),
        (parse_bool(fields[4]), WIFI_LENS_LINK_CAPTURE_WINDOW_VALID),
        (parse_bool(fields[6]), WIFI_LENS_LINK_HAS_CORE_WLAN_MODE),
        (
            parse_bool(fields[10]),
            WIFI_LENS_LINK_HAS_RADIO_POWER_ON_RAW,
        ),
        (
            parse_bool(fields[10]) && parse_bool(fields[11]),
            WIFI_LENS_LINK_RADIO_POWER_ON_RAW,
        ),
        (
            parse_bool(fields[12]),
            WIFI_LENS_LINK_INTERFACE_NAME_NONEMPTY,
        ),
    ] {
        if enabled {
            flags |= flag;
        }
    }
    WiFiLensLinkEvidenceInput {
        flags,
        mode: fields[5].parse::<i32>().unwrap(),
        core_wlan_mode_raw_value: fields[7].parse::<i64>().unwrap(),
        other_mode_raw_value: fields[8].parse::<i64>().unwrap(),
        radio: fields[9].parse::<i32>().unwrap(),
        link_active: fields[13].parse::<i32>().unwrap(),
    }
}

#[test]
fn link_evidence_matches_shared_swift_fixtures_through_typed_and_c_apis() {
    let mut case_count = 0;
    for (line_index, line) in include_str!("fixtures/link-evidence-cases.tsv")
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
            17,
            "invalid fixture on line {}",
            line_index + 1
        );
        let input = parse_input(&fields);
        let expected = parse_expected(&fields);
        assert_eq!(
            interpret_link_evidence(input),
            expected,
            "fixture {}",
            fields[0]
        );

        let ffi_input = parse_ffi_input(&fields);
        let mut ffi_result = WiFiLensLinkEvidenceResult::default();
        let status = unsafe {
            wifi_lens_interpret_link_evidence(
                std::ptr::from_ref(&ffi_input),
                std::ptr::from_mut(&mut ffi_result),
            )
        };
        assert_eq!(status, WIFI_LENS_STATUS_OK, "fixture {}", fields[0]);
        assert_eq!(ffi_result, expected.into(), "C ABI fixture {}", fields[0]);
        case_count += 1;
    }
    assert_eq!(case_count, 23);
}

#[test]
fn c_abi_rejects_invalid_codes_and_flags_without_partial_output() {
    let mut input = WiFiLensLinkEvidenceInput {
        flags: WIFI_LENS_LINK_HAS_EVIDENCE
            | WIFI_LENS_LINK_CYCLE_MATCHES
            | WIFI_LENS_LINK_EXPECTED_TIMESTAMP_MATCHES
            | WIFI_LENS_LINK_CAPTURE_WINDOW_VALID,
        mode: WIFI_LENS_LINK_MODE_STATION,
        core_wlan_mode_raw_value: 1,
        other_mode_raw_value: 0,
        radio: WIFI_LENS_LINK_RADIO_REPORTED_ON,
        link_active: WIFI_LENS_LINK_ACTIVE,
    };
    let sentinel = WiFiLensLinkEvidenceResult {
        state: -1,
        reason: -2,
        candidate_state: -3,
    };
    let mut output = sentinel;

    for invalid_input in [
        WiFiLensLinkEvidenceInput {
            mode: i32::MAX,
            ..input
        },
        WiFiLensLinkEvidenceInput {
            radio: i32::MAX,
            ..input
        },
        WiFiLensLinkEvidenceInput {
            link_active: i32::MAX,
            ..input
        },
        WiFiLensLinkEvidenceInput {
            flags: input.flags | (1 << 31),
            ..input
        },
        WiFiLensLinkEvidenceInput {
            flags: input.flags | WIFI_LENS_LINK_RADIO_POWER_ON_RAW,
            ..input
        },
    ] {
        input = invalid_input;
        assert_eq!(
            unsafe {
                wifi_lens_interpret_link_evidence(
                    std::ptr::from_ref(&input),
                    std::ptr::from_mut(&mut output),
                )
            },
            WIFI_LENS_STATUS_INVALID_LINK_EVIDENCE
        );
        assert_eq!(output, sentinel);
    }
}

#[test]
fn c_abi_rejects_null_pointers() {
    let input = WiFiLensLinkEvidenceInput::default();
    let mut output = WiFiLensLinkEvidenceResult::default();
    assert_eq!(
        unsafe {
            wifi_lens_interpret_link_evidence(std::ptr::null(), std::ptr::from_mut(&mut output))
        },
        WIFI_LENS_STATUS_INVALID_POINTER
    );
    assert_eq!(
        unsafe {
            wifi_lens_interpret_link_evidence(std::ptr::from_ref(&input), std::ptr::null_mut())
        },
        WIFI_LENS_STATUS_INVALID_POINTER
    );
}
