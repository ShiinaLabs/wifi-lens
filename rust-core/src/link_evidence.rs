use crate::{
    WIFI_LENS_STATUS_INVALID_LINK_EVIDENCE, WIFI_LENS_STATUS_INVALID_POINTER, WIFI_LENS_STATUS_OK,
    WIFI_LENS_STATUS_PANIC,
};
use std::panic::catch_unwind;

pub const WIFI_LENS_LINK_HAS_EVIDENCE: u32 = 1 << 0;
pub const WIFI_LENS_LINK_CYCLE_MATCHES: u32 = 1 << 1;
pub const WIFI_LENS_LINK_EXPECTED_TIMESTAMP_MATCHES: u32 = 1 << 2;
pub const WIFI_LENS_LINK_CAPTURE_WINDOW_VALID: u32 = 1 << 3;
pub const WIFI_LENS_LINK_HAS_CORE_WLAN_MODE: u32 = 1 << 4;
pub const WIFI_LENS_LINK_HAS_RADIO_POWER_ON_RAW: u32 = 1 << 5;
pub const WIFI_LENS_LINK_RADIO_POWER_ON_RAW: u32 = 1 << 6;
pub const WIFI_LENS_LINK_INTERFACE_NAME_NONEMPTY: u32 = 1 << 7;

const KNOWN_INPUT_FLAGS: u32 = WIFI_LENS_LINK_HAS_EVIDENCE
    | WIFI_LENS_LINK_CYCLE_MATCHES
    | WIFI_LENS_LINK_EXPECTED_TIMESTAMP_MATCHES
    | WIFI_LENS_LINK_CAPTURE_WINDOW_VALID
    | WIFI_LENS_LINK_HAS_CORE_WLAN_MODE
    | WIFI_LENS_LINK_HAS_RADIO_POWER_ON_RAW
    | WIFI_LENS_LINK_RADIO_POWER_ON_RAW
    | WIFI_LENS_LINK_INTERFACE_NAME_NONEMPTY;

pub const WIFI_LENS_LINK_MODE_UNAVAILABLE: i32 = 0;
pub const WIFI_LENS_LINK_MODE_STATION: i32 = 1;
pub const WIFI_LENS_LINK_MODE_NONE: i32 = 2;
pub const WIFI_LENS_LINK_MODE_NONE_OR_READ_FAILURE: i32 = 3;
pub const WIFI_LENS_LINK_MODE_OTHER: i32 = 4;

pub const WIFI_LENS_LINK_RADIO_UNAVAILABLE: i32 = 0;
pub const WIFI_LENS_LINK_RADIO_REPORTED_ON: i32 = 1;
pub const WIFI_LENS_LINK_RADIO_REPORTED_OFF: i32 = 2;
pub const WIFI_LENS_LINK_RADIO_REPORTED_OFF_OR_READ_FAILURE: i32 = 3;

pub const WIFI_LENS_LINK_ACTIVE_UNAVAILABLE: i32 = 0;
pub const WIFI_LENS_LINK_ACTIVE: i32 = 1;
pub const WIFI_LENS_LINK_INACTIVE: i32 = 2;

pub const WIFI_LENS_LINK_STATE_UNKNOWN: i32 = 0;
pub const WIFI_LENS_LINK_STATE_ASSOCIATED: i32 = 1;
pub const WIFI_LENS_LINK_STATE_DISCONNECTED: i32 = 2;

pub const WIFI_LENS_LINK_REASON_STATION_MODE: i32 = 1;
pub const WIFI_LENS_LINK_REASON_CYCLE_MISMATCH: i32 = 2;
pub const WIFI_LENS_LINK_REASON_RADIO_UNAVAILABLE: i32 = 3;
pub const WIFI_LENS_LINK_REASON_MODE_UNAVAILABLE: i32 = 4;
pub const WIFI_LENS_LINK_REASON_UNSUPPORTED_MODE: i32 = 5;
pub const WIFI_LENS_LINK_REASON_CAPTURE_TIMESTAMP_MISMATCH: i32 = 6;
pub const WIFI_LENS_LINK_REASON_LINK_STATE_UNAVAILABLE: i32 = 7;
pub const WIFI_LENS_LINK_REASON_CONFLICTING_LINK_EVIDENCE: i32 = 8;
pub const WIFI_LENS_LINK_REASON_DISCONNECT_CANDIDATE: i32 = 9;

pub const WIFI_LENS_LINK_CANDIDATE_NONE: i32 = 0;
pub const WIFI_LENS_LINK_CANDIDATE_DISCONNECTED: i32 = WIFI_LENS_LINK_STATE_DISCONNECTED;

