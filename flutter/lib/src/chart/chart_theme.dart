import 'package:flutter/widgets.dart';

import 'chart_types.dart';

/// 尺寸配置（逻辑像素），集中管理，杜绝散落的魔法数。
@immutable
class ChartDims {
  const ChartDims({
    this.candleMinWidth = 3,
    this.candleMaxWidth = 30,
    this.candleDefaultWidth = 8,
    this.candleGapRatio = 0.25,
    this.axisTextSize = 10,
    this.legendTextSize = 11,
    this.rightAxisWidth = 46,
    this.bottomAxisHeight = 18,
    this.paneGap = 6,
    this.subLegendHeight = 16,
    this.volumePaneFraction = 0.16,
    this.subPaneFraction = 0.18,
    this.tradeMarkMaxVisibleBars = 50,
  });

  final double candleMinWidth;
  final double candleMaxWidth;
  final double candleDefaultWidth;

  /// 间隙占单根宽度比例。
  final double candleGapRatio;
  final double axisTextSize;
  final double legendTextSize;

  /// 右侧价格刻度留白的下限（实际宽度随最长价格标签自适应）。
  final double rightAxisWidth;

  /// 底部时间轴高度。
  final double bottomAxisHeight;
  final double paneGap;

  /// 副图顶部图例独占行高（数值不与指标重叠）。
  final double subLegendHeight;

  /// 成交量窗格占图高比例。
  final double volumePaneFraction;

  /// 每个副图窗格占图高比例。
  final double subPaneFraction;

  /// 可见 K 线超过此值时隐藏买卖标记。
  final int tradeMarkMaxVisibleBars;

  ChartDims copyWith({
    double? candleMinWidth,
    double? candleMaxWidth,
    double? candleDefaultWidth,
    double? candleGapRatio,
    double? axisTextSize,
    double? legendTextSize,
    double? rightAxisWidth,
    double? bottomAxisHeight,
    double? paneGap,
    double? subLegendHeight,
    double? volumePaneFraction,
    double? subPaneFraction,
    int? tradeMarkMaxVisibleBars,
  }) =>
      ChartDims(
        candleMinWidth: candleMinWidth ?? this.candleMinWidth,
        candleMaxWidth: candleMaxWidth ?? this.candleMaxWidth,
        candleDefaultWidth: candleDefaultWidth ?? this.candleDefaultWidth,
        candleGapRatio: candleGapRatio ?? this.candleGapRatio,
        axisTextSize: axisTextSize ?? this.axisTextSize,
        legendTextSize: legendTextSize ?? this.legendTextSize,
        rightAxisWidth: rightAxisWidth ?? this.rightAxisWidth,
        bottomAxisHeight: bottomAxisHeight ?? this.bottomAxisHeight,
        paneGap: paneGap ?? this.paneGap,
        subLegendHeight: subLegendHeight ?? this.subLegendHeight,
        volumePaneFraction: volumePaneFraction ?? this.volumePaneFraction,
        subPaneFraction: subPaneFraction ?? this.subPaneFraction,
        tradeMarkMaxVisibleBars: tradeMarkMaxVisibleBars ?? this.tradeMarkMaxVisibleBars,
      );
}

/// 主题：颜色 + 尺寸 + 网格密度。内置 [dark]/[light]，可用 [copyWith] 自定义。
@immutable
class ChartTheme {
  const ChartTheme({
    required this.background,
    required this.grid,
    required this.axisText,
    required this.candleUp,
    required this.candleDown,
    required this.crosshair,
    required this.crosshairLabelBg,
    required this.crosshairLabelText,
    required this.lastPriceLine,
    required this.timeLineStroke,
    required this.timeLineFillTop,
    required this.timeLineFillBottom,
    required this.indicatorColors,
    this.volumeUpAlpha = 0.6,
    this.gridRows = 4,
    this.dims = const ChartDims(),
    this.fontFamily,
    this.crosshairVertical,
    this.crosshairVerticalWidth,
    this.lastPriceText = const Color(0xFFFFFFFF),
    this.highLowText,
  }) : assert(gridRows > 0);

  final Color background;
  final Color grid;
  final Color axisText;
  final Color candleUp;
  final Color candleDown;
  final Color crosshair;
  final Color crosshairLabelBg;
  final Color crosshairLabelText;
  final Color lastPriceLine;
  final Color timeLineStroke;
  final Color timeLineFillTop;
  final Color timeLineFillBottom;

  /// 指标多线循环取色（不可为空）。
  final List<Color> indicatorColors;
  final double volumeUpAlpha;
  final int gridRows;
  final ChartDims dims;

  /// 图内文字字体；为空用系统默认。
  final String? fontFamily;

