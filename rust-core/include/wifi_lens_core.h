#ifndef WIFI_LENS_CORE_H
#define WIFI_LENS_CORE_H

#include <stdint.h>
#include <stddef.h>

#define WIFI_LENS_STATUS_OK 0
#define WIFI_LENS_STATUS_INVALID_BAND 1
#define WIFI_LENS_STATUS_INVALID_DIRECTION 2
#define WIFI_LENS_STATUS_WIDTH_BELOW_20_MHZ 3
#define WIFI_LENS_STATUS_PANIC 4
#define WIFI_LENS_STATUS_INVALID_POINTER 5
#define WIFI_LENS_STATUS_INVALID_INPUT_SLICE 6
#define WIFI_LENS_STATUS_OUTPUT_TOO_SMALL 7
#define WIFI_LENS_STATUS_INVALID_UTF8 8
#define WIFI_LENS_STATUS_INVALID_WIDTH 9
#define WIFI_LENS_STATUS_INVALID_LINK_EVIDENCE 10
#define WIFI_LENS_STATUS_INVALID_REGULATORY_INPUT 11

typedef struct {
    int32_t status;
    int64_t left;
    int64_t right;
} WiFiLensChannelBlockResult;

#define WIFI_LENS_LINK_HAS_EVIDENCE (1u << 0)
#define WIFI_LENS_LINK_CYCLE_MATCHES (1u << 1)
#define WIFI_LENS_LINK_EXPECTED_TIMESTAMP_MATCHES (1u << 2)
#define WIFI_LENS_LINK_CAPTURE_WINDOW_VALID (1u << 3)
#define WIFI_LENS_LINK_HAS_CORE_WLAN_MODE (1u << 4)
#define WIFI_LENS_LINK_HAS_RADIO_POWER_ON_RAW (1u << 5)
#define WIFI_LENS_LINK_RADIO_POWER_ON_RAW (1u << 6)
#define WIFI_LENS_LINK_INTERFACE_NAME_NONEMPTY (1u << 7)

#define WIFI_LENS_LINK_MODE_UNAVAILABLE 0
#define WIFI_LENS_LINK_MODE_STATION 1
#define WIFI_LENS_LINK_MODE_NONE 2
#define WIFI_LENS_LINK_MODE_NONE_OR_READ_FAILURE 3
#define WIFI_LENS_LINK_MODE_OTHER 4

#define WIFI_LENS_LINK_RADIO_UNAVAILABLE 0
#define WIFI_LENS_LINK_RADIO_REPORTED_ON 1
#define WIFI_LENS_LINK_RADIO_REPORTED_OFF 2
#define WIFI_LENS_LINK_RADIO_REPORTED_OFF_OR_READ_FAILURE 3

#define WIFI_LENS_LINK_ACTIVE_UNAVAILABLE 0
#define WIFI_LENS_LINK_ACTIVE 1
#define WIFI_LENS_LINK_INACTIVE 2

#define WIFI_LENS_LINK_STATE_UNKNOWN 0
#define WIFI_LENS_LINK_STATE_ASSOCIATED 1
#define WIFI_LENS_LINK_STATE_DISCONNECTED 2

#define WIFI_LENS_LINK_REASON_STATION_MODE 1
#define WIFI_LENS_LINK_REASON_CYCLE_MISMATCH 2
#define WIFI_LENS_LINK_REASON_RADIO_UNAVAILABLE 3
#define WIFI_LENS_LINK_REASON_MODE_UNAVAILABLE 4
#define WIFI_LENS_LINK_REASON_UNSUPPORTED_MODE 5
#define WIFI_LENS_LINK_REASON_CAPTURE_TIMESTAMP_MISMATCH 6
#define WIFI_LENS_LINK_REASON_LINK_STATE_UNAVAILABLE 7
#define WIFI_LENS_LINK_REASON_CONFLICTING_LINK_EVIDENCE 8
#define WIFI_LENS_LINK_REASON_DISCONNECT_CANDIDATE 9

#define WIFI_LENS_LINK_CANDIDATE_NONE 0
#define WIFI_LENS_LINK_CANDIDATE_DISCONNECTED WIFI_LENS_LINK_STATE_DISCONNECTED

