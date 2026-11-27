import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';

/// 支持的图元格式版本（图元格式 SCHEMA 的 `v`）。
const int scriptSchemaVersion = 1;

/// 图元画在哪个窗格：主图（叠在 K 线上、共用价格轴）或单独的副图。
enum ScriptPane { main, sub }

/// 逐根序列的画法。
enum ScriptSeriesKind { line, area, bar, dots }

/// 线型（序列、水平线、方框边框）。
enum ScriptLineStyle { solid, dashed, dotted }

/// 线段的线型，比 [ScriptLineStyle] 多三种箭头。
enum ScriptSegmentStyle { solid, dashed, dotted, arrowLeft, arrowRight, arrowBoth }

/// 线段、方框往哪边延伸到图表边缘。
enum ScriptExtend { none, left, right, both }

/// 柱子的粗细：histogram 细柱（按线宽），columns 粗柱（按 K 线实体宽）。
enum ScriptBarVariant { histogram, columns }

enum ScriptDotShape { circle, cross }

/// 标记（plotshape / plotchar / plotarrow）的形状。[char] 是 plotchar，画 `char` 字段里的字符。
enum ScriptMarkerShape {
  triangleup,
  triangledown,
  circle,
  cross,
  xcross,
  diamond,
  square,
  arrowup,
  arrowdown,
  flag,
  labelup,
  labeldown,
  char,
}

/// 标记的纵向位置。
enum ScriptMarkerLocation { abovebar, belowbar, absolute, top, bottom }

/// 文字、标记的尺寸档位。
enum ScriptSize { tiny, small, normal, large, huge, auto }

/// 标签样式：带箭头的气泡、只有文字（[none]）、或画在锚点上的形状。
enum ScriptLabelStyle {
  labelUp,
  labelDown,
  labelLeft,
  labelRight,
  labelCenter,
  labelUpperLeft,
  labelUpperRight,
  labelLowerLeft,
  labelLowerRight,
  none,
  circle,
  square,
  diamond,
  triangleup,
  triangledown,
  arrowup,
  arrowdown,
  cross,
  xcross,
  flag,
}

/// 标签的纵坐标来源。abovebar / belowbar 时服务端已把价格换成那根的最高 / 最低价。
enum ScriptYLoc { price, abovebar, belowbar }

enum ScriptHAlign { left, center, right }

enum ScriptVAlign { top, center, bottom }

/// 表格贴在窗格的哪个位置。
enum ScriptTablePosition {
  topLeft,
  topCenter,
  topRight,
  middleLeft,
  middleCenter,
  middleRight,
  bottomLeft,
  bottomCenter,
  bottomRight,
}

enum ScriptTradeSide { buy, sell }

enum ScriptTradeKind { entry, exit }

/// 逐根序列的对齐信息：第 i 个值对应本地 K 线里从 [from] 那根起往后数第 i 根，[to] 是最后一根。
@immutable
class ScriptBars {
  const ScriptBars({
    required this.from,
    required this.to,
    required this.count,
    required this.intervalMs,
  });

  final int from;
  final int to;
  final int count;
  final int intervalMs;

  @override
  String toString() => 'ScriptBars($from..$to, $count, ${intervalMs}ms)';
}

/// 一条逐根序列（曲线 / 面积 / 柱 / 点）。[values] 里没有值的位置是 NaN。
class ScriptSeries {
  ScriptSeries({
    required this.id,
    required this.kind,
    required this.title,
    required this.visible,
    required this.color,
    required this.colors,
    required this.values,
    required this.width,
    required this.style,
    required this.step,
    required this.breakGaps,
    required this.base,
    required this.variant,
    required this.shape,
    required this.size,
    required this.trackPrice,
    required this.legend,
    this.mainPane = false,
  });

  /// 副图脚本里这个图元画到主图（元素上的 `pane: "main"`）。主图脚本里没有作用。
  final bool mainPane;

  final String id;
  final ScriptSeriesKind kind;
  final String title;

  /// false 的只给填充当边界，不画、不进图例。
  final bool visible;

  /// 全程一个颜色时的调色板下标（[colors] 为空时用）。
  final int color;

  /// 逐根颜色下标，长度等于 `bars.count`；为空表示全程用 [color]。
  final Uint16List? colors;
  final Float64List values;
  final double width;
  final ScriptLineStyle style;

  /// 阶梯线。
  final bool step;

  /// true：在没有值的地方断开；false：跨过去连上。
  final bool breakGaps;

  /// 面积、柱子的基线。
  final double base;
  final ScriptBarVariant variant;
  final ScriptDotShape shape;
  final double size;

  /// 在右侧价格轴标出最新值。
  final bool trackPrice;

  /// 是否进图例（取值接口里会带上它）。
  final bool legend;

  /// 第 [i] 个值的颜色下标。
  int colorAt(int i) {
    final c = colors;
    return c == null ? color : (i >= 0 && i < c.length ? c[i] : 0);
  }
}

/// 水平线。
@immutable
class ScriptHLine {
  const ScriptHLine({
    required this.id,
    required this.title,
    required this.price,
    required this.color,
    required this.style,
    required this.width,
    required this.visible,
    this.mainPane = false,
  });

  /// 副图脚本里这个图元画到主图（元素上的 `pane: "main"`）。主图脚本里没有作用。
  final bool mainPane;

  final String id;
  final String title;
  final double price;
  final int color;
  final ScriptLineStyle style;
  final double width;

  /// false 的只给填充当边界。
  final bool visible;
}

