import 'package:flutter/widgets.dart';

import '../model/candle.dart';
import '../model/time_frame.dart';
import 'chart_formatter.dart';
import 'chart_theme.dart';
import 'chart_types.dart';
import 'number_format.dart';

const Color _white = Color(0xFFFFFFFF);
const Color _black = Color(0xFF000000);

/// 内置详情行：时间 / 开 / 高 / 低 / 收 / 涨跌 / 涨跌幅 / 振幅 / 量 / 额。
List<CrosshairDetailRow> defaultCrosshairRows({
  required Candle candle,
  required ChartFormatter formatter,
  required ChartLabels labels,
  required ChartTheme theme,
  required UpDownColor upDownColor,
  required TimeFrame timeFrame,
}) {
  final change = candle.change;
  final pct = candle.changeRate * 100;
  final amp = candle.close != 0 ? (candle.high - candle.low) / candle.close * 100 : 0.0;
  final color = change >= 0 ? theme.upColor(upDownColor) : theme.downColor(upDownColor);
  final sign = change >= 0 ? '+' : '';
  return [
    CrosshairDetailRow(labels.time, formatter.crosshairTime(candle.time, timeFrame)),
    CrosshairDetailRow(labels.open, formatter.price(candle.open)),
    CrosshairDetailRow(labels.high, formatter.price(candle.high)),
    CrosshairDetailRow(labels.low, formatter.price(candle.low)),
    CrosshairDetailRow(labels.close, formatter.price(candle.close)),
    CrosshairDetailRow(labels.change, '$sign${formatter.price(change)}', color: color),
    CrosshairDetailRow(labels.changePct, '$sign${fixed(pct, 2)}%', color: color),
    CrosshairDetailRow(labels.amplitude, '${fixed(amp, 2)}%'),
    CrosshairDetailRow(labels.volume, formatter.volume(candle.volume)),
    CrosshairDetailRow(labels.turnover, formatter.volume(candle.turnover)),
  ];
}

/// 该根 K 线上的买卖记录行（追加在详情浮窗底部）。[onTap] 非空时行可点击。
List<CrosshairDetailRow> tradeMarkRows({
  required Iterable<TradeMark> marks,
  required ChartFormatter formatter,
  required ChartLabels labels,
  required ChartTheme theme,
  required UpDownColor upDownColor,
  required void Function(TradeMark mark)? onTap,
}) =>
    [
      for (final m in marks)
        CrosshairDetailRow(
          m.isBuy ? labels.buy : labels.sell,
          // 最近一笔单价(成交笔数)
          '${m.price == null ? '' : formatter.price(m.price!)}${m.count == null ? '' : ' (${m.count})'}',
          color: m.isBuy ? theme.upColor(upDownColor) : theme.downColor(upDownColor),
          labelColor: m.isBuy ? theme.upColor(upDownColor) : theme.downColor(upDownColor),
          onTap: onTap == null ? null : () => onTap(m),
        ),
    ];

/// 十字光标详情浮窗：若干「标签 / 数据」两列行。
class CrosshairPanel extends StatelessWidget {
  const CrosshairPanel({super.key, required this.rows, required this.theme});

  final List<CrosshairDetailRow> rows;
  final ChartTheme theme;

  @override
  Widget build(BuildContext context) {
    final valueColor = theme.background.computeLuminance() < 0.5 ? _white : _black;
    return Container(
      width: 150,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.background.withValues(alpha: 0.92),
        border: Border.all(color: theme.grid, width: 0.5),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < rows.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 5),
              child: _Metric(row: rows[i], theme: theme, defaultValueColor: valueColor),
            ),
        ],
      ),
    );
  }
}

/// 浮窗内一行：标签靠左、数据靠右。可点击行尾部加中性色 › 提示。
class _Metric extends StatelessWidget {
  const _Metric({required this.row, required this.theme, required this.defaultValueColor});

  final CrosshairDetailRow row;
  final ChartTheme theme;
  final Color defaultValueColor;

  TextStyle _style(Color color, [double size = 11]) =>
      TextStyle(inherit: false, color: color, fontSize: size, fontFamily: theme.fontFamily);

  @override
  Widget build(BuildContext context) {
    final content = Row(
      children: [
        Text(row.label, style: _style(row.labelColor ?? theme.axisText)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            row.value,
            textAlign: TextAlign.end,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _style(row.color ?? defaultValueColor),
          ),
        ),
        if (row.onTap != null)
          Padding(
            padding: const EdgeInsets.only(left: 3),
            child: Text('›', style: _style(theme.axisText, 17).copyWith(height: 0.8)),
          ),
      ],
    );
    if (row.onTap == null) return content;
    return GestureDetector(behavior: HitTestBehavior.opaque, onTap: row.onTap, child: content);
  }
}

/// 图例单项：值变化时数字滚动过渡（[animate] 为 true，最新根实时更新用）；
/// 十字光标拖动时即时显示。
class LegendItem extends StatelessWidget {
  const LegendItem({
    super.key,
    required this.name,
    required this.value,
    required this.style,
    required this.format,
    required this.animate,
  });

  final String name;
  final double value;
  final TextStyle style;
  final String Function(double) format;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    if (!animate) return Text('$name ${format(value)}', style: style);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: value),
      duration: const Duration(milliseconds: 280),
      builder: (context, shown, _) => Text('$name ${format(shown)}', style: style),
    );
  }
}

/// 全屏按钮图标：四角括号（自绘，无需图片资源）。
class FullscreenGlyphPainter extends CustomPainter {
  const FullscreenGlyphPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final len = s * 0.34;
    final paint = Paint()
      ..color = color
      ..strokeWidth = s * 0.10 < 1 ? 1 : s * 0.10
      ..strokeCap = StrokeCap.square;
    final corners = [Offset.zero, Offset(s, 0), Offset(0, s), Offset(s, s)];
    for (final c in corners) {
      final dx = c.dx == 0 ? len : -len;
      final dy = c.dy == 0 ? len : -len;
      canvas.drawLine(c, c + Offset(dx, 0), paint);
      canvas.drawLine(c, c + Offset(0, dy), paint);
    }
  }

  @override
  bool shouldRepaint(FullscreenGlyphPainter oldDelegate) => oldDelegate.color != color;
}