/// CoreWLAN mode facts normalized by the native acquisition adapter.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum LinkModeEvidence {
    /// No usable interpretation was available.
    Unavailable,
    /// CoreWLAN identified station mode.
    Station,
    /// CoreWLAN explicitly identified no mode.
    None,
    /// CoreWLAN's no-mode value was ambiguous with an API read failure.
    NoneOrReadFailure,
    /// A mode other than station or none, retaining its interpreted raw value.
    Other { raw_value: i64 },
}

/// Radio facts normalized by the native acquisition adapter.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum LinkRadioEvidence {
    /// No usable radio state was available.
    Unavailable,
    /// The radio was reported on.
    ReportedOn,
    /// The radio was independently confirmed off.
    ReportedOff,
    /// CoreWLAN's off value was ambiguous with an API read failure.
    ReportedOffOrReadFailure,
}

/// Link-active fact from the same interface snapshot, when available.
pub type LinkActiveEvidence = Option<bool>;

/// Portable inputs for interpreting one collected Wi-Fi link sample.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct LinkEvidenceInput {
    /// Whether a raw evidence sample was collected.
    pub evidence_present: bool,
    /// Whether its snapshot cycle matches the expected cycle.
    pub cycle_matches: bool,
    /// Whether its capture timestamp matches an optional expected timestamp.
    pub expected_timestamp_matches: bool,
    /// Whether capture start ≤ captured time ≤ capture end.
    pub capture_window_valid: bool,
    /// Interpreted mode and the raw CoreWLAN mode value, if available.
    pub mode: LinkModeEvidence,
    pub core_wlan_mode_raw_value: Option<i64>,
    /// Radio interpretation and the raw CoreWLAN power result, if available.
    pub radio: LinkRadioEvidence,
    pub radio_power_on_raw: Option<bool>,
    /// Whether the captured interface name was non-empty.
    pub interface_name_nonempty: bool,
    /// Link-active state; `None` preserves an unavailable read as unknown.
    pub link_active: LinkActiveEvidence,
}

/// Interpreted link state, reason, and an optional unconfirmed candidate.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct LinkEvidenceAssessment {
    pub state: LinkState,
    pub reason: LinkEvidenceReason,
    pub candidate_state: Option<LinkState>,
}

/// Verified state derived from one evidence sample.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum LinkState {
    Associated,
    Disconnected,
    Unknown,
}

/// Reason for the interpreted state.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum LinkEvidenceReason {
    StationMode,
    CycleMismatch,
    RadioUnavailable,
    ModeUnavailable,
    UnsupportedMode,
    CaptureTimestampMismatch,
    LinkStateUnavailable,
    ConflictingLinkEvidence,
    DisconnectCandidate,
}

/// Interpret collected link facts without using platform APIs.
pub fn interpret_link_evidence(input: LinkEvidenceInput) -> LinkEvidenceAssessment {
    let unknown = |reason| LinkEvidenceAssessment {
        state: LinkState::Unknown,
        reason,
        candidate_state: None,
    };

    if !input.evidence_present {
        return unknown(LinkEvidenceReason::ModeUnavailable);
    }
    if !input.cycle_matches {
        return unknown(LinkEvidenceReason::CycleMismatch);
    }
    if !input.expected_timestamp_matches || !input.capture_window_valid {
        return unknown(LinkEvidenceReason::CaptureTimestampMismatch);
    }
    if let Some(raw_mode) = input.core_wlan_mode_raw_value {
        let conflicts = match input.mode {
            LinkModeEvidence::Station => raw_mode != 1,
            LinkModeEvidence::None | LinkModeEvidence::NoneOrReadFailure => raw_mode != 0,
            LinkModeEvidence::Other { raw_value } => raw_value != raw_mode,
            LinkModeEvidence::Unavailable => false,
        };
        if conflicts {
            return unknown(LinkEvidenceReason::ConflictingLinkEvidence);
        }
    }
    if input.radio == LinkRadioEvidence::ReportedOn && input.radio_power_on_raw == Some(false) {
        return unknown(LinkEvidenceReason::RadioUnavailable);
    }
    if input.mode != LinkModeEvidence::Station {
        if matches!(input.mode, LinkModeEvidence::Other { .. }) {
            return unknown(LinkEvidenceReason::UnsupportedMode);
        }
        if matches!(
            input.mode,
            LinkModeEvidence::None | LinkModeEvidence::NoneOrReadFailure
        ) && input.radio == LinkRadioEvidence::ReportedOn
            && input.link_active == Some(false)
        {
            return LinkEvidenceAssessment {
                state: LinkState::Unknown,
                reason: LinkEvidenceReason::DisconnectCandidate,
                candidate_state: Some(LinkState::Disconnected),
            };
        }
        return unknown(LinkEvidenceReason::ModeUnavailable);
    }
    if input.radio != LinkRadioEvidence::ReportedOn {
        return unknown(LinkEvidenceReason::RadioUnavailable);
    }
    match input.link_active {
        Some(true) if input.interface_name_nonempty => LinkEvidenceAssessment {
            state: LinkState::Associated,
            reason: LinkEvidenceReason::StationMode,
            candidate_state: None,
        },
        Some(true) => unknown(LinkEvidenceReason::CaptureTimestampMismatch),
        Some(false) => unknown(LinkEvidenceReason::ConflictingLinkEvidence),
        None => unknown(LinkEvidenceReason::LinkStateUnavailable),
    }
}

