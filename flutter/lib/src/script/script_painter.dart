import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../chart/chart_formatter.dart';
import '../chart/chart_layout.dart';
import '../model/candle.dart';
import 'script_align.dart';
import 'script_controller.dart';
import 'script_output.dart';

/// 对齐成功的一个脚本：(id, 各对象下标, 输出版本)。
typedef ScriptEntry = (String, ResolvedScript, int);

/// 图元上的文字：按（文字, 字号, 颜色, 对齐）缓存排好版的 [TextPainter]，几百个标签逐帧重画时不重新排版。
class ScriptTextCache {
  ScriptTextCache({this.fontFamily, this.textScaler = TextScaler.noScaling, this.capacity = 2048});

  final String? fontFamily;
  final TextScaler textScaler;
  final int capacity;
  final LinkedHashMap<(String, double, Color, ScriptHAlign), TextPainter> _cache = LinkedHashMap();

  TextPainter layout(String text, double fontSize, Color color,
      [ScriptHAlign align = ScriptHAlign.center]) {
    final key = (text, fontSize, color, align);
    final hit = _cache.remove(key);
    if (hit != null) return _cache[key] = hit;
    if (_cache.length >= capacity) _cache.remove(_cache.keys.first)?.dispose();
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(inherit: false, fontSize: fontSize, color: color, fontFamily: fontFamily),
      ),
      textDirection: TextDirection.ltr,
      textAlign: switch (align) {
        ScriptHAlign.left => TextAlign.left,
        ScriptHAlign.center => TextAlign.center,
        ScriptHAlign.right => TextAlign.right,
      },
      textScaler: textScaler,
    )..layout();
    return _cache[key] = tp;
  }

  void dispose() {
    for (final tp in _cache.values) {
      tp.dispose();
    }
    _cache.clear();
  }
}

/// 图元渲染用到的、不来自输出调色板的颜色（都取图表主题）。
@immutable
class ScriptColors {
  const ScriptColors({
    required this.buy,
    required this.sell,
    required this.axisText,
    required this.grid,
    required this.labelText,
  });

  /// 策略买入成交点。
  final Color buy;

  /// 策略卖出成交点。
  final Color sell;
  final Color axisText;
  final Color grid;

  /// 右轴最新值标签（`trackPrice`）上的文字。
  final Color labelText;
}

/// 每个脚本、每个窗格录好的图层。键没变就直接重放，不重新画。
class ScriptLayerCache {
  final Map<String, (Object, Picture)> _layers = {};

  Picture? _get(String key, Object signature) {
    final hit = _layers[key];
    return hit != null && hit.$1 == signature ? hit.$2 : null;
  }

  void _put(String key, Object signature, Picture picture) {
    _layers.remove(key)?.$2.dispose();
    _layers[key] = (signature, picture);
  }

  /// 丢掉不再显示的脚本的图层。
  void retain(Set<String> scriptIds) {
    _layers.removeWhere((key, value) {
      final keep = scriptIds.contains(key.substring(key.indexOf(':') + 1));
      if (!keep) value.$2.dispose();
      return !keep;
    });
  }

  void dispose() {
    for (final v in _layers.values) {
      v.$2.dispose();
    }
    _layers.clear();
  }
}

@immutable
class ScriptPaintConfig {
  const ScriptPaintConfig({
    required this.controller,
    required this.cache,
    required this.text,
    required this.colors,
    required this.fontSize,
    required this.themeKey,
    this.cutAtLast = false,
  });

  final ScriptOutputController controller;
  final ScriptLayerCache cache;
  final ScriptTextCache text;
  final ScriptColors colors;

  /// 图元文字 normal 档以外的字号按它缩放（取图表坐标轴字号）。
  final double fontSize;

  /// 主题变化时让缓存的图层失效。
  final Object themeKey;

  /// 回放中：只画到图上最后一根（游标）为止。图元对齐的是完整数据，回放的数据是它的前一段。
  final bool cutAtLast;
}

/// 主图价格区间要容下的脚本数值：画在主图上的可见曲线、面积、点和自绘 K 线（不含柱、水平线和对象）。
/// 副图脚本里标了 `pane: "main"` 的序列和自绘 K 线也算。[positiveOnly] 时跳过非正数（对数刻度）。
({double min, double max})? scriptMainRange(List<ScriptEntry> scripts, int first, int last,
    {bool positiveOnly = false}) {
  var lo = double.infinity;
  var hi = double.negativeInfinity;
  void take(double v) {
    if (positiveOnly && v <= 0) return;
    if (v < lo) lo = v;
    if (v > hi) hi = v;
  }

  for (final (_, r, _) in scripts) {
    final o = r.output;
    final whole = o.pane == ScriptPane.main;
    final from = r.alignment.fromIndex;
    final i0 = math.max(0, first - from);
    final i1 = math.min(o.bars.count - 1, last - from);
    if (i1 < i0) continue;
    for (final s in o.series) {
      if (!s.visible || s.kind == ScriptSeriesKind.bar || !(whole || s.mainPane)) continue;
      final skip = _dropsLoneValues(s);
      for (var i = i0; i <= i1; i++) {
        final v = s.values[i];
        if (v.isFinite && !(skip && _lone(s.values, i))) take(v);
      }
    }
    for (final c in o.candles) {
      if (!(whole || c.mainPane)) continue;
      for (var i = i0; i <= i1; i++) {
        if (c.high[i].isFinite) take(c.high[i]);
        if (c.low[i].isFinite) take(c.low[i]);
      }
    }
  }
  return lo.isFinite ? (min: lo, max: hi) : null;
}

/// 在空值处断开的曲线、面积（含阶梯线）：前后都是空值（或到头）的单个值没有线段可画（同 Pine 的 `linebr`），
/// 画的时候本来就跳过（见 `_ScriptPainter._runs`），价格区间和副图纵轴也不算它。点、柱逐根画，不受影响。
bool _dropsLoneValues(ScriptSeries s) =>
    s.breakGaps && (s.kind == ScriptSeriesKind.line || s.kind == ScriptSeriesKind.area);

bool _lone(Float64List v, int i) =>
    (i == 0 || v[i - 1].isNaN) && (i == v.length - 1 || v[i + 1].isNaN);

/// K 线改色：返回第 i 根的新颜色，没有改色时 null。后设置的脚本覆盖先设置的。
Color? Function(int index)? scriptBarColors(List<ScriptEntry> scripts, int first, int last) {
  Map<int, Color>? colors;
  for (final (_, r, _) in scripts) {
    final o = r.output;
    for (var g = 0; g < o.barColors.length; g++) {
      final runs = o.barColors[g];
      final k = r.barColorRuns[g];
      for (var j = 0; j < runs.length; j++) {
        final c = o.colorOf(runs[j].color);
        if (c == null) continue;
        final a = math.max(k[j * 2], first);
        final b = math.min(k[j * 2 + 1], last);
        for (var i = a; i <= b; i++) {
          (colors ??= {})[i] = c;
        }
      }
    }
  }
  final map = colors;
  return map == null ? null : (i) => map[i];
}