/// 两条序列（或水平线）之间的填充。
class ScriptFill {
  ScriptFill(
      {required this.a,
      required this.b,
      required this.color,
      required this.colors,
      this.mainPane = false});

  /// 副图脚本里这个图元画到主图（元素上的 `pane: "main"`）。主图脚本里没有作用。
  final bool mainPane;

  /// `between` 里两项的 id。
  final String a;
  final String b;
  final int color;
  final Uint16List? colors;

  int colorAt(int i) {
    final c = colors;
    return c == null ? color : (i >= 0 && i < c.length ? c[i] : 0);
  }
}

/// 一组标记。点按 [times] / [prices] / [colors] 平行存放。
class ScriptMarkers {
  ScriptMarkers({
    required this.title,
    required this.shape,
    required this.location,
    required this.size,
    required this.char,
    required this.text,
    required this.textColor,
    required this.times,
    required this.prices,
    required this.colors,
    this.mainPane = false,
  });

  /// 副图脚本里这个图元画到主图（元素上的 `pane: "main"`）。主图脚本里没有作用。
  final bool mainPane;

  final String title;
  final ScriptMarkerShape shape;
  final ScriptMarkerLocation location;
  final ScriptSize size;
  final String? char;
  final String? text;
  final int textColor;
  final Int64List times;

  /// top / bottom 时为 NaN。
  final Float64List prices;
  final Uint16List colors;

  int get length => times.length;
}

/// 策略成交点。
@immutable
class ScriptTrade {
  const ScriptTrade({
    required this.time,
    required this.price,
    required this.side,
    required this.kind,
    required this.qty,
    required this.id,
    required this.comment,
  });

  final int time;
  final double price;
  final ScriptTradeSide side;
  final ScriptTradeKind kind;
  final double qty;
  final String id;
  final String? comment;
}

/// 一段同色的 K 线区间（背景色、K 线改色），两端都含。
@immutable
class ScriptRun {
  const ScriptRun(this.t1, this.t2, this.color);

  final int t1;
  final int t2;
  final int color;
}

/// 一组背景色区间。
@immutable
class ScriptBackground {
  const ScriptBackground(this.runs, {this.mainPane = false});

  final List<ScriptRun> runs;

  /// 副图脚本里这组背景色画到主图（`pane: "main"`）。主图脚本里没有作用。
  final bool mainPane;
}

/// 脚本自己画的 K 线（plotcandle / plotbar）。
class ScriptCandles {
  ScriptCandles({
    required this.title,
    required this.bars,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.color,
    required this.colors,
    this.mainPane = false,
  });

  /// 副图脚本里这个图元画到主图（元素上的 `pane: "main"`）。主图脚本里没有作用。
  final bool mainPane;

  final String title;

  /// true 是美国线（plotbar），否则是蜡烛。
  final bool bars;
  final Float64List open;
  final Float64List high;
  final Float64List low;
  final Float64List close;
  final int color;
  final Uint16List? colors;

  int colorAt(int i) {
    final c = colors;
    return c == null ? color : (i >= 0 && i < c.length ? c[i] : 0);
  }
}

/// 线段。
@immutable
class ScriptSegment {
  const ScriptSegment({
    required this.t1,
    required this.p1,
    required this.t2,
    required this.p2,
    required this.extend,
    required this.color,
    required this.style,
    required this.width,
    this.mainPane = false,
  });

  /// 副图脚本里这个图元画到主图（元素上的 `pane: "main"`）。主图脚本里没有作用。
  final bool mainPane;

  final int t1;
  final double p1;
  final int t2;
  final double p2;
  final ScriptExtend extend;
  final int color;
  final ScriptSegmentStyle style;
  final double width;
}

/// 方框里的文字。
@immutable
class ScriptBoxText {
  const ScriptBoxText({
    required this.text,
    required this.color,
    required this.size,
    this.points,
    required this.halign,
    required this.valign,
  });

  final String text;
  final int color;
  final ScriptSize size;

  /// 脚本直接写的字号（Pine v6 允许 `size = 12`，单位是点）；有它时不看 [size]。
  final double? points;
  final ScriptHAlign halign;
  final ScriptVAlign valign;
}

/// 方框。
@immutable
class ScriptBox {
  const ScriptBox({
    required this.t1,
    required this.top,
    required this.t2,
    required this.bottom,
    required this.extend,
    required this.bg,
    required this.borderColor,
    required this.borderWidth,
    required this.borderStyle,
    required this.text,
    this.mainPane = false,
  });

  /// 副图脚本里这个图元画到主图（元素上的 `pane: "main"`）。主图脚本里没有作用。
  final bool mainPane;

  final int t1;
  final double top;
  final int t2;
  final double bottom;
  final ScriptExtend extend;
  final int bg;
  final int borderColor;
  final double borderWidth;
  final ScriptLineStyle borderStyle;
  final ScriptBoxText? text;
}

/// 标签。
@immutable
class ScriptLabel {
  const ScriptLabel({
    required this.time,
    required this.price,
    required this.yloc,
    required this.text,
    required this.style,
    required this.color,
    required this.textColor,
    required this.size,
    this.points,
    required this.align,
    required this.tooltip,
    this.mainPane = false,
  });

  /// 副图脚本里这个图元画到主图（元素上的 `pane: "main"`）。主图脚本里没有作用。
  final bool mainPane;

  final int time;

  /// abovebar / belowbar 且那根不在服务端数据里时为 NaN（不画）。
  final double price;
  final ScriptYLoc yloc;
  final String text;
  final ScriptLabelStyle style;