/// C-compatible input for [`wifi_lens_interpret_link_evidence`].
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct WiFiLensLinkEvidenceInput {
    /// Presence and validity flags documented in `wifi_lens_core.h`.
    pub flags: u32,
    /// One of the `WIFI_LENS_LINK_MODE_*` values.
    pub mode: i32,
    /// Raw CoreWLAN mode value when `WIFI_LENS_LINK_HAS_CORE_WLAN_MODE` is set.
    pub core_wlan_mode_raw_value: i64,
    /// Interpreted raw value used by `WIFI_LENS_LINK_MODE_OTHER`.
    pub other_mode_raw_value: i64,
    /// One of the `WIFI_LENS_LINK_RADIO_*` values.
    pub radio: i32,
    /// One of the `WIFI_LENS_LINK_ACTIVE_*` values.
    pub link_active: i32,
}

/// C-compatible output for [`wifi_lens_interpret_link_evidence`].
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct WiFiLensLinkEvidenceResult {
    /// One of the `WIFI_LENS_LINK_STATE_*` values.
    pub state: i32,
    /// One of the `WIFI_LENS_LINK_REASON_*` values.
    pub reason: i32,
    /// One of the `WIFI_LENS_LINK_CANDIDATE_*` values.
    pub candidate_state: i32,
}

impl From<LinkEvidenceAssessment> for WiFiLensLinkEvidenceResult {
    fn from(assessment: LinkEvidenceAssessment) -> Self {
        let state = match assessment.state {
            LinkState::Unknown => WIFI_LENS_LINK_STATE_UNKNOWN,
            LinkState::Associated => WIFI_LENS_LINK_STATE_ASSOCIATED,
            LinkState::Disconnected => WIFI_LENS_LINK_STATE_DISCONNECTED,
        };
        let reason = match assessment.reason {
            LinkEvidenceReason::StationMode => WIFI_LENS_LINK_REASON_STATION_MODE,
            LinkEvidenceReason::CycleMismatch => WIFI_LENS_LINK_REASON_CYCLE_MISMATCH,
            LinkEvidenceReason::RadioUnavailable => WIFI_LENS_LINK_REASON_RADIO_UNAVAILABLE,
            LinkEvidenceReason::ModeUnavailable => WIFI_LENS_LINK_REASON_MODE_UNAVAILABLE,
            LinkEvidenceReason::UnsupportedMode => WIFI_LENS_LINK_REASON_UNSUPPORTED_MODE,
            LinkEvidenceReason::CaptureTimestampMismatch => {
                WIFI_LENS_LINK_REASON_CAPTURE_TIMESTAMP_MISMATCH
            }
            LinkEvidenceReason::LinkStateUnavailable => {
                WIFI_LENS_LINK_REASON_LINK_STATE_UNAVAILABLE
            }
            LinkEvidenceReason::ConflictingLinkEvidence => {
                WIFI_LENS_LINK_REASON_CONFLICTING_LINK_EVIDENCE
            }
            LinkEvidenceReason::DisconnectCandidate => WIFI_LENS_LINK_REASON_DISCONNECT_CANDIDATE,
        };
        let candidate_state = match assessment.candidate_state {
            None => WIFI_LENS_LINK_CANDIDATE_NONE,
            Some(LinkState::Disconnected) => WIFI_LENS_LINK_CANDIDATE_DISCONNECTED,
            Some(LinkState::Associated | LinkState::Unknown) => WIFI_LENS_LINK_CANDIDATE_NONE,
        };
        Self {
            state,
            reason,
            candidate_state,
        }
    }
}

