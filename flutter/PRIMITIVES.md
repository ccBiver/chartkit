# 脚本图元

把服务端脚本引擎输出的通用图元 JSON 画到 K 线图上。格式是图元格式 SCHEMA v1（格式文档由服务端维护，不在本仓库），15 类图元：曲线、面积、柱、点、填充、水平线、标记、策略成交点、背景色、K 线改色、自绘 K 线、线段、方框、标签、表格。图表只按图元类型画，不需要知道是哪个指标。

默认关闭：不传 `scriptOutputs` 时图表的界面、手势和原来完全一样（和基线逐像素比对过，见文末「测试」）。

## 接法

```dart
final scripts = ScriptOutputController(
  onAlignmentIssue: (issue) {
    // 输出和本地 K 线对不上（多半是本地还没有 bars.to 那根，或切了周期）：重新拉输出或 K 线
  },
);

KLineChart(state: state, scriptOutputs: scripts);

// 引擎每次推来整份输出（字符串或 jsonDecode 的结果都行），按脚本 id 设置或替换
final r = scripts.setJson('rsi', responseItem['output']);
if (!r.ok) log('${r.error}');        // 例如 v 不是 1：整份不画，原来的也移除
if (r.warnings.isNotEmpty) log('${r.warnings}'); // 跳过的字段、不认识的枚举值

scripts.remove('rsi');
scripts.clear();
scripts.visible = false;             // 全部隐藏，副图窗格收起，数据保留
```

输出比较大（100 KB 以上）时可以在后台 isolate 里解析，再交给控制器：

```dart
final r = await Isolate.run(() => parseScriptOutput(text));
if (r.output != null) scripts.setOutput('smc', r.output!);
```

`scriptId` 是调用方给的键：同一个脚本开两份不同参数，用两个不同的键即可。

## 控制器

| 成员 | 说明 |
|---|---|
| `setJson(id, json)` | 解析并设置；返回 `ScriptParseResult`（`output`、`error`、`warnings`）。解析失败时移除这个 id 原有的输出 |
| `setOutput(id, output)` | 设置已解析好的输出。已有的 id 保持原来的位置 |
| `remove(id)`、`clear()` | 移除 |
| `visible` | 全部显示 / 隐藏 |
| `scriptIds`、`subPaneIds`、`outputOf(id)` | 当前的脚本、副图窗格顺序、某个脚本的输出 |
| `valuesAt(index)` | 取值接口，见下 |
| `alignmentOf(id)` | 对齐结果（`alignment` 或 `issue`） |
| `onAlignmentIssue` | 对不上 K 线时调用，同一份输出同一种原因只报一次，在帧末调用 |
| `attachCandles(candles)`、`deliverIssues()` | 图表内部调用；不用图表、只用 `valuesAt` 时自己调 `attachCandles` |

### 取值接口

```dart
final values = scripts.valuesAt(state.crosshairIndex);   // 本地 K 线下标
for (final v in values) {
  // v.scriptId, v.scriptName, v.pane, v.seriesId, v.title, v.value（没有值为 null）, v.color, v.precision
}
```

返回各脚本可见序列在这一根的值，脚本按设置顺序、序列按输出里的顺序。`visible: false`（只当填充边界）和 `legend: false` 的序列不返回；对不上 K 线的脚本不返回。图例和十字光标数值的界面由 App 自己画，图表只在副图左上角写脚本名。

## 点选

传 `onScriptTap` 后，点到标记、策略成交点、标签、线段、水平线、方框时回调。不传时不做点选，点击和原来完全一样。

```dart
KLineChart(
  state: state,
  scriptOutputs: scripts,
  onScriptTap: (hit) {
    // hit.scriptId, hit.kind, hit.index（标记还有 hit.point）, hit.pane
    // hit.time, hit.price（锚点）, hit.time2, hit.price2（线段、方框的另一端）, hit.position（点击位置）
    if (hit.kind == ScriptHitKind.marker) showSignal(hit.time, hit.price);
    if (hit.kind == ScriptHitKind.hline) highlight(hit.output.hlines[hit.index].id);
  },
);
```