/*
 * Link facts use fixed integer codes above. Flags encode optional presence and
 * native-snapshot consistency facts. RADIO_POWER_ON_RAW means true when
 * HAS_RADIO_POWER_ON_RAW is also set; link_active uses its tri-state code.
 * Status 10 rejects unknown flags or enum codes.
 */
typedef struct {
    uint32_t flags;
    int32_t mode;
    int64_t core_wlan_mode_raw_value;
    int64_t other_mode_raw_value;
    int32_t radio;
    int32_t link_active;
} WiFiLensLinkEvidenceInput;

typedef struct {
    int32_t state;
    int32_t reason;
    int32_t candidate_state;
} WiFiLensLinkEvidenceResult;

typedef struct {
    uint32_t flags;
    uint32_t country_code;
    int32_t ht_channel_operation;
    int32_t vht_channel_operation;
    int32_t max_mcs_index;
    int32_t spatial_streams;
    size_t group_cipher_offset;
    size_t group_cipher_length;
} WiFiLensIEParseResult;

typedef struct {
    size_t offset;
    size_t length;
} WiFiLensIEStringRange;

/* IE operation values: -1 = absent/unknown; HT: 0 = 20 MHz, 1 = 40 MHz
 * above, 2 = 40 MHz below; VHT: 0 = use HT, 1 = 80 MHz, 2 = 160 MHz,
 * 3 = 80+80 MHz. Missing MCS/NSS values are -1. Country is packed in ASCII
 * byte order from most to least significant byte. */

/*
 * Access-point band codes are 1 = 2.4 GHz, 2 = 5 GHz, 3 = 6 GHz.
 * Width values are 20, 40, 80, 160, or 8080 for 80+80 MHz.
 * BSSID/SSID values are UTF-8 slices in the shared input byte buffer.
 * BSSID matching is ASCII case-insensitive; SSID matching is byte-exact.
 */
typedef struct {
    int64_t channel;
    int64_t rssi;
    int32_t band;
    int32_t channel_width_mhz;
    size_t bssid_offset;
    size_t bssid_length;
    size_t ssid_offset;
    size_t ssid_length;
} WiFiLensAccessPointInput;

/*
 * current_band: 0 means apply current_channel in every supported band;
 * otherwise use band codes 1, 2, or 3. supported_band_mask uses the
 * WIFI_LENS_BAND_* bits. Optional values are enabled by WIFI_LENS_QUALITY_*.
 */
typedef struct {
    uint32_t flags;
    int64_t current_channel;
    int64_t target_channel;
    int32_t current_band;
    uint32_t supported_band_mask;
    size_t target_bssid_offset;
    size_t target_bssid_length;
    size_t target_ssid_offset;
    size_t target_ssid_length;
} WiFiLensChannelQualityConfig;

/*
 * recommendation_confidence: 0 unknown, 1 exact BSSID, 2 unique SSID fallback.
 * recommendation_state: 0 recommended, 1 current channel good enough,
 * 2 insufficient improvement, 3 not a candidate, 4 target identity unknown.
 */
typedef struct {
    int64_t channel;
    int32_t band;
    int32_t quality_score;
    int32_t ap_count;
    int32_t co_channel_count;
    int32_t adjacent_count;
    int32_t interference_score;
    int32_t strongest_neighbor_rssi;
    int32_t recommendation_score;
    int32_t recommendation_confidence;
    int32_t recommendation_state;
    uint8_t is_recommended;
    uint8_t is_current_channel;
    uint8_t show_in_simple_view;
} WiFiLensChannelQualityResult;

#define WIFI_LENS_IE_MAX_SUITES 256
#define WIFI_LENS_IE_MAX_SUITE_LABEL_BYTES 32
#define WIFI_LENS_IE_MAX_TEXT_BYTES 16416
#define WIFI_LENS_MAX_CHANNEL_QUALITIES 105

#define WIFI_LENS_REGULATORY_DOMAIN_UNKNOWN 0
#define WIFI_LENS_REGULATORY_DOMAIN_US 1
#define WIFI_LENS_REGULATORY_DOMAIN_JP 2
#define WIFI_LENS_REGULATORY_DOMAIN_CN 3
#define WIFI_LENS_REGULATORY_DOMAIN_EU 4

