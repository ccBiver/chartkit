import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../chart/chart_layout.dart';
import '../chart/chart_renderer.dart' show indexForTime;
import '../model/candle.dart';
import 'drawing.dart';

/// 选中画线时端点圆点的半径（逻辑像素）。
const double drawingHandleRadius = 4;

/// 手指点中线身的容差（逻辑像素）。
const double drawingHitSlop = 10;

/// 手指点中端点的容差（逻辑像素），比线身大，端点好抓。
const double drawingHandleSlop = 18;

/// 江恩扇形的 9 条角度线：价格方向斜率 = 1×1 线斜率 × 比值。
const List<(double, String)> gannFanRatios = [
  (1 / 8, '1×8'), (1 / 4, '1×4'), (1 / 3, '1×3'), (1 / 2, '1×2'), //
  (1, '1×1'),
  (2, '2×1'), (3, '3×1'), (4, '4×1'), (8, '8×1'),
];

/// K 线时间 ↔ 小数索引。
///
/// 每根 K 线的开盘时间落在它的中心（与时间轴标签同一口径），相邻两根之间按时间线性插值，
/// 数据范围之外按周期 [interval] 外推。所以别的周期画的锚点（比如 1 分钟图上的 10:37）
/// 在 1 小时图上落在 10:00 和 11:00 两根之间的 37/60 处，切回 1 分钟图又回到原处。
class DrawingTimeline {
  DrawingTimeline(this.candles, this.interval) : assert(candles.isNotEmpty && interval > 0);

  final List<Candle> candles;

  /// 周期毫秒数（通常是 `TimeFrame.millis`）。
  final int interval;

  double indexOf(int time) {
    final first = candles.first.time;
    final last = candles.last.time;
    if (time <= first) return (time - first) / interval;
    if (time >= last) return candles.length - 1 + (time - last) / interval;
    final i = indexForTime(candles, time);
    final t0 = candles[i].time;
    final t1 = candles[i + 1].time;
    return i + (time - t0) / (t1 - t0);
  }

  int timeAt(double index) {
    final lastIndex = candles.length - 1;
    if (index <= 0) return (candles.first.time + index * interval).round();
    if (index >= lastIndex) return (candles.last.time + (index - lastIndex) * interval).round();
    final i = index.floor();
    final t0 = candles[i].time;
    return (t0 + (index - i) * (candles[i + 1].time - t0)).round();
  }
}

/// 一帧的「锚点 ↔ 屏幕」换算：主图矩形、横向视口、价格区间。与渲染层共用同一份布局。
@immutable
class DrawingProjection {
  const DrawingProjection({
    required this.rect,
    required this.timeline,
    required this.rightFloat,
    required this.candleWidth,
    required this.priceMin,
    required this.priceMax,
    this.logScale = false,
    double? priceTop,
  }) : _priceTop = priceTop;

  factory DrawingProjection.of(ChartLayout layout, DrawingTimeline timeline) => DrawingProjection(
        rect: layout.mainRect,
        timeline: timeline,
        rightFloat: layout.rightFloat,
        candleWidth: layout.candleWidth,
        priceMin: layout.priceMin,
        priceMax: layout.priceMax,
        logScale: layout.logScale,
        priceTop: layout.mainContentTop,
      );

  /// 主图矩形（蜡烛区，不含右轴、量图、副图）。
  final Rect rect;
  final DrawingTimeline timeline;
  final double rightFloat;
  final double candleWidth;
  final double priceMin;
  final double priceMax;

  /// 主图价格轴按对数刻度。
  final bool logScale;

  /// 价格映射的顶边（`ChartLayout.mainContentTop`）；不传时等于 [rect] 的顶。
  double get priceTop => _priceTop ?? rect.top;
  final double? _priceTop;

  /// 小数索引 → 像素 X（整数索引落在蜡烛中心）。
  double indexToX(double index) => rect.right - (rightFloat - index + 0.5) * candleWidth;

  /// 像素 X → 小数索引（[indexToX] 的反函数）。
  double xToIndex(double x) => rightFloat + 0.5 - (rect.right - x) / candleWidth;

  double priceToY(double price) =>
      ChartLayout.priceToPixel(price, priceTop, rect.bottom, priceMin, priceMax, log: logScale);

  double yToPrice(double y) =>
      ChartLayout.pixelToPrice(y, priceTop, rect.bottom, priceMin, priceMax, log: logScale);

