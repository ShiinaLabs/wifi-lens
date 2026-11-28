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

typedef struct {
    int32_t status;
    int64_t left;
    int64_t right;
} WiFiLensChannelBlockResult;

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

#endif
