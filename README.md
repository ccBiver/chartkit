# chartkit

简体中文 | [English](README.en.md)

完全用 Jetpack Compose 编写的**高性能、可扩展 K 线图**，参考 OKX / Binance 的行情图体验。

- **纯 Compose** —— 全部画在一个 `Canvas` 上；不用 `AndroidView`，不依赖第三方图表引擎。
- **流畅体验** —— 数据到达前先显示骨架行情（幽灵 K 线）、入场揭示动画、实时滚动数字图例、连续的指标线、副图增删卷帘动画、切周期淡入淡出。
- **指标后台计算** —— 在 `Dispatchers.Default` 计算，按数据版本合并高频 tick；实时 tick 只增量重算末根，不重算整条序列。
- **易扩展** —— 一个 lambda 公式即可加主图/副图指标；副图可多选叠加。

## 演示

![chartkit demo](demo.jpg)

https://github.com/user-attachments/assets/7bc1ff7e-96d2-4090-954a-25da83fd9d92

```
chartkit/
├── core/      # 纯 Kotlin/JVM：Candle、TimeFrame、Indicator + 内置指标（有单测）
├── compose/   # Android 库：KLineChart 组合项、状态、主题
└── kmp/       # Compose Multiplatform 库（Android/iOS/Desktop），复用 core + compose 源码 → chartkit-kmp
```

---

## 接入

