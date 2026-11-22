## Unreleased

- 新增画线工具（默认关闭）：`KLineChart.drawingController` 传入 `DrawingController` 后开启。12 个工具：水平线、垂直线、
  趋势线、射线、矩形、斐波那契回撤、价格区间测量、多头/空头头寸、江恩扇形、安德鲁分叉、艾略特波浪。支持选中、
  拖端点、整体拖动、锁定、删除、显示开关、清除全部、JSON 保存恢复。不传时界面和手势不变。说明见 `DRAWING.md`。
- 新增 `initialBlankScroll`：首屏和每次全量更新后，最新一根停在留白区左缘，右侧先空出
  `blankScrollWidth` / `blankScrollRatio` 那么宽（默认关闭，行为不变）。
- 现价标签与盘口贴纸的内边距改按逻辑像素：现价标签四周 4、两行间隔 2、圆角 4；贴纸横 6 竖 3、圆角 4、
  离标签 4。原先按物理像素，高分屏上只有 1～2 逻辑像素，显得很挤。十字光标价签等其它右轴标签不变。

## 0.1.0

- 首个版本：chartkit（Compose）渲染层与指标层的 Dart 移植。
- 新增 Flutter 侧专有能力：坐标映射 `KLineChartState.mapper`、同帧图层绘制 `overlayPainter`、惯性滚动。
- 业务图层配套：`repaint`、`isViewportLocked`、`onCrosshairPriceChange`、`showCrosshairPriceLabel`、
  `crosshairTrigger`、`crosshairExtraRows`；现价标签支持 `showCountdown` 与 `orderbookProvider`。
- `lockCrosshairPrice`、`crosshairPanelMargin`、`blankScrollWidth`、`showHighLow`，以及主题色
  `crosshairVertical` / `crosshairVerticalWidth` / `lastPriceText` / `highLowText`。