#define WIFI_LENS_REGULATORY_BAND_24_GHZ 1
#define WIFI_LENS_REGULATORY_BAND_5_GHZ 2
#define WIFI_LENS_REGULATORY_BAND_6_GHZ 3

#define WIFI_LENS_REGULATORY_CONFIDENCE_LOW 0
#define WIFI_LENS_REGULATORY_CONFIDENCE_MEDIUM 1
#define WIFI_LENS_REGULATORY_CONFIDENCE_HIGH 2

#define WIFI_LENS_REGULATORY_CONFLICT_CHANNELS_DISAGREE_WITH_AP 1

#define WIFI_LENS_REGULATORY_CLASSIFICATION_RECOMMENDED 1
#define WIFI_LENS_REGULATORY_CLASSIFICATION_ADVANCED 2
#define WIFI_LENS_REGULATORY_CLASSIFICATION_RESTRICTED 3

#define WIFI_LENS_REGULATORY_FILTER_HAS_SUPPORTED_CHANNELS (1u << 0)
#define WIFI_LENS_DEVICE_SUPPORTS_N (1u << 0)
#define WIFI_LENS_DEVICE_SUPPORTS_AC (1u << 1)
#define WIFI_LENS_DEVICE_SUPPORTS_AX (1u << 2)
#define WIFI_LENS_DEVICE_SUPPORTS_BE (1u << 3)
#define WIFI_LENS_DEVICE_SUPPORTS_6_GHZ (1u << 4)
#define WIFI_LENS_DEVICE_SUPPORTS_DFS (1u << 5)
#define WIFI_LENS_DEVICE_SUPPORTS_160_MHZ (1u << 6)

#define WIFI_LENS_REGULATORY_META_IS_DFS (1u << 0)
#define WIFI_LENS_REGULATORY_META_IS_RADAR_SENSITIVE (1u << 1)
#define WIFI_LENS_REGULATORY_META_REQUIRES_CAC (1u << 2)
#define WIFI_LENS_REGULATORY_META_FORCED_SWITCH_RISK (1u << 3)
#define WIFI_LENS_REGULATORY_META_IS_INDOOR_ONLY (1u << 4)
#define WIFI_LENS_REGULATORY_META_REQUIRES_AFC (1u << 5)
#define WIFI_LENS_REGULATORY_META_WIFI_6E_AVAILABLE (1u << 6)
#define WIFI_LENS_REGULATORY_META_WIFI_7_AVAILABLE (1u << 7)

#define WIFI_LENS_REGULATORY_REASON_REGION_UNKNOWN 1
#define WIFI_LENS_REGULATORY_REASON_REGION_BLOCKED 2
#define WIFI_LENS_REGULATORY_REASON_DFS 3
#define WIFI_LENS_REGULATORY_REASON_RADAR_SENSITIVE 4
#define WIFI_LENS_REGULATORY_REASON_CAC_REQUIRED 5
#define WIFI_LENS_REGULATORY_REASON_INDOOR_ONLY 6
#define WIFI_LENS_REGULATORY_REASON_AFC_REQUIRED 7
#define WIFI_LENS_REGULATORY_REASON_REGION_LOW_CONFIDENCE 8
#define WIFI_LENS_REGULATORY_REASON_DEVICE_INCOMPATIBLE 9
#define WIFI_LENS_REGULATORY_REASON_USER_OVERRIDE 10
#define WIFI_LENS_REGULATORY_MAX_FILTER_REASONS 10

#define WIFI_LENS_DEVICE_REASON_NONE 0
#define WIFI_LENS_DEVICE_REASON_CHANNEL_UNSUPPORTED 1
#define WIFI_LENS_DEVICE_REASON_6_GHZ_UNSUPPORTED 2
#define WIFI_LENS_DEVICE_REASON_AFC_UNSUPPORTED 3
#define WIFI_LENS_DEVICE_REASON_DFS_UNSUPPORTED 4