通过 [JitPack](https://jitpack.io) 发布。加上仓库后依赖 `compose` 即可（它已 `api` 暴露 `core`，一行足够）：

```kotlin
// settings.gradle.kts
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://jitpack.io") }
    }
}

// 模块 build.gradle.kts
implementation("com.github.ccBiver.chartkit:chartkit-compose:0.1.4")
```

要求 `minSdk 24`，已开启 Compose。坐标 / 版本 / 发布细节见 [PUBLISHING.md](PUBLISHING.md)。

> 想直接内嵌源码？把 `core/`、`compose/` 拷进你的工程，`include(":core", ":compose")`，再 `implementation(project(":compose"))`。

### Compose Multiplatform（Android / iOS / Desktop）

需要跨端时用 KMP 版 `chartkit-kmp`（同一份渲染代码，Android 原生仍可用上面的 `chartkit-compose`）：

```kotlin
// commonMain
implementation("com.github.ccBiver.chartkit:chartkit-kmp:0.1.4")
```

目标平台：`androidTarget`、`iosX64/iosArm64/iosSimulatorArm64`、`jvm`(Desktop)。API 与 Android 版一致，`@Composable fun KLineChart(...)` 直接在 `commonMain` 调用。差异：全屏（`launchChartFullscreen`，依赖 Android `Activity`）仅 Android 版提供，KMP 端用 `onToggleFullscreen` 回调由宿主自行实现。

跨端示例 `:composeApp`（一份 `App()` 跑 Android / iOS / Desktop，含周期/指标切换、明暗主题）：

```bash
# Desktop（直接弹窗）
./gradlew :composeApp:run

# Android（需连真机/模拟器，或用 Android Studio 选 composeApp 运行）
./gradlew :composeApp:installDebug

# iOS：用 Xcode 打开 iosApp/iosApp.xcodeproj，选模拟器 Run
#（构建阶段会自动调 Gradle 生成并嵌入 ComposeApp.framework）
open iosApp/iosApp.xcodeproj
```

> `:demo`（Android 原生，基于 `chartkit-compose`）依旧可用：`./gradlew :demo:installDebug`。`:composeApp` 则走 KMP 的 `chartkit-kmp`。

运行内置示例：`./gradlew :demo:installDebug`（见 [`demo/`](demo/)）。

---

## 快速开始

```kotlin
@Composable
fun MyChart(rows: List<Candle>) {
    val state = rememberKLineChartState(timeFrame = TimeFrame.M15)

    LaunchedEffect(rows) { state.applyUpdate(KLineUpdate.RESET, rows) }

    KLineChart(
        state = state,
        modifier = Modifier.fillMaxWidth().height(320.dp),
        theme = ChartTheme.Dark,
        upDownColor = UpDownColor.GreenUpRedDown,
        mainIndicators = listOf(Ma(intArrayOf(7, 25, 99))),
        subIndicators = listOf(Macd(), Kdj()),
    )
}
```

`Candle`（不可变；`time` 为该根开盘时间的毫秒时间戳）：

```kotlin
data class Candle(
    val time: Long,
    val open: Double, val high: Double, val low: Double, val close: Double,
    val volume: Double = 0.0, val turnover: Double = 0.0,
)
```

---

## `KLineChart` 参数

把这些参数传给组合项即可调整表现，均有合理默认值。

| 参数 | 类型 | 默认 | 作用 / 怎么改 |
|---|---|---|---|
| `state` | `KLineChartState` | — | 数据 + 视口宿主，用 `rememberKLineChartState()` 创建。 |
| `theme` | `ChartTheme` | `Dark` | 颜色 + 尺寸。用 `ChartTheme.Light`，或 `.copy(...)` 微调（见下）。 |
| `upDownColor` | `UpDownColor` | `GreenUpRedDown` | 涨跌配色。国内习惯用 `RedUpGreenDown`。 |
| `mode` | `ChartMode` | `Candle` | `Candle` 蜡烛图，`TimeLine` 分时折线+渐变。 |
| `mainIndicators` | `List<Indicator>` | `[]` | 主图叠加，如 `listOf(Ma(), Boll(20, 2.0))`。 |
| `subIndicators` | `List<Indicator>` | `[]` | 每个独立成一个副图（可叠加），如 `listOf(Macd(), Kdj())`。 |
| `formatter` | `ChartFormatter` | `Default` | 价格/量/时间格式化（精度、千分位、locale）。 |
| `entranceAnimation` | `Boolean` | `true` | 首屏/切周期的从左往右揭示动画；`false` 关闭。 |
| `showVolume` | `Boolean` | `true` | 是否显示成交量窗格。 |
| `tradeMarks` | `List<TradeMark>` | `[]` | K 线上的买卖标记（可点击）。 |
| `logo` | `Painter?` | `null` | 水印图片，`painterResource(R.drawable.x)`。 |
| `logoPosition` | `LogoPosition` | `Center` | `Center`/`TopStart`/`TopEnd`/`BottomStart`/`BottomEnd`。 |
| `logoAlpha` | `Float` | `0.10f` | 水印透明度（0..1）。 |
| `logoHeight` | `Dp` | `32.dp` | 水印高度。 |
| `showSkeleton` | `Boolean` | `true` | 无数据时显示「幽灵行情」骨架屏。 |
| `blankScrollRatio` | `Float` | `0f` | 是否允许把最新一根拖离右边缘留白（类 Binance）。`0` 贴右；`0.5f` 最多留半屏空白。 |
| `crosshairMode` | `CrosshairMode` | `Free` | `Free` 横线跟手指；`SnapToClose` 吸附收盘价。 |
| `crosshairDismiss` | `CrosshairDismiss` | `Persistent` | `Persistent` 松手不消失，点击/拖动/缩放才消失；`OnRelease` 松手即消失。同时影响买卖标记交互（见下）。 |
| `lastPriceMode` | `LastPriceMode` | `Latest` | 现价线/标签取值方式。`Latest`（业内标准）= 恒取最新成交价；最新一根滑出屏幕、且现价超出可见价格区间时，标签贴到上/下边缘，而非消失。`RightmostVisible` = 跟随屏幕最右那根可见 K 线的收盘价（值与颜色都随之）。 |
| `labels` | `ChartLabels` | `ChartLabels()` | 内置详情浮窗字段的本地化标签。 |
| `crosshairDetail` | `((Candle) -> List<CrosshairDetailRow>)?` | `null` | `null` 用内置完整面板（时间/开高低收/涨跌额/涨跌幅/振幅/量/额，自动计算）。传 lambda 可整体覆盖。 |
| `onToggleFullscreen` | `(() -> Unit)?` | `null` | 非空时主图左下角出现一个按钮，点击回调此函数。 |
| `onLoadMore` | `() -> Unit` | `{}` | 滚动接近最早一根时触发（分页加载更多）。 |
| `onCrosshairChange` | `(Candle?) -> Unit` | `{}` | 长按时聚焦的 K 线（松手为 null）。 |
| `onTradeMarkClick` | `(TradeMark) -> Unit` | `{}` | 点击买卖标记。 |

---

## 调尺寸与颜色 —— `ChartTheme` / `ChartDims`

`ChartTheme` 和 `ChartDims` 都是 data class，按需 `copy(...)`：

```kotlin
val theme = ChartTheme.Dark.copy(
    dims = ChartTheme.Dark.dims.copy(
        candleDefaultWidth = 6.dp,   // 蜡烛更细更密
        axisTextSize = 9.sp,         // 轴/读数字号
        legendTextSize = 10.sp,      // 顶部图例（MA7 …、DIF …）
        rightAxisWidth = 52.dp,      // 右侧价格留白
        bottomAxisHeight = 18.dp,    // 底部时间轴高度
        paneGap = 6.dp,              // 窗格间距
    ),
)
```

`ChartDims` 字段：`candleMinWidth`(3.dp)、`candleMaxWidth`(30.dp)、`candleDefaultWidth`(8.dp)、`candleGapRatio`(0.25f)、`axisTextSize`(10.sp)、`legendTextSize`(11.sp)、`rightAxisWidth`(46.dp)、`bottomAxisHeight`(18.dp)、`paneGap`(6.dp)。

颜色和网格在 `ChartTheme` 上（`background`、`grid`、`axisText`、`crosshair`、`lastPriceLine`、`indicatorColors`、涨跌色经 `upDownColor`…），同样用 `copy()` 改。

---

## 数值与时间格式化 —— `ChartFormatter`

```kotlin
formatter = ChartFormatter(
    price = { v -> String.format(java.util.Locale.US, "%,.2f", v) },  // 62,978.00
    volume = { v -> compact(v) },                                     // 9.17K
    time = { t, tf -> /* 时间轴刻度 */ },
    crosshairTime = { t, tf -> /* 十字光标的完整日期 */ },
)
```

> 提示：价格建议固定一个 `Locale`，否则 JVM 默认 locale 在某些地区会把小数点/千分位分隔符对调。

---

## 驱动更新 —— `KLineUpdate`

数据由宿主持有，用一个常量驱动图：

| `KLineUpdate` | 何时 | 效果 |
|---|---|---|
| `RESET`  | 首屏 / 切周期（完整列表） | 全量替换、回到最新一屏、重播入场 |
| `LATEST` | 完整列表含新/更新的末根 | 同时间替换末根，否则追加 |
| `MORE`   | 完整列表，头部插入了更早的数据 | 只 prepend 多出的头部增量，保持滚动位置 |

```kotlin
state.applyUpdate(KLineUpdate.RESET, fullList)
```

### 实时 tick

把最新一根直接喂进去（O(1)，不重建整张表）：

```kotlin
LaunchedEffect(Unit) { tickFlow.collect { state.appendOrUpdate(it) } }
```

`appendOrUpdate` 同时间替换末根，否则追加。

---

## 指标

内置（`com.biver.chartkit.indicator.builtin`）：

| 窗格 | 指标 |
|---|---|
| 主图叠加 | `Ma`、`Ema`、`Boll`、`Sar`（抛物线 SAR，散点绘制） |
| 副图 | `Macd`、`Kdj`、`Rsi`、`Wr`（威廉指标）、`Obv`（能量潮）、`VolMa` |

```kotlin
mainIndicators = listOf(Ma(intArrayOf(7, 25, 99)), Boll(20, 2.0), Sar())
subIndicators  = listOf(Macd(12, 26, 9), Kdj(), Rsi(intArrayOf(6, 12, 24)), Wr(intArrayOf(14)), Obv())
```

调用一次 `Indicators.registerDefaults()` 可把全部内置指标注册进 `ChartRegistry`（按 id 查找）。

### 用公式自定义指标

一个 lambda 就能加主图/副图，无需继承：

```kotlin
val vwap = indicator("VWAP", Pane.Sub) { candles ->
    listOf(IndicatorLine("VWAP", candles.runningVwap()))  // 与 candles 等长的 List<Double?>
}
KLineChart(state = state, subIndicators = listOf(vwap), /* ... */)
```

规则：
- 输出的每条线**与 K 线列表等长、按索引对齐**。
- 无值处用 `null`（如均线前置窗口）—— 渲染层跨 `null` 不连线（线不会断、也不会掉到 0）。
- `compute` 必须是**纯函数**（在后台线程跑）。多线指标（MACD = DIF + DEA + 柱）返回多条 `IndicatorLine`。每条线用 `LineStyle` 选绘制风格：`Line`（默认）、`Histogram`（MACD 柱）、`Points`（散点，如 SAR）。
- 可选地设置 `lookback`（`indicator(...)` DSL 有该参数，或重写属性）为「算末值所需的回看根数」。实时 tick 时图只重算这个窗口而非整条序列。路径相关指标（OBV、SAR 等必须全量重算）保持默认 `Int.MAX_VALUE` 即可。

---

## 详情浮窗

长按显示详情面板。**开箱即用（不传 `crosshairDetail`）**：库会用注入的 `formatter` 和 `upDownColor`，自动算出聚焦那根的完整面板——时间、开、高、低、收、涨跌额（带 +/− 与涨跌色）、涨跌幅、振幅、量、额，**无需自己计算**。

本地化只需用 `ChartLabels` 传标签：

```kotlin
KLineChart(
    state = state,
    labels = ChartLabels(
        time = "时间", open = "开", high = "高", low = "低", close = "收",
        change = "涨跌", changePct = "涨跌幅", amplitude = "振幅",
        volume = "量", turnover = "额",
    ),
)
```

想要不同字段/布局？用 `crosshairDetail` 整体覆盖：

```kotlin
crosshairDetail = { c ->
    listOf(
        CrosshairDetailRow("收盘", fmt(c.close)),
        CrosshairDetailRow("涨跌", sign + fmt(c.close - c.open), if (up) Color.Green else Color.Red),
    )
}
```

### 消失方式 —— `crosshairDismiss`

| 模式 | 十字光标 | 浮窗里的买卖行 | 蜡烛上的标记 |
|---|---|---|---|
| `Persistent`（默认） | 松手不消失；点击空白 / 拖动 / 缩放才消失 | **可点击**（带 `›`）→ `onTradeMarkClick` | 不可点 |
| `OnRelease` | 仅按住时显示，松手即消失 | 显示但**不可点**（无箭头） | **点击徽章** → `onTradeMarkClick` |

想让用户松手后还能看/点面板就用 `Persistent`；想要「按一下瞄一眼、用图上 B/S 徽章做点击目标」就用 `OnRelease`。

设了 `tradeMarks` 时，聚焦那根的买/卖记录会追加到浮窗（标签 + 最近一笔单价 + 成交笔数），颜色随 `upDownColor`。可见 K 线柱超过约 50 根时标记自动隐藏。

---

## 架构

- `:core` —— 纯 Kotlin/JVM，有单测（`./gradlew :core:test`）；SMA/EMA/BOLL/MACD/KDJ/RSI/WR/OBV/SAR 有金标测试，另有一个测试验证 `lookback` 窗口重算出的末值与全量末值一致。
- `:compose` —— 单 `Canvas`；指标用 `produceState` 在 `Dispatchers.Default` 计算，按数据版本合并高频 tick，并对末根做增量重算（`IndicatorCache`）；状态上提到 `KLineChartState`。

## License

[MIT License](LICENSE)。
