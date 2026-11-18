import 'dart:math' as math;
import 'dart:ui';

import 'chart_theme.dart';

// 确定性「假行情」：多个正弦叠加，形似真实 K 线（归一化大致 0..1，按 i 取值，无随机）。
double _skClose(int i) =>
    (0.5 + 0.26 * math.sin(i * 0.16) + 0.12 * math.sin(i * 0.045 + 1.2) + 0.05 * math.sin(i * 0.9))
        .clamp(0.05, 0.95);
double _skOpen(int i) => i == 0 ? _skClose(0) - 0.03 : _skClose(i - 1);
double _skWick(int i) => 0.018 + 0.022 * math.sin(i * 1.3).abs();
double _skVol(int i) => 0.30 + 0.45 * math.sin(i * 0.22 + 0.5).abs();

/// 骨架屏：无数据时画一套「幽灵行情」——淡网格 + 蜡烛 + 平滑均线 + 成交量 + 副图占位。
/// 窗格比例与真实图一致；[phase] 为扫光相位（-0.2..1.2），[unit] 为 1 物理像素对应的逻辑长度。
void drawSkeleton(
  Canvas canvas,
  Size size, {
  required ChartTheme theme,
  required Color up,
  required Color down,
  required double phase,
  required double candleWidth,
  required bool showVolume,
  required int subCount,
  required double unit,
}) {
  final w = size.width;
  final h = size.height;
  if (w <= 0 || h <= 0) return;
  final dims = theme.dims;
  final cw = math.max(1.0, candleWidth);
  final n = (w / cw).floor().clamp(1, 400);
  final bodyW = cw * (1 - dims.candleGapRatio);

  // 窗格分配：与真实图同比例（主图 + 可选成交量 + 各副图）
  final gap = h * 0.02;
  final volH = showVolume ? h * dims.volumePaneFraction : 0.0;
  final subTotal = subCount > 0 ? math.min(h * dims.subPaneFraction * subCount, h * 0.5) : 0.0;
  final mainTop = h * 0.05;
  final mainBot = h - volH - subTotal - gap;
  final volTop = mainBot + gap;
  final volBot = mainBot + volH;

  double cx(int i) => cw * (i + 0.5);
  double sweep(int i, double base, double peak) =>
      (peak - (i / n - phase).abs() * (peak - base) * 2.4).clamp(base, peak);

  final fill = Paint();
  final stroke = Paint()..style = PaintingStyle.stroke;

  // 主图网格
  stroke
    ..color = theme.grid
    ..strokeWidth = unit;
  const rows = 4;
  for (var r = 0; r <= rows; r++) {
    final y = mainTop + (mainBot - mainTop) * r / rows;
    canvas.drawLine(Offset(0, y), Offset(w, y), stroke);
  }

  // 价格区间（含影线）
  var lo = double.infinity;
  var hi = double.negativeInfinity;
  for (var i = 0; i < n; i++) {
    hi = math.max(hi, _skClose(i) + _skWick(i));
    lo = math.min(lo, _skClose(i) - _skWick(i));
  }
  final pad = (hi - lo) * 0.08;
  lo -= pad;
  hi += pad;
  double yMain(double v) => mainTop + (hi - v) / (hi - lo) * (mainBot - mainTop);

  // 蜡烛（影线 + 实体，涨跌淡色）
  for (var i = 0; i < n; i++) {
    final close = _skClose(i);
    final open = _skOpen(i);
    final color = (close >= open ? up : down).withValues(alpha: sweep(i, 0.10, 0.30));
    final x = cx(i);
    final top = yMain(math.max(open, close));
    final bot = yMain(math.min(open, close));
    stroke.color = color;
    canvas.drawLine(
      Offset(x, yMain(math.max(open, close) + _skWick(i))),
      Offset(x, yMain(math.min(open, close) - _skWick(i))),
      stroke,
    );
    fill.color = color;
    canvas.drawRect(Rect.fromLTWH(x - bodyW / 2, top, bodyW, math.max(unit, bot - top)), fill);
  }

  // 平滑均线（窗口 5 居中），淡指标色
  final maPath = Path();
  for (var i = 0; i < n; i++) {
    var sum = 0.0;
    var cnt = 0;
    for (var k = math.max(0, i - 2); k <= math.min(n - 1, i + 2); k++) {
      sum += _skClose(k);
      cnt++;
    }
    final y = yMain(sum / cnt);
    i == 0 ? maPath.moveTo(cx(i), y) : maPath.lineTo(cx(i), y);
  }
  stroke
    ..color = theme.indicatorColor(0).withValues(alpha: 0.28)
    ..strokeWidth = 1.6 * unit;
  canvas.drawPath(maPath, stroke);

  // 成交量
  if (showVolume) {
    for (var i = 0; i < n; i++) {
      final bull = i == 0 || _skClose(i) >= _skClose(i - 1);
      final vh = _skVol(i) * (volBot - volTop);
      fill.color = (bull ? up : down).withValues(alpha: sweep(i, 0.08, 0.22));
      canvas.drawRect(Rect.fromLTWH(cx(i) - bodyW / 2, volBot - vh, bodyW, vh), fill);
    }
  }

  // 副图占位：每格一条幽灵指标线（不同相位错开，像 MACD/KDJ/RSI）
  if (subCount <= 0) return;
  final eachH = (subTotal - gap * subCount) / subCount;
  var top = volBot + gap;
  for (var p = 0; p < subCount; p++) {
    stroke
      ..color = theme.grid
      ..strokeWidth = unit;
    canvas.drawLine(Offset(0, top), Offset(w, top), stroke);
    final path = Path();
    for (var i = 0; i < n; i++) {
      final v = (0.5 + 0.32 * math.sin(i * 0.18 + p * 1.7) + 0.12 * math.sin(i * 0.06)).clamp(0, 1);
      final y = top + eachH * 0.18 + (1 - v) * eachH * 0.64;
      i == 0 ? path.moveTo(cx(i), y) : path.lineTo(cx(i), y);
    }
    stroke
      ..color = theme.indicatorColor(p).withValues(alpha: 0.26)
      ..strokeWidth = 1.4 * unit;
    canvas.drawPath(path, stroke);
    top += eachH + gap;
  }
}
