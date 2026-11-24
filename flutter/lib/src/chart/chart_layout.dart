import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../indicator/indicator.dart';
import '../model/candle.dart';
import 'chart_theme.dart';

/// 全部副图（含图例行与间隙）最多占绘图区高度的比例。
const double _maxSubShare = 0.6;

/// 纵向窗格分配：主图 + (成交量) + 各副图。副图按各自动画权重（0..1）分配高度。
@immutable
class PaneSplit {
  const PaneSplit._({
    required this.mainBottom,
    required this.volTop,
    required this.volBottom,
    required this.subFullHeight,
    required this.subPaneHeights,
  });

  factory PaneSplit.compute({
    required double chartHeight,
    required ChartDims dims,
    required bool showVolume,
    required List<double> subWeights,
  }) {
    final volH = showVolume ? chartHeight * dims.volumePaneFraction : 0.0;
    final subUnits = subWeights.fold<double>(0, (a, b) => a + b);
    final perSubFull = chartHeight * dims.subPaneFraction;
    // 副图过多时整体缩放，避免挤掉主图
    final overflow = subUnits > 0 && perSubFull * subUnits > chartHeight * 0.5;
    final subFull = overflow ? chartHeight * 0.5 / subUnits : perSubFull;
    // 每格高 = 指标绘图高 + 图例行高，整体按动画权重伸缩
    final rawHeights = [for (final w in subWeights) (subFull + dims.subLegendHeight) * w];
    final rawSum = rawHeights.fold<double>(0, (a, b) => a + b);
    final gaps = dims.paneGap * subUnits;
    // 图例行与间隙不参与上面的缩放；矮图 + 多副图时再整体压一次，给主图留出至少 ~1/4 高度
    final cap = chartHeight * _maxSubShare;
    final squeeze = rawSum + gaps > cap && rawSum > 0 ? math.max(0.0, cap - gaps) / rawSum : 1.0;
    final heights = [for (final h in rawHeights) h * squeeze];
    final subTotal = rawSum * squeeze + gaps;
    final mainBottom = chartHeight - volH - subTotal;
    final gap = showVolume ? dims.paneGap : 0.0;
    return PaneSplit._(
      mainBottom: mainBottom,
      volTop: mainBottom + gap,
      volBottom: mainBottom + volH,
      subFullHeight: subFull,
      subPaneHeights: List.unmodifiable(heights),
    );
  }

  final double mainBottom;
  final double volTop;
  final double volBottom;

  /// 副图指标绘图区的稳定态高度（不含图例行、不随动画权重变化）。
  final double subFullHeight;

  /// 各副图当前可见高度（含图例行，已乘动画权重）。
  final List<double> subPaneHeights;
}

/// 一个副图窗格在当前帧的位置。
@immutable
class SubPaneRect {
  const SubPaneRect({
    required this.top,
    required this.height,
    required this.contentTop,
    required this.contentHeight,
  });

  /// 窗格顶（图例行顶）。
  final double top;

  /// 当前可见高度（动画中会小于完整高度）。
  final double height;

  /// 指标绘图区顶（图例行之下）。
  final double contentTop;

  /// 指标绘图区的稳定态高度。
  final double contentHeight;

  double get bottom => top + height;
}

/// 一帧的完整几何信息：窗格、可见区间、价格区间与坐标换算。
/// 纯计算、不可变；渲染、手势命中与 [KLineChartMapper] 共用同一份，保证互不漂移。
@immutable
class ChartLayout {
  const ChartLayout._({
    required this.size,
    required this.chartWidth,
    required this.chartHeight,
    required this.candleWidth,
    required this.mainBottom,
    required this.volTop,
    required this.volBottom,
    required this.subPanes,
    required this.minOffset,
    required this.maxOffset,
    required this.offset,
    required this.rightFloat,
    required this.firstIndex,
    required this.lastIndex,
    required this.priceMin,
    required this.priceMax,
    required this.itemCount,
  });

