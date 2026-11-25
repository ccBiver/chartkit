## Unreleased

- 新增 `Boll.fillColor`（默认不填，行为不变）：在 BOLL 上下轨之间填宿主给的颜色（一般是半透明色），画在网格和脚本背景色之上、
  K 线、指标线、画线和脚本图元之下。按连续有值的区间分段、每段一次画完，可见范围两边各多取一根，裁在主图矩形里；
  分时模式不画。对数坐标、回放、图例留位、`mainBottomGap` 和美国线、折线图、面积图下照常。
  `IndicatorSeries` 加可选的 `fill`（`IndicatorFill`：两条线的下标和颜色），自定义主图指标也能用。
- 新增 `KLineChart.mainBottomGap`（默认 0，行为不变）：在主图正下方给宿主自己的控件留一段空白，成交量和副图整体往下挪；
  没有副图时空白在主图和时间轴之间。各窗格按「绘图区高度 − 空白」分配，宿主把图表高度加上空白，主图和副图就和
  原来一样高。空白里只铺背景色，不画网格、十字光标和标签，落在里面的手势也不归图表；最多占绘图区高度的 40%。
  `KLineChartMapper` 加 `mainBottomGapRect`，宿主按它摆放控件。
- 新增 `KLineChart.reserveMainLegend`（默认关闭）：主图顶部按「图例行数 × `ChartDims.mainLegendRowHeight` +
  `ChartDims.mainLegendTop`」给左上角的指标读数图例留位置，价格从图例下面开始映射，最高价标签、贴顶的 K 线和
  指标线不再压在图例上；最多占主图高度的 40%，分时模式不留。网格、十字光标命中和 `mainRect` 不变，画线和
  脚本图元跟着新的价格区换算。`KLineChartMapper` 加 `mainContentTop`（价格区顶边，宿主把东西排在图例下方时用它）。
- 新增图表类型（默认仍是蜡烛图）：`ChartMode.ohlc` 美国线、`ChartMode.line` 折线图、`ChartMode.area` 面积图。
  折线图和面积图复用分时的画法，价格区间只看收盘价；三者都照常画主图指标和脚本图元。
- 新增主图对数坐标（默认关闭）：`KLineChart.logScale`。价格换算、网格标签、现价、十字光标、自动价格区间、画线和
  脚本图元都按对数算，非正数不计入价格区间；副图和成交量不变。`KLineChartMapper` 加 `logScale`。
- 新增 K 线回放（默认关闭）：`KLineChart.replay` 传入 `ChartReplayController`。选起点、下一根、播放暂停和倍速、
  重选起点、退出；回放时本地指标按截断数据重算，实时行情不影响回放，脚本图元只画到游标。控制条由宿主做。
- 新增 `combineCandles` / `combineCandle` / `CombineOp`：两个品种的 K 线按开盘时间对齐后加减乘除（合成图）。
- 十字光标浮窗在图太窄、放不下时整体挪回图内，不再被裁掉；放得下时位置不变。说明见 `CHART_TOOLS.md`。
- 新增脚本图元渲染（默认关闭）：`KLineChart.scriptOutputs` 传入 `ScriptOutputController` 后，把服务端脚本引擎的
  图元 JSON（SCHEMA v1）画到图上：15 类图元，主图脚本叠在 K 线上，副图脚本各占一个窗格。按脚本 id 设置、替换、移除，
  替换时只重画受影响的窗格；`valuesAt` 给图例和十字光标取值。不传时界面和手势不变。说明见 `PRIMITIVES.md`。
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