fn decode_input(input: WiFiLensLinkEvidenceInput) -> Result<LinkEvidenceInput, i32> {
    if input.flags & !KNOWN_INPUT_FLAGS != 0 {
        return Err(WIFI_LENS_STATUS_INVALID_LINK_EVIDENCE);
    }
    let mode = match input.mode {
        WIFI_LENS_LINK_MODE_UNAVAILABLE => LinkModeEvidence::Unavailable,
        WIFI_LENS_LINK_MODE_STATION => LinkModeEvidence::Station,
        WIFI_LENS_LINK_MODE_NONE => LinkModeEvidence::None,
        WIFI_LENS_LINK_MODE_NONE_OR_READ_FAILURE => LinkModeEvidence::NoneOrReadFailure,
        WIFI_LENS_LINK_MODE_OTHER => LinkModeEvidence::Other {
            raw_value: input.other_mode_raw_value,
        },
        _ => return Err(WIFI_LENS_STATUS_INVALID_LINK_EVIDENCE),
    };
    let radio = match input.radio {
        WIFI_LENS_LINK_RADIO_UNAVAILABLE => LinkRadioEvidence::Unavailable,
        WIFI_LENS_LINK_RADIO_REPORTED_ON => LinkRadioEvidence::ReportedOn,
        WIFI_LENS_LINK_RADIO_REPORTED_OFF => LinkRadioEvidence::ReportedOff,
        WIFI_LENS_LINK_RADIO_REPORTED_OFF_OR_READ_FAILURE => {
            LinkRadioEvidence::ReportedOffOrReadFailure
        }
        _ => return Err(WIFI_LENS_STATUS_INVALID_LINK_EVIDENCE),
    };
    let link_active = match input.link_active {
        WIFI_LENS_LINK_ACTIVE_UNAVAILABLE => None,
        WIFI_LENS_LINK_ACTIVE => Some(true),
        WIFI_LENS_LINK_INACTIVE => Some(false),
        _ => return Err(WIFI_LENS_STATUS_INVALID_LINK_EVIDENCE),
    };
    let has_radio_power_on_raw = input.flags & WIFI_LENS_LINK_HAS_RADIO_POWER_ON_RAW != 0;
    let radio_power_on_raw = if has_radio_power_on_raw {
        Some(input.flags & WIFI_LENS_LINK_RADIO_POWER_ON_RAW != 0)
    } else {
        if input.flags & WIFI_LENS_LINK_RADIO_POWER_ON_RAW != 0 {
            return Err(WIFI_LENS_STATUS_INVALID_LINK_EVIDENCE);
        }
        None
    };

    Ok(LinkEvidenceInput {
        evidence_present: input.flags & WIFI_LENS_LINK_HAS_EVIDENCE != 0,
        cycle_matches: input.flags & WIFI_LENS_LINK_CYCLE_MATCHES != 0,
        expected_timestamp_matches: input.flags & WIFI_LENS_LINK_EXPECTED_TIMESTAMP_MATCHES != 0,
        capture_window_valid: input.flags & WIFI_LENS_LINK_CAPTURE_WINDOW_VALID != 0,
        mode,
        core_wlan_mode_raw_value: (input.flags & WIFI_LENS_LINK_HAS_CORE_WLAN_MODE != 0)
            .then_some(input.core_wlan_mode_raw_value),
        radio,
        radio_power_on_raw,
        interface_name_nonempty: input.flags & WIFI_LENS_LINK_INTERFACE_NAME_NONEMPTY != 0,
        link_active,
    })
}

/// Interpret a collected link sample through the stable C ABI.
///
/// # Safety
///
/// `input` and `output` must be non-null, correctly aligned, and valid for one
/// read or write respectively. They must not overlap.
#[no_mangle]
pub unsafe extern "C" fn wifi_lens_interpret_link_evidence(
    input: *const WiFiLensLinkEvidenceInput,
    output: *mut WiFiLensLinkEvidenceResult,
) -> i32 {
    if input.is_null() || output.is_null() {
        return WIFI_LENS_STATUS_INVALID_POINTER;
    }
    let raw_input = unsafe { *input };
    match catch_unwind(|| decode_input(raw_input).map(interpret_link_evidence)) {
        Ok(Ok(assessment)) => {
            unsafe { *output = assessment.into() };
            WIFI_LENS_STATUS_OK
        }
        Ok(Err(status)) => status,
        Err(_) => WIFI_LENS_STATUS_PANIC,
    }
}
