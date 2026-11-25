import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../model/candle.dart';
import 'chart_layout.dart';

/// 图上坐标映射快照：「价格 ↔ 像素 Y」「蜡烛索引 ↔ 像素 X」的双向换算，
/// 供宿主的图层（挂单线、持仓标签、快捷下单等）在正确像素位置定位。
///
/// 换算与渲染层共用同一份 [ChartLayout]，保证图层与 K 线不漂移。
/// 通过 `KLineChartState.mapper` 监听（坐标变化后在帧末更新，滞后至多一帧）；
/// 需零滞后的线条请用 `KLineChart.overlayPainter` 直接画在同一画布上。
@immutable
class KLineChartMapper {
  KLineChartMapper(ChartLayout layout, List<Candle> candles)
      : _layout = layout,
        latestPrice = candles.last.close;

  final ChartLayout _layout;

  /// 最新价（最后一根蜡烛收盘价）。
  final double latestPrice;

  /// 主图区域（蜡烛所在矩形，不含量图/副图/时间轴/右轴）。
  Rect get mainRect => _layout.mainRect;

  /// 主图价格区的顶边。开了 `KLineChart.reserveMainLegend` 时在图例下面，宿主要把
  /// 东西排在图例下方时以它为准；没开时等于 `mainRect.top`。
  double get mainContentTop => _layout.mainContentTop;

  /// 主图下方给宿主控件留的空白（`KLineChart.mainBottomGap`）：从 `mainRect.bottom` 往下，
  /// 横跨整个图宽（含右轴）。宿主把自己的控件摆在这里；图表在里面只铺背景色、不接手势。
  /// 没留空白时高度为 0。
  Rect get mainBottomGapRect => _layout.mainBottomGapRect;

  /// 整个图表的尺寸。
  Size get size => _layout.size;

  /// 当前数据总条数。
  int get itemCount => _layout.itemCount;

  /// 当前可视区首/末蜡烛索引。
  int get firstIndex => _layout.firstIndex;
  int get lastIndex => _layout.lastIndex;

  /// 单根蜡烛宽度（含间隙）。
  double get candleWidth => _layout.candleWidth;

  /// 主图价格轴是否按对数刻度（[priceToY]、[yToPrice] 已按它换算）。
  bool get logScale => _layout.logScale;

  /// 价格 → 主图像素 Y。
  double priceToY(double price) => _layout.priceToY(price);

  /// 主图像素 Y → 价格（[priceToY] 的反函数）。
  double yToPrice(double y) => _layout.yToPrice(y);

  /// 蜡烛索引 → 像素 X（蜡烛中心）。
  double indexToX(int index) => _layout.centerX(index);

  /// 像素 X → 蜡烛索引。
  int xToIndex(double x) => _layout.indexAtX(x);

  /// 像素 Y 是否落在主图区域内。
  bool containsY(double y) => y >= mainRect.top && y <= mainRect.bottom;

  /// 蜡烛索引是否落在当前可视区。
  bool indexVisible(int index) => index >= firstIndex && index <= lastIndex;

  /// 把 Y 夹紧到主图区域内。
  double clampY(double y) => y.clamp(mainRect.top, mainRect.bottom).toDouble();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KLineChartMapper &&
          other.latestPrice == latestPrice &&
          other._layout.size == _layout.size &&
          other._layout.chartWidth == _layout.chartWidth &&
          other._layout.mainBottom == _layout.mainBottom &&
          other._layout.mainContentTop == _layout.mainContentTop &&
          other._layout.mainBottomGap == _layout.mainBottomGap &&
          other._layout.candleWidth == _layout.candleWidth &&
          other._layout.rightFloat == _layout.rightFloat &&
          other._layout.priceMin == _layout.priceMin &&
          other._layout.priceMax == _layout.priceMax &&
          other._layout.itemCount == _layout.itemCount &&
          other._layout.logScale == _layout.logScale;

  @override
  int get hashCode => Object.hash(
        latestPrice,
        _layout.size,
        _layout.chartWidth,
        _layout.mainBottom,
        _layout.mainContentTop,
        _layout.mainBottomGap,
        _layout.candleWidth,
        _layout.rightFloat,
        _layout.priceMin,
        _layout.priceMax,
        _layout.itemCount,
        _layout.logScale,
      );
}
