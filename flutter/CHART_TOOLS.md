# 图表工具

图表类型、对数坐标、K 线回放、多图、合成图。控制条、图表菜单、格子排法这些界面由 App 做，图表库只提供能力。

五项都默认关闭：不传新参数时图表和 `feat/flutter-port` 的 `c9a569b`（合并画线和脚本图元之后）逐像素一致，见文末「测试」。

## 图表类型

```dart
KLineChart(state: state, mode: ChartMode.ohlc); // candle（默认）、ohlc、line、area，另有原来的 timeLine
```

| 类型 | 画法 | 价格区间 | 主图指标 | 最高最低价标注 | 脚本的 K 线改色 |
|---|---|---|---|---|---|
| `candle` 蜡烛图 | 原样 | 最高最低价 | 画 | 画（`showHighLow`） | 生效 |
| `ohlc` 美国线 | 竖线是最高到最低，左短横是开盘价，右短横是收盘价，短横长度是实体宽度的一半 | 最高最低价 | 画 | 画 | 生效 |
| `line` 折线图 | 收盘价连线，颜色和线宽同分时（`timeLineStroke`，2 物理像素） | 只看收盘价 | 画 | 不画 | 不适用 |
| `area` 面积图 | 折线图加分时的渐变填充（`timeLineFillTop` / `timeLineFillBottom`） | 只看收盘价 | 画 | 不画 | 不适用 |
| `timeLine` 分时 | 原样，不变 | 最高最低价 | 不画 | 不画 | 不适用 |

折线图和面积图复用分时的画法（`ChartRenderer.drawTimeLine`），区别是照常画主图指标，价格区间只看收盘价。脚本图元在五种类型下都照常画，自绘 K 线（`candles` 图元）也照画。

## 对数坐标

```dart
KLineChart(state: state, logScale: true);
```

只影响主图价格轴，成交量和副图不变。跟着换算的有：

- 价格和纵坐标的换算：`ChartLayout.priceToY` / `yToPrice`，以及宿主拿到的 `KLineChartMapper`（多了 `logScale` 字段）。
- 网格：仍然等分 5 格，标签写那一格对应的价格（不是整数刻度，和线性时的写法一致）。
- 现价线、现价标签、十字光标的水平线和读数、`onCrosshairPriceChange`。
- 自动价格区间：上下各留对数跨度的 6%（线性时是价格跨度的 6%）。整段只有一个价时上下各放 2%。
- 画线：锚点照常按价格存，换算用同一套；整体拖动时价格按比例移动，形状在屏幕上不变。斐波那契的各档仍按价格线性插值。
- 脚本图元：画在主图上的全部图元（含副图脚本里标了 `pane: "main"` 的）用同一套换算。

非正数在对数刻度下画不出来，不计入价格区间：主图指标、脚本曲线里的 0（例如 ML 超级趋势预热期的 0）不会把轴拉下去。这些点本身画到窗格下方很远处，被裁掉。

## K 线回放

```dart
final replay = ChartReplayController(source: state); // source 就是 KLineChart.state
KLineChart(state: state, replay: replay);

replay.start();      // 进入选起点：之后用户点图上任意位置，那一根就是起点
replay.select(i);    // 也可以直接指定起点（state.candles 的下标）
replay.next();       // 下一根，返回是否已经到最后一根
replay.play();       // 按倍速自动放，放到最后自动暂停
replay.pause();
replay.speed = 2;    // 默认可选 0.5、1、2、4，1x 每根 1 秒
replay.start();      // 重选起点
replay.exit();       // 退出，图回到实时数据
```

给控制条用的状态：`phase`（`off` / `picking` / `active`）、`playing`、`speed`、`cursor`（游标那根，标题里的「回放 11-28 14:00」取它的时间）、`atEnd`。控制器每次变化都会通知。

回放时图上只有起点到游标的 K 线，游标在最右边（开了 `blankScrollWidth` 就留出空白）。具体规则：

- 宿主照常往 `state` 推实时行情，回放的画面不动；退出后图回到 `state`，就是最新的数据。回放能一直放到实时推来的新 K 线。
- 主图和副图的本地指标按截断后的数据重算：回放画面和直接把前 i 根交给图表画出来的完全一样（测试逐像素比过）。
- 脚本图元仍按完整数据对齐，只画到游标为止：逐根的曲线、柱、填充、背景色、K 线改色、自绘 K 线画到游标那根；标记、成交点、标签只画时间不晚于游标的；方框、线段起点晚于游标的不画，跨过游标的从游标那根的右沿裁掉；水平线也只画到游标右沿。表格按窗格定位、和时间无关，照常画。
- 十字光标、画线照常可用。时间晚于游标的画线锚点按周期外推，画在右侧空白里。
- 宿主整份换数据（`setData`，例如切周期）时自动退出；往前加载更早的数据（`prepend`）时回放里也补上。
- 进出回放不播入场动画。

**脚本图元可能带未来信息。** 脚本是服务端按全量 K 线算的，图表只按时间把游标之后的部分藏起来，游标之前的部分是「站在全量数据最后一根」算出来的结果，不等于回放到那一刻时脚本会画出的东西。受影响的图元类型：