  /// 气泡底色。
  final int color;
  final int textColor;
  final ScriptSize size;

  /// 脚本直接写的字号（Pine v6 允许 `size = 12`，单位是点）；有它时不看 [size]。
  final double? points;
  final ScriptHAlign align;
  final String? tooltip;
}

/// 表格的一格。
@immutable
class ScriptTableCell {
  const ScriptTableCell({
    required this.column,
    required this.row,
    required this.text,
    required this.textColor,
    required this.bg,
    required this.size,
    this.points,
    required this.halign,
  });

  final int column;
  final int row;
  final String text;
  final int textColor;
  final int bg;
  final ScriptSize size;

  /// 脚本直接写的字号（Pine v6 允许 `size = 12`，单位是点）；有它时不看 [size]。
  final double? points;
  final ScriptHAlign halign;
}

/// 表格。不随 K 线滚动，贴在所属窗格的 [position]。
@immutable
class ScriptTable {
  const ScriptTable({
    required this.position,
    required this.columns,
    required this.rows,
    required this.bg,
    required this.frameColor,
    required this.frameWidth,
    required this.borderColor,
    required this.borderWidth,
    required this.cells,
    this.mainPane = false,
  });

  /// 副图脚本里这个图元画到主图（元素上的 `pane: "main"`）。主图脚本里没有作用。
  final bool mainPane;

  final ScriptTablePosition position;
  final int columns;
  final int rows;
  final int bg;
  final int frameColor;
  final double frameWidth;
  final int borderColor;
  final double borderWidth;
  final List<ScriptTableCell> cells;
}

/// 参数定义（给 App 的参数面板用，图表本身不用）。
@immutable
class ScriptInput {
  const ScriptInput({
    required this.id,
    required this.type,
    required this.title,
    required this.defaultValue,
    required this.min,
    required this.max,
    required this.step,
    required this.options,
    required this.group,
    required this.tooltip,
  });

  final String id;

  /// int、float、bool、string、source、color、timeframe、text；不认识的原样保留。
  final String type;
  final String title;
  final Object? defaultValue;
  final double? min;
  final double? max;
  final double? step;
  final List<Object?>? options;
  final String? group;
  final String? tooltip;
}

/// 一个脚本的一份完整输出（SCHEMA v1）。不可变；可以在后台 isolate 里解析后传回来。
class ScriptOutput {
  ScriptOutput({
    required this.scriptId,
    required this.scriptName,
    required this.symbol,
    required this.period,
    required this.pane,
    required this.precision,
    required this.bars,
    required this.palette,
    required this.series,
    required this.hlines,
    required this.fills,
    required this.markers,
    required this.trades,
    required this.bg,
    required this.barColors,
    required this.candles,
    required this.lines,
    required this.boxes,
    required this.labels,
    required this.tables,
    required this.inputs,
    required this.engineWarnings,
    this.ext,
  });

  final String scriptId;
  final String scriptName;
  final String symbol;
  final String period;
  final ScriptPane pane;

  /// 脚本声明的小数位；null 表示跟随品种（用图表的 `ChartFormatter`）。
  final int? precision;
  final ScriptBars bars;

  /// 调色板；下标 0 和解析失败的颜色是 null（不画）。
  final List<Color?> palette;
  final List<ScriptSeries> series;
  final List<ScriptHLine> hlines;
  final List<ScriptFill> fills;
  final List<ScriptMarkers> markers;
  final List<ScriptTrade> trades;

  /// 每项是一组背景色区间。
  final List<ScriptBackground> bg;

  /// 每项是一组 K 线改色区间。
  final List<List<ScriptRun>> barColors;
  final List<ScriptCandles> candles;
  final List<ScriptSegment> lines;
  final List<ScriptBox> boxes;
  final List<ScriptLabel> labels;
  final List<ScriptTable> tables;
  final List<ScriptInput> inputs;

  /// 引擎自己的警告（调试用，App 不显示）。
  final List<String> engineWarnings;

  /// 宿主自己的附加数据：输出顶层 `ext` 的原值（JSON 解码后的对象、数组、字符串或数字），没有时为 null。
  /// 图表不读、不校验，里面的键也不记「不认识的字段」警告。
  final Object? ext;

  /// 调色板下标 → 颜色；0、越界都返回 null（不画）。
  Color? colorOf(int index) => index > 0 && index < palette.length ? palette[index] : null;
}

/// 整份输出画不了的原因。
enum ScriptOutputErrorCode {
  /// 顶层不是 JSON 对象，或字符串不是合法 JSON。
  notAnObject,

  /// `v` 不是 [scriptSchemaVersion]。
  unsupportedVersion,

  /// 缺了画图必须的字段（`bars`、`palette`、`pane`、`script.id`），或它们的值不对。
  invalid,
}

@immutable
class ScriptOutputError {
  const ScriptOutputError(this.code, this.message);

  final ScriptOutputErrorCode code;
  final String message;

  @override
  String toString() => 'ScriptOutputError(${code.name}): $message';
}

/// 解析结果：成功时 [output] 非空；[warnings] 是跳过的字段、不认识的枚举值等，不影响其余部分。
@immutable
class ScriptParseResult {
  const ScriptParseResult._(this.output, this.error, this.warnings);

  final ScriptOutput? output;
  final ScriptOutputError? error;
  final List<String> warnings;

  bool get ok => output != null;
}