  double timeToX(int time) => indexToX(timeline.indexOf(time));

  Offset toScreen(DrawingAnchor a) => Offset(timeToX(a.time), priceToY(a.price));

  /// 像素位置 → 锚点，时间吸到最近一根（可落在右侧留白或最早一根之前）。
  DrawingAnchor fromScreen(Offset p) =>
      DrawingAnchor(timeline.timeAt(xToIndex(p.dx).roundToDouble()), yToPrice(p.dy));

  /// 新建时的落点：时间吸到最近一根；离那根的开高低收在 [radius] 像素以内时价格吸过去。
  DrawingAnchor snap(Offset p, {double radius = 0}) {
    final index = xToIndex(p.dx).round();
    final time = timeline.timeAt(index.toDouble());
    var price = yToPrice(p.dy);
    final candles = timeline.candles;
    if (radius > 0 && index >= 0 && index < candles.length) {
      final c = candles[index];
      var best = radius;
      for (final v in [c.open, c.high, c.low, c.close]) {
        final d = (priceToY(v) - p.dy).abs();
        if (d <= best) {
          best = d;
          price = v;
        }
      }
    }
    return DrawingAnchor(time, price);
  }
}

// ───────────────────────── 基础几何 ─────────────────────────

/// 点 [p] 到线段 [a]-[b] 的距离。
double distanceToSegment(Offset p, Offset a, Offset b) {
  final d = b - a;
  final len2 = d.dx * d.dx + d.dy * d.dy;
  final t = len2 == 0 ? 0.0 : (((p - a).dx * d.dx + (p - a).dy * d.dy) / len2).clamp(0.0, 1.0);
  return (p - (a + d * t)).distance;
}

/// 从 [from] 沿 [dir] 方向射出，离开 [bounds] 时的点；方向为零时返回 [from]。
Offset rayEnd(Offset from, Offset dir, Rect bounds) {
  if (dir.dx == 0 && dir.dy == 0) return from;
  var t = double.infinity;
  if (dir.dx > 0) t = math.min(t, (bounds.right - from.dx) / dir.dx);
  if (dir.dx < 0) t = math.min(t, (bounds.left - from.dx) / dir.dx);
  if (dir.dy > 0) t = math.min(t, (bounds.bottom - from.dy) / dir.dy);
  if (dir.dy < 0) t = math.min(t, (bounds.top - from.dy) / dir.dy);
  if (!(t > 0) || t == double.infinity) return from;
  return from + dir * t;
}

/// 斐波那契各档的价格：第 1 个点是 1，第 2 个点是 0（与 TradingView 相同）。
List<(double, double)> fibLevelPrices(double p1, double p2, List<double> levels) => [
      for (final l in levels) (l, p2 + (p1 - p2) * l),
    ];

/// 江恩扇形各角度线从 [origin] 出发到图边的终点；[second] 决定 1×1 线。
List<(double, String, Offset)> gannFanRays(Offset origin, Offset second, Rect bounds) {
  final d = second - origin;
  if (d.dx == 0 && d.dy == 0) return const [];
  return [
    for (final (r, label) in gannFanRatios)
      (r, label, rayEnd(origin, Offset(d.dx, d.dy * r), bounds)),
  ];
}

/// 安德鲁分叉：中线从 [p0] 穿过 [p1]、[p2] 的中点，上下两条叉线从 [p1]、[p2] 出发与中线平行，都延到图边。
({Offset median, Offset upper, Offset lower}) pitchforkEnds(
  Offset p0,
  Offset p1,
  Offset p2,
  Rect bounds,
) {
  final mid = (p1 + p2) / 2;
  final dir = mid - p0;
  return (
    median: rayEnd(p0, dir, bounds),
    upper: rayEnd(p1, dir, bounds),
    lower: rayEnd(p2, dir, bounds),
  );
}

/// 头寸的盈亏：[reward]、[risk] 按交易方向取正，[ratio] 是盈亏比（reward / risk）。
typedef PositionStats = ({
  double reward,
  double risk,
  double ratio,
  double rewardPercent,
  double riskPercent,
});

PositionStats positionStats({
  required bool long,
  required double entry,
  required double target,
  required double stop,
}) {
  final reward = long ? target - entry : entry - target;
  final risk = long ? entry - stop : stop - entry;
  return (
    reward: reward,
    risk: risk,
    ratio: risk != 0 ? reward / risk : 0,
    rewardPercent: entry != 0 ? reward / entry * 100 : 0,
    riskPercent: entry != 0 ? risk / entry * 100 : 0,
  );
}

