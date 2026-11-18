## Unreleased

- 新增 `initialBlankScroll`：首屏和每次全量更新后，最新一根停在留白区左缘，右侧先空出
  `blankScrollWidth` / `blankScrollRatio` 那么宽（默认关闭，行为不变）。

## 0.1.0

- 首个版本：chartkit（Compose）渲染层与指标层的 Dart 移植。
- 新增 Flutter 侧专有能力：坐标映射 `KLineChartState.mapper`、同帧图层绘制 `overlayPainter`、惯性滚动。
- 业务图层配套：`repaint`、`isViewportLocked`、`onCrosshairPriceChange`、`showCrosshairPriceLabel`、
  `crosshairTrigger`、`crosshairExtraRows`；现价标签支持 `showCountdown` 与 `orderbookProvider`。
- `lockCrosshairPrice`、`crosshairPanelMargin`、`blankScrollWidth`、`showHighLow`，以及主题色
  `crosshairVertical` / `crosshairVerticalWidth` / `lastPriceText` / `highLowText`。