/// 解析 SCHEMA v1 的图元 JSON。[json] 可以是 JSON 字符串、`jsonDecode` 的结果。
///
/// 所有数都按 `num` 读：经过 protobuf `Value` 的 JSON 里整数会变成 double
/// （`1795290000000.0`、`1.79529e+12`），这里一律取整。不认识的字段、不认识的枚举值记一条警告后跳过。
/// 纯函数，没有用到 Flutter 绑定，可以放进 `Isolate.run`。
ScriptParseResult parseScriptOutput(Object? json) {
  if (json is String) {
    try {
      json = jsonDecode(json);
    } on FormatException catch (e) {
      return ScriptParseResult._(null,
          ScriptOutputError(ScriptOutputErrorCode.notAnObject, 'not JSON: ${e.message}'), const []);
    }
  }
  final p = _Parser();
  try {
    final out = p.parse(json);
    return ScriptParseResult._(out, null, List.unmodifiable(p.warnings));
  } on ScriptOutputError catch (e) {
    return ScriptParseResult._(null, e, List.unmodifiable(p.warnings));
  }
}

// ───────────────────────── 解析 ─────────────────────────

const _topKeys = {
  'v', 'script', 'symbol', 'period', 'pane', 'precision', 'bars', 'palette', 'series', 'hlines', //
  'fills', 'markers', 'trades', 'bg', 'barColors', 'candles', 'lines', 'boxes', 'labels', 'tables',
  'inputs', 'warnings',
  // 留给宿主的附加数据，原样放进 ScriptOutput.ext，不解析
  'ext',
};
const _seriesKeys = {
  'pane',
  'id', 'kind', 'title', 'visible', 'color', 'colors', 'values', 'width', 'style', 'step', //
  'gaps', 'base', 'variant', 'shape', 'size', 'trackPrice', 'legend',
};
const _hlineKeys = {'pane', 'id', 'title', 'price', 'color', 'style', 'width', 'visible'};
const _fillKeys = {'pane', 'between', 'color', 'colors'};
const _markerKeys = {
  'pane',
  'title', 'shape', 'location', 'size', 'char', 'text', 'textColor', 'points', //
};
const _tradeKeys = {'t', 'price', 'side', 'kind', 'qty', 'id', 'comment'};
const _runsKeys = {'runs'};
const _bgKeys = {'runs', 'pane'};
const _candleKeys = {'pane', 'title', 'bars', 'open', 'high', 'low', 'close', 'color', 'colors'};
const _lineKeys = {'pane', 't1', 'p1', 't2', 'p2', 'extend', 'color', 'style', 'width'};
const _boxKeys = {'pane', 't1', 'top', 't2', 'bottom', 'extend', 'bg', 'border', 'text'};
const _borderKeys = {'color', 'width', 'style'};
const _boxTextKeys = {'text', 'color', 'size', 'halign', 'valign'};
const _labelKeys = {
  'pane',
  't', 'p', 'yloc', 'text', 'style', 'color', 'textColor', 'size', 'align', 'tooltip', //
};
const _tableKeys = {'pane', 'position', 'columns', 'rows', 'bg', 'frame', 'border', 'cells'};
const _frameKeys = {'color', 'width'};
const _inputKeys = {
  'id', 'type', 'title', 'default', 'min', 'max', 'step', 'options', 'group', 'tooltip', //
};

/// 枚举的 JSON 名：下划线写法（label_up）转成 Dart 名（labelUp）后比较。
Map<String, T> _names<T extends Enum>(List<T> values) {
  String snake(String s) => s.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');
  return {for (final v in values) snake(v.name): v};
}

final _kinds = _names(ScriptSeriesKind.values);
final _lineStyles = _names(ScriptLineStyle.values);
final _segmentStyles = _names(ScriptSegmentStyle.values);
final _extends = _names(ScriptExtend.values);
final _variants = _names(ScriptBarVariant.values);
final _dotShapes = _names(ScriptDotShape.values);
final _markerShapes = _names(ScriptMarkerShape.values);
final _locations = _names(ScriptMarkerLocation.values);
final _sizes = _names(ScriptSize.values);
final _labelStyles = _names(ScriptLabelStyle.values);
final _ylocs = _names(ScriptYLoc.values);
final _hAligns = _names(ScriptHAlign.values);
final _vAligns = _names(ScriptVAlign.values);
final _positions = _names(ScriptTablePosition.values);
final _sides = _names(ScriptTradeSide.values);
final _tradeKinds = _names(ScriptTradeKind.values);

class _Parser {
  final List<String> warnings = [];
  final Set<String> _unknownKeys = {};
  int _count = 0;
  int _paletteLength = 0;

  Never _fail(ScriptOutputErrorCode code, String message) => throw ScriptOutputError(code, message);

  void _warn(String message) {
    // 几千个点里同一种问题只记前几条，免得警告本身比数据还大
    if (warnings.length < 200) warnings.add(message);
  }

  void _checkKeys(Map m, Set<String> known, String where) {
    for (final k in m.keys) {
      if (known.contains(k)) continue;
      if (_unknownKeys.add('$where.$k')) _warn('unknown field $where.$k ignored');
    }
  }

  // ---- 基本类型：数一律按 num 读 ----

  static num? _numOrNull(Object? v) {
    if (v is num) return v;
    if (v is String) return num.tryParse(v);
    return null;
  }

  double? _double(Object? v) {
    final n = _numOrNull(v);
    return n == null || !n.isFinite ? null : n.toDouble();
  }

  int? _int(Object? v) {
    final n = _numOrNull(v);
    return n == null || !n.isFinite ? null : n.round();
  }