| 类型 | 序号 | `id` | 锚点 `time` / `price` | `time2` / `price2` |
|---|---|---|---|---|
| `marker` | `index` 是 `markers` 的组，`point` 是组内的点 | — | 那个点的时间和价位（`top`、`bottom` 位置没有价位，为 null） | — |
| `trade` | `trades` 序号 | 成交的 `id` | 成交时间和成交价 | — |
| `label` | `labels` 序号 | — | `t`、`p` | — |
| `line` | `lines` 序号 | — | `t1`、`p1` | `t2`、`p2` |
| `hline` | `hlines` 序号 | 水平线的 `id` | 时间为 null，价格是 `price` | — |
| `box` | `boxes` 序号 | — | `t1`、`top` | `t2`、`bottom` |

原图元用 `hit.output` 取，例如 `hit.output.labels[hit.index].tooltip`。

- 命中范围：图元画出来的形状再往外放 `scriptHitSlop`（12 逻辑像素）。标记、成交、标签、方框按画出来的外框（含文字，裁在价位区里，被裁掉的部分点不到）；线段、水平线按到线的距离。只看点击所在的窗格（主图或某个脚本副图），曲线、柱、点、填充、背景色、自绘 K 线、表格不参与。
- 几个图元都点到时只回调一个：标记、成交、标签优先于线段、水平线，再优先于方框；同一类里取离得最近的；一样近（比如都压在手指下）取画在上面的，即后设置的脚本、同一脚本里后画的。
- 和其他手势：点击依次交给回放选起点、画线（选了画线工具时落点；点中画线时选中；有画线选中时点空白只取消选中）、常驻的十字光标（显示着时这次点击只关掉它），之后才看脚本图元。点到了就不再触发 `onTradeMarkTap` 和点击唤出十字光标（`CrosshairTrigger.tapOrLongPress`）；没点到时照原来的顺序走。长按、拖动、缩放不受影响。

## 对齐

完全按 SCHEMA「约定」一节：

- 逐根序列（曲线、面积、柱、点、填充、自绘 K 线）以 `bars.to` 那根为锚，往前连续数 `bars.count` 根：第 i 个值画在本地第 `toIndex - (count - 1) + i` 根。不按时间间隔推，所以休市空档不影响。
- 本地也有 `bars.from` 那根时核对两者正好相隔 `count - 1` 根，不对就整份不画（`barsMismatch`）。本地比输出短（没有那么早的 K 线）时照常画，前面的值没有地方画。
- 本地没有 `bars.to` 那一根：不画，回调 `missingLastBar`。本地在 `bars.to` 之后多出几根（实时推来的新 K 线）不影响。
- 输出的 `bars.intervalMs` 和图表当前周期（`KLineChartState.timeFrame`）不一样：不画，回调 `periodMismatch`。
- 对象（线段、方框、标签、标记、成交点、背景色和改色区间）的时间：晚于 `bars.to` 的按「`bars.to` 往右第 k 根」，k = (t − to) / intervalMs 向下取整；早于 `bars.from` 的同理往左；在两者之间的取开盘时间不大于它的最近一根（落在休市空档里的取空档前那根）。
- 末根原地更新（同一开盘时间）不重新对齐；新增一根、往前加载更多时重新对齐。

## 窗格和纵轴