/// 价格区间测量：价差、涨跌幅（%）、跨过的 K 线根数。
typedef RangeStats = ({double diff, double percent, int bars});

RangeStats rangeStats(DrawingAnchor a, DrawingAnchor b, DrawingTimeline timeline) => (
      diff: b.price - a.price,
      percent: a.price != 0 ? (b.price - a.price) / a.price * 100 : 0,
      bars: (timeline.indexOf(b.time) - timeline.indexOf(a.time)).round(),
    );

/// 把新建时点下的锚点补成完整锚点。头寸工具点 2 下（入场、目标），
/// 目标按方向放到入场的正确一侧，止损按 1:1 放在另一侧，止损时间与入场相同。
List<DrawingAnchor> completeAnchors(DrawingTool tool, List<DrawingAnchor> placed) {
  if (!tool.isPosition) return placed;
  final entry = placed[0];
  final second = placed.length > 1 ? placed[1] : placed[0];
  var dist = (second.price - entry.price).abs();
  if (dist == 0) dist = entry.price.abs() * 0.01;
  if (dist == 0) dist = 1;
  final sign = tool == DrawingTool.longPosition ? 1 : -1;
  return [
    entry,
    DrawingAnchor(second.time, entry.price + sign * dist),
    DrawingAnchor(entry.time, entry.price - sign * dist),
  ];
}

// ───────────────────────── 编辑 ─────────────────────────

/// 把第 [handle] 个端点拖到 [to]。
///
/// 水平线只改价格，垂直线只改时间；头寸的止损只改价格（时间跟着入场），拖入场时止损的时间一起走。
Drawing moveHandle(Drawing d, int handle, DrawingAnchor to) {
  final anchors = [...d.anchors];
  switch (d.tool) {
    case DrawingTool.horizontalLine:
      anchors[0] = anchors[0].copyWith(price: to.price);
    case DrawingTool.verticalLine:
      anchors[0] = anchors[0].copyWith(time: to.time);
    case DrawingTool.longPosition || DrawingTool.shortPosition:
      if (handle == 0) {
        anchors[0] = to;
        anchors[2] = anchors[2].copyWith(time: to.time);
      } else if (handle == 1) {
        anchors[1] = to;
      } else {
        anchors[2] = DrawingAnchor(anchors[0].time, to.price);
      }
    default:
      anchors[handle] = to;
  }
  return d.copyWith(anchors: anchors);
}

/// 整体平移：时间方向移 [bars] 根（按当前周期的 K 线），价格先乘 [priceFactor] 再加 [priceDelta]。
Drawing translateDrawing(Drawing d, DrawingTimeline timeline, int bars, double priceDelta,
        {double priceFactor = 1}) =>
    d.copyWith(anchors: [
      for (final a in d.anchors)
        DrawingAnchor(
          bars == 0 ? a.time : timeline.timeAt(timeline.indexOf(a.time) + bars),
          a.price * priceFactor + priceDelta,
        ),
    ]);

// ───────────────────────── 形状与命中 ─────────────────────────

/// 一条画线在屏幕上的可点部分：端点、线段、填充区域。绘制、命中、选中框共用。
@immutable
class DrawingShape {
  const DrawingShape({required this.handles, this.segments = const [], this.areas = const []});

  /// 端点位置，下标与 [moveHandle] 的 handle 一致。
  final List<Offset> handles;
  final List<(Offset, Offset)> segments;
  final List<Rect> areas;

  /// 包住整条画线的矩形（不裁切）。
  Rect get bounds {
    var r = Rect.fromPoints(handles.first, handles.first);
    for (final h in handles) {
      r = r.expandToInclude(Rect.fromPoints(h, h));
    }
    for (final (a, b) in segments) {
      r = r.expandToInclude(Rect.fromPoints(a, b));
    }
    for (final a in areas) {
      r = r.expandToInclude(a);
    }
    return r;
  }
}

/// 命中结果：[handle] 为端点下标，null 表示点中线身。
@immutable
class DrawingHit {
  const DrawingHit(this.handle);

  final int? handle;

  bool get isBody => handle == null;
}