  String _str(Object? v, [String fallback = '']) => v is String ? v : (v == null ? fallback : '$v');

  String? _strOrNull(Object? v) => v is String ? v : (v == null ? null : '$v');

  bool _bool(Object? v, bool fallback) => v is bool ? v : fallback;

  List _list(Object? v, String where) {
    if (v == null) return const [];
    if (v is List) return v;
    _warn('$where is not a list, ignored');
    return const [];
  }

  T _enum<T>(Map<String, T> names, Object? v, T fallback, String where) {
    if (v == null) return fallback;
    final hit = names[v];
    if (hit != null) return hit;
    _warn('unknown $where "$v", using ${fallback is Enum ? fallback.name : fallback}');
    return fallback;
  }

  /// 不认识的值返回 null，调用方跳过整个元素。
  T? _enumOrSkip<T>(Map<String, T> names, Object? v, String where) {
    final hit = names[v];
    if (hit == null) _warn('unknown $where "$v", element skipped');
    return hit;
  }

  int _color(Object? v, String where) {
    if (v == null) return 0;
    final i = _int(v);
    if (i == null || i < 0 || i >= _paletteLength) {
      _warn('$where color $v is not a palette index, not drawn');
      return 0;
    }
    return i;
  }

  Uint16List? _colors(Object? v, String where) {
    if (v == null) return null;
    if (v is! List) {
      _warn('$where.colors is not a list, ignored');
      return null;
    }
    final out = Uint16List(_count);
    var bad = 0;
    for (var i = 0; i < _count && i < v.length; i++) {
      final c = _int(v[i]);
      if (c == null || c < 0 || c >= _paletteLength) {
        if (v[i] != null) bad++;
        continue;
      }
      out[i] = c;
    }
    if (bad > 0) _warn('$where.colors has $bad entries outside the palette, not drawn');
    if (v.length != _count) _warn('$where.colors has ${v.length} entries, bars.count is $_count');
    return out;
  }

  /// 逐根数值：长度对不上时补 NaN 或截断，并记警告。
  Float64List _values(Object? v, String where) {
    final out = Float64List(_count)..fillRange(0, _count, double.nan);
    if (v is! List) {
      _warn('$where is not a list, treated as empty');
      return out;
    }
    if (v.length != _count) _warn('$where has ${v.length} values, bars.count is $_count');
    for (var i = 0; i < _count && i < v.length; i++) {
      final d = _double(v[i]);
      if (d != null) out[i] = d;
    }
    return out;
  }

  // ---- 顶层 ----

  ScriptOutput parse(Object? json) {
    if (json is! Map) _fail(ScriptOutputErrorCode.notAnObject, 'top level is not an object');
    final v = _int(json['v']);
    if (v != scriptSchemaVersion) {
      _fail(ScriptOutputErrorCode.unsupportedVersion,
          'schema version ${json['v']} is not supported (expected $scriptSchemaVersion)');
    }
    _checkKeys(json, _topKeys, 'output');

    final script = json['script'];
    final scriptId = script is Map ? _strOrNull(script['id']) : null;
    if (scriptId == null || scriptId.isEmpty) {
      _fail(ScriptOutputErrorCode.invalid, 'script.id is missing');
    }
    final pane = switch (json['pane']) {
      'main' => ScriptPane.main,
      'sub' => ScriptPane.sub,
      final other => _fail(ScriptOutputErrorCode.invalid, 'pane "$other" is not main or sub'),
    };
    final bars = _bars(json['bars']);
    _count = bars.count;
    final palette = _palette(json['palette']);
    _paletteLength = palette.length;

    final series = <ScriptSeries>[];
    final seen = <String>{};
    final rawSeries = _list(json['series'], 'series');
    for (var k = 0; k < rawSeries.length; k++) {
      final s = _series(rawSeries[k], 'series[$k]');
      if (s == null) continue;
      if (!seen.add(s.id)) _warn('series id "${s.id}" is repeated');
      series.add(s);
    }
    final hlines = _each(json['hlines'], 'hlines', _hline);
    final ids = {for (final s in series) s.id, for (final h in hlines) h.id};

    return ScriptOutput(
      scriptId: scriptId,
      scriptName: _str(script is Map ? script['name'] : null, scriptId),
      symbol: _str(json['symbol']),
      period: _str(json['period']),
      pane: pane,
      precision: _int(json['precision']),
      bars: bars,
      palette: palette,
      series: List.unmodifiable(series),
      hlines: List.unmodifiable(hlines),
      fills: _each(json['fills'], 'fills', (v, w) => _fill(v, w, ids)),
      markers: _each(json['markers'], 'markers', _markers),
      trades: _each(json['trades'], 'trades', _trade),
      bg: _each(json['bg'], 'bg', _background),
      barColors: _each(json['barColors'], 'barColors', _runs),
      candles: _each(json['candles'], 'candles', _candles),
      lines: _each(json['lines'], 'lines', _segment),
      boxes: _each(json['boxes'], 'boxes', _box),
      labels: _each(json['labels'], 'labels', _label),
      tables: _each(json['tables'], 'tables', _table),
      inputs: _each(json['inputs'], 'inputs', _input),
      engineWarnings: List.unmodifiable([
        for (final w in _list(json['warnings'], 'warnings')) _str(w),
      ]),
      ext: json['ext'],
    );
  }

