#ifndef WIFI_LENS_CORE_H
#define WIFI_LENS_CORE_H

#include <stdint.h>

typedef struct {
    int32_t status;
    int64_t left;
    int64_t right;
} WiFiLensChannelBlockResult;

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

#endif