#define WIFI_LENS_RECOMMENDATION_REASON_CURRENT_CHANNEL 1
#define WIFI_LENS_RECOMMENDATION_REASON_CURRENTLY_OPTIMAL 2
#define WIFI_LENS_RECOMMENDATION_REASON_CLEAR_SPECTRUM 3
#define WIFI_LENS_RECOMMENDATION_REASON_LOW_CONGESTION 4
#define WIFI_LENS_RECOMMENDATION_REASON_CONGESTED 5
#define WIFI_LENS_RECOMMENDATION_REASON_LOW_OVERLAP 6
#define WIFI_LENS_RECOMMENDATION_REASON_HIGH_OVERLAP 7
#define WIFI_LENS_RECOMMENDATION_REASON_LOW_INTERFERENCE 8
#define WIFI_LENS_RECOMMENDATION_REASON_HIGH_INTERFERENCE 9
#define WIFI_LENS_RECOMMENDATION_REASON_LESS_CROWDED_BAND 10
#define WIFI_LENS_RECOMMENDATION_REASON_DFS_REQUIRED 11
#define WIFI_LENS_RECOMMENDATION_REASON_INDOOR_ONLY 12
#define WIFI_LENS_RECOMMENDATION_REASON_CAC_REQUIRED 13
#define WIFI_LENS_RECOMMENDATION_REASON_RADAR_SENSITIVE 14
#define WIFI_LENS_RECOMMENDATION_REASON_MAX 14

#define WIFI_LENS_RESTRICTION_HAS_DFS (1u << 0)
#define WIFI_LENS_RESTRICTION_HAS_INDOOR_ONLY (1u << 1)
#define WIFI_LENS_RESTRICTION_HAS_CAC_REQUIRED (1u << 2)
#define WIFI_LENS_RESTRICTION_HAS_RADAR_SENSITIVE (1u << 3)

typedef struct {
    size_t offset;
    size_t length;
} WiFiLensRegulatoryStringRange;

typedef struct {
    int32_t band;
    int32_t channel;
} WiFiLensRegulatorySupportedChannel;

typedef struct {
    size_t locale_region_offset;
    size_t locale_region_length;
    int32_t user_override_domain;
    size_t ap_country_code_count;
    const WiFiLensRegulatoryStringRange *ap_country_codes;
    size_t supported_channel_count;
    const WiFiLensRegulatorySupportedChannel *supported_channels;
    size_t strings_length;
    const uint8_t *strings;
} WiFiLensRegulatoryInferenceInput;

typedef struct {
    int32_t domain;
    int32_t confidence;
    int32_t locale_domain;
    int32_t ap_domain;
    int32_t supported_channels_domain;
    int32_t conflict_resolution;
} WiFiLensRegulatoryInferenceResult;

typedef struct {
    int32_t channel;
    uint8_t has_metadata;
    uint32_t metadata_flags;
    int32_t max_eirp_dbm;
    uint8_t has_max_eirp;
    int32_t note_code;
} WiFiLensRegulatoryChannelRule;

typedef struct {
    size_t band_offset;
    size_t band_length;
    int32_t channel;
    int32_t rf_score;
    uint8_t score_selected;
    int32_t recommendation_score;
    uint8_t is_current_channel;
    uint8_t show_in_simple_view;
    int32_t user_classification_override;
} WiFiLensRegulatoryFilterCandidate;

typedef struct {
    int32_t domain;
    int32_t confidence;
    uint32_t flags;
    uint32_t capability_flags;
} WiFiLensRegulatoryFilterConfig;

typedef struct {
    size_t original_index;
    int32_t classification;
    uint32_t restriction_reason_flags;
    uint8_t device_compatible;
    int32_t device_reason;
    uint8_t show_in_simple_view;
} WiFiLensRegulatoryFilterResult;

typedef struct {
    int32_t band_code;
    int32_t channel;
    uint8_t has_supported_channels;
    uint32_t capability_flags;
    uint8_t has_metadata;
    uint32_t metadata_flags;
    int32_t max_eirp_dbm;
    uint8_t has_max_eirp;
    int32_t note_code;
} WiFiLensDeviceCompatibilityInput;