  /// 字号：tiny…auto，或者数字（Pine v6 的点数，可能是字符串 "12"）。
  (ScriptSize, double?) _size(Object? v, ScriptSize fallback, String where) {
    final n = v is String ? double.tryParse(v) : (v is num ? v.toDouble() : null);
    if (n != null && n.isFinite && n > 0) return (fallback, n);
    return (_enum(_sizes, v, fallback, where), null);
  }

  /// 单个图元上的 `pane`：`"main"` 表示副图脚本里这个图元画到主图；没有这个字段或 `"sub"` 时照常。
  bool _mainPane(Object? v, String where) {
    if (v == null || v == 'sub') return false;
    if (v == 'main') return true;
    _warn('unknown $where.pane "$v", ignored');
    return false;
  }

  ScriptBars _bars(Object? v) {
    if (v is! Map) _fail(ScriptOutputErrorCode.invalid, 'bars is missing');
    final from = _int(v['from']);
    final to = _int(v['to']);
    final count = _int(v['count']);
    final interval = _int(v['intervalMs']);
    if (from == null || to == null || count == null || interval == null) {
      _fail(ScriptOutputErrorCode.invalid, 'bars needs from, to, count and intervalMs');
    }
    if (count <= 0 || interval <= 0 || to < from) {
      _fail(ScriptOutputErrorCode.invalid, 'bars is inconsistent: $v');
    }
    _checkKeys(v, const {'from', 'to', 'count', 'intervalMs'}, 'bars');
    return ScriptBars(from: from, to: to, count: count, intervalMs: interval);
  }

  List<Color?> _palette(Object? v) {
    if (v is! List) _fail(ScriptOutputErrorCode.invalid, 'palette is missing');
    final out = <Color?>[];
    for (var i = 0; i < v.length; i++) {
      final s = v[i];
      if (i == 0) {
        out.add(null);
        continue;
      }
      final c = s is String ? _hexColor(s) : null;
      if (c == null) _warn('palette[$i] "$s" is not #RRGGBBAA, not drawn');
      out.add(c);
    }
    return List.unmodifiable(out);
  }

  /// `#RRGGBBAA`（也认 `#RRGGBB`）。
  static Color? _hexColor(String s) {
    if (!s.startsWith('#') || (s.length != 9 && s.length != 7)) return null;
    final rgb = int.tryParse(s.substring(1, 7), radix: 16);
    final a = s.length == 9 ? int.tryParse(s.substring(7, 9), radix: 16) : 0xFF;
    if (rgb == null || a == null) return null;
    return Color((a << 24) | rgb);
  }

  ScriptSeries? _series(Object? v, String where) {
    if (v is! Map) return _skip(where);
    _checkKeys(v, _seriesKeys, 'series');
    final id = _strOrNull(v['id']);
    if (id == null) return _skip(where, 'no id');
    final kind = _enumOrSkip(_kinds, v['kind'], '$where.kind');
    if (kind == null) return null;
    return ScriptSeries(
      mainPane: _mainPane(v['pane'], where),
      id: id,
      kind: kind,
      title: _str(v['title']),
      visible: _bool(v['visible'], true),
      color: _color(v['color'], where),
      colors: _colors(v['colors'], where),
      values: _values(v['values'], '$where.values'),
      width: _double(v['width']) ?? 1,
      style: _enum(_lineStyles, v['style'], ScriptLineStyle.solid, '$where.style'),
      step: _bool(v['step'], false),
      breakGaps: _enum(const {'connect': false, 'break': true}, v['gaps'], false, '$where.gaps'),
      base: _double(v['base']) ?? 0,
      variant: _enum(_variants, v['variant'], ScriptBarVariant.histogram, '$where.variant'),
      shape: _enum(_dotShapes, v['shape'], ScriptDotShape.circle, '$where.shape'),
      size: _double(v['size']) ?? 1,
      trackPrice: _bool(v['trackPrice'], false),
      legend: _bool(v['legend'], true),
    );
  }

  ScriptHLine? _hline(Object? v, String where) {
    if (v is! Map) return _skip(where);
    _checkKeys(v, _hlineKeys, 'hlines');
    final id = _strOrNull(v['id']);
    final price = _double(v['price']);
    if (id == null || price == null) return _skip(where, 'no id or price');
    return ScriptHLine(
      mainPane: _mainPane(v['pane'], where),
      id: id,
      title: _str(v['title']),
      price: price,
      color: _color(v['color'], where),
      style: _enum(_lineStyles, v['style'], ScriptLineStyle.solid, '$where.style'),
      width: _double(v['width']) ?? 1,
      visible: _bool(v['visible'], true),
    );
  }

  ScriptFill? _fill(Object? v, String where, Set<String> ids) {
    if (v is! Map) return _skip(where);
    _checkKeys(v, _fillKeys, 'fills');
    final between = v['between'];
    if (between is! List || between.length != 2) return _skip(where, 'between needs two ids');
    final a = _str(between[0]);
    final b = _str(between[1]);
    if (!ids.contains(a) || !ids.contains(b)) {
      return _skip(where, 'between refers to an unknown id ($a, $b)');
    }
    return ScriptFill(
        mainPane: _mainPane(v['pane'], where),
        a: a,
        b: b,
        color: _color(v['color'], where),
        colors: _colors(v['colors'], where));
  }

