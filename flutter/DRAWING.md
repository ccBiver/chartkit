# 画线工具

chartkit_flutter 的画线功能：12 个工具、选中、拖动、锁定、删除、按品种保存。默认关闭，
`KLineChart` 不传 `drawingController` 时界面和手势与原来完全一样。工具栏、样式面板、选中后的浮层都由调用方自己做，
库只提供控制接口。

## 工具

| 工具 | 枚举 | 新建点数 | 说明 |
|---|---|---|---|
| 水平线 | `horizontalLine` | 1 | 横贯主图，右端标价格 |
| 垂直线 | `verticalLine` | 1 | 竖贯主图 |
| 趋势线 | `trendLine` | 2 | 两点之间的线段 |
| 射线 | `ray` | 2 | 从第 1 点穿过第 2 点延到图边 |
| 矩形 | `rectangle` | 2 | 两个对角 |
| 斐波那契回撤 | `fibRetracement` | 2 | 第 1 点是 1，第 2 点是 0；显示哪几档可改 |
| 价格区间测量 | `priceRange` | 2 | 显示价差、涨跌幅、跨过的根数 |
| 多头头寸 | `longPosition` | 2 | 第 1 点入场，第 2 点定目标；止损按 1:1 自动放在另一侧，之后可拖。显示入场、目标、止损和盈亏比 |
| 空头头寸 | `shortPosition` | 2 | 同上，方向相反 |
| 江恩扇形 | `gannFan` | 2 | 9 条角度线（1×8 到 8×1），1×1 线穿过第 2 点 |
| 安德鲁分叉 | `pitchfork` | 3 | 中线从第 1 点穿过后两点的中点，两条叉线与中线平行 |
| 艾略特波浪 | `elliottWave` | 6 | 0 到 5 六个转折点连成折线并编号 |

几何算法参照 omen 的 `kline-pro/src/chart/drawings.ts`。

## 接入

```dart
final drawings = DrawingController(
  style: DrawingStyle(color: colors.primary),   // 新建画线的颜色和线宽，必须由调用方给
  onChanged: () => storage.save(symbol, jsonEncode(drawings.toJson())),
);

KLineChart(
  state: state,
  drawingController: drawings,
  drawingTheme: DrawingTheme(profit: colors.up, loss: colors.down),  // 可省，省掉的取图表主题
  drawingLabels: DrawingLabels(entry: s.entry, target: s.target, stop: s.stop,
      riskReward: s.riskReward, bars: s.bars),                       // 可省，默认英文
)
```

`DrawingController` 是 `ChangeNotifier`，用完要 `dispose()`。工具栏可以直接监听它刷新。

## 控制接口

| 接口 | 作用 |
|---|---|
| `tool` | 当前工具，读写。设成某个工具进入新建；设成 null 退出新建。切工具会放弃没点完的画线、取消选中，并自动打开显示 |
| `draft` | 新建中已经点下的点。工具栏可以据此提示「点第几个点」 |
| `cancelDraft()` | 放弃没点完的画线，工具不变 |
| `visible` | 是否显示全部画线，读写。关掉后画线不画、点不中，数据保留 |
| `clear()` | 清除全部画线 |
| `drawings` | 全部画线，按绘制顺序，后画的在上 |
| `selectedId` / `selected` | 选中的画线 |
| `select(id)` | 选中，传 null 取消选中 |
| `remove(id)` / `removeSelected()` | 删除 |
| `setLocked(id, bool)` | 锁定、解锁。锁定后不能拖，仍可选中、删除、改样式 |
| `setStyle(id, DrawingStyle)` | 改颜色、线宽 |
| `setFibLevels(id, levels)` | 改斐波那契显示的档位。可选档位见 `allFibLevels`，默认 `defaultFibLevels` |
| `style` / `fibLevels` | 新建画线用的样式和斐波那契档位 |
| `magnet` / `magnetRadius` | 新建时的吸附开关和半径，默认开、20 逻辑像素 |
| `selectionBounds` | 选中项在图上的范围（相对图表左上角，已裁到主图内），用来摆放「样式 / 锁定 / 删除」浮层；没有选中或不在可视区时为 null |
| `toJson()` / `loadJson(json)` | 序列化和恢复 |
| `onChanged` | 需要保存时回调 |
| `add(drawing)` | 直接加一条画线 |