/// 一帧里画全部脚本图元：主图底层（背景色）、主图上层、各副图窗格。
class ScriptLayersPainter {
  ScriptLayersPainter({
    required this.canvas,
    required this.layout,
    required this.candles,
    required this.config,
    required this.formatter,
    required this.scripts,
  });

  final Canvas canvas;
  final ChartLayout layout;
  final List<Candle> candles;
  final ScriptPaintConfig config;
  final ChartFormatter formatter;
  final List<ScriptEntry> scripts;

  /// 横向几何的签名：缩放、滚动、尺寸变了图层就要重录。
  Object get _xKey => (
        layout.size,
        layout.chartWidth,
        layout.candleWidth,
        layout.rightFloat,
        config.themeKey,
        _cutoff,
      );

  int? get _cutoff => config.cutAtLast ? layout.itemCount - 1 : null;

  /// 主图背景色，画在 K 线下面。
  void paintMainUnder() {
    final pane = _PaneGeom.main(layout);
    for (final (id, r, version) in scripts) {
      final o = r.output;
      final any = o.pane == ScriptPane.main ? o.bg.isNotEmpty : o.bg.any((b) => b.mainPane);
      if (!any) continue;
      _replay('under:$id', (version, _xKey, pane.key), id, (c) {
        _ScriptPainter(c, layout, pane, r, config, formatter, onMain: true).paintBackground();
      });
    }
  }

  /// 主图上的其余图元，叠在 K 线和主图指标上：主图脚本的全部图元，
  /// 以及副图脚本的策略成交点和标了 `pane: "main"` 的图元。
  void paintMainOver() {
    final pane = _PaneGeom.main(layout);
    for (final (id, r, version) in scripts) {
      if (!_hasMainContent(r.output)) continue;
      _replay('main:$id', (version, _xKey, pane.key), id, (c) {
        _ScriptPainter(c, layout, pane, r, config, formatter, onMain: true).paintContent();
      });
    }
  }

  static bool _hasMainContent(ScriptOutput o) =>
      o.pane == ScriptPane.main ||
      o.trades.isNotEmpty ||
      o.series.any((e) => e.mainPane) ||
      o.hlines.any((e) => e.mainPane) ||
      o.fills.any((e) => e.mainPane) ||
      o.markers.any((e) => e.mainPane) ||
      o.candles.any((e) => e.mainPane) ||
      o.lines.any((e) => e.mainPane) ||
      o.boxes.any((e) => e.mainPane) ||
      o.labels.any((e) => e.mainPane) ||
      o.tables.any((e) => e.mainPane);

  /// 副图脚本，[panes] 和 [ids] 一一对应。
  void paintSubPanes(List<SubPaneRect> panes, List<String> ids) {
    for (var p = 0; p < panes.length && p < ids.length; p++) {
      final pane = panes[p];
      if (pane.height < 1) continue;
      final entry = scripts.where((e) => e.$1 == ids[p]).firstOrNull;
      if (entry == null) {
        // 对不上 K 线（或正在收起）：留着窗格和标题，等新输出，避免窗格来回伸缩
        _paneFrame(canvas, pane, config.controller.outputOf(ids[p])?.scriptName ?? '');
        continue;
      }
      final (id, r, version) = entry;
      _replay(
        'sub:$id',
        (version, _xKey, pane.top, pane.height, pane.contentTop, pane.contentHeight),
        id,
        (c) => _paintSub(c, pane, r),
      );
    }
  }

  void _paintSub(Canvas c, SubPaneRect pane, ResolvedScript r) {
    final o = r.output;
    final contentBottom = pane.contentTop + pane.contentHeight;
    final range = _subRange(r);
    final geom = _PaneGeom(
      top: pane.contentTop,
      bottom: contentBottom,
      left: 0,
      right: layout.chartWidth,
      min: range.min,
      max: range.max,
    );
    final text = config.text;
    final colors = config.colors;
    c.save();
    c.clipRect(Rect.fromLTRB(0, pane.top, layout.size.width, pane.bottom));
    _paneFrame(c, pane, o.scriptName);
    String fmt(double v) =>
        o.precision != null ? v.toStringAsFixed(o.precision!) : formatter.price(v);
    final hi = text.layout(fmt(range.max), config.fontSize, colors.axisText, ScriptHAlign.right);
    final lo = text.layout(fmt(range.min), config.fontSize, colors.axisText, ScriptHAlign.right);
    hi.paint(c, Offset(layout.size.width - 4 - hi.width, pane.contentTop));
    lo.paint(c, Offset(layout.size.width - 4 - lo.width, contentBottom - lo.height));
    _ScriptPainter(c, layout, geom, r, config, formatter, onMain: false)
      ..paintBackground()
      ..paintContent();
    c.restore();
  }

  /// 窗格上沿的分隔线和左上角的脚本名（图例行里）。
  void _paneFrame(Canvas c, SubPaneRect pane, String name) {
    c.save();
    c.clipRect(Rect.fromLTRB(0, pane.top, layout.size.width, pane.bottom));
    c.drawLine(Offset(0, pane.top), Offset(layout.chartWidth, pane.top),
        Paint()..color = config.colors.grid);
    if (name.isNotEmpty) {
      final title =
          config.text.layout(name, config.fontSize, config.colors.axisText, ScriptHAlign.left);
      title.paint(c, Offset(6, pane.top + (pane.contentTop - pane.top - title.height) / 2));
    }
    c.restore();
  }

  /// 副图纵轴：[scriptSubRange] 的结果上下各留 5%。
  ({double min, double max}) _subRange(ResolvedScript r) {
    final vis = _VisibleRange.of(layout, _cutoff);
    final raw = scriptSubRange(r, vis.first, vis.last);
    if (raw == null) return (min: 0, max: 1);
    if (raw.max - raw.min < 1e-9) return (min: raw.min - 1, max: raw.max + 1);
    final pad = (raw.max - raw.min) * 0.05;
    return (min: raw.min - pad, max: raw.max + pad);
  }

  void _replay(String key, Object signature, String scriptId, void Function(Canvas) paint) {
    var picture = config.cache._get(key, signature);
    if (picture == null) {
      final recorder = PictureRecorder();
      paint(Canvas(recorder));
      picture = recorder.endRecording();
      config.cache._put(key, signature, picture);
      config.controller.countPaint(scriptId);
    }
    canvas.drawPicture(picture);
  }
}