  /// [candles] 不可为空；[candleWidth] 必须 > 0。
  factory ChartLayout.compute({
    required Size size,
    required List<Candle> candles,
    required double candleWidth,
    required double scrollOffset,
    required ChartDims dims,
    required bool showVolume,
    required double blankScrollRatio,
    double blankScrollWidth = 0,
    required List<double> subWeights,
    required List<IndicatorSeries> mainSeries,
    required double Function(String text) measureText,
    required String Function(double price) formatPrice,
    required double labelPad,
    ({double min, double max})? Function(int first, int last)? extraMainRange,
    bool closeOnly = false,
  }) {
    assert(candles.isNotEmpty && candleWidth > 0);
    final last = candles.length - 1;
    final blank = math.min(blankScrollRatio, 0.9);

    // 给定蜡烛区宽度时的滚动范围与可见区间
    _Viewport viewport(double width) {
      final maxOff = math.max(0.0, candles.length * candleWidth - width);
      // 绝对宽度优先于比例；两者都不超过蜡烛区的 90%
      final minOff = blankScrollWidth > 0
          ? -math.min(blankScrollWidth, width * 0.9)
          : (blank > 0 ? -width * blank : 0.0);
      final off = scrollOffset.clamp(minOff, maxOff).toDouble();
      final rf = last - off / candleWidth;
      return _Viewport(
        minOffset: minOff,
        maxOffset: maxOff,
        offset: off,
        rightFloat: rf,
        first: (rf - width / candleWidth).floor().clamp(0, last),
        last: rf.ceil().clamp(0, last),
      );
    }

    // 自适应右轴：先用最小留白粗算可见价格区间，量出最宽价格标签，
    // 把右轴撑到「最长价格 + 内边距」，蜡烛区不会被价格标签压住。
    final rough = viewport(math.max(1.0, size.width - dims.rightAxisWidth));
    final roughRange =
        _priceRange(candles, mainSeries, rough.first, rough.last, extraMainRange, closeOnly);
    final widest = math.max(
      measureText(formatPrice(roughRange.max)),
      measureText(formatPrice(roughRange.min)),
    );
    final rightAxis = math.max(dims.rightAxisWidth, widest + labelPad * 2);
    final chartWidth = math.max(1.0, size.width - rightAxis);

    final chartHeight = size.height - dims.bottomAxisHeight;
    final split = PaneSplit.compute(
      chartHeight: chartHeight,
      dims: dims,
      showVolume: showVolume,
      subWeights: subWeights,
    );
    final vp = viewport(chartWidth);
    final range = _priceRange(candles, mainSeries, vp.first, vp.last, extraMainRange, closeOnly);

    return ChartLayout._(
      size: size,
      chartWidth: chartWidth,
      chartHeight: chartHeight,
      candleWidth: candleWidth,
      mainBottom: split.mainBottom,
      volTop: split.volTop,
      volBottom: split.volBottom,
      subPanes: _subPanes(split, subWeights, dims),
      minOffset: vp.minOffset,
      maxOffset: vp.maxOffset,
      offset: vp.offset,
      rightFloat: vp.rightFloat,
      firstIndex: vp.first,
      lastIndex: vp.last,
      priceMin: range.min,
      priceMax: range.max,
      itemCount: candles.length,
    );
  }

  final Size size;

  /// 蜡烛区宽度（不含右轴）。
  final double chartWidth;

  /// 绘图区高度（不含底部时间轴）。
  final double chartHeight;
  final double candleWidth;
  final double mainBottom;
  final double volTop;
  final double volBottom;
  final List<SubPaneRect> subPanes;

  /// 滚动下界（<0 表示允许拖离右边缘留白）。
  final double minOffset;
  final double maxOffset;

  /// 已钳制的滚动偏移。
  final double offset;

  /// 贴右边缘的数据索引（可为小数）。
  final double rightFloat;
  final int firstIndex;
  final int lastIndex;

  /// 主图价格区间（已含上下 6% 留白）。
  final double priceMin;
  final double priceMax;
  final int itemCount;

  double get mainTop => 0;

  double get rightAxisWidth => size.width - chartWidth;

  Rect get mainRect => Rect.fromLTRB(0, mainTop, chartWidth, mainBottom);

  /// 蜡烛索引 → 像素 X（蜡烛中心）。
  double centerX(int index) => chartWidth - (rightFloat - index + 0.5) * candleWidth;