- `pane: main` 的全部图元画在主图，和 K 线共用价格轴。主图价格区间会把可见范围内画在主图上的曲线、面积、点和自绘 K 线算进去（和内置主图指标一样，免得被裁掉）；柱、水平线和各类对象不算进去。
- `pane: sub` 的每个脚本单独一个副图，排在内置副图（`subIndicators`）之后，按设置顺序从上到下。纵轴按这个窗格里可见范围内的序列（柱、面积含基线）、水平线、自绘 K 线和对象（线段、方框、标签、`absolute` 标记）算，上下各留 5%。右轴标最大、最小值，小数位用输出的 `precision`，为空时用图表的 `ChartFormatter`。
- `gaps: "break"` 的曲线和面积（含阶梯线）上，前后都是空值（或在序列开头、结尾，另一侧是空值）的单个值没有线段可画（同 Pine 的 `plot.style_linebr`），不画，也不算进主图价格区间和副图纵轴；面积只剩这种值时基线也不算。`gaps: "connect"` 的曲线和点、柱不受影响。例子：ML 超级趋势第一根是 0、之后 129 根为空，这个 0 不会再把最早一屏的价格轴拉到 0。
- 策略成交点（`trades`）一律画在主图的价格上，不管脚本的 `pane` 是 main 还是 sub，也不计入副图纵轴。
- 单个图元上的 `pane: "main"`：副图脚本里这个图元画到主图，并按主图的规则参与（曲线、面积、点、自绘 K 线）或不参与（其余）主图价格区间，也不计入副图纵轴。支持的图元：`series`、`hlines`、`fills`、`markers`、`candles`、`lines`、`boxes`、`labels`、`tables`、`bg`。没有这个字段、或值是 `"sub"` 时照常画在副图；别的值记一条警告后忽略。主图脚本里这个字段没有作用。取值接口里这类序列的 `pane` 是 main。
- 副图的增删和内置副图一样有 300 ms 的伸缩动画。替换同一个 id 时窗格不动。对不上 K 线时窗格和标题保留、内容不画，等新输出到了再画，免得窗格来回伸缩。
- 表格贴在所属窗格的九个位置之一，不随 K 线滚动。

## 画的顺序

SCHEMA 没规定，参照 TradingView：

1. 主图：背景色在 K 线下面；K 线改色直接改 K 线的颜色；其余图元在 K 线和内置主图指标之上、宿主的 `tradeMarks` 和画线之下。
2. 每个窗格内：填充 → 水平线 → 自绘 K 线 → 序列（按输出顺序）→ 标记 → 成交点 → 方框 → 线段 → 标签 → 表格，最后是右轴的最新值标签（`trackPrice`）。
3. 多个主图脚本按设置顺序，后设置的在上面。K 线改色后设置的覆盖先设置的。

## 各类图元画到什么程度

| 图元 | 支持 | 说明 |
|---|---|---|
| 曲线 | `color`/`colors`、`width`、`style`（实线、虚线、点线）、`step`、`gaps`、`trackPrice` | 两点之间那段用后一点的颜色，颜色 0 的段不画；`gaps: "break"` 时孤立的单个值不画 |
| 面积 | 同曲线，外加 `base` | 填充用线色的 35% 不透明度（SCHEMA 没规定） |
| 柱 | `variant`：histogram 按 `width` 画细柱（不超过 K 线宽的 75%），columns 按 K 线实体宽；`base` | |
| 点 | `shape`：circle、cross；`size` | |
| 填充 | 两条序列、序列和水平线、两条水平线之间；`color`/`colors` | 两条水平线、单色时填满整个窗格宽度；任一边没有值的那根不填 |
| 水平线 | `style`、`width`、`visible` | |
| 标记 | 12 种形状 + `char`；5 种位置；6 档尺寸；`text`、`textColor` | abovebar / belowbar 贴着输出给的最高 / 最低价往外画；labelup / labeldown 画成带箭头的气泡，`text` 在气泡里 |
| 策略成交点 | 一律画在主图；买入三角朝上、卖出朝下，尖在成交价；entry 实心、exit 空心；K 线宽 ≥ 6 时在旁边写 `id` | 颜色取图表的涨跌色（SCHEMA 没给颜色） |
| 背景色 | 主图填满主图高度，副图填满内容区 | |
| K 线改色 | 只在蜡烛模式下生效，分时模式忽略 | |
| 自绘 K 线 | 蜡烛和美国线（`bars: true`）；`color`/`colors` | 影线、实体、边框同色（SCHEMA 没有分开的颜色） |
| 线段 | 6 种 `style`（含三种箭头）、4 种 `extend`、`width` | 竖线延伸时贯穿窗格上下；箭头画在原端点 |
| 方框 | `extend`（左右）、`bg`、边框三种线型、文字的水平 / 竖直对齐和字号 | 文字不换行，超出方框的部分裁掉 |
| 标签 | 9 种气泡（上、下、左、右、居中、四个角）、`none`（只有文字）、10 种形状；`size`、`align`（多行文字的对齐） | `tooltip` 不显示（图表没有悬停） |
| 表格 | 9 个位置、`bg`、`frame`、`border`、每格的字色 / 底色 / 字号 / 水平对齐 | 列宽、行高按内容算；格子里的 `\n` 换行 |