/// 副图纵轴要容下的数值：本地下标 [first]..[last] 里的序列（含柱、面积的基线）、水平线、自绘 K 线和各类对象。
/// 画到主图的（策略成交点、标了 `pane: "main"` 的图元）不算。什么都没有时返回 null。
({double min, double max})? scriptSubRange(ResolvedScript r, int first, int last) {
  final o = r.output;
  final vis = _VisibleRange(first, last);
  var lo = double.infinity;
  var hi = double.negativeInfinity;
  void take(double v) {
    if (!v.isFinite) return;
    if (v < lo) lo = v;
    if (v > hi) hi = v;
  }

  final from = r.alignment.fromIndex;
  final i0 = math.max(0, vis.first - from);
  final i1 = math.min(o.bars.count - 1, vis.last - from);
  for (final s in o.series) {
    if (!s.visible || s.mainPane) continue;
    final skip = _dropsLoneValues(s);
    var any = false;
    for (var i = i0; i <= i1; i++) {
      final v = s.values[i];
      if (v.isFinite && !(skip && _lone(s.values, i))) {
        take(v);
        any = true;
      }
    }
    if (any && (s.kind == ScriptSeriesKind.bar || s.kind == ScriptSeriesKind.area)) take(s.base);
  }
  for (final c in o.candles) {
    if (c.mainPane) continue;
    for (var i = i0; i <= i1; i++) {
      take(c.high[i]);
      take(c.low[i]);
    }
  }
  for (final h in o.hlines) {
    if (h.visible && !h.mainPane) take(h.price);
  }
  bool seen(int a, int b) => math.max(a, b) >= vis.first && math.min(a, b) <= vis.last;
  for (var j = 0; j < o.lines.length; j++) {
    final l = o.lines[j];
    if (l.mainPane) continue;
    if (l.extend != ScriptExtend.none || seen(r.segK1[j], r.segK2[j])) {
      take(l.p1);
      take(l.p2);
    }
  }
  for (var j = 0; j < o.boxes.length; j++) {
    final b = o.boxes[j];
    if (b.mainPane) continue;
    if (b.extend != ScriptExtend.none || seen(r.boxK1[j], r.boxK2[j])) {
      take(b.top);
      take(b.bottom);
    }
  }
  for (var j = 0; j < o.labels.length; j++) {
    if (!o.labels[j].mainPane && seen(r.labelK[j], r.labelK[j])) take(o.labels[j].price);
  }
  for (var g = 0; g < o.markers.length; g++) {
    final m = o.markers[g];
    if (m.location != ScriptMarkerLocation.absolute || m.mainPane) continue;
    final ks = r.markerK[g];
    for (var j = 0; j < m.length; j++) {
      if (seen(ks[j], ks[j])) take(m.prices[j]);
    }
  }
  return lo.isFinite ? (min: lo, max: hi) : null;
}

/// 一个窗格的纵向映射。
class _PaneGeom {
  _PaneGeom({
    required this.top,
    required this.bottom,
    required this.left,
    required this.right,
    required this.min,
    required this.max,
    this.log = false,
    double? valueTop,
  }) : valueTop = valueTop ?? top;

  factory _PaneGeom.main(ChartLayout l) => _PaneGeom(
        top: l.mainTop,
        valueTop: l.mainContentTop,
        bottom: l.mainBottom,
        left: 0,
        right: l.chartWidth,
        min: l.priceMin,
        max: l.priceMax,
        log: l.logScale,
      );

  final double top;
  final double bottom;
  final double left;
  final double right;
  final double min;
  final double max;

  /// 按对数刻度（只有主图会是）。
  final bool log;

  /// 数值映射的顶边。主图开了图例留位时在图例下面（`ChartLayout.mainContentTop`），
  /// [rect] 仍是整个窗格。
  final double valueTop;

  Rect get rect => Rect.fromLTRB(left, top, right, bottom);

  Object get key => (top, valueTop, bottom, min, max, log);

  double y(double v) => ChartLayout.priceToPixel(v, valueTop, bottom, min, max, log: log);
}

/// 可见的本地下标范围（含右侧留白里的虚拟下标），两边各多一根，免得线在边缘断开。
class _VisibleRange {
  const _VisibleRange(this.first, this.last);

  /// [cutoff] 非空时（回放）最多到这一根。
  factory _VisibleRange.of(ChartLayout l, [int? cutoff]) {
    final last = l.rightFloat.ceil() + 1;
    return _VisibleRange(
      (l.rightFloat - l.chartWidth / l.candleWidth).floor() - 1,
      cutoff == null || cutoff > last ? last : cutoff,
    );
  }

  final int first;
  final int last;

  bool contains(int k) => k >= first && k <= last;
}

/// 一个脚本在一个窗格里的绘制。
class _ScriptPainter {
  _ScriptPainter(this.canvas, this.layout, this.pane, this.r, this.config, this.formatter,
      {required this.onMain})
      : o = r.output,
        cutoff = config.cutAtLast ? layout.itemCount - 1 : null,
        vis = _VisibleRange.of(layout, config.cutAtLast ? layout.itemCount - 1 : null);

  /// 画在主图（true）还是脚本自己的副图（false）。
  final bool onMain;

  /// 这个图元画不画在当前窗格：主图脚本的都画；副图脚本里标了 `pane: "main"` 的画在主图，其余画在副图。
  bool _here(bool mainPane) => o.pane == ScriptPane.main || mainPane == onMain;

  final Canvas canvas;
  final ChartLayout layout;
  final _PaneGeom pane;
  final ResolvedScript r;
  final ScriptOutput o;
  final ScriptPaintConfig config;
  final ChartFormatter formatter;
  final _VisibleRange vis;

  /// 回放的游标；非空时只画到它为止，跨过它的方框、线段从它右边裁掉。
  final int? cutoff;

  /// 图元的裁剪区：窗格，回放时右边到游标那根的右沿。背景色按它裁（整列铺到窗格顶）。
  Rect get _clip {
    final k = cutoff;
    if (k == null) return pane.rect;
    final r = pane.rect;
    return Rect.fromLTRB(r.left, r.top, math.min(r.right, x(k) + cw / 2), r.bottom);
  }

  /// 按价位定位的图元的裁剪区：[_clip] 的顶边换成数值映射的顶边。主图开了图例留位时，
  /// 价位从图例下面开始映射，略高于可见范围的水平线、方框等不会画进图例那一条。
  Rect get _valueClip {
    final c = _clip;
    return pane.valueTop > c.top ? Rect.fromLTRB(c.left, pane.valueTop, c.right, c.bottom) : c;
  }

  final Paint _fill = Paint()..isAntiAlias = true;
  final Paint _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..isAntiAlias = true;

  ScriptTextCache get text => config.text;
  double get cw => layout.candleWidth;

  double x(int k) => layout.centerX(k);
  double y(double v) => pane.y(v);

  int get from => r.alignment.fromIndex;

  /// 可见的值下标范围。
  (int, int) get _valueRange =>
      (math.max(0, vis.first - from), math.min(o.bars.count - 1, vis.last - from));

  double fontOf(ScriptSize s) =>
      config.fontSize *
      switch (s) {
        ScriptSize.tiny => 0.8,
        ScriptSize.small => 1.0,
        ScriptSize.normal => 1.2,
        ScriptSize.large => 1.5,
        ScriptSize.huge => 2.0,
        ScriptSize.auto => 1.0,
      };

