# chartkit_flutter

[chartkit](../README.md) 的 Flutter 版：把 Compose 版的渲染层与指标层用 Dart 重写，全部画在一个 `CustomPaint` 上，
不依赖 PlatformView，也不依赖第三方图表引擎。

- 骨架行情、入场揭示动画、切周期淡入淡出、副图增删卷帘动画、图例滚动数字
- 10 个内置指标（MA / EMA / BOLL / SAR / MACD / KDJ / RSI / WR / OBV / VOLMA），一个公式即可自定义
- 实时 tick 只增量重算末根指标
- 横向拖动（带惯性）、双指缩放、长按十字光标；纵向手势让给父级滚动
- 坐标映射与同帧图层绘制，方便叠加挂单线、持仓标签、快捷下单等业务图层

## 接入

目前未发布到 pub.dev，用 git 依赖：

```yaml
dependencies:
  chartkit_flutter:
    git:
      url: https://github.com/ccBiver/chartkit.git
      path: flutter
```

要求 Flutter ≥ 3.27（Dart ≥ 3.5）。

## 用法

```dart
final state = KLineChartState(timeFrame: TimeFrame.m15);

// 首屏 / 切周期
state.setData(candles);
// 实时 tick：同一根替换，新一根追加
state.appendOrUpdate(candle);
// 加载更早的数据
state.prepend(olderCandles);

SizedBox(
  height: 420,
  child: KLineChart(
    state: state,
    theme: ChartTheme.dark,
    mainIndicators: [Ma(), const Boll()],
    subIndicators: [const Macd(), const Kdj()],
    formatter: ChartFormatter(price: (v) => v.toStringAsFixed(2)),
    onLoadMore: loadOlder,
  ),
)
```

`KLineChartState` 是 `ChangeNotifier`，用完需要 `dispose()`。图表会撑满父级给的空间，需要有界的宽高。

指标列表、买卖标记这类 list 参数按不可变值对待：要变更请传入新的 list，不要原地修改。

### 自定义指标

```dart
final typicalPrice = indicator(
  'TP',
  pane: Pane.sub,
  compute: (candles) => [
    IndicatorLine('TP', [for (final c in candles) (c.high + c.low + c.close) / 3]),
  ],
);
```

### 副图单选 / 叠加

```dart
final subs = SubIndicatorController(mode: SubIndicatorMode.multiple);
subs.toggle(const Macd());
// KLineChart(subIndicators: subs.selected)
```

### 叠加业务图层

两种方式，按是否需要像素级同步选：

```dart
// 1. 同帧绘制（零滞后）：直接画在图表画布上，在十字光标之下
KLineChart(
  state: state,
  overlayPainter: (canvas, size, mapper) {
    final y = mapper.priceToY(orderPrice);
    if (mapper.containsY(y)) {
      canvas.drawLine(Offset(0, y), Offset(mapper.mainRect.right, y), paint);
    }
  },
)

// 2. 组件图层：监听坐标映射，在 Stack 里定位自己的组件（滞后至多一帧）
ValueListenableBuilder(
  valueListenable: state.mapper,
  builder: (context, mapper, _) => mapper == null
      ? const SizedBox.shrink()
      : Positioned(top: mapper.priceToY(orderPrice), right: 0, child: orderLabel),
)
```

`KLineChartMapper` 提供 `priceToY` / `yToPrice` / `indexToX` / `xToIndex` / `mainRect` / `latestPrice` 等。

绘制顺序：行情内容 → `overlayPainter` → 现价线与标签 → 十字光标。所以图层不会盖住现价标签。

配合图层常用的几个参数：

| 参数 | 作用 |
|---|---|
| `repaint` | 额外的重绘信号。图层自己的状态（挂单、持仓、盘口）变了而行情没变时，用它触发重绘 |
| `isViewportLocked` | 返回 true 时暂停平移/缩放/惯性，比如正在拖拽图层上的改价标签 |
| `onCrosshairPriceChange` | 十字光标水平线所指的价格，消失或不在主图区时为 null |
| `showCrosshairPriceLabel` | 设为 false 隐藏十字光标的右轴价签，由宿主自己的组件代替 |
| `crosshairTrigger` | `CrosshairTrigger.tapOrLongPress` 让单击也能唤出十字光标 |
| `crosshairExtraRows` | 在详情浮窗默认行之后追加行 |
| `lockCrosshairPrice` | 自由模式下把水平线锁在价位上，价格区间变化时线跟着价位走。适合用十字光标选下单价 |
| `crosshairPanelMargin` | 详情浮窗的额外外边距，用来避开叠在图上的组件 |
| `blankScrollWidth` | 右侧可拖出的留白，按绝对宽度指定（优先于 `blankScrollRatio`） |
| `initialBlankScroll` | 首屏和每次 `setData` 后让最新一根停在留白区左缘（右侧先空出留白），默认 `false` 贴右 |
| `showHighLow` | 标注可见区的最高价与最低价 |

主题里与此相关的颜色：`crosshairVertical` / `crosshairVerticalWidth`（竖线单独配色，给宽度则画成半透明竖带）、
`lastPriceText`（现价标签文字色）、`highLowText`。

### 现价标签：倒计时与盘口贴纸

```dart
KLineChart(
  state: state,
  showCountdown: true,                 // 现价标签第二行显示当根剩余时间，每秒刷新
  repaint: orderbookNotifier,          // 盘口变化时重绘
  orderbookProvider: () => ChartOrderbook(
    bid: bestBid, ask: bestAsk, bidLabel: '买', askLabel: '卖',
  ),
)
```

`orderbookProvider` 在每次绘制时调用，里面不要访问 `BuildContext`。

## 与 Compose 版的差异

| 项 | Compose 版 | Flutter 版 |
|---|---|---|
| 状态 | `KLineChartState`（Compose State） | `KLineChartState`（`ChangeNotifier`） |
| 枚举值 | `TimeFrame.M15`、`KLineUpdate.RESET` | `TimeFrame.m15`、`KLineUpdate.reset` |
| 单位 | 状态里是物理像素 | 全部是逻辑像素 |
| 指标计算 | 后台线程 | 主 isolate 同步计算（末根更新走增量） |
| 惯性滚动 | 无 | 有，`enableFling` 可关 |
| 坐标映射 / 图层绘制 | 无 | `state.mapper`、`overlayPainter` |
| Logo | `Painter` | 任意 `Widget` |
| 分时填充 | 纯色 | 自上而下渐变（用上了 `timeLineFillBottom`） |
| 全屏 | Android 版内置 | 仅 `onToggleFullscreen` 回调，宿主自行实现 |

## 示例

```bash
cd example && flutter run
```

## 测试

```bash
flutter test
```
