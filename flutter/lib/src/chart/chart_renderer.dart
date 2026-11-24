import 'dart:math' as math;
import 'dart:ui';

import '../indicator/indicator.dart';
import '../model/candle.dart';
import '../model/time_frame.dart';
import 'chart_formatter.dart';
import 'chart_layout.dart';
import 'chart_text.dart';
import 'chart_theme.dart';
import 'chart_types.dart';

const Color _white = Color(0xFFFFFFFF);

/// 把 [time] 落到所属 K 线的索引（二分；早于首根取 0，晚于末根取末根）。空数据返回 -1。
int indexForTime(List<Candle> candles, int time) {
  if (candles.isEmpty) return -1;
  if (time <= candles.first.time) return 0;
  if (time >= candles.last.time) return candles.length - 1;
  var lo = 0;
  var hi = candles.length - 1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    final t = candles[mid].time;
    if (t == time) return mid;
    if (t < time) {
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return hi.clamp(0, candles.length - 1); // 落在 hi 这根的区间内
}

double _clamp(double v, double lo, double hi) => hi < lo ? lo : v.clamp(lo, hi).toDouble();

double? _at(List<double?> values, int i) => i >= 0 && i < values.length ? values[i] : null;

/// 一帧的绘制器：持有本帧的画布、几何与样式，按区块绘制。
/// [unit] 为 1 物理像素对应的逻辑长度（线宽、细小留白沿用 Compose 版的像素口径）。
class ChartRenderer {
  ChartRenderer({
    required this.canvas,
    required this.layout,
    required this.candles,
    required this.theme,
    required this.upDownColor,
    required this.formatter,
    required this.timeFrame,
    required this.text,
    required this.markText,
    required this.unit,
    required double entrance,
  })  : up = theme.upColor(upDownColor),
        down = theme.downColor(upDownColor),
        revealLast = _revealLast(layout, entrance);

  final Canvas canvas;
  final ChartLayout layout;
  final List<Candle> candles;
  final ChartTheme theme;
  final UpDownColor upDownColor;
  final ChartFormatter formatter;
  final TimeFrame timeFrame;
  final ChartText text;
  final ChartText markText;
  final double unit;
  final Color up;
  final Color down;

  /// 入场动画：只绘制到这一根（随动画 0→1 从左往右推进）。
  final int revealLast;

  final Paint _fill = Paint();
  final Paint _stroke = Paint()..style = PaintingStyle.stroke;

  Size get size => layout.size;
  ChartDims get dims => theme.dims;
  double get labelPad => 4 * unit;
  /// 现价标签四周内边距（逻辑像素），同旧版 App K 线。
  static const double lastPriceLabelPad = 4;

  double get labelHalfHeight => text.lineHeight / 2 + text.scaledFontSize * 0.3;
  double get bodyWidth => layout.candleWidth * (1 - dims.candleGapRatio);

  static int _revealLast(ChartLayout l, double entrance) {
    if (entrance >= 1) return l.lastIndex;
    final hidden = l.chartWidth * (1 - entrance) / l.candleWidth;
    return (l.rightFloat + 0.5 - hidden).floor().clamp(l.firstIndex - 1, l.lastIndex);
  }

  // ───────────────────────── 基础图元 ─────────────────────────

  void line(Color color, Offset a, Offset b, [double width = 1]) {
    _stroke
      ..color = color
      ..strokeWidth = width * unit;
    canvas.drawLine(a, b, _stroke);
  }

  void rect(Color color, Rect r) => canvas.drawRect(r, _fill..color = color);

  void roundRect(Color color, Rect r, double radius) =>
      canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(radius)), _fill..color = color);

  /// 水平或垂直虚线（[on]/[off] 为物理像素）。
  void dashedLine(Color color, Offset a, Offset b, double on, double off) {
    final total = (b - a).distance;
    if (total <= 0) return;
    final dir = (b - a) / total;
    final step = (on + off) * unit;
    _stroke
      ..color = color
      ..strokeWidth = unit;
    for (var d = 0.0; d < total; d += step) {
      canvas.drawLine(a + dir * d, a + dir * math.min(d + on * unit, total), _stroke);
    }
  }

  void _rightAlignedText(String s, double baselineY, Color color) =>
      text.drawBaselineLeft(canvas, s, size.width - labelPad - text.measure(s), baselineY, color);

  /// 右轴标签：以 [yCenter] 为竖直中心，贴右边缘、宽度随文本自适应。
  /// [second] 非空时在下方多一行（右对齐），标签相应增高。返回标签占用的矩形。
  ///
  /// [pad] 非空时按逻辑像素给四周内边距（两行之间隔 2、圆角 4），用于现价标签；
  /// 为空时沿用按物理像素的紧凑尺寸（十字光标价签等）。
  Rect rightLabel(double yCenter, String s, Color bg, Color fg, {String? second, double? pad}) {
    final line = text.lineHeight;
    const rowGap = 2.0;
    final padH = pad ?? labelPad;
    final half = pad != null
        ? (second == null ? line / 2 : line + rowGap / 2) + pad
        : (second == null ? labelHalfHeight : line + text.scaledFontSize * 0.3);
    final cy = _clamp(yCenter, half, layout.chartHeight - half);
    final width = math.max(text.measure(s), second == null ? 0.0 : text.measure(second));
    final box = Rect.fromLTRB(size.width - padH * 2 - width, cy - half, size.width, cy + half);
    roundRect(bg, box, pad != null ? 4 : 5 * unit);
    final right = size.width - padH;
    final rowOffset = pad != null ? (line + rowGap) / 2 : line / 2;
    if (second == null) {
      text.drawVCenterLeft(canvas, s, right - text.measure(s), cy, fg);
    } else {
      text.drawVCenterLeft(canvas, s, right - text.measure(s), cy - rowOffset, fg);
      text.drawVCenterLeft(canvas, second, right - text.measure(second), cy + rowOffset, fg);
    }
    return box;
  }

  /// 以 [xCenter] 为中心、占据竖直区间 [top]..[bottom] 的时间标签。
  void timeLabel(double xCenter, double top, double bottom, String s, Color bg, Color fg) {
    final tw = text.measure(s);
    final halfW = tw / 2 + 8 * unit;
    final cx = _clamp(xCenter, halfW, layout.chartWidth - halfW);
    roundRect(bg, Rect.fromLTRB(cx - halfW, top, cx + halfW, bottom), 5 * unit);
    text.drawVCenterLeft(canvas, s, cx - tw / 2, (top + bottom) / 2, fg);
  }

  /// 跨 null 不连线地绘制一条指标线。
  void seriesLine(List<double?> values, double Function(double) yOf, Color color) {
    final path = Path();
    var started = false;
    for (var i = layout.firstIndex; i <= revealLast; i++) {
      final v = _at(values, i);
      if (v == null || !v.isFinite) {
        started = false;
        continue;
      }
      final x = layout.centerX(i);
      started ? path.lineTo(x, yOf(v)) : path.moveTo(x, yOf(v));
      started = true;
    }
    _stroke
      ..color = color
      ..strokeWidth = 1.5 * unit;
    canvas.drawPath(path, _stroke);
  }

  /// 散点绘制（SAR 等）：每个非空值画一个小圆点，半径随蜡烛宽自适应。
  void seriesPoints(List<double?> values, double Function(double) yOf, Color color) {
    final r = _clamp(layout.candleWidth * 0.12, 1.2 * unit, 3 * unit);
    _fill.color = color;
    for (var i = layout.firstIndex; i <= revealLast; i++) {
      final v = _at(values, i);
      if (v == null || !v.isFinite) continue;
      canvas.drawCircle(Offset(layout.centerX(i), yOf(v)), r, _fill);
    }
  }

  // ───────────────────────── 主图 ─────────────────────────

  /// 网格 + 右侧价格刻度。
  void drawGrid() {
    final l = layout;
    final rows = theme.gridRows;
    for (var r = 0; r <= rows; r++) {
      final y = l.mainTop + (l.mainBottom - l.mainTop) * r / rows;
      line(theme.grid, Offset(0, y), Offset(l.chartWidth, y));
      final price = l.priceMax - (l.priceMax - l.priceMin) * r / rows;
      // 最上面一档贴着画布上沿：基线下移到整行可见，避免被裁掉
      final baseline = math.max(y + text.scaledFontSize / 3, text.scaledFontSize);
      _rightAlignedText(formatter.price(price), baseline, theme.axisText);
    }
  }

  /// 分时：收盘价折线 + 填充。
  void drawTimeLine() {
    final l = layout;
    if (revealLast < l.firstIndex) return;
    final stroke = Path();
    final fill = Path();
    var lastX = 0.0;
    for (var i = l.firstIndex; i <= revealLast; i++) {
      final x = l.centerX(i);
      final y = l.priceToY(candles[i].close);
      if (i == l.firstIndex) {
        stroke.moveTo(x, y);
        fill
          ..moveTo(x, l.mainBottom)
          ..lineTo(x, y);
      } else {
        stroke.lineTo(x, y);
        fill.lineTo(x, y);
      }
      lastX = x;
    }
    fill
      ..lineTo(lastX, l.mainBottom)
      ..close();
    final shader = Gradient.linear(
      Offset(0, l.mainTop),
      Offset(0, l.mainBottom),
      [theme.timeLineFillTop, theme.timeLineFillBottom],
    );
    canvas.drawPath(fill, Paint()..shader = shader);
    _stroke
      ..color = theme.timeLineStroke
      ..strokeWidth = 2 * unit;
    canvas.drawPath(stroke, _stroke);
  }

  /// 蜡烛（影线 + 实体）。[colorOf] 给某根返回颜色时用它代替涨跌色（脚本的 K 线改色）。
  void drawCandles({Color? Function(int index)? colorOf}) {
    final l = layout;
    final bw = bodyWidth;
    for (var i = l.firstIndex; i <= revealLast; i++) {
      final c = candles[i];
      final x = l.centerX(i);
      final color = colorOf?.call(i) ?? (c.isBullish ? up : down);
      final yOpen = l.priceToY(c.open);
      final yClose = l.priceToY(c.close);
      final top = math.min(yOpen, yClose);
      line(color, Offset(x, l.priceToY(c.high)), Offset(x, l.priceToY(c.low)), 1.2);
      rect(color, Rect.fromLTWH(x - bw / 2, top, bw, math.max(unit, (yOpen - yClose).abs())));
    }
  }

  /// 可见区最高价 / 最低价标注：一小段引线 + 价格，朝图表中部一侧展开以免出界。
  void drawHighLow() {
    final ext = visibleExtremes(candles, layout.firstIndex, revealLast);
    if (ext == null) return;
    _extremeLabel(ext.high, candles[ext.high].high);
    _extremeLabel(ext.low, candles[ext.low].low);
  }

  void _extremeLabel(int index, double price) {
    const lead = 12.0, gap = 3.0;
    final color = theme.highLowText ?? theme.axisText;
    final x = layout.centerX(index);
    final y = layout.priceToY(price);
    final label = formatter.price(price);
    final toRight = x < layout.chartWidth / 2;
    line(color, Offset(x, y), Offset(toRight ? x + lead : x - lead, y));
    final left = toRight ? x + lead + gap : x - lead - gap - text.measure(label);
    text.drawVCenterLeft(canvas, label, left, y, color);
  }

  /// 主图叠加指标（SAR 等散点用圆点）。
  void drawMainIndicators(List<IndicatorSeries> series) {
    for (final s in series) {
      for (var li = 0; li < s.lines.length; li++) {
        final ln = s.lines[li];
        final color = theme.indicatorColor(li);
        if (ln.style == LineStyle.points) {
          seriesPoints(ln.values, layout.priceToY, color);
        } else {
          seriesLine(ln.values, layout.priceToY, color);
        }
      }
    }
  }

  /// 买卖标记：圆角徽章 + 指向蜡烛的小三角（B 在下方、S 在上方）。可见根数过多时隐藏。
  void drawTradeMarks(List<TradeMark> marks) {
    final l = layout;
    if (marks.isEmpty || l.lastIndex - l.firstIndex + 1 > dims.tradeMarkMaxVisibleBars) return;
    const bw = 16.0, bh = 14.0, corner = 2.0, ptrW = 2.0, ptrH = 3.0, gap = 2.0;
    for (final m in marks) {
      final idx = indexForTime(candles, m.time);
      if (idx < l.firstIndex || idx > revealLast) continue;
      final x = l.centerX(idx);
      final color = m.isBuy ? up : down;
      // 三角尖贴近蜡烛；买入徽章在三角下方，卖出在上方
      final tipY =
          m.isBuy ? l.priceToY(candles[idx].low) + gap : l.priceToY(candles[idx].high) - gap;
      final baseY = m.isBuy ? tipY + ptrH : tipY - ptrH;
      final badgeTop = m.isBuy ? baseY : baseY - bh;
      final tri = Path()
        ..moveTo(x - ptrW, baseY)
        ..lineTo(x + ptrW, baseY)
        ..lineTo(x, tipY)
        ..close();
      roundRect(color, Rect.fromLTWH(x - bw / 2, badgeTop, bw, bh), corner);
      canvas.drawPath(tri, _fill..color = color);
      final glyph = m.isBuy ? 'B' : 'S';
      markText.drawVCenterLeft(
          canvas, glyph, x - markText.measure(glyph) / 2, badgeTop + bh / 2, _white);
    }
  }

  /// 现价线 / 标签。
  ///
  /// [countdown] 非空时作为标签第二行（当根剩余时间）；[orderbook] 非空时在标签左侧贴买一/卖一。
  void drawLastPrice(LastPriceMode mode, {String? countdown, ChartOrderbook? orderbook}) {
    final l = layout;
    final c = mode == LastPriceMode.rightmostVisible ? candles[l.lastIndex] : candles.last;
    final color = c.isBullish ? up : down;
    final y = l.priceToY(c.close);
    final inView = y >= l.mainTop && y <= l.mainBottom;
    final drawLine = inView || mode == LastPriceMode.rightmostVisible;
    if (drawLine) dashedLine(color, Offset(0, y), Offset(l.chartWidth, y), 8, 6);
    // 最新价在可见价格区间外：标签贴主图上/下沿（不画线）
    final half = labelHalfHeight;
    final labelY = drawLine ? y : (y < l.mainTop ? l.mainTop + half : l.mainBottom - half);
    final box = rightLabel(labelY, formatter.price(c.close), color, theme.lastPriceText,
        second: countdown, pad: lastPriceLabelPad);
    if (orderbook != null) _drawOrderbook(orderbook, box);
  }

  /// 买一/卖一贴纸：实色圆角块，贴在现价标签 [label] 左侧，在标签中线处上下相接（卖上、买下）。
  /// 内边距横 6、竖 3，圆角 4，离标签 4（逻辑像素，不随 [unit] 缩）。
  void _drawOrderbook(ChartOrderbook ob, Rect label) {
    const padH = 6.0;
    final height = text.lineHeight + 6;
    final right = label.left - 4;
    final cy = _clamp(label.center.dy, height, layout.chartHeight - height);
    void pill(String s, Color color, double top) {
      final width = text.measure(s) + padH * 2;
      roundRect(color, Rect.fromLTWH(right - width, top, width, height), 4);
      text.drawVCenterLeft(canvas, s, right - width + padH, top + height / 2, theme.lastPriceText);
    }

    if (ob.ask > 0) {
      pill('${ob.askLabel} ${formatter.price(ob.ask)}', ob.askColor ?? down, cy - height);
    }
    if (ob.bid > 0) {
      pill('${ob.bidLabel} ${formatter.price(ob.bid)}', ob.bidColor ?? up, cy);
    }
  }
}