  /// 形状半径。auto 随 K 线宽度变化。
  double halfOf(ScriptSize s) => switch (s) {
        ScriptSize.tiny => 3,
        ScriptSize.small => 4.5,
        ScriptSize.normal => 6,
        ScriptSize.large => 8,
        ScriptSize.huge => 11,
        ScriptSize.auto => (cw * 0.35).clamp(2.5, 6.0).toDouble(),
      };

  // ───────────────────────── 背景色 ─────────────────────────

  void paintBackground() {
    if (o.bg.isEmpty) return;
    canvas.save();
    canvas.clipRect(_clip);
    for (var g = 0; g < o.bg.length; g++) {
      if (!_here(o.bg[g].mainPane)) continue;
      final runs = o.bg[g].runs;
      final k = r.bgRuns[g];
      for (var j = 0; j < runs.length; j++) {
        final a = k[j * 2], b = k[j * 2 + 1];
        if (b < vis.first || a > vis.last) continue;
        final c = o.colorOf(runs[j].color);
        if (c == null) continue;
        canvas.drawRect(
            Rect.fromLTRB(x(a) - cw / 2, pane.top, x(b) + cw / 2, pane.bottom), _fill..color = c);
      }
    }
    canvas.restore();
  }

  // ───────────────────────── 其余图元 ─────────────────────────

  /// 画的顺序（SCHEMA 没规定，参照 TradingView）：
  /// 填充 → 水平线 → 自绘 K 线 → 序列 → 标记 → 成交点 → 方框 → 线段 → 标签 → 表格，最后是右轴最新值。
  void paintContent() {
    canvas.save();
    canvas.clipRect(_valueClip);
    _fills();
    for (final h in o.hlines) {
      if (!h.visible || !_here(h.mainPane)) continue;
      final c = o.colorOf(h.color);
      if (c == null) continue;
      final yy = y(h.price);
      _styledLine(Offset(pane.left, yy), Offset(pane.right, yy), c, h.width, h.style);
    }
    for (final cs in o.candles) {
      if (_here(cs.mainPane)) _candles(cs);
    }
    for (final s in o.series) {
      if (!s.visible || !_here(s.mainPane)) continue;
      switch (s.kind) {
        case ScriptSeriesKind.line:
          _line(s, area: false);
        case ScriptSeriesKind.area:
          _line(s, area: true);
        case ScriptSeriesKind.bar:
          _bars(s);
        case ScriptSeriesKind.dots:
          _dots(s);
      }
    }
    for (var g = 0; g < o.markers.length; g++) {
      if (_here(o.markers[g].mainPane)) _markers(o.markers[g], r.markerK[g]);
    }
    // 策略成交点一律画在主图的价格上
    if (onMain) _trades();
    for (var j = 0; j < o.boxes.length; j++) {
      if (_here(o.boxes[j].mainPane)) _box(o.boxes[j], r.boxK1[j], r.boxK2[j]);
    }
    for (var j = 0; j < o.lines.length; j++) {
      if (_here(o.lines[j].mainPane)) _segment(o.lines[j], r.segK1[j], r.segK2[j]);
    }
    for (var j = 0; j < o.labels.length; j++) {
      if (_here(o.labels[j].mainPane)) _label(o.labels[j], r.labelK[j]);
    }
    if (cutoff != null || pane.valueTop > pane.top) {
      // 表格按窗格定位，和时间、价位都无关：回放时不跟着游标裁，图例留位时也照常贴窗格的边
      canvas
        ..restore()
        ..save()
        ..clipRect(pane.rect);
    }
    for (final t in o.tables) {
      if (_here(t.mainPane)) _table(t);
    }
    canvas.restore();
    _trackPrices();
  }

  // ---- 逐根序列 ----

  /// 把 [i0]..[i1] 切成同色、连续的段，交给 [emit]（段内是值下标，至少两个点）。
  /// 两点之间的那一段用后一点的颜色；[connect] 时跨过没有值的位置。
  void _runs(int i0, int i1, bool Function(int i) has, int Function(int i) colorAt, bool connect,
      void Function(List<int> run, int color) emit) {
    var run = <int>[];
    var runColor = -1;
    var prev = -1;
    void flush() {
      if (run.length >= 2 && runColor > 0) emit(run, runColor);
      run = <int>[];
      runColor = -1;
    }

    for (var i = i0; i <= i1; i++) {
      if (!has(i)) {
        if (!connect) {
          flush();
          prev = -1;
        }
        continue;
      }
      if (prev < 0) {
        prev = i;
        continue;
      }
      final c = colorAt(i);
      if (c != runColor) {
        flush();
        run = [prev];
        runColor = c;
      }
      run.add(i);
      prev = i;
    }
    flush();
  }

  void _line(ScriptSeries s, {required bool area}) {
    var (i0, i1) = _valueRange;
    if (i1 < i0) return;
    final vals = s.values;
    if (!s.breakGaps) {
      // 跨过空值连线：把视口外最近的有值点也带上，线才不会在边缘断掉
      while (i0 > 0 && vals[i0].isNaN) {
        i0--;
      }
      while (i1 < vals.length - 1 && vals[i1].isNaN) {
        i1++;
      }
    }
    final width = math.max(0.5, s.width);
    final baseY = y(s.base);
    _runs(i0, i1, (i) => !vals[i].isNaN, s.colorAt, !s.breakGaps, (run, ci) {
      final color = o.colorOf(ci);
      if (color == null) return;
      final path = Path();
      var px = x(from + run.first), py = y(vals[run.first]);
      path.moveTo(px, py);
      for (var n = 1; n < run.length; n++) {
        final nx = x(from + run[n]), ny = y(vals[run[n]]);
        if (s.step) path.lineTo(nx, py);
        path.lineTo(nx, ny);
        px = nx;
        py = ny;
      }
      if (area) {
        final fill = Path.from(path)
          ..lineTo(px, baseY)
          ..lineTo(x(from + run.first), baseY)
          ..close();
        canvas.drawPath(fill, _fill..color = color.withValues(alpha: color.a * 0.35));
      }
      _strokePath(path, color, width, s.style);
    });
  }

  void _bars(ScriptSeries s) {
    final (i0, i1) = _valueRange;
    final baseY = y(s.base);
    final body = s.variant == ScriptBarVariant.columns
        ? math.max(1.0, cw * 0.75)
        : math.max(1.0, math.min(s.width, cw * 0.75));
    for (var i = i0; i <= i1; i++) {
      final v = s.values[i];
      if (v.isNaN) continue;
      final c = o.colorOf(s.colorAt(i));
      if (c == null) continue;
      final cx = x(from + i), vy = y(v);
      canvas.drawRect(
          Rect.fromLTRB(cx - body / 2, math.min(vy, baseY), cx + body / 2, math.max(vy, baseY)),
          _fill..color = c);
    }
  }