字号按图表坐标轴字号（默认 10）缩放：tiny 0.8、small 1.0、normal 1.2、large 1.5、huge 2.0、auto 1.0。形状半径：tiny 3、small 4.5、normal 6、large 8、huge 11，auto 随 K 线宽度在 2.5～6 之间。标签、方框文字、表格格子的字号也可以是数字（Pine v6 的 `size = 12`，引擎可能写成字符串 `"12"`）：直接当作字号（逻辑像素）；标签的形状样式用它的一半当半径。SCHEMA 还没写这种情况。图元里的文字原样画，不翻译。

## 解析

- 所有数都按 `num` 读再转换：经过 `google.protobuf.Value` + protojson 后，时间可能是 `1795290000000.0` 或 `1.79529e+12`，颜色下标、宽度、行列号、`count` 也可能是 double，一律取整。数字写成字符串（`"900000"`）也认。键的顺序不影响。
- `v` 不是 1（含缺失）：整份不画，`error.code == unsupportedVersion`。缺 `bars`、`palette`、`pane`、`script.id` 或值不对：`invalid`。不是 JSON 对象：`notAnObject`。
- 不认识的字段：跳过，每个字段路径记一条警告。
- 不认识的枚举值：决定「画什么」的（序列的 `kind`、标记的 `shape`、成交点的 `side`）跳过这一个元素；决定「怎么画」的（线型、尺寸、对齐、延伸、位置等）退回默认值。都记警告。
- 颜色下标超出调色板、调色板里不是 `#RRGGBBAA` 的颜色：当作 0（不画），记警告。逐根数组长度和 `bars.count` 不一样：多的截掉、少的补空值，记警告。
- `fills` 引用了不存在的 id：跳过这一条。
- 警告最多记 200 条。

## 性能

- 只画可见范围（两边各多一根）里的逐根数据和对象。
- 每个脚本在每个窗格的图元录成一个 `Picture`，缩放、滚动、窗格高度、价格区间、主题和输出都没变时直接重放。替换一个副图脚本只重录它自己的窗格；替换一个不影响价格区间的主图脚本只重录它自己；十字光标移动、现价跳动不重录。
- 文字排版按（文字, 字号, 颜色, 对齐）缓存，最多 2048 条。
- 测试在 `test/script/benchmark_test.dart`。

## 改了哪些原有代码

都只在传了 `scriptOutputs` 时才生效：

- `KLineChart`：新增参数 `scriptOutputs`；监听控制器；副图脚本的窗格动画；帧末调 `deliverIssues`。
- `ChartLayout.compute`：新增可选参数 `extraMainRange`，主图价格区间额外要容下的数值。
- `ChartRenderer.drawCandles`：新增可选参数 `colorOf`，K 线改色用。
- `KLineChartPainter`：背景色画在 K 线下面，其余主图图元画在主图指标之后、最高最低价标注之前（不传时顺序和原来一样），副图脚本画在内置副图之后、时间轴之前。
- `ChartFrameSource`（内部接口）：新增 `scriptPaneIds`、`scriptPaneWeights`。
- 点选（只在传了 `onScriptTap` 时生效）：`KLineChart` 新增参数 `onScriptTap`；`ChartGestures` 的点击在关掉十字光标之后、买卖标记之前先问脚本图元。

## 没做的、和 SCHEMA 不一致的

- 增量更新（`tail`）：引擎目前只发整份，没做。
- `tooltip`：图表没有悬停，不显示。
- `inputs`：解析成 `ScriptInput` 给 App 的参数面板用，图表不用。
- 画到主图的对象（线段、方框、标签、标记）不进主图价格区间，超出可见 K 线价格范围的部分会被裁掉。例如 `com-macd-with-htf-panels-...` 画在最后一根右边的大周期面板，价格在 3424～3709，比可见 K 线的范围宽，面板上下会被截断；`com-trend-exhaustion-...` 的大方框也会超出上沿。
- 数字字号：SCHEMA 只列了 tiny～auto，真样本里有 `"12"`、`"4"`、`"6"`，图表按字号处理（见上）。
- 图例、十字光标数值的界面不做，只提供 `valuesAt`。

