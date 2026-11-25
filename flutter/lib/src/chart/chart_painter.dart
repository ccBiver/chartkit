import 'dart:ui' show ClipOp;

import 'package:flutter/widgets.dart';

import '../drawing/drawing_geometry.dart';
import '../drawing/drawing_painter.dart';
import '../indicator/indicator.dart';
import '../script/script_painter.dart';
import 'chart_formatter.dart';
import 'chart_layout.dart';
import 'chart_mapper.dart';
import 'chart_renderer.dart';
import 'chart_renderer_panes.dart';
import 'chart_text.dart';
import 'countdown.dart';
import 'chart_theme.dart';
import 'chart_types.dart';
import 'k_line_chart_state.dart';
import 'skeleton_painter.dart';

/// 在图表画布上追加自定义绘制（挂单线、持仓线等），与 K 线同帧、零滞后。
/// 画在行情内容之上、现价标签与十字光标之下；坐标换算用 [mapper]。
typedef ChartOverlayPainter = void Function(Canvas canvas, Size size, KLineChartMapper mapper);

/// 画布小于此尺寸时不绘制行情（避免极端约束下的退化几何）。
const Size _minChartSize = Size(80, 60);

/// 绘制所需的静态配置（来自组件参数，每次 build 重建）。
@immutable
class ChartPaintConfig {
  const ChartPaintConfig({
    required this.theme,
    required this.upDownColor,
    required this.mode,
    required this.formatter,
    required this.showVolume,
    required this.tradeMarks,
    required this.showSkeleton,
    required this.blankScrollRatio,
    required this.blankScrollWidth,
    required this.showHighLow,
    required this.crosshairMode,
    required this.lastPriceMode,
    required this.skeletonSubCount,
    required this.overlayPainter,
    required this.orderbookProvider,
    required this.showCountdown,
    required this.showCrosshairPriceLabel,
    required this.unit,
    required this.text,
    required this.markText,
    this.drawing,
    this.scripts,
    this.logScale = false,
    this.reserveMainLegend = false,
    this.mainBottomGap = 0,
  });

  final ChartTheme theme;
  final UpDownColor upDownColor;
  final ChartMode mode;
  final ChartFormatter formatter;
  final bool showVolume;
  final List<TradeMark> tradeMarks;
  final bool showSkeleton;
  final double blankScrollRatio;
  final double blankScrollWidth;
  final bool showHighLow;
  final CrosshairMode crosshairMode;
  final LastPriceMode lastPriceMode;
  final int skeletonSubCount;
  final ChartOverlayPainter? overlayPainter;
  final ChartOrderbook? Function()? orderbookProvider;
  final bool showCountdown;
  final bool showCrosshairPriceLabel;

  /// 1 物理像素对应的逻辑长度。
  final double unit;
  final ChartText text;
  final ChartText markText;

  /// 画线；为空时不画（未开启画线）。
  final DrawingPaintConfig? drawing;

  /// 脚本图元；为空时不画（未传 `scriptOutputs`）。
  final ScriptPaintConfig? scripts;

  /// 主图价格轴按对数刻度。
  final bool logScale;

  /// 主图顶部给图例留位置（见 `KLineChart.reserveMainLegend`）。
  final bool reserveMainLegend;

  /// 主图下方给宿主留的空白高度（见 `KLineChart.mainBottomGap`）。
  final double mainBottomGap;
}

/// 每帧变化的数据来源（指标结果、动画进度），由组件的 State 实现。
/// 画家在重绘时实时读取，因此动画/滚动只触发重绘、不触发 rebuild。
abstract interface class ChartFrameSource {
  List<IndicatorSeries> get mainSeries;
  List<IndicatorSeries> get subSeries;

  /// 当前显示的副图 id（含正在收缩退场的），与 [subPaneWeights] 一一对应。
  List<String> get subPaneIds;

  /// 各副图的动画权重（0..1）。
  List<double> get subPaneWeights;

  /// 脚本副图的 id 和动画权重，窗格排在内置副图之后。
  List<String> get scriptPaneIds;
  List<double> get scriptPaneWeights;