  void _dots(ScriptSeries s) {
    final (i0, i1) = _valueRange;
    final rad = math.max(1.2, 0.8 + s.size * 0.7);
    for (var i = i0; i <= i1; i++) {
      final v = s.values[i];
      if (v.isNaN) continue;
      final c = o.colorOf(s.colorAt(i));
      if (c == null) continue;
      final p = Offset(x(from + i), y(v));
      if (s.shape == ScriptDotShape.circle) {
        canvas.drawCircle(p, rad, _fill..color = c);
      } else {
        _stroke
          ..color = c
          ..strokeWidth = math.max(1, s.size * 0.8);
        canvas.drawLine(p - Offset(rad, 0), p + Offset(rad, 0), _stroke);
        canvas.drawLine(p - Offset(0, rad), p + Offset(0, rad), _stroke);
      }
    }
  }

  void _fills() {
    final series = {for (final s in o.series) s.id: s};
    final hlines = {for (final h in o.hlines) h.id: h};
    final (i0, i1) = _valueRange;
    for (final f in o.fills) {
      if (!_here(f.mainPane)) continue;
      final ha = hlines[f.a], hb = hlines[f.b];
      if (ha != null && hb != null && f.colors == null) {
        // 两条水平线之间：整个窗格宽度
        final c = o.colorOf(f.color);
        if (c != null) {
          canvas.drawRect(
              Rect.fromLTRB(pane.left, y(ha.price), pane.right, y(hb.price)), _fill..color = c);
        }
        continue;
      }
      double at(String id, int i) => series[id]?.values[i] ?? hlines[id]!.price;
      _runs(i0, i1, (i) => !at(f.a, i).isNaN && !at(f.b, i).isNaN, f.colorAt, false, (run, ci) {
        final c = o.colorOf(ci);
        if (c == null) return;
        final path = Path()..moveTo(x(from + run.first), y(at(f.a, run.first)));
        for (var n = 1; n < run.length; n++) {
          path.lineTo(x(from + run[n]), y(at(f.a, run[n])));
        }
        for (var n = run.length - 1; n >= 0; n--) {
          path.lineTo(x(from + run[n]), y(at(f.b, run[n])));
        }
        path.close();
        canvas.drawPath(path, _fill..color = c);
      });
    }
  }

  void _candles(ScriptCandles cs) {
    final (i0, i1) = _valueRange;
    final body = math.max(1.0, cw * 0.75);
    for (var i = i0; i <= i1; i++) {
      final op = cs.open[i], hi = cs.high[i], lo = cs.low[i], cl = cs.close[i];
      if (op.isNaN || hi.isNaN || lo.isNaN || cl.isNaN) continue;
      final c = o.colorOf(cs.colorAt(i));
      if (c == null) continue;
      final cx = x(from + i);
      _stroke
        ..color = c
        ..strokeWidth = 1;
      canvas.drawLine(Offset(cx, y(hi)), Offset(cx, y(lo)), _stroke);
      if (cs.bars) {
        canvas.drawLine(Offset(cx - body / 2, y(op)), Offset(cx, y(op)), _stroke);
        canvas.drawLine(Offset(cx, y(cl)), Offset(cx + body / 2, y(cl)), _stroke);
      } else {
        final top = math.min(y(op), y(cl)), bottom = math.max(y(op), y(cl));
        canvas.drawRect(Rect.fromLTRB(cx - body / 2, top, cx + body / 2, math.max(bottom, top + 1)),
            _fill..color = c);
      }
    }
  }

  // ---- 标记和成交点 ----

  void _markers(ScriptMarkers m, List<int> ks) {
    final half = halfOf(m.size);
    const gap = 3.0;
    for (var j = 0; j < m.length; j++) {
      final k = ks[j];
      if (!vis.contains(k)) continue;
      final color = o.colorOf(m.colors[j]);
      if (color == null) continue;
      final cx = x(k);
      final p = m.prices[j];
      final double anchor;
      switch (m.location) {
        case ScriptMarkerLocation.abovebar:
          if (p.isNaN) continue;
          anchor = y(p) - gap;
        case ScriptMarkerLocation.belowbar:
          if (p.isNaN) continue;
          anchor = y(p) + gap;
        case ScriptMarkerLocation.absolute:
          if (p.isNaN) continue;
          anchor = y(p);
        case ScriptMarkerLocation.top:
          anchor = pane.top + gap;
        case ScriptMarkerLocation.bottom:
          anchor = pane.bottom - gap;
      }
      // 形状往远离 K 线的方向画：上方的往上长、下方的往下长
      final up =
          m.location == ScriptMarkerLocation.abovebar || m.location == ScriptMarkerLocation.bottom;
      final down =
          m.location == ScriptMarkerLocation.belowbar || m.location == ScriptMarkerLocation.top;
      final textColor = m.textColor == 0 && m.text != null ? color : o.colorOf(m.textColor);
      if (m.shape == ScriptMarkerShape.labelup || m.shape == ScriptMarkerShape.labeldown) {
        _bubble(
          m.text ?? '',
          Offset(cx, anchor),
          m.shape == ScriptMarkerShape.labelup
              ? ScriptLabelStyle.labelUp
              : ScriptLabelStyle.labelDown,
          color,
          textColor,
          fontOf(m.size == ScriptSize.auto ? ScriptSize.small : m.size),
          ScriptHAlign.center,
        );
        continue;
      }
      final cy = up ? anchor - half : (down ? anchor + half : anchor);
      if (m.shape == ScriptMarkerShape.char) {
        final glyph = text.layout(m.char ?? '•', half * 2.4, color);
        glyph.paint(canvas, Offset(cx - glyph.width / 2, cy - glyph.height / 2));
      } else {
        _shape(_markerShape(m.shape), Offset(cx, cy), half, color);
      }
      final t = m.text;
      if (t != null && textColor != null) {
        final tp = text.layout(t, fontOf(ScriptSize.small), textColor);
        final ty = down || m.location == ScriptMarkerLocation.bottom
            ? cy + half + 2
            : cy - half - 2 - tp.height;
        tp.paint(canvas, Offset(cx - tp.width / 2, ty));
      }
    }
  }

  static ScriptLabelStyle _markerShape(ScriptMarkerShape s) => switch (s) {
        ScriptMarkerShape.triangleup => ScriptLabelStyle.triangleup,
        ScriptMarkerShape.triangledown => ScriptLabelStyle.triangledown,
        ScriptMarkerShape.circle => ScriptLabelStyle.circle,
        ScriptMarkerShape.cross => ScriptLabelStyle.cross,
        ScriptMarkerShape.xcross => ScriptLabelStyle.xcross,
        ScriptMarkerShape.diamond => ScriptLabelStyle.diamond,
        ScriptMarkerShape.square => ScriptLabelStyle.square,
        ScriptMarkerShape.arrowup => ScriptLabelStyle.arrowup,
        ScriptMarkerShape.arrowdown => ScriptLabelStyle.arrowdown,
        ScriptMarkerShape.flag => ScriptLabelStyle.flag,
        _ => ScriptLabelStyle.circle,
      };

