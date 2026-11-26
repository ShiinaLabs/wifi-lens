# Regulatory Pipeline

Multi-stage pipeline that infers the user's regulatory domain from multiple signals, then filters and classifies channel recommendations based on region rules and device hardware capabilities.

## Architecture

```
WiFiNetwork[] (IE country codes)
System Locale (region identifier)
Hardware Supported Channels (CoreWLAN)  ─┐
                                          ▼
                              RegionInferenceEngine
                                   │
                                   ▼
                           RegionInferenceResult
                     (domain + confidence + contributions)
                                   │
                                   ▼
        RegulatoryFilter — 5-stage pipeline
          1. Wrap ChannelQuality → ChannelRecommendation
          2. Apply region rules (allowed/restricted/DFS/indoor/AFC)
          3. Device compatibility check
          4. User classification overrides
          5. Sort by tier → recommendation score → RF score → band → channel
                                   │
                                   ▼
                        [ChannelRecommendation]
                                   │
                                   ▼
                           OverviewView / ChannelQualityView
```

## Data Flow

`ScannerViewModel` gathers visible APs plus the current connection identity (BSSID/SSID/channel), then passes them to `ChannelQualityCalculator`. The calculator produces both observed RF quality and counterfactual recommendation state by excluding the current target AP from recommendation scoring. These qualities are then passed along with network IEs, device capabilities, and user preferences to `RegulatoryPipeline.computeRecommendations()`. The pipeline returns classified `[ChannelRecommendation]` for display in the channel quality views.

## Key Types

| File | Type | Purpose |
|------|------|---------|
| `ChannelQualityCalculator.swift` | `enum` | Swift-facing adapter for Rust observed RF and counterfactual recommendation scoring |
| `RegulatoryPipeline.swift` | `final class` | `@Observable` orchestrator — collects inputs, calls inference + filter, exposes `inferredRegion` |
| `RegionInferenceEngine.swift` | `enum` | Multi-source region inference with confidence scoring |
| `RegulatoryFilter.swift` | `enum` | 5-stage classification pipeline |
| `RegulatoryDatabase.swift` | `enum` | Static per-region channel rules (US/JP/CN/EU, 2.4/5/6 GHz) |
| `RegulatoryDomain.swift` | `enum` | `US`/`JP`/`CN`/`EU`/`unknown` with locale-based mapping |
| `DeviceCompatibilityFilter.swift` | `enum` | Checks PHY/band/DFS/6 GHz support per device |
| `ChannelRecommendation.swift` | `struct` | Output model: observed RF data + counterfactual score + regulatory classification + restriction reasons |

## Region Inference

`RegionInferenceEngine.infer()` resolves the regulatory domain from up to four sources, in priority order:

| Source | Method | Confidence |
|--------|--------|------------|
| User override | Manual domain selection | `.high` |
| Hardware channels | Jaccard-like fingerprint matching against known region channel sets | `.medium`–`.high` |
| AP beacon country IE | Consensus among visible AP country codes | `.medium`–`.low` |
| System locale | `Locale.region` → `RegulatoryDomain.from(localeRegionCode:)` | `.low` |

### Resolution Logic

1. **User override** — always wins, recorded with `.high` confidence.
2. **Channel fingerprint + AP consensus agree** — `.high` confidence.
3. **Channel fingerprint alone** — `.medium` (hardware/driver is authoritative). If AP disagrees, a conflict is recorded but the hardware wins.
4. **AP consensus alone** — `.medium` (with consensus) / `.low` (without). AP country codes can be wrong (flashed routers, etc.).
5. **Locale alone** — `.low`.
6. **Nothing** — `.unknown` with `.low` confidence.

### Channel Fingerprint

For each known domain (US/JP/CN/EU), builds an expected channel set from `RegulatoryDatabase`, then computes a Jaccard-like score: `|intersection| / |smaller set|`. The domain with the best score wins if > 0.3.

Special signals:
- **JP bonus**: Channel 14 (2.4 GHz) is uniquely Japanese; presence adds +0.15 to JP score.
- **CN negative**: No DFS channels in CN 5 GHz allocation; if no DFS channels are available and the best score is < 0.5, CN is re-evaluated as a candidate.

## Filter Pipeline

`RegulatoryFilter.apply()` runs five stages:

### Stage 1: Wrap
Each `ChannelQuality` is wrapped into a `ChannelRecommendation`, preserving the original RF score/level/AP counts verbatim while also carrying the counterfactual recommendation score and score-selected state.

### Stage 2: Region rules
For each recommendation, looks up `RegulatoryDatabase.rules[region][band]`:
- **Not in database** → `.restricted` (`REGION_UNKNOWN`)
- **Channel not allowed** → `.restricted` (`REGION_BLOCKED`)
- **DFS channel** → `.advanced` (`DFS`)
- **Indoor-only** → `.advanced` or lower (`INDOOR_ONLY`)
- **AFC-required** → `.restricted` (`AFC_REQUIRED`)
- **Low confidence region** → downgrade `.recommended` → `.advanced` (`REGION_LOW_CONFIDENCE`)
- Other metadata flags (`radarSensitive`, `requiresCAC`) are recorded as restriction reasons but do not change classification.

### Stage 3: Device compatibility
`DeviceCompatibilityFilter.check()` verifies:
1. Channel is in hardware's supported set
2. 6 GHz channels require 6 GHz hardware support
3. AFC-required channels not supported
4. DFS channels require DFS hardware support

If incompatible → `.restricted` (`DEVICE_INCOMPATIBLE`).

### Stage 4: User overrides
Manual classification overrides are applied on top.

### Stage 5: Sort
Current channel first, then by classification tier (recommended > advanced > restricted), then score-selected channels, then recommendation score descending, then observed RF score descending, then band/channel.

Restricted channels are hidden by default (`showInSimpleView = false`).

## Regulatory Database

`RegulatoryDatabase` is a static, data-driven lookup table. No business logic — pure channel data sourced from public allocation tables.

| Domain | 2.4 GHz | 5 GHz | 6 GHz |
|--------|---------|-------|-------|
| US (FCC) | 1–11 | 36–165 (DFS on 52–144) | 1–233 LPI (no AFC) |
| JP (MIC) | 1–14 (ch14: 802.11b only) | 36–144 (DFS on W53/W56) | 1–93 LPI |
| CN (SRRC) | 1–13 | 36–48, 149–165 (no DFS) | None |
| EU (ETSI) | 1–13 | 36–144 (DFS on 52–144) | 1–93 LPI |

`RegulatoryChannelMeta` attaches per-channel caveats (DFS, radar sensitivity, CAC, indoor-only, max EIRP, AFC, Wi-Fi 6E/7 availability).

## Counterfactual Channel Scoring

The recommendation algorithm answers a local configuration question: if the current AP moved to a candidate channel, how much external interference would it face? The current AP must not count against itself, so recommendation scoring excludes the current target AP while observed RF scoring still includes every visible AP.

### Model

1. **Observed score** — `qualityScore` is computed from all APs in the current scan snapshot. This is used for charts, current-environment diagnostics, and RF preservation.

2. **Target exclusion** — `recommendationScore` is computed from the same AP set after excluding the current target AP. BSSID matching is exact. SSID fallback is used only when BSSID is unavailable and exactly one AP with that SSID is visible on the current channel; ambiguous SSID fallback is treated as unknown.

3. **Recommendation selection** — The current channel is considered good enough at `recommendationScore >= 80`. Candidate channels must score at least 70, improve by at least 10 points, and are limited to two per band.

### Effect

- The current AP does not make its own current channel look artificially congested.
- External APs still reduce recommendation quality.
- Unknown target identity suppresses recommendation selection while preserving observed RF display.
- The algorithm is deterministic and does not use history, trend forecasting, previous-recommendation pressure, or remote adoption assumptions.

## Key Patterns

- **Decoupled RF + regulatory**: `ChannelQualityCalculator` is never modified by the regulatory pipeline — RF scoring and regulatory filtering are completely independent.
- **Verbatim RF preservation**: Original RF score, level, and AP counts are preserved as-is in `ChannelRecommendation.rfScore`/`rfLevel`/`apCount`. The counterfactual layer adds `recommendationScore`, and the regulatory layer adds classification and restrictions.
- **Confidence downgrade**: Low-confidence region inference downgrades all `.recommended` channels to `.advanced` rather than `.restricted`, so users still see useful recommendations with a caveat.
- **Comparable sort order**: `ChannelRecommendation.Classification.order` (recommended=2, advanced=1, restricted=0) enables tiered sorting by simple integer comparison.