  /// 入场动画进度（0..1）。
  double get entrance;

  /// 骨架屏扫光相位。
  double get skeletonPhase;

  /// 画家每帧回报本帧几何（无数据或尺寸过小时为 null），供手势命中与坐标映射使用。
  void onFrameLayout(ChartLayout? layout);
}

class KLineChartPainter extends CustomPainter {
  KLineChartPainter({
    required this.state,
    required this.source,
    required this.config,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final KLineChartState state;
  final ChartFrameSource source;
  final ChartPaintConfig config;

  @override
  void paint(Canvas canvas, Size size) {
    final theme = config.theme;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, Paint()..color = theme.background);
    final scripts = config.scripts?.controller.resolved() ?? const <ScriptEntry>[];
    final layout = _layoutFor(size, scripts);
    source.onFrameLayout(layout);
    if (layout != null) {
      final gap = layout.mainBottomGapRect;
      // 主图下方的空白归宿主：只留背景色，之后的内容（网格、十字光标、标签）都不进去
      if (!gap.isEmpty) {
        canvas.clipRect(gap, clipOp: ClipOp.difference);
      }
      _paintChart(canvas, layout, scripts);
    } else if (state.candles.isEmpty && config.showSkeleton) {
      _paintSkeleton(canvas, size);
    }
    canvas.restore();
  }

  ChartLayout? _layoutFor(Size size, List<ScriptEntry> scripts) {
    final candles = state.candles;
    if (candles.isEmpty) return null;
    if (size.width < _minChartSize.width || size.height < _minChartSize.height) return null;
    return ChartLayout.compute(
      size: size,
      candles: candles,
      candleWidth: effectiveCandleWidth(state, config.theme.dims),
      scrollOffset: state.scrollOffset,
      dims: config.theme.dims,
      showVolume: config.showVolume,
      blankScrollRatio: config.blankScrollRatio,
      blankScrollWidth: config.blankScrollWidth,
      subWeights: config.scripts == null
          ? source.subPaneWeights
          : [...source.subPaneWeights, ...source.scriptPaneWeights],
      mainSeries: source.mainSeries,
      extraMainRange: scripts.isEmpty
          ? null
          : (first, last) =>
              scriptMainRange(scripts, first, last, positiveOnly: config.logScale),
      measureText: config.text.measure,
      formatPrice: config.formatter.price,
      labelPad: 4 * config.unit,
      closeOnly: config.mode.closeOnly,
      logScale: config.logScale,
      mainContentInset: mainLegendInset(
        reserve: config.reserveMainLegend,
        mode: config.mode,
        rows: source.mainSeries.length,
        dims: config.theme.dims,
      ),
      mainBottomGap: config.mainBottomGap,
    );
  }

  void _paintSkeleton(Canvas canvas, Size size) {
    final theme = config.theme;
    drawSkeleton(
      canvas,
      size,
      theme: theme,
      up: theme.upColor(config.upDownColor),
      down: theme.downColor(config.upDownColor),
      phase: source.skeletonPhase,
      candleWidth: effectiveCandleWidth(state, theme.dims),
      showVolume: config.showVolume,
      subCount: config.skeletonSubCount,
      unit: config.unit,
    );
  }

  void _paintChart(Canvas canvas, ChartLayout layout, List<ScriptEntry> scripts) {
    final candles = state.candles;
    final r = ChartRenderer(
      canvas: canvas,
      layout: layout,
      candles: candles,
      theme: config.theme,
      upDownColor: config.upDownColor,
      formatter: config.formatter,
      timeFrame: state.timeFrame,
      text: config.text,
      markText: config.markText,
      unit: config.unit,
      entrance: source.entrance,
    );
    final crosshair = state.crosshairIndex;
    // 读数聚焦索引：十字光标命中某根时取该根，否则取最新一根
    final focus = crosshair >= 0 && crosshair < candles.length ? crosshair : candles.length - 1;

    final sc = config.scripts;
    final sp = sc == null || scripts.isEmpty
        ? null
        : ScriptLayersPainter(
            canvas: canvas,
            layout: layout,
            candles: candles,
            config: sc,
            formatter: config.formatter,
            scripts: scripts,
          );

    r.drawGrid();
    sp?.paintMainUnder();
    // 主图指标的填充（BOLL 上下轨之间等）在脚本背景色之上、K 线之下；分时不画主图指标，也不画填充
    if (config.mode != ChartMode.timeLine) r.drawMainFills(source.mainSeries);
    switch (config.mode) {
      case ChartMode.timeLine:
        r.drawTimeLine();
      case ChartMode.line || ChartMode.area:
        r.drawTimeLine(withFill: config.mode == ChartMode.area);
        r.drawMainIndicators(source.mainSeries);
      case ChartMode.candle || ChartMode.ohlc:
        final barColors =
            sp == null ? null : scriptBarColors(scripts, layout.firstIndex, layout.lastIndex);
        if (config.mode == ChartMode.ohlc) {
          r.drawOhlcBars(colorOf: barColors);
        } else if (barColors == null) {
          r.drawCandles();
        } else {
          r.drawCandles(colorOf: barColors);
        }
        r.drawMainIndicators(source.mainSeries);
    }
    sp?.paintMainOver();
    if (config.showHighLow && !config.mode.closeOnly && config.mode != ChartMode.timeLine) {
      r.drawHighLow();
    }
    r.drawTradeMarks(config.tradeMarks);
    if (config.showVolume) r.drawVolume();
    r.drawSubPanes(source.subPaneIds, source.subSeries, focus);
    if (sp != null) {
      final builtIn = source.subPaneIds.length;
      final panes = layout.subPanes;
      sp.paintSubPanes(
        builtIn < panes.length ? panes.sublist(builtIn) : const [],
        source.scriptPaneIds,
      );
    }
    r.drawTimeAxis();
    final drawing = config.drawing;
    if (drawing != null) {
      DrawingPainter(
        canvas: canvas,
        projection: DrawingProjection.of(layout, DrawingTimeline(candles, state.timeFrame.millis)),
        colors: drawing.colors,
        labels: drawing.labels,
        text: drawing.text,
        formatPrice: config.formatter.price,
      ).paintAll(drawing.controller);
    }
    config.overlayPainter?.call(canvas, layout.size, KLineChartMapper(layout, candles));
    // 现价线/标签画在宿主图层之上：挂单线、成交标记不会盖住现价
    final now = DateTime.now().millisecondsSinceEpoch;
    r.drawLastPrice(
      config.lastPriceMode,
      countdown: config.showCountdown ? candleCountdown(candles, state.timeFrame, now) : null,
      orderbook: config.orderbookProvider?.call(),
    );
    if (crosshair >= 0) {
      r.drawCrosshair(
        index: crosshair,
        fingerY: state.crosshairY,
        lockedPrice: state.crosshairPrice,
        mode: config.crosshairMode,
        hasSubPanes: layout.subPanes.isNotEmpty,
        showPriceLabel: config.showCrosshairPriceLabel,
      );
    }
  }

  @override
  bool shouldRepaint(KLineChartPainter oldDelegate) => true;
}

/// 当前生效的单根宽度：未缩放过（0）时取主题默认值。
double effectiveCandleWidth(KLineChartState state, ChartDims dims) =>
    state.candleWidth > 0 ? state.candleWidth : dims.candleDefaultWidth;

/// 主图顶部给图例留的高度：图例顶距 + 行数 × 行高；没开、分时模式（不显示图例）
/// 或没有主图指标时为 0。和 `ChartLegend` 的位置用同一组 [ChartDims]。
double mainLegendInset({
  required bool reserve,
  required ChartMode mode,
  required int rows,
  required ChartDims dims,
}) {
  if (!reserve || rows <= 0 || mode == ChartMode.timeLine) return 0;
  return dims.mainLegendTop + rows * dims.mainLegendRowHeight;
}
