# Contributing to chartkit

Thanks for your interest! chartkit is a Jetpack Compose K-line chart split into two modules:

```
chartkit/
├── core/      # pure Kotlin/JVM — model + indicator engine + built-ins (no Android deps)
└── compose/   # Android library — KLineChart composable, state, theme, gestures, drawing
```

Keep logic that can be unit-tested in `core`; keep rendering/interaction in `compose`.

## Prerequisites

- JDK 17+ (Android Studio's bundled JBR — JDK 21 — works; AGP 8.9 requires 17+).
- Android SDK with `compileSdk 35`. `minSdk` is 24.

## Build & test

```bash
# Run the core unit tests (golden-value tests for every indicator)
./gradlew :core:test

# Compile the Compose layer
./gradlew :compose:compileDebugKotlin

# Publish both modules to your local Maven repo (~/.m2) to try them in another project
./gradlew :core:publishToMavenLocal :compose:publishToMavenLocal
```

## Coding style

- Idiomatic Kotlin, official code style. `val` over `var`; no `!!`.
- Prefer many small focused files. The Compose layer is split into `KLineChart.kt`, `ChartDrawing.kt`, `CrosshairPanel.kt`, `ChartTypes.kt`, `ChartTheme.kt`, `IndicatorEngine.kt` — keep new responsibilities in the right place.
- `Indicator.compute` must be **pure** (it runs on a background thread). Output lines must be the same length as the candle list and index-aligned; use `null` for warm-up gaps.

## Adding an indicator

Most indicators need no new class — use the DSL:

```kotlin
val vwap = indicator("VWAP", Pane.Sub, lookback = 1) { candles ->
    listOf(IndicatorLine("VWAP", candles.runningVwap()))
}
```

For a built-in, add a class in `core/.../indicator/builtin/Builtins.kt`, register it in `Indicators.registerDefaults()`, and add a **golden-value test** in `core/src/test/.../BuiltinIndicatorTest.kt`. Set `lookback` to the trailing-bar window needed for the latest value (or leave the default for path-dependent indicators that must recompute fully).

## Pull requests

1. Branch from `main`.
2. Make sure `:core:test` is green and both modules compile.
3. Add/adjust tests for any `core` change.
4. Update `CHANGELOG.md` under `[Unreleased]` and the READMEs if you changed public API.
5. Use clear, conventional commit messages (`feat:`, `fix:`, `refactor:` …).

## License

By contributing you agree your contributions are licensed under the [MIT License](LICENSE).