/// 屏幕上的端点和线段。只用到 [p] 的映射，不依赖画布。
DrawingShape shapeOf(Drawing d, DrawingProjection p) {
  final rect = p.rect;
  final pts = [for (final a in d.anchors) p.toScreen(a)];
  switch (d.tool) {
    case DrawingTool.horizontalLine:
      final y = pts[0].dy;
      return DrawingShape(
        handles: [Offset(rect.center.dx, y)],
        segments: [(Offset(rect.left, y), Offset(rect.right, y))],
      );
    case DrawingTool.verticalLine:
      final x = pts[0].dx;
      return DrawingShape(
        handles: [Offset(x, rect.center.dy)],
        segments: [(Offset(x, rect.top), Offset(x, rect.bottom))],
      );
    case DrawingTool.trendLine:
      return DrawingShape(handles: pts, segments: [(pts[0], pts[1])]);
    case DrawingTool.ray:
      return DrawingShape(
        handles: pts,
        segments: [(pts[0], rayEnd(pts[0], pts[1] - pts[0], rect))],
      );
    case DrawingTool.rectangle || DrawingTool.priceRange:
      return DrawingShape(handles: pts, areas: [Rect.fromPoints(pts[0], pts[1])]);
    case DrawingTool.fibRetracement:
      final (left, right) = fibSpan(pts[0], pts[1], rect);
      final ys = [
        for (final (_, price)
            in fibLevelPrices(d.anchors[0].price, d.anchors[1].price, d.fibLevels))
          p.priceToY(price),
      ];
      return DrawingShape(
        handles: pts,
        segments: [
          (pts[0], pts[1]),
          for (final y in ys) (Offset(left, y), Offset(right, y)),
        ],
      );
    case DrawingTool.longPosition || DrawingTool.shortPosition:
      final (left, right) = positionSpan(pts[0], pts[1]);
      return DrawingShape(
        handles: pts,
        areas: [
          Rect.fromLTRB(
              left, math.min(pts[0].dy, pts[1].dy), right, math.max(pts[0].dy, pts[1].dy)),
          Rect.fromLTRB(
              left, math.min(pts[0].dy, pts[2].dy), right, math.max(pts[0].dy, pts[2].dy)),
        ],
      );
    case DrawingTool.gannFan:
      return DrawingShape(
        handles: pts,
        segments: [for (final (_, _, end) in gannFanRays(pts[0], pts[1], rect)) (pts[0], end)],
      );
    case DrawingTool.pitchfork:
      final ends = pitchforkEnds(pts[0], pts[1], pts[2], rect);
      return DrawingShape(handles: pts, segments: [
        (pts[0], ends.median),
        (pts[1], ends.upper),
        (pts[2], ends.lower),
        (pts[1], pts[2]),
      ]);
    case DrawingTool.elliottWave:
      return DrawingShape(handles: pts, segments: [
        for (var i = 1; i < pts.length; i++) (pts[i - 1], pts[i]),
      ]);
  }
}

/// 斐波那契横线的左右端：两点之间；两点几乎同一根时延到图右边。
(double, double) fibSpan(Offset a, Offset b, Rect rect) {
  final left = math.min(a.dx, b.dx);
  final right = math.max(a.dx, b.dx);
  return right - left < 1 ? (left, rect.right) : (left, right);
}

/// 头寸方框的左右端：入场与目标之间，至少 24 像素宽。
(double, double) positionSpan(Offset entry, Offset target) {
  final left = math.min(entry.dx, target.dx);
  final right = math.max(entry.dx, target.dx);
  return (left, math.max(right, left + 24));
}

/// [pos] 点中了 [shape] 的哪里：先端点（[withHandles] 时，取最近的），再线段，再填充区域。
DrawingHit? hitTestShape(DrawingShape shape, Offset pos, {bool withHandles = true}) {
  if (withHandles) {
    int? best;
    var bestDist = drawingHandleSlop;
    for (var i = 0; i < shape.handles.length; i++) {
      final dist = (shape.handles[i] - pos).distance;
      if (dist <= bestDist) {
        bestDist = dist;
        best = i;
      }
    }
    if (best != null) return DrawingHit(best);
  }
  for (final (a, b) in shape.segments) {
    if (distanceToSegment(pos, a, b) <= drawingHitSlop) return const DrawingHit(null);
  }
  for (final area in shape.areas) {
    if (area.inflate(drawingHitSlop / 2).contains(pos)) return const DrawingHit(null);
  }
  return null;
}