  /// 画一个形状，中心 [c]、半径 [h]。
  void _shape(ScriptLabelStyle style, Offset c, double h, Color color) {
    _fill.color = color;
    switch (style) {
      case ScriptLabelStyle.circle:
        canvas.drawCircle(c, h, _fill);
      case ScriptLabelStyle.square:
        canvas.drawRect(Rect.fromCenter(center: c, width: h * 2, height: h * 2), _fill);
      case ScriptLabelStyle.diamond:
        canvas.drawPath(
            Path()
              ..moveTo(c.dx, c.dy - h)
              ..lineTo(c.dx + h, c.dy)
              ..lineTo(c.dx, c.dy + h)
              ..lineTo(c.dx - h, c.dy)
              ..close(),
            _fill);
      case ScriptLabelStyle.triangleup:
        canvas.drawPath(
            Path()
              ..moveTo(c.dx, c.dy - h)
              ..lineTo(c.dx + h, c.dy + h)
              ..lineTo(c.dx - h, c.dy + h)
              ..close(),
            _fill);
      case ScriptLabelStyle.triangledown:
        canvas.drawPath(
            Path()
              ..moveTo(c.dx - h, c.dy - h)
              ..lineTo(c.dx + h, c.dy - h)
              ..lineTo(c.dx, c.dy + h)
              ..close(),
            _fill);
      case ScriptLabelStyle.arrowup || ScriptLabelStyle.arrowdown:
        final d = style == ScriptLabelStyle.arrowup ? 1.0 : -1.0;
        canvas.drawPath(
            Path()
              ..moveTo(c.dx, c.dy - h * d)
              ..lineTo(c.dx + h, c.dy)
              ..lineTo(c.dx + h * 0.4, c.dy)
              ..lineTo(c.dx + h * 0.4, c.dy + h * d)
              ..lineTo(c.dx - h * 0.4, c.dy + h * d)
              ..lineTo(c.dx - h * 0.4, c.dy)
              ..lineTo(c.dx - h, c.dy)
              ..close(),
            _fill);
      case ScriptLabelStyle.cross || ScriptLabelStyle.xcross:
        _stroke
          ..color = color
          ..strokeWidth = math.max(1, h / 3);
        final r = style == ScriptLabelStyle.xcross ? h * 0.8 : h;
        if (style == ScriptLabelStyle.cross) {
          canvas.drawLine(c - Offset(r, 0), c + Offset(r, 0), _stroke);
          canvas.drawLine(c - Offset(0, r), c + Offset(0, r), _stroke);
        } else {
          canvas.drawLine(c - Offset(r, r), c + Offset(r, r), _stroke);
          canvas.drawLine(c + Offset(-r, r), c + Offset(r, -r), _stroke);
        }
      case ScriptLabelStyle.flag:
        _stroke
          ..color = color
          ..strokeWidth = 1;
        canvas.drawLine(
            Offset(c.dx - h * 0.7, c.dy + h), Offset(c.dx - h * 0.7, c.dy - h), _stroke);
        canvas.drawPath(
            Path()
              ..moveTo(c.dx - h * 0.7, c.dy - h)
              ..lineTo(c.dx + h, c.dy - h * 0.5)
              ..lineTo(c.dx - h * 0.7, c.dy)
              ..close(),
            _fill);
      default:
        canvas.drawCircle(c, h, _fill);
    }
  }

  void _trades() {
    if (o.trades.isEmpty) return;
    final s = (cw * 0.35).clamp(3.0, 6.0).toDouble();
    final colors = config.colors;
    final showText = cw >= 6;
    for (var j = 0; j < o.trades.length; j++) {
      final k = r.tradeK[j];
      if (!vis.contains(k)) continue;
      final t = o.trades[j];
      final buy = t.side == ScriptTradeSide.buy;
      final color = buy ? colors.buy : colors.sell;
      final cx = x(k), ty = y(t.price);
      // 买：三角朝上、尖顶在成交价；卖：朝下
      final base = buy ? ty + s * 1.6 : ty - s * 1.6;
      final tri = Path()
        ..moveTo(cx, ty)
        ..lineTo(cx + s, base)
        ..lineTo(cx - s, base)
        ..close();
      if (t.kind == ScriptTradeKind.entry) {
        canvas.drawPath(tri, _fill..color = color);
      } else {
        _stroke
          ..color = color
          ..strokeWidth = 1.2;
        canvas.drawPath(tri, _stroke);
      }
      if (showText && t.id.isNotEmpty) {
        final tp = text.layout(t.id, fontOf(ScriptSize.tiny), color);
        tp.paint(canvas, Offset(cx - tp.width / 2, buy ? base + 1 : base - 1 - tp.height));
      }
    }
  }

  // ---- 画图对象 ----

  double get _leftEdge => pane.left - 1;
  double get _rightEdge => pane.right + 1;

  void _box(ScriptBox b, int k1, int k2) {
    final extL = b.extend == ScriptExtend.left || b.extend == ScriptExtend.both;
    final extR = b.extend == ScriptExtend.right || b.extend == ScriptExtend.both;
    final lo = math.min(k1, k2), hi = math.max(k1, k2);
    if (!extR && lo > vis.last) return;
    if (!extL && hi < vis.first) return;
    final rect = Rect.fromLTRB(
      extL ? _leftEdge : x(lo),
      y(math.max(b.top, b.bottom)),
      extR ? _rightEdge : x(hi),
      y(math.min(b.top, b.bottom)),
    );
    final bg = o.colorOf(b.bg);
    if (bg != null) canvas.drawRect(rect, _fill..color = bg);
    final bc = o.colorOf(b.borderColor);
    if (bc != null && b.borderWidth > 0) {
      final path = Path()..addRect(rect);
      _strokePath(path, bc, b.borderWidth, b.borderStyle);
    }
    final t = b.text;
    final tc = t == null ? null : o.colorOf(t.color);
    if (t != null && tc != null) {
      final tp = text.layout(t.text, t.points ?? fontOf(t.size), tc, t.halign);
      const pad = 3.0;
      final inner = rect.deflate(pad);
      final dx = switch (t.halign) {
        ScriptHAlign.left => inner.left,
        ScriptHAlign.center => inner.center.dx - tp.width / 2,
        ScriptHAlign.right => inner.right - tp.width,
      };
      final dy = switch (t.valign) {
        ScriptVAlign.top => inner.top,
        ScriptVAlign.center => inner.center.dy - tp.height / 2,
        ScriptVAlign.bottom => inner.bottom - tp.height,
      };
      canvas.save();
      canvas.clipRect(rect);
      tp.paint(canvas, Offset(dx, dy));
      canvas.restore();
    }
  }