`addDraftPoint`、`setDraftPreview`、`replaceDuringEdit`、`commitEdit`、`updateSelectionBounds` 是给图表内部用的，调用方不用调。

## 手势

| 状态 | 操作 | 结果 |
|---|---|---|
| 选了工具 | 单击主图 | 落一个点，点数够了就生成画线、选中它、退出工具 |
| 选了工具 | 长按后拖动 | 先显示预览，松手落点。这时长按不唤出十字光标 |
| 选了工具 | 横拖、双指缩放 | 照常移动、缩放图表 |
| 没选工具 | 单击画线 | 选中，端点出现圆点 |
| 没选工具 | 单击空白 | 有选中时取消选中；没有选中时交给图表（十字光标等原有行为） |
| 有选中 | 按住它的端点拖 | 改形状 |
| 有选中 | 按住它的线身或填充区拖 | 整体移动。时间方向按整根 K 线移，价格方向跟手 |
| 有选中 | 按在别处拖 | 照常移动图表 |
| 选中的已锁定 | 拖 | 不动，按图表原有手势处理 |

只有已选中的画线能拖：先点选，再拖。这样大面积的画线（矩形、斐波那契）不会挡住平常的拖动看图。
按在选中画线上时画线立即接手这次触摸，图表不滚动，外层页面也不会上下滚；代价是这次触摸里再放第二根手指不会缩放。

新建时落点吸到最近一根 K 线的中心；离这根的开高低收在 `magnetRadius` 以内时价格吸过去。拖端点时时间也吸到 K 线，价格不吸。
落点在主图之外（量图、副图、右侧价格轴）的单击不落点。

## 坐标和切周期

锚点存 K 线开盘时间（毫秒）和价格，不存屏幕坐标，所以缩放、平移后画线跟着 K 线走。

时间换成横坐标的规则：每根 K 线的开盘时间对着它的中心（和时间轴标签一致），两根之间按时间线性插值，数据范围之外按
`state.timeFrame.millis` 外推。所以：

- 当前周期画的点都在 K 线中心上。
- 别的周期画的点按时间落位。1 分钟图上 10:37 的点，在 1 小时图上落在 10:00 和 11:00 两根之间的 37/60 处，切回 1 分钟图回到原处。
- 休市跳空时，跳空两侧两根之间也按时间插值。
- 右侧留白区可以落点，时间按周期往后推。宿主要保证 `KLineChartState.timeFrame` 和数据周期一致（调 `changeTimeFrame`），
  否则留白区的点会按错误的周期换算。

## 保存和恢复

```dart
// 保存（onChanged 里）
final json = jsonEncode(drawings.toJson());
// 换品种
drawings.loadJson(saved == null ? null : jsonDecode(saved));
```

格式：

```json
{
  "version": 1,
  "drawings": [
    {"id": "m3k1x2-0", "tool": "trendLine", "points": [[1764756000000, 3537.22], [1764759600000, 3551.4]],
     "color": 4282090230, "width": 1},
    {"id": "m3k1x2-1", "tool": "fibRetracement", "points": [[...], [...]], "color": 4293953568, "width": 1,
     "locked": true, "fib": [0, 0.382, 0.5, 0.618, 1]}
  ]
}
```

- `tool` 存枚举名，`DrawingTool` 只能往后加，不能改名。
- `points` 是 `[开盘时间毫秒, 价格]`。多头/空头头寸存 3 个点：入场、目标、止损。
- `color` 是 ARGB 整数。
- `loadJson` 跳过认不出的条目（工具名不认识、点数不对、字段类型不对），不报错。`loadJson` 不触发 `onChanged`。