  ScriptMarkers? _markers(Object? v, String where) {
    if (v is! Map) return _skip(where);
    _checkKeys(v, _markerKeys, 'markers');
    final shape = _enumOrSkip(_markerShapes, v['shape'], '$where.shape');
    if (shape == null) return null;
    final points = _list(v['points'], '$where.points');
    final times = Int64List(points.length);
    final prices = Float64List(points.length);
    final colors = Uint16List(points.length);
    var n = 0;
    var bad = 0;
    for (final pt in points) {
      final t = pt is List && pt.length == 3 ? _int(pt[0]) : null;
      if (t == null) {
        bad++;
        continue;
      }
      times[n] = t;
      prices[n] = _double(pt[1]) ?? double.nan;
      final c = _int(pt[2]);
      colors[n] = c != null && c >= 0 && c < _paletteLength ? c : 0;
      n++;
    }
    if (bad > 0) _warn('$where has $bad malformed points, skipped');
    final text = _strOrNull(v['text']);
    return ScriptMarkers(
      mainPane: _mainPane(v['pane'], where),
      title: _str(v['title']),
      shape: shape,
      location: _enum(_locations, v['location'], ScriptMarkerLocation.abovebar, '$where.location'),
      size: _enum(_sizes, v['size'], ScriptSize.auto, '$where.size'),
      char: _strOrNull(v['char']),
      text: text == null || text.isEmpty ? null : text,
      textColor: _color(v['textColor'], where),
      times: n == points.length ? times : Int64List.sublistView(times, 0, n),
      prices: n == points.length ? prices : Float64List.sublistView(prices, 0, n),
      colors: n == points.length ? colors : Uint16List.sublistView(colors, 0, n),
    );
  }

  ScriptTrade? _trade(Object? v, String where) {
    if (v is! Map) return _skip(where);
    _checkKeys(v, _tradeKeys, 'trades');
    final t = _int(v['t']);
    final price = _double(v['price']);
    if (t == null || price == null) return _skip(where, 'no time or price');
    final side = _enumOrSkip(_sides, v['side'], '$where.side');
    if (side == null) return null;
    return ScriptTrade(
      time: t,
      price: price,
      side: side,
      kind: _enum(_tradeKinds, v['kind'], ScriptTradeKind.entry, '$where.kind'),
      qty: _double(v['qty']) ?? 0,
      id: _str(v['id']),
      comment: _strOrNull(v['comment']),
    );
  }

  ScriptBackground? _background(Object? v, String where) {
    final runs = _runs(v, where);
    if (runs == null) return null;
    return ScriptBackground(runs, mainPane: _mainPane((v as Map)['pane'], where));
  }

  List<ScriptRun>? _runs(Object? v, String where) {
    if (v is! Map) return _skip(where);
    _checkKeys(v, where.startsWith('bg') ? _bgKeys : _runsKeys,
        where.startsWith('bg') ? 'bg' : 'barColors');
    final out = <ScriptRun>[];
    var bad = 0;
    for (final r in _list(v['runs'], '$where.runs')) {
      final t1 = r is List && r.length == 3 ? _int(r[0]) : null;
      final t2 = t1 != null ? _int((r as List)[1]) : null;
      final c = t2 != null ? _int(r[2]) : null;
      if (t1 == null || t2 == null || c == null) {
        bad++;
        continue;
      }
      out.add(ScriptRun(t1, t2, c >= 0 && c < _paletteLength ? c : 0));
    }
    if (bad > 0) _warn('$where has $bad malformed runs, skipped');
    return List.unmodifiable(out);
  }

  ScriptCandles? _candles(Object? v, String where) {
    if (v is! Map) return _skip(where);
    _checkKeys(v, _candleKeys, 'candles');
    return ScriptCandles(
      mainPane: _mainPane(v['pane'], where),
      title: _str(v['title']),
      bars: _bool(v['bars'], false),
      open: _values(v['open'], '$where.open'),
      high: _values(v['high'], '$where.high'),
      low: _values(v['low'], '$where.low'),
      close: _values(v['close'], '$where.close'),
      color: _color(v['color'], where),
      colors: _colors(v['colors'], where),
    );
  }

  ScriptSegment? _segment(Object? v, String where) {
    if (v is! Map) return _skip(where);
    _checkKeys(v, _lineKeys, 'lines');
    final t1 = _int(v['t1']), t2 = _int(v['t2']);
    final p1 = _double(v['p1']), p2 = _double(v['p2']);
    if (t1 == null || t2 == null || p1 == null || p2 == null) return _skip(where, 'no coordinates');
    return ScriptSegment(
      mainPane: _mainPane(v['pane'], where),
      t1: t1,
      p1: p1,
      t2: t2,
      p2: p2,
      extend: _enum(_extends, v['extend'], ScriptExtend.none, '$where.extend'),
      color: _color(v['color'], where),
      style: _enum(_segmentStyles, v['style'], ScriptSegmentStyle.solid, '$where.style'),
      width: _double(v['width']) ?? 1,
    );
  }