  /// 像素 X → 蜡烛索引。上界放宽到右边缘槽位，允许落入右侧留白（虚拟索引 > 末根）。
  int indexAtX(double x) {
    final idx = (rightFloat - (chartWidth - x) / candleWidth).round();
    final upper = math.max(rightFloat.ceil(), math.max(itemCount - 1, 0));
    return idx.clamp(0, upper);
  }

  /// 价格 → 主图像素 Y。
  double priceToY(double price) => valueToY(price, mainTop, mainBottom, priceMin, priceMax);

  /// 主图像素 Y → 价格（[priceToY] 的反函数）。
  double yToPrice(double y) =>
      priceMax - (y - mainTop) / (mainBottom - mainTop) * (priceMax - priceMin);

  /// 把数值 [v] 从区间 [lo]..[hi] 线性映射到像素区间 [top]..[bottom]（大值在上）。
  static double valueToY(double v, double top, double bottom, double lo, double hi) =>
      top + (hi - v) / (hi - lo) * (bottom - top);

  static List<SubPaneRect> _subPanes(PaneSplit split, List<double> weights, ChartDims dims) {
    final panes = <SubPaneRect>[];
    var top = split.volBottom;
    for (var p = 0; p < weights.length; p++) {
      // 间隙随权重缩放，保证所有副图始终落在绘图区内、不侵入底部时间轴
      top += dims.paneGap * weights[p];
      final height = split.subPaneHeights[p];
      panes.add(SubPaneRect(
        top: top,
        height: height,
        contentTop: top + dims.subLegendHeight,
        contentHeight: split.subFullHeight,
      ));
      top += height;
    }
    return List.unmodifiable(panes);
  }
}

class _Viewport {
  const _Viewport({
    required this.minOffset,
    required this.maxOffset,
    required this.offset,
    required this.rightFloat,
    required this.first,
    required this.last,
  });

  final double minOffset;
  final double maxOffset;
  final double offset;
  final double rightFloat;
  final int first;
  final int last;
}

/// 一组数值在 [first]..[last] 内的 (min, max)；全为空时返回 null。
({double min, double max})? valueRange(Iterable<List<double?>> lines, int first, int last) {
  var lo = double.infinity;
  var hi = double.negativeInfinity;
  for (final values in lines) {
    final end = math.min(last, values.length - 1);
    for (var i = first; i <= end; i++) {
      final v = values[i];
      if (v == null || !v.isFinite) continue;
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
  }
  return lo.isFinite ? (min: lo, max: hi) : null;
}

/// [first]..[last] 内最高价与最低价所在的索引；区间为空时返回 null。
({int high, int low})? visibleExtremes(List<Candle> candles, int first, int last) {
  if (last < first) return null;
  var high = first;
  var low = first;
  for (var i = first + 1; i <= last; i++) {
    if (candles[i].high > candles[high].high) high = i;
    if (candles[i].low < candles[low].low) low = i;
  }
  return (high: high, low: low);
}

/// 主图价格区间（含主指标线，避免裁切），返回已含 6% 上下留白的 (min, max)。
/// [closeOnly] 时 K 线只按收盘价算（折线图、面积图）。
({double min, double max}) _priceRange(
  List<Candle> candles,
  List<IndicatorSeries> mainSeries,
  int first,
  int last, [
  ({double min, double max})? Function(int first, int last)? extra,
  bool closeOnly = false,
]) {
  var lo = double.infinity;
  var hi = double.negativeInfinity;
  for (var i = first; i <= last; i++) {
    lo = math.min(lo, closeOnly ? candles[i].close : candles[i].low);
    hi = math.max(hi, closeOnly ? candles[i].close : candles[i].high);
  }
  final ind = valueRange([
    for (final s in mainSeries)
      for (final line in s.lines) line.values,
  ], first, last);
  if (ind != null) {
    lo = math.min(lo, ind.min);
    hi = math.max(hi, ind.max);
  }
  final more = extra?.call(first, last);
  if (more != null) {
    lo = math.min(lo, more.min);
    hi = math.max(hi, more.max);
  }
  if (!lo.isFinite || !hi.isFinite) {
    lo = 0;
    hi = 1;
  }
  if (hi - lo < 1e-9) hi = lo + 1;
  final pad = (hi - lo) * 0.06;
  return (min: lo - pad, max: hi + pad);
}