typedef struct {
    uint8_t is_compatible;
    int32_t reason;
} WiFiLensDeviceCompatibilityResult;

typedef struct {
    size_t band_offset;
    size_t band_length;
    int32_t channel;
    int32_t rf_score;
    int32_t ap_count;
    uint8_t is_current_channel;
    uint8_t is_recommended;
    int32_t adjacent_count;
    int32_t interference_score;
    int32_t overlap_level;
    uint32_t restriction_flags;
} WiFiLensRecommendationReasonInput;

typedef struct {
    uint32_t reason_flags;
} WiFiLensRecommendationReasonResult;

#define WIFI_LENS_IE_SUPPORTS_80211K (1u << 0)
#define WIFI_LENS_IE_SUPPORTS_80211R (1u << 1)
#define WIFI_LENS_IE_SUPPORTS_80211V (1u << 2)
#define WIFI_LENS_IE_SUPPORTS_80211W (1u << 3)
#define WIFI_LENS_IE_SUPPORTS_WPA3 (1u << 4)
#define WIFI_LENS_IE_HT_SUPPORTED (1u << 5)
#define WIFI_LENS_IE_VHT_SUPPORTED (1u << 6)
#define WIFI_LENS_IE_HE_SUPPORTED (1u << 7)
#define WIFI_LENS_IE_EHT_SUPPORTED (1u << 8)
#define WIFI_LENS_IE_SUPPORTS_40_MHZ (1u << 9)
#define WIFI_LENS_IE_HIDDEN_SSID (1u << 10)
#define WIFI_LENS_IE_HAS_COUNTRY_CODE (1u << 11)
#define WIFI_LENS_IE_HAS_GROUP_CIPHER (1u << 12)

#define WIFI_LENS_QUALITY_HAS_CURRENT_CHANNEL (1u << 0)
#define WIFI_LENS_QUALITY_HAS_TARGET_BSSID (1u << 1)
#define WIFI_LENS_QUALITY_HAS_TARGET_SSID (1u << 2)
#define WIFI_LENS_QUALITY_HAS_TARGET_CHANNEL (1u << 3)

#define WIFI_LENS_BAND_24_GHZ (1u << 0)
#define WIFI_LENS_BAND_5_GHZ (1u << 1)
#define WIFI_LENS_BAND_6_GHZ (1u << 2)

/* Returns the channel-number half-span for a width in MHz. */
int64_t wifi_lens_channel_half_span(int64_t width_mhz);

/*
 * band: 1 = 2.4 GHz, 2 = 5 GHz, 3 = 6 GHz
 * direction: 0 = unspecified, 1 = upper, 2 = lower
 * status: 0 = success, 1 = invalid band, 2 = invalid direction,
 *         3 = 6 GHz width below 20 MHz, 4 = Rust panic caught at the ABI
 */
WiFiLensChannelBlockResult wifi_lens_channel_block(
    int64_t primary_channel,
    int64_t width_mhz,
    int32_t band,
    int32_t direction
);

/*
 * Interpret one collected Wi-Fi link sample. Input and output records remain
 * caller-owned and must be non-null, correctly aligned, valid, and non-overlapping.
 * Statuses: 0 success, 4 Rust panic caught at the ABI, 5 invalid pointer,
 * 10 invalid flags or enum codes.
 */
int32_t wifi_lens_interpret_link_evidence(
    const WiFiLensLinkEvidenceInput *input,
    WiFiLensLinkEvidenceResult *output
);

/*
 * Parse 802.11 information elements. Input bytes are borrowed for this call.
 * Output records and suite buffers are caller-owned. Every non-null pointer
 * must remain valid and correctly aligned for the call; writable outputs must
 * not overlap inputs or each other. The result, count, and text-length pointers
 * are required; other pointers may be null only when their length/capacity is
 * zero. The parser writes canonical suite-name bytes to the text buffer and
 * returns ranges; the group cipher range is in the result record. A null input
 * is valid only with length zero. Counts and text length report required
 * capacity; status 7 writes no partial result.
 */