  void _segment(ScriptSegment l, int k1, int k2) {
    final c = o.colorOf(l.color);
    if (c == null) return;
    final extL = l.extend == ScriptExtend.left || l.extend == ScriptExtend.both;
    final extR = l.extend == ScriptExtend.right || l.extend == ScriptExtend.both;
    if (!extR && math.min(k1, k2) > vis.last) return;
    if (!extL && math.max(k1, k2) < vis.first) return;
    var a = Offset(x(k1), y(l.p1));
    var b = Offset(x(k2), y(l.p2));
    final ends = (a, b);
    if (extL || extR) {
      final dx = b.dx - a.dx;
      if (dx.abs() < 1e-6) {
        // 竖线：往两头延伸到窗格上下沿
        final lo = a.dy < b.dy ? a : b, hi = a.dy < b.dy ? b : a;
        if (extL || extR) {
          a = Offset(lo.dx, pane.top);
          b = Offset(hi.dx, pane.bottom);
        }
      } else {
        final slope = (b.dy - a.dy) / dx;
        final left = a.dx < b.dx ? a : b, right = a.dx < b.dx ? b : a;
        double clampY(double v) => v.clamp(-1e6, 1e6).toDouble();
        final nl = extL ? Offset(_leftEdge, clampY(left.dy + slope * (_leftEdge - left.dx))) : left;
        final nr =
            extR ? Offset(_rightEdge, clampY(right.dy + slope * (_rightEdge - right.dx))) : right;
        a = nl;
        b = nr;
      }
    }
    final style = switch (l.style) {
      ScriptSegmentStyle.dashed => ScriptLineStyle.dashed,
      ScriptSegmentStyle.dotted => ScriptLineStyle.dotted,
      _ => ScriptLineStyle.solid,
    };
    _styledLine(a, b, c, l.width, style);
    final head = 4 + 2 * l.width;
    if (l.style == ScriptSegmentStyle.arrowRight || l.style == ScriptSegmentStyle.arrowBoth) {
      _arrowHead(ends.$1, ends.$2, head, c);
    }
    if (l.style == ScriptSegmentStyle.arrowLeft || l.style == ScriptSegmentStyle.arrowBoth) {
      _arrowHead(ends.$2, ends.$1, head, c);
    }
  }

  /// 在 [to] 处画一个从 [from] 指向 [to] 的实心箭头。
  void _arrowHead(Offset from, Offset to, double size, Color color) {
    final d = to - from;
    final len = d.distance;
    if (len < 1e-6) return;
    final u = d / len;
    final n = Offset(-u.dy, u.dx);
    final base = to - u * size;
    canvas.drawPath(
        Path()
          ..moveTo(to.dx, to.dy)
          ..lineTo(base.dx + n.dx * size * 0.5, base.dy + n.dy * size * 0.5)
          ..lineTo(base.dx - n.dx * size * 0.5, base.dy - n.dy * size * 0.5)
          ..close(),
        _fill..color = color);
  }

  void _label(ScriptLabel l, int k) {
    if (!vis.contains(k) || l.price.isNaN) return;
    final p = Offset(x(k), y(l.price));
    final bg = o.colorOf(l.color);
    final fg = o.colorOf(l.textColor);
    final font = l.points ?? fontOf(l.size);
    switch (l.style) {
      case ScriptLabelStyle.none:
        if (fg == null || l.text.isEmpty) return;
        final tp = text.layout(l.text, font, fg, l.align);
        tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
      case ScriptLabelStyle.labelUp ||
            ScriptLabelStyle.labelDown ||
            ScriptLabelStyle.labelLeft ||
            ScriptLabelStyle.labelRight ||
            ScriptLabelStyle.labelCenter ||
            ScriptLabelStyle.labelUpperLeft ||
            ScriptLabelStyle.labelUpperRight ||
            ScriptLabelStyle.labelLowerLeft ||
            ScriptLabelStyle.labelLowerRight:
        _bubble(l.text, p, l.style, bg, fg, font, l.align);
      default:
        // 形状样式：形状画在锚点，文字在形状上方（朝上的形状放下方）
        final h = l.points != null
            ? l.points! / 2
            : halfOf(l.size == ScriptSize.normal ? ScriptSize.small : l.size);
        if (bg != null) _shape(l.style, p, h, bg);
        if (fg != null && l.text.isNotEmpty) {
          final tp = text.layout(l.text, font, fg, l.align);
          final below =
              l.style == ScriptLabelStyle.triangleup || l.style == ScriptLabelStyle.arrowup;
          tp.paint(
              canvas, Offset(p.dx - tp.width / 2, below ? p.dy + h + 2 : p.dy - h - 2 - tp.height));
        }
    }
  }