`onChanged` 在新建完成、删除、清除、拖动松手、改样式、锁定时调用；选中、切工具、拖动过程中不调用。

## 绘制

画在主图矩形内（不压右侧价格轴、量图、副图），顺序是：K 线和主图指标 → 画线 → `overlayPainter` → 现价线 → 十字光标。
所以挂单线、持仓线这些宿主图层在画线之上，现价标签和十字光标不会被画线盖住。

颜色：

- 线的颜色、线宽在每条画线的 `DrawingStyle` 里，新建时取 `controller.style`。库里不设默认色。
- `DrawingTheme` 管几种公共颜色：盈利区（默认取主题涨色）、亏损区（跌色）、端点圆点填充（背景色）、色块上的文字（现价标签文字色）。
- 填充用线色加透明度：矩形 12%，斐波那契档位之间 5%/10% 交替，测量 14%，头寸 15%，安德鲁分叉 6%。

文字字号取主题的 `axisTextSize`，价格用 `formatter.price` 格式化。

## 横屏和尺寸

画线全部按当前布局换算，不依赖固定尺寸。横屏、窄屏、加减副图后都按新的主图矩形重画。

## 对现有代码的改动

| 文件 | 改动 |
|---|---|
| `lib/src/chart/k_line_chart.dart` | 加 3 个可选参数 `drawingController`、`drawingTheme`、`drawingLabels`；监听控制器重绘；帧末更新 `selectionBounds`。传了控制器时，手势外面多包一层 `RawGestureDetector`（拖选中画线），单击和长按先问画线；不传时走原来的 `GestureDetector`，代码路径不变 |
| `lib/src/chart/chart_painter.dart` | `ChartPaintConfig` 加可选字段 `drawing`；不为空时在时间轴之后、`overlayPainter` 之前画画线 |
| `lib/chartkit_flutter.dart` | 导出画线相关的类 |

新增文件都在 `lib/src/drawing/`：

| 文件 | 内容 |
|---|---|
| `drawing.dart` | `DrawingTool`、`DrawingAnchor`、`DrawingStyle`、`Drawing`，JSON 序列化 |
| `drawing_controller.dart` | `DrawingController` |
| `drawing_geometry.dart` | 时间换算、坐标换算、各工具几何、编辑（拖端点、平移）、命中判断。纯计算，单元测试覆盖 |
| `drawing_painter.dart` | 画到画布上 |
| `drawing_gestures.dart` | 手势分派和拖动识别器 |
| `drawing_theme.dart` | `DrawingTheme`、`DrawingLabels` |

## 没做的

- 工具栏、样式面板、选中后的浮层（设计稿⑥⑦⑧的界面），由 App 侧做。
- 画线不进副图，只画在主图。
- 多选、撤销重做、复制画线。
- 后端算的指标的图元渲染。

## 示例和测试

示例 App（`example/lib/main.dart`）的第一行工具栏演示 12 个工具、显示开关、清除、恢复，选中后可以锁定、删除、换色、改线宽、改斐波那契档位。

测试在 `test/drawing/`：

- `drawing_geometry_test.dart`：时间换算（含跳空、外推、跨周期）、坐标换算、吸附、各工具几何、头寸和测量的数值、拖端点和平移、命中判断。
- `drawing_model_test.dart`：12 个工具的 JSON 往返、坏数据跳过、控制器的新建、删除、清除、锁定、改样式、显示开关、保存回调。
- `drawing_chart_test.dart`：在图表上点出 12 个工具、吸附、长按预览、选中和取消、拖端点、拖整体、锁定后拖不动、拖别处照常滚动、
  删除和清除、隐藏后点不中、没选工具时长按仍出十字光标、切周期后位置不变、横屏、放在列表里拖画线页面不滚动、去掉控制器后不报错。
