# Changelog

All notable changes to **chartkit** are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/); versioning follows [SemVer](https://semver.org/).

## [Unreleased]

## [0.1.6] - 2026-06-29

### Changed
- **`chartkit-kmp` now ships on Maven Central** (namespace `io.github.ccbiver`) instead of JitPack. JitPack's builders are Linux-only and Kotlin/Native Apple targets (`iosX64`/`iosArm64`/`iosSimulatorArm64`) can only be compiled on macOS, so JitPack could not produce the iOS klibs — its `chartkit-kmp` POM/metadata 404'd and the iOS variants never resolved. The `:kmp` module now publishes via `com.vanniktech.maven.publish`, emitting the full Gradle Module Metadata + every target (Android AAR, Desktop jar, three iOS klibs) with signing. New consumer coordinate: `io.github.ccbiver:chartkit-kmp:0.1.6`.
- `:core` and `:compose` are unchanged and continue to publish on JitPack (`com.github.ccBiver.chartkit`); `jitpack.yml` no longer attempts to build `:kmp`.

## [0.1.5] - 2026-06-26

### Fixed
- JitPack build reliability: removed the China-only Maven mirrors (aliyun) from `settings.gradle.kts`. They were listed first and 502'd intermittently on JitPack's overseas builders, breaking the 0.1.3 build. The repo now uses official repositories only; configure local mirrors via a global `~/.gradle/init.gradle.kts` instead (see PUBLISHING.md). Supersedes 0.1.4 (same flaw).

## [0.1.4] - 2026-06-26

### Added
- **Compose Multiplatform support** — new `:kmp` module published as `chartkit-kmp`, targeting Android, iOS (x64/arm64/simulatorArm64) and Desktop (JVM). Native Android consumers keep using `chartkit-compose` unchanged.

### Changed
- `:compose` renderer now draws text via Compose's multiplatform `TextMeasurer` instead of `android.graphics.Paint`/`nativeCanvas` (behavior-preserving), so the entire chart renderer is shared by the KMP module — a single source of truth, no duplicated rendering code.
- Number formatting extracted to a multiplatform helper (`NumberFormat.kt`); `ChartFormatter` split into its own file (Android keeps `java.util.Calendar`; KMP uses `kotlinx-datetime`).

## [0.1.3] - 2026-06-26

### Fixed
- Sub-pane legend (e.g. MACD `DIF/DEA/MACD` readouts) now occupies its own row at the top of each sub-pane instead of overlapping the indicator bars/lines, so the values stay readable. Each sub-pane grows by the legend-row height (`Dims.subLegendHeight`), keeping the indicator drawing area unchanged.

### Changed
- Docs: demo video now embeds via a GitHub `user-attachments` link (plays inline on GitHub); added `demo.jpg` static preview and removed the 7 MB in-repo `demo.mp4`.

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
