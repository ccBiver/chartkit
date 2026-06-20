# Changelog

All notable changes to **chartkit** are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/); versioning follows [SemVer](https://semver.org/).

## [Unreleased]

## [0.1.2] - 2026-06-20

### Fixed
- Logo watermark now anchors to the actual (animated) main-pane geometry, so it stays centered in the price pane and no longer drifts when sub-panes are toggled.

### Changed
- Demo: added a logo watermark and a short first-load delay so the skeleton screen is visible on launch.

## [0.1.1] - 2026-06-20

First version successfully published on JitPack.

### Fixed
- `gradle.properties` (with `android.useAndroidX=true`) was excluded by a global gitignore and never committed, so the 0.1.0 tag failed to build on JitPack. The file is now tracked; 0.1.0 is superseded by 0.1.1.

## [0.1.0] - 2026-06-20

Initial public release.

### Added

**`:core`** (pure Kotlin/JVM, unit-tested)
- `Candle`, `TimeFrame` models and an index-aligned indicator engine.
- Built-in indicators: `Ma`, `Ema`, `Boll`, `Sar` (main); `Macd`, `Kdj`, `Rsi`, `Wr`, `Obv`, `VolMa` (sub).
- Custom-indicator DSL (`indicator("ID", Pane.Sub) { ... }`) and `ChartRegistry`.
- Per-indicator `lookback` for last-bar incremental recompute.

**`:compose`** (Android library, single `Canvas`)
- Candlestick + timeline modes; volume pane and multiple stacked sub-panes.
- Crosshair tooltip: localizable labels (`ChartLabels`), custom rows (`crosshairDetail`), `CrosshairDismiss` (Persistent / OnRelease) modes; extra time tag on the main pane when sub-panes are present.
- Trade marks (buy/sell badges) with click-through.
- Last-price line/label with `LastPriceMode` (`Latest` — industry standard, pins to edge when scrolled off; `RightmostVisible`).
- Right-axis values right-aligned; labels grow leftward so long prices never clip.
- Skeleton ghost chart while data is empty.
- Animations: entrance reveal, rolling-number legend, sub-pane add/remove, timeframe crossfade.
- Pinch-zoom anchored at focal point; direction-locked pan (vertical drags pass through to the parent scroll).
- Off-main-thread indicators (`Dispatchers.Default`), coalesced per data version, with last-bar incremental recompute (`IndicatorCache`).

### Meta
- MIT license; English + Simplified Chinese READMEs.