| 图元 | 为什么可能不对 |
|---|---|
| 曲线、面积、柱、点、填充（逐根序列） | 会重画的脚本（用 `barstate.islast`、未来函数、`request.security` 的前视，或事后修改历史值）在游标之前的值可能和当时不同 |
| 背景色、K 线改色、自绘 K 线 | 同上，逐根的颜色和数值可能是事后确定的 |
| 标记、成交点 | 信号可能是事后确认才出现的（例如摆动高低点要等右边几根确认），回放里会提前看到 |
| 方框、线段、标签 | 这些对象通常在后来某一根才创建或修改（例如订单块、结构线在突破时回头画），游标之前看到的可能是之后才画出来的；跨过游标的对象，其斜率和范围用到了游标之后的数据 |
| 水平线 | 不带时间，数值按全量数据算 |
| 表格 | 不带时间、不裁，内容是全量数据最后一根的统计 |

图表库没有绕开这一点。要严格回放，需要引擎按游标截断后的 K 线重算（每一步都算一次），这是引擎和 App 的事。

## 多图

图表库这边保证同一页放多个 `KLineChart` 互不影响；格子怎么排、点哪格算当前格是 App 的事。

- 没有影响渲染的全局状态。唯一的静态可变状态是 `ChartRegistry`（宿主注册自定义指标用，渲染时不读写）。文字缓存、脚本图层缓存都在各自的组件实例里。
- 每格用自己的 `KLineChartState`、`ScriptOutputController`、`ChartReplayController`。`ScriptOutputController` 记着一份对齐用的 K 线，两格共用会来回重算，不要共用。
- 同一品种的画线要各格都显示时，把同一个 `DrawingController` 传给多格，画线会在各格按各自的周期显示（测过）。但选中框（`selectionBounds`，App 用它放「样式、锁定、删除」）每帧由各格分别写，共用时以最后画的那格为准，位置可能落在别的格子上。建议每格一个控制器，App 在 `onChanged` 里用 `toJson` / `loadJson` 按品种同步。
- 小尺寸：十字光标浮窗放不下时整体挪回图内，不会被裁掉（放得下时位置不变）。竖屏 430 宽 4 格时每格 215 宽，浮窗约 150 宽，会盖住主图大半，建议多图里用 `crosshairDetail` 只留几行。横屏 900×420 4 格时每格 450×210，同时开成交量和两个副图时主图只剩 48 像素高（四分之一）；CFD 没有成交量，多图里关掉 `showVolume` 后主图约 79 像素。
- 十字线联动：图表库不做，App 用现有接口就能做：监听一格的 `state`，把 `crosshairIndex` 那根的时间换成另一格的下标，再调那一格的 `state.setCrosshair(index, mapper.indexToX(index), -1)`（`multi_chart_test.dart` 里有例子）。

## 合成图

```dart
final ratio = combineCandles(xauusd, xagusd, CombineOp.divide); // 金银比
state.setData(ratio);
// 实时：两边同一开盘时间的最新一根合成一根
final last = combineCandle(xauLast, xagLast, CombineOp.divide);
if (last != null) state.appendOrUpdate(last);
```

规则：

- 只保留两边都有的开盘时间，某一边缺的那根直接跳过，不补值。
- 开高低收各自运算；最高、最低再取四个结果里的最大、最小，保证 K 线成立（相除、相减时 `high ÷ high` 不一定是最高）。
- 成交量、成交额为 0。

结果有非有限数（除以 0）时跳过那一根，因为图表不接受非有限数。

函数只接两组 K 线和一个运算，不解析任意公式。常用组合：金银比 `XAUUSD ÷ XAGUSD`、金铂比 `XAUUSD ÷ XPTUSD`、欧元计价金价 `XAUUSD ÷ EURUSD`、日元计价金价 `XAUUSD × USDJPY`。

这是数据处理，和画图无关，放在图表库里是为了现在能写能测，以后可以挪到 App 侧。

## 测试

在 `test/tools/`，参考图在 `testdata/chart_tools/goldens/`：

| 文件 | 内容 |
|---|---|
| `chart_type_test.dart` | 三种类型的价格区间、美国线短横的像素位置和颜色、填充有无、最高最低价标注、K 线改色，4 张参考图 |
| `log_scale_test.dart` | 换算和反函数、对数留白、非正数不计入、整体拖动按比例；现价、十字光标读数、画线和脚本水平线、曲线的像素位置；副图和成交量逐像素不变；2 张参考图 |
| `replay_test.dart` | 控制器的阶段、下一根、倍速、实时行情、切周期退出、加载更早数据；点击选起点、回放画面和截断数据画面逐像素一致、脚本图元游标右侧为空、表格照画；1 张参考图（回放加副图脚本） |
| `multi_chart_test.dart` | 4 图同页时滚动、十字光标、回放、对数坐标、行情只改自己那一格；共用画线控制器；十字线联动的写法；两种尺寸不溢出；2 张参考图；帧耗时 |
| `combine_test.dart` | 四种运算、最高最低、缺 K 线、除以 0；和另一份独立实现在真实 K 线上逐位对照；1 张参考图（金油比） |
| `combo_test.dart` | 对数坐标加画线加主图和副图脚本；美国线、对数、回放、画线、脚本同时打开；面积图加脚本；3 张参考图 |
| `benchmark_test.dart` | 各图表类型开关对数坐标的一帧绘制耗时、回放每走一根的耗时、合成 1000 根的耗时 |

默认关闭：`test/baseline/chart_tools_off_golden_test.dart` 在画线、脚本图元、内置指标全开的三种配置下和 `testdata/baseline_chart_tools/`（在 `c9a569b` 上生成）逐像素比对；原有的基线和参考图测试不改照样通过。

截图工具：`SHOTS_DIR=<目录> flutter test test/tools/screenshots_tool.dart`，用 XAUUSD 样本 K 线（`testdata/chart_tools/klines/`）。