int32_t wifi_lens_parse_information_elements(
    const uint8_t *data,
    size_t data_length,
    WiFiLensIEParseResult *result,
    WiFiLensIEStringRange *akm_suites,
    size_t akm_capacity,
    size_t *akm_count,
    WiFiLensIEStringRange *pairwise_ciphers,
    size_t pairwise_capacity,
    size_t *pairwise_count,
    uint8_t *text,
    size_t text_capacity,
    size_t *text_length
);

/*
 * Analyze portable channel quality. AP strings are UTF-8 slices into the
 * supplied string buffer. Empty slices mean absent values. Inputs and output
 * records are caller-owned; Rust does not retain or return allocated pointers.
 * Every non-null pointer must remain valid and correctly aligned for the call.
 * Writable outputs must not overlap inputs or each other. The configuration
 * and result-count pointers are required; other pointers may be null only for
 * zero lengths/capacity. Output count reports required capacity, and status 7
 * writes no partial output.
 *
 * Statuses: 0 success, 1 invalid band, 4 Rust panic caught at the ABI,
 * 5 invalid pointer, 6 invalid input slice, 7 output capacity too small,
 * 8 invalid UTF-8, 9 invalid channel width.
 */
int32_t wifi_lens_channel_quality_analyze(
    const WiFiLensAccessPointInput *access_points,
    size_t access_point_count,
    const uint8_t *strings,
    size_t strings_length,
    const WiFiLensChannelQualityConfig *config,
    WiFiLensChannelQualityResult *results,
    size_t result_capacity,
    size_t *result_count
);

/*
 * Map an ISO 3166-1 alpha-2 country code to a regulatory domain. Unknown or
 * invalid UTF-8 codes return WIFI_LENS_REGULATORY_DOMAIN_UNKNOWN; status 5
 * reports a null pointer paired with a nonzero length.
 */
int32_t wifi_lens_regulatory_domain_from_country_code(
    const uint8_t *country_code,
    size_t country_code_length
);

/*
 * Infer a regulatory domain from locale, AP country codes, supported channels,
 * and an optional user override. All strings are UTF-8 slices in one caller-owned
 * byte buffer. Output is caller-owned; no Rust pointer escapes. The input,
 * output, and every non-empty array must be valid, aligned, and non-overlapping.
 */
int32_t wifi_lens_regulatory_infer(
    const WiFiLensRegulatoryInferenceInput *input,
    WiFiLensRegulatoryInferenceResult *output
);

/*
 * Return every allowed channel and its metadata for one known domain and band.
 * output_count reports the required capacity; status 7 writes no partial output.
 */
int32_t wifi_lens_regulatory_channel_rules(
    int32_t domain_code,
    int32_t band_code,
    WiFiLensRegulatoryChannelRule *output,
    size_t output_capacity,
    size_t *output_count
);

/* Check normalized hardware facts against device PHY and channel metadata. */
int32_t wifi_lens_regulatory_device_compatibility(
    const WiFiLensDeviceCompatibilityInput *input,
    const WiFiLensRegulatorySupportedChannel *supported_channels,
    size_t supported_channel_count,
    WiFiLensDeviceCompatibilityResult *output
);

/*
 * Apply regulatory rules, device compatibility, user classifications, and the
 * established channel sort. Band strings use UTF-8 ranges in strings. Output
 * records are sorted and retain original_index for Swift model mapping. Status 7
 * reports required result capacity and writes no partial output.
 */
int32_t wifi_lens_regulatory_filter(
    const WiFiLensRegulatoryFilterCandidate *candidates,
    size_t candidate_count,
    const uint8_t *strings,
    size_t strings_length,
    const WiFiLensRegulatorySupportedChannel *supported_channels,
    size_t supported_channel_count,
    const WiFiLensRegulatoryFilterConfig *config,
    WiFiLensRegulatoryFilterResult *output,
    size_t output_capacity,
    size_t *output_count
);

/* Compute stable reason identifiers for a sorted recommendation list. */
int32_t wifi_lens_recommendation_reasons(
    const WiFiLensRecommendationReasonInput *inputs,
    size_t input_count,
    const uint8_t *strings,
    size_t strings_length,
    WiFiLensRecommendationReasonResult *outputs,
    size_t output_capacity,
    size_t *output_count
);

#endif
