import 'package:flutter/widgets.dart';

import '../indicator/indicator.dart';
import 'chart_renderer.dart';
import 'chart_types.dart';
import 'crosshair_panel.dart';
import 'k_line_chart.dart';
import 'replay_controller.dart';

/// 主图指标读数图例（左上角）：每个主图指标占一行，行内是该指标的各条线。
/// 无十字光标时显示最新根并带数字滚动；拖动十字光标时即时显示命中根。
class ChartLegend extends StatelessWidget {
  const ChartLegend({super.key, required this.chart, required this.seriesOf});

  final KLineChart chart;
  final List<IndicatorSeries> Function() seriesOf;

  @override
  Widget build(BuildContext context) => Positioned(
        left: 8,
        top: chart.theme.dims.mainLegendTop,
        right: 8,
        child: IgnorePointer(
          child: ListenableBuilder(listenable: shownState(chart), builder: (context, _) => _rows()),
        ),
      );

  Widget _rows() {
    final state = shownState(chart);
    final candles = state.candles;
    final series = seriesOf();
    if (candles.isEmpty || series.isEmpty || chart.mode == ChartMode.timeLine) {
      return const SizedBox.shrink();
    }
    final crosshair = state.crosshairIndex;
    final onCandle = crosshair >= 0 && crosshair < candles.length;
    final focus = onCandle ? crosshair : candles.length - 1;
    final theme = chart.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final s in series)
          Padding(
            padding: const EdgeInsets.only(bottom: 1),
            child: Wrap(
              spacing: 10,
              children: [
                for (var li = 0; li < s.lines.length; li++)
                  if (focus < s.lines[li].values.length && s.lines[li].values[focus] != null)
                    LegendItem(
                      name: s.lines[li].name,
                      value: s.lines[li].values[focus]!,
                      format: chart.formatter.price,
                      animate: !onCandle,
                      style: TextStyle(
                        inherit: false,
                        color: theme.indicatorColor(li),
                        fontSize: theme.dims.legendTextSize,
                        fontFamily: theme.fontFamily,
                      ),
                    ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 十字光标详情浮窗：内容可由 `crosshairDetail` 自定义，否则用内置 OHLC 行；
/// 放在手指对侧避免遮挡。该根若有买卖记录，底部追加买/卖行。
class ChartCrosshairPanel extends StatelessWidget {
  const ChartCrosshairPanel({super.key, required this.chart, required this.chartWidth});

  final KLineChart chart;
  final double chartWidth;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: shownState(chart),
        builder: (context, _) {
          final state = shownState(chart);
          final index = state.crosshairIndex;
          final visible = index >= 0 && index < state.candles.length;
          final fingerOnLeft = state.crosshairX >= 0 && state.crosshairX <= chartWidth / 2;
          // 放右侧时让开右轴，不遮住十字光标的价格标签
          final mapper = state.mapper.value;
          final rightAxis = mapper == null ? 0.0 : mapper.size.width - mapper.mainRect.width;
          // 隐藏时也保持为定位子项，避免未定位的空组件影响外层 Stack 的尺寸
          return Positioned.fill(
            child: CustomSingleChildLayout(
              delegate: _PanelPosition(
                top: 18 + chart.crosshairPanelMargin.top,
                left: fingerOnLeft ? null : 8 + chart.crosshairPanelMargin.left,
                right: fingerOnLeft ? 8 + rightAxis + chart.crosshairPanelMargin.right : null,
              ),
              child: visible ? _panel(_rows(index)) : const SizedBox.shrink(),
            ),
          );
        },
      );

  /// 没有可点击行时浮窗不拦截手势：点在浮窗上同样能关闭十字光标、拖动图表。
  Widget _panel(List<CrosshairDetailRow> rows) => IgnorePointer(
        ignoring: rows.every((row) => row.onTap == null),
        child: CrosshairPanel(rows: rows, theme: chart.theme),
      );

  List<CrosshairDetailRow> _rows(int index) {
    final state = shownState(chart);
    final candle = state.candles[index];
    final base = chart.crosshairDetail?.call(candle) ??
        defaultCrosshairRows(
          candle: candle,
          formatter: chart.formatter,
          labels: chart.labels,
          theme: chart.theme,
          upDownColor: chart.upDownColor,
          timeFrame: state.timeFrame,
        );
    // 常驻模式下浮窗买卖行可点击跳转；松手即消失模式不可点（改点蜡烛上的标记）
    final tappable = chart.crosshairDismiss == CrosshairDismiss.persistent;
    final marks = tradeMarkRows(
      marks: chart.tradeMarks.where((m) => indexForTime(state.candles, m.time) == index),
      formatter: chart.formatter,
      labels: chart.labels,
      theme: chart.theme,
      upDownColor: chart.upDownColor,
      onTap: tappable ? chart.onTradeMarkTap : null,
    );
    return [...base, ...?chart.crosshairExtraRows?.call(candle), ...marks];
  }
}

/// 浮窗的位置：贴左（[left]）或贴右（[right]）；图太窄放不下时整体挪回图内，不被裁掉。
class _PanelPosition extends SingleChildLayoutDelegate {
  const _PanelPosition({required this.top, this.left, this.right});

  final double top;
  final double? left;
  final double? right;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => const BoxConstraints();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final x = left ?? size.width - right! - childSize.width;
    final maxX = size.width - childSize.width;
    return Offset(maxX <= 0 ? 0 : x.clamp(0.0, maxX), top);
  }

  @override
  bool shouldRelayout(_PanelPosition old) =>
      old.top != top || old.left != left || old.right != right;
}

/// 钉在主图区域内的浮层：Logo 水印与左下角全屏按钮。[mainBottom] 为主图底边 y。
List<Widget> buildMainPaneOverlays({required KLineChart chart, required double mainBottom}) {
  final logo = chart.logo;
  final onToggleFullscreen = chart.onToggleFullscreen;
  final height = mainBottom < 0 ? 0.0 : mainBottom;
  return [
    if (logo != null)
      Positioned(
        left: 0,
        top: 0,
        right: 0,
        height: height,
        child: IgnorePointer(
          child: Align(
            alignment: chart.logoPosition.alignment,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Opacity(
                opacity: chart.logoOpacity,
                child: SizedBox(height: chart.logoHeight, child: logo),
              ),
            ),
          ),
        ),
      ),
    if (onToggleFullscreen != null)
      Positioned(
        left: 0,
        top: mainBottom - 28,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onToggleFullscreen,
          // 图标 14，四周留出点击热区
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: CustomPaint(
              size: const Size.square(14),
              painter: FullscreenGlyphPainter(chart.theme.axisText),
            ),
          ),
        ),
      ),
  ];
}