  /// 带箭头的气泡：箭头尖在 [p]，气泡按 [style] 放在它的某一侧。
  void _bubble(String s, Offset p, ScriptLabelStyle style, Color? bg, Color? fg, double font,
      ScriptHAlign align) {
    if (bg == null && (fg == null || s.isEmpty)) return;
    final tp = s.isEmpty || fg == null ? null : text.layout(s, font, fg, align);
    const padH = 4.0, padV = 2.0, ptr = 5.0;
    final w = (tp?.width ?? 4) + padH * 2;
    final h = (tp?.height ?? 4) + padV * 2;
    const diag = ptr * 0.8;
    final Rect box;
    final List<Offset> pointer;
    switch (style) {
      case ScriptLabelStyle.labelUp:
        box = Rect.fromLTWH(p.dx - w / 2, p.dy + ptr, w, h);
        pointer = [p, Offset(p.dx + ptr, box.top), Offset(p.dx - ptr, box.top)];
      case ScriptLabelStyle.labelDown:
        box = Rect.fromLTWH(p.dx - w / 2, p.dy - ptr - h, w, h);
        pointer = [p, Offset(p.dx + ptr, box.bottom), Offset(p.dx - ptr, box.bottom)];
      case ScriptLabelStyle.labelLeft:
        box = Rect.fromLTWH(p.dx + ptr, p.dy - h / 2, w, h);
        pointer = [p, Offset(box.left, p.dy - ptr), Offset(box.left, p.dy + ptr)];
      case ScriptLabelStyle.labelRight:
        box = Rect.fromLTWH(p.dx - ptr - w, p.dy - h / 2, w, h);
        pointer = [p, Offset(box.right, p.dy - ptr), Offset(box.right, p.dy + ptr)];
      case ScriptLabelStyle.labelUpperLeft:
        box = Rect.fromLTWH(p.dx + diag, p.dy + diag, w, h);
        pointer = [p, Offset(box.left + ptr, box.top), Offset(box.left, box.top + ptr)];
      case ScriptLabelStyle.labelUpperRight:
        box = Rect.fromLTWH(p.dx - diag - w, p.dy + diag, w, h);
        pointer = [p, Offset(box.right - ptr, box.top), Offset(box.right, box.top + ptr)];
      case ScriptLabelStyle.labelLowerLeft:
        box = Rect.fromLTWH(p.dx + diag, p.dy - diag - h, w, h);
        pointer = [p, Offset(box.left + ptr, box.bottom), Offset(box.left, box.bottom - ptr)];
      case ScriptLabelStyle.labelLowerRight:
        box = Rect.fromLTWH(p.dx - diag - w, p.dy - diag - h, w, h);
        pointer = [p, Offset(box.right - ptr, box.bottom), Offset(box.right, box.bottom - ptr)];
      default:
        box = Rect.fromCenter(center: p, width: w, height: h);
        pointer = const [];
    }
    if (bg != null) {
      canvas.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(2)), _fill..color = bg);
      if (pointer.isNotEmpty) {
        canvas.drawPath(
            Path()
              ..moveTo(pointer[0].dx, pointer[0].dy)
              ..lineTo(pointer[1].dx, pointer[1].dy)
              ..lineTo(pointer[2].dx, pointer[2].dy)
              ..close(),
            _fill);
      }
    }
    tp?.paint(canvas, Offset(box.left + padH, box.top + padV));
  }

  void _table(ScriptTable t) {
    if (t.cells.isEmpty || t.columns <= 0 || t.rows <= 0) return;
    const padH = 4.0, padV = 2.0, margin = 4.0;
    final widths = List<double>.filled(t.columns, 0);
    final heights = List<double>.filled(t.rows, 0);
    final painted = <(ScriptTableCell, TextPainter?)>[];
    for (final c in t.cells) {
      final fg = o.colorOf(c.textColor);
      final tp = c.text.isEmpty
          ? null
          : text.layout(
              c.text, c.points ?? fontOf(c.size), fg ?? const Color(0x00000000), c.halign);
      painted.add((c, fg == null ? null : tp));
      final w = (tp?.width ?? 0) + padH * 2;
      final h = (tp?.height ?? c.points ?? fontOf(c.size)) + padV * 2;
      if (w > widths[c.column]) widths[c.column] = w;
      if (h > heights[c.row]) heights[c.row] = h;
    }
    final tw = widths.fold<double>(0, (a, b) => a + b);
    final th = heights.fold<double>(0, (a, b) => a + b);
    final name = t.position.name;
    final left = name.endsWith('Left')
        ? pane.left + margin
        : name.endsWith('Center')
            ? (pane.left + pane.right - tw) / 2
            : pane.right - margin - tw;
    final top = name.startsWith('top')
        ? pane.top + margin
        : name.startsWith('middle')
            ? (pane.top + pane.bottom - th) / 2
            : pane.bottom - margin - th;
    final table = Rect.fromLTWH(left, top, tw, th);
    final bg = o.colorOf(t.bg);
    if (bg != null) canvas.drawRect(table, _fill..color = bg);
    double colX(int c) => left + widths.take(c).fold<double>(0, (a, b) => a + b);
    double rowY(int r) => top + heights.take(r).fold<double>(0, (a, b) => a + b);
    for (final (c, tp) in painted) {
      final cell = Rect.fromLTWH(colX(c.column), rowY(c.row), widths[c.column], heights[c.row]);
      final cbg = o.colorOf(c.bg);
      if (cbg != null) canvas.drawRect(cell, _fill..color = cbg);
      if (tp == null) continue;
      final dx = switch (c.halign) {
        ScriptHAlign.left => cell.left + padH,
        ScriptHAlign.center => cell.center.dx - tp.width / 2,
        ScriptHAlign.right => cell.right - padH - tp.width,
      };
      tp.paint(canvas, Offset(dx, cell.center.dy - tp.height / 2));
    }
    final bc = o.colorOf(t.borderColor);
    if (bc != null && t.borderWidth > 0) {
      _stroke
        ..color = bc
        ..strokeWidth = t.borderWidth;
      for (var c = 1; c < t.columns; c++) {
        canvas.drawLine(Offset(colX(c), top), Offset(colX(c), top + th), _stroke);
      }
      for (var r = 1; r < t.rows; r++) {
        canvas.drawLine(Offset(left, rowY(r)), Offset(left + tw, rowY(r)), _stroke);
      }
    }
    final fc = o.colorOf(t.frameColor);
    if (fc != null && t.frameWidth > 0) {
      _stroke
        ..color = fc
        ..strokeWidth = t.frameWidth;
      canvas.drawRect(table, _stroke);
    }
  }

  // ---- 右轴最新值 ----

  void _trackPrices() {
    for (final s in o.series) {
      if (!s.visible || !s.trackPrice || !_here(s.mainPane)) continue;
      var i = math.min(o.bars.count - 1, layout.itemCount - 1 - from);
      while (i >= 0 && s.values[i].isNaN) {
        i--;
      }
      if (i < 0) continue;
      final c = o.colorOf(s.colorAt(i));
      if (c == null) continue;
      final v = s.values[i];
      final label = o.precision != null ? v.toStringAsFixed(o.precision!) : formatter.price(v);
      final tp = text.layout(label, config.fontSize, config.colors.labelText);
      final h = tp.height + 4;
      final cy = y(v).clamp(pane.top + h / 2, pane.bottom - h / 2).toDouble();
      final box = Rect.fromLTRB(
          layout.size.width - tp.width - 8, cy - h / 2, layout.size.width, cy + h / 2);
      canvas.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(2)), _fill..color = c);
      tp.paint(canvas, Offset(box.left + 4, cy - tp.height / 2));
    }
  }

  // ---- 线型 ----

  void _styledLine(Offset a, Offset b, Color color, double width, ScriptLineStyle style) {
    if (style == ScriptLineStyle.solid) {
      _stroke
        ..color = color
        ..strokeWidth = math.max(0.5, width)
        ..strokeCap = StrokeCap.butt;
      canvas.drawLine(a, b, _stroke);
      return;
    }
    _strokePath(
        Path()
          ..moveTo(a.dx, a.dy)
          ..lineTo(b.dx, b.dy),
        color,
        width,
        style);
  }

  void _strokePath(Path path, Color color, double width, ScriptLineStyle style) {
    _stroke
      ..color = color
      ..strokeWidth = math.max(0.5, width)
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = style == ScriptLineStyle.dotted ? StrokeCap.round : StrokeCap.butt;
    if (style == ScriptLineStyle.solid) {
      canvas.drawPath(path, _stroke);
      return;
    }
    final w = math.max(1.0, width);
    final on = style == ScriptLineStyle.dashed ? 4 + w * 2 : 0.01;
    final off = style == ScriptLineStyle.dashed ? 3 + w : w * 2.5;
    final dashed = Path();
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += on + off) {
        dashed.addPath(m.extractPath(d, math.min(d + on, m.length)), Offset.zero);
      }
    }
    canvas.drawPath(dashed, _stroke);
    _stroke.strokeCap = StrokeCap.butt;
  }
}