  /// 十字光标竖线颜色；为空则与横线同为 [crosshair]。
  final Color? crosshairVertical;

  /// 十字光标竖线宽度（逻辑像素）。为空画细虚线；给定则画实色竖带（通常配半透明色）。
  final double? crosshairVerticalWidth;

  /// 现价标签与盘口贴纸的文字颜色。
  final Color lastPriceText;

  /// 可见区最高/最低价标注的颜色；为空用 [axisText]。
  final Color? highLowText;

  static const ChartTheme dark = ChartTheme(
    background: Color(0xFF0E1116),
    grid: Color(0xFF222934),
    axisText: Color(0xFF8A93A2),
    candleUp: Color(0xFF16C784),
    candleDown: Color(0xFFEA3943),
    crosshair: Color(0xFF9AA4B2),
    crosshairLabelBg: Color(0xFF2A313C),
    crosshairLabelText: Color(0xFFE6E9EE),
    lastPriceLine: Color(0xFFF0A020),
    timeLineStroke: Color(0xFF3B82F6),
    timeLineFillTop: Color(0x333B82F6),
    timeLineFillBottom: Color(0x003B82F6),
    indicatorColors: [
      Color(0xFFF0A020), Color(0xFF3B82F6), Color(0xFFB44BE0), //
      Color(0xFF16C784), Color(0xFFEA3943),
    ],
  );

  static const ChartTheme light = ChartTheme(
    background: Color(0xFFFFFFFF),
    grid: Color(0xFFEDEDED),
    axisText: Color(0xFF757880),
    candleUp: Color(0xFF16C784),
    candleDown: Color(0xFFEA3943),
    crosshair: Color(0xFF757880),
    crosshairLabelBg: Color(0xFF2A313C),
    crosshairLabelText: Color(0xFFFFFFFF),
    lastPriceLine: Color(0xFFF0A020),
    timeLineStroke: Color(0xFF3B82F6),
    timeLineFillTop: Color(0x333B82F6),
    timeLineFillBottom: Color(0x003B82F6),
    indicatorColors: [
      Color(0xFFE0860E), Color(0xFF3B82F6), Color(0xFFB44BE0), //
      Color(0xFF0E9C66), Color(0xFFD32E3B),
    ],
  );

  Color upColor(UpDownColor scheme) => scheme == UpDownColor.greenUpRedDown ? candleUp : candleDown;

  Color downColor(UpDownColor scheme) =>
      scheme == UpDownColor.greenUpRedDown ? candleDown : candleUp;

  /// 第 [lineIndex] 条指标线的颜色（循环取色）。
  Color indicatorColor(int lineIndex) => indicatorColors[lineIndex % indicatorColors.length];

  ChartTheme copyWith({
    Color? background,
    Color? grid,
    Color? axisText,
    Color? candleUp,
    Color? candleDown,
    Color? crosshair,
    Color? crosshairLabelBg,
    Color? crosshairLabelText,
    Color? lastPriceLine,
    Color? timeLineStroke,
    Color? timeLineFillTop,
    Color? timeLineFillBottom,
    List<Color>? indicatorColors,
    double? volumeUpAlpha,
    int? gridRows,
    ChartDims? dims,
    String? fontFamily,
    Color? crosshairVertical,
    double? crosshairVerticalWidth,
    Color? lastPriceText,
    Color? highLowText,
  }) =>
      ChartTheme(
        background: background ?? this.background,
        grid: grid ?? this.grid,
        axisText: axisText ?? this.axisText,
        candleUp: candleUp ?? this.candleUp,
        candleDown: candleDown ?? this.candleDown,
        crosshair: crosshair ?? this.crosshair,
        crosshairLabelBg: crosshairLabelBg ?? this.crosshairLabelBg,
        crosshairLabelText: crosshairLabelText ?? this.crosshairLabelText,
        lastPriceLine: lastPriceLine ?? this.lastPriceLine,
        timeLineStroke: timeLineStroke ?? this.timeLineStroke,
        timeLineFillTop: timeLineFillTop ?? this.timeLineFillTop,
        timeLineFillBottom: timeLineFillBottom ?? this.timeLineFillBottom,
        indicatorColors: indicatorColors ?? this.indicatorColors,
        volumeUpAlpha: volumeUpAlpha ?? this.volumeUpAlpha,
        gridRows: gridRows ?? this.gridRows,
        dims: dims ?? this.dims,
        fontFamily: fontFamily ?? this.fontFamily,
        crosshairVertical: crosshairVertical ?? this.crosshairVertical,
        crosshairVerticalWidth: crosshairVerticalWidth ?? this.crosshairVerticalWidth,
        lastPriceText: lastPriceText ?? this.lastPriceText,
        highLowText: highLowText ?? this.highLowText,
      );
}
