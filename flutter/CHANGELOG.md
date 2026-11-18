## 0.1.0

- 首个版本：chartkit（Compose）渲染层与指标层的 Dart 移植。
- 新增 Flutter 侧专有能力：坐标映射 `KLineChartState.mapper`、同帧图层绘制 `overlayPainter`、惯性滚动。
- 业务图层配套：`repaint`、`isViewportLocked`、`onCrosshairPriceChange`、`showCrosshairPriceLabel`、
  `crosshairTrigger`、`crosshairExtraRows`；现价标签支持 `showCountdown` 与 `orderbookProvider`。
- `lockCrosshairPrice`、`crosshairPanelMargin`、`blankScrollWidth`、`showHighLow`，以及主题色
  `crosshairVertical` / `crosshairVerticalWidth` / `lastPriceText` / `highLowText`。