  ScriptBox? _box(Object? v, String where) {
    if (v is! Map) return _skip(where);
    _checkKeys(v, _boxKeys, 'boxes');
    final t1 = _int(v['t1']), t2 = _int(v['t2']);
    final top = _double(v['top']), bottom = _double(v['bottom']);
    if (t1 == null || t2 == null || top == null || bottom == null) {
      return _skip(where, 'no coordinates');
    }
    final border = v['border'];
    if (border is Map) _checkKeys(border, _borderKeys, 'boxes.border');
    final text = v['text'];
    ScriptBoxText? boxText;
    if (text is Map) {
      _checkKeys(text, _boxTextKeys, 'boxes.text');
      final s = _str(text['text']);
      if (s.isNotEmpty) {
        final textSize = _size(text['size'], ScriptSize.auto, '$where.text.size');
        boxText = ScriptBoxText(
          text: s,
          color: _color(text['color'], '$where.text'),
          size: textSize.$1,
          points: textSize.$2,
          halign: _enum(_hAligns, text['halign'], ScriptHAlign.center, '$where.text.halign'),
          valign: _enum(_vAligns, text['valign'], ScriptVAlign.center, '$where.text.valign'),
        );
      }
    }
    return ScriptBox(
      mainPane: _mainPane(v['pane'], where),
      t1: t1,
      top: top,
      t2: t2,
      bottom: bottom,
      extend: _enum(_extends, v['extend'], ScriptExtend.none, '$where.extend'),
      bg: _color(v['bg'], where),
      borderColor: border is Map ? _color(border['color'], '$where.border') : 0,
      borderWidth: border is Map ? (_double(border['width']) ?? 1) : 0,
      borderStyle: border is Map
          ? _enum(_lineStyles, border['style'], ScriptLineStyle.solid, '$where.border.style')
          : ScriptLineStyle.solid,
      text: boxText,
    );
  }

  ScriptLabel? _label(Object? v, String where) {
    if (v is! Map) return _skip(where);
    _checkKeys(v, _labelKeys, 'labels');
    final t = _int(v['t']);
    if (t == null) return _skip(where, 'no time');
    final size = _size(v['size'], ScriptSize.normal, '$where.size');
    return ScriptLabel(
      mainPane: _mainPane(v['pane'], where),
      time: t,
      price: _double(v['p']) ?? double.nan,
      yloc: _enum(_ylocs, v['yloc'], ScriptYLoc.price, '$where.yloc'),
      text: _str(v['text']),
      style: _enum(_labelStyles, v['style'], ScriptLabelStyle.labelDown, '$where.style'),
      color: _color(v['color'], where),
      textColor: _color(v['textColor'], where),
      size: size.$1,
      points: size.$2,
      align: _enum(_hAligns, v['align'], ScriptHAlign.center, '$where.align'),
      tooltip: _strOrNull(v['tooltip']),
    );
  }

  ScriptTable? _table(Object? v, String where) {
    if (v is! Map) return _skip(where);
    _checkKeys(v, _tableKeys, 'tables');
    final frame = v['frame'];
    final border = v['border'];
    if (frame is Map) _checkKeys(frame, _frameKeys, 'tables.frame');
    if (border is Map) _checkKeys(border, _frameKeys, 'tables.border');
    final cells = <ScriptTableCell>[];
    var bad = 0;
    for (final c in _list(v['cells'], '$where.cells')) {
      final col = c is List && c.length >= 3 ? _int(c[0]) : null;
      final row = col != null ? _int((c as List)[1]) : null;
      if (col == null || row == null || col < 0 || row < 0) {
        bad++;
        continue;
      }
      final size = c.length > 5
          ? _size(c[5], ScriptSize.normal, '$where.cell.size')
          : (ScriptSize.normal, null);
      cells.add(ScriptTableCell(
        column: col,
        row: row,
        text: _str(c[2]),
        textColor: c.length > 3 ? _color(c[3], '$where.cell') : 0,
        bg: c.length > 4 ? _color(c[4], '$where.cell') : 0,
        size: size.$1,
        points: size.$2,
        halign: c.length > 6
            ? _enum(_hAligns, c[6], ScriptHAlign.center, '$where.cell.halign')
            : ScriptHAlign.center,
      ));
    }
    if (bad > 0) _warn('$where has $bad malformed cells, skipped');
    final columns = _int(v['columns']) ?? 0;
    final rows = _int(v['rows']) ?? 0;
    return ScriptTable(
      mainPane: _mainPane(v['pane'], where),
      position: _enum(_positions, v['position'], ScriptTablePosition.topRight, '$where.position'),
      columns: [columns, for (final c in cells) c.column + 1].reduce((a, b) => a > b ? a : b),
      rows: [rows, for (final c in cells) c.row + 1].reduce((a, b) => a > b ? a : b),
      bg: _color(v['bg'], where),
      frameColor: frame is Map ? _color(frame['color'], '$where.frame') : 0,
      frameWidth: frame is Map ? (_double(frame['width']) ?? 0) : 0,
      borderColor: border is Map ? _color(border['color'], '$where.border') : 0,
      borderWidth: border is Map ? (_double(border['width']) ?? 0) : 0,
      cells: List.unmodifiable(cells),
    );
  }

  ScriptInput? _input(Object? v, String where) {
    if (v is! Map) return _skip(where);
    _checkKeys(v, _inputKeys, 'inputs');
    final id = _strOrNull(v['id']);
    if (id == null) return _skip(where, 'no id');
    final options = v['options'];
    return ScriptInput(
      id: id,
      type: _str(v['type']),
      title: _str(v['title'], id),
      defaultValue: v['default'],
      min: _double(v['min']),
      max: _double(v['max']),
      step: _double(v['step']),
      options: options is List ? List.unmodifiable(options) : null,
      group: _strOrNull(v['group']),
      tooltip: _strOrNull(v['tooltip']),
    );
  }

  List<T> _each<T extends Object>(
      Object? v, String name, T? Function(Object? v, String where) parse) {
    final list = _list(v, name);
    return List.unmodifiable([
      for (var k = 0; k < list.length; k++) parse(list[k], '$name[$k]'),
    ].nonNulls);
  }

  Null _skip(String where, [String why = 'not an object']) {
    _warn('$where skipped: $why');
    return null;
  }
}