## 和图表工具一起用

- 对数坐标（`logScale`）：画在主图上的图元（含副图脚本里标了 `pane: "main"` 的）按对数换算；主图价格区间只算正数，曲线里的 0 不会把轴拉下去。副图纵轴不变。
- K 线回放（`replay`）：图元仍按完整数据对齐，只画到游标为止，跨过游标的方框、线段从游标右沿裁掉，表格照常画。游标之前的部分是按全量数据算的，可能带未来信息，受影响的图元见 `CHART_TOOLS.md`。
- 图表类型：五种类型下图元都照常画；K 线改色只对蜡烛图和美国线生效。

## 测试

| 文件 | 内容 |
|---|---|
| `test/script/parse_test.dart` | 24 份真输出逐类核对；数字字号；protojson 版（double、科学计数法、键乱序）解析结果和原版逐字段相同；不认识的字段和枚举、`v` 不对、缺字段、坏颜色、长度不对 |
| `test/script/align_test.dart` | 期望下标用线性扫描独立算，期望像素用公式独立算：真样本全部对象的下标；休市空档、越过最后一根、早于第一根；本地缺 `bars.to`、根数对不上、周期对不上、本地比输出短、实时新 K 线；从渲染出的图片里找线和点的像素位置（误差 0.5 像素以内） |
| `test/script/render_golden_test.dart` | 21 张参考图：每类图元一张、全部样式两张、3 主图 + 2 副图深浅各一张、多个主图脚本叠加、和内置副图并存的横屏 |
| `test/script/pane_test.dart` | 副图策略 `st-macd` 的成交点画在主图对应 K 线和价格上（像素核对）、副图里没有、副图纵轴只按自己的序列；手写合成样本里十类图元标 `pane: "main"` 时的解析、画的位置、主图价格区间、副图纵轴、取值接口的 `pane`；主图脚本里这个字段没有作用；2 张参考图 |
| `test/script/real_pane_test.dart` | 用服务端脚本引擎修复 display 和 force_overlay 后的真样本：6 个副图脚本的副图纵轴（全部 1000 根）和引擎输出里各窗格的数值范围一致；画到主图的曲线和自绘 K 线不超出 K 线范围；趋势衰竭的方框、标记、表格，已实现方差的自绘 K 线，大周期面板的线段，卡尔曼滤波的曲线、圆点标签、背景色和表格都画在主图，位置用「同一份输出渲染两次、只把目标图元改成不画、取差异」的办法和独立公式核对 |
| `test/script/lone_value_test.dart` | 断开曲线上的孤立值：开头、中间、结尾都不画、不算进主图价格区间和副图纵轴；面积和阶梯线同样处理；`connect` 曲线和点不受影响；ML 超级趋势真样本滚到最早一屏时价格轴不再到 0 |
| `test/script/update_test.dart` | 替换副图脚本只重录它的窗格；替换主图脚本只重录受影响的；十字光标不重录；替换后下一帧就是新内容；移除副图收起窗格；末根原地更新不重新对齐 |
| `test/script/script_tap_test.dart` | 点选：六类图元的类型、序号、锚点和点击位置，脚本副图；外放范围的边界；标记压在方框里、水平线穿过方框、两条水平线、两个标签、两个脚本重叠时选哪个；不传回调、点空白、常驻十字光标、长按、画线工具、画线和脚本水平线重合、买卖标记时的先后；传不传回调画面逐像素一样 |
| `test/script/benchmark_test.dart` | 解析耗时、500 个标签首次排版、一帧的绘制耗时 |
| `test/baseline/script_off_golden_test.dart` | 空控制器、设置了输出但隐藏：7 个场景都和基线 9d3ee15 的参考图逐像素一致 |

样本和来源见 `testdata/primitives/SOURCE.md`。`test/script/screenshots_tool.dart` 用真字体出截图给人看（`SHOTS_DIR=<目录> flutter test test/script/screenshots_tool.dart`），不是测试。
