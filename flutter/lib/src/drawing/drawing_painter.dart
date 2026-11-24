import 'dart:math' as math;
import 'dart:ui';

import '../chart/chart_text.dart';
import 'drawing.dart';
import 'drawing_controller.dart';
import 'drawing_geometry.dart';
import 'drawing_theme.dart';

/// 画线绘制所需的已解析配色（主题里为空的项已用图表主题补上）。
class DrawingColors {
  const DrawingColors({
    required this.profit,
    required this.loss,
    required this.handleFill,
    required this.labelText,
  });

  final Color profit;
  final Color loss;
  final Color handleFill;
  final Color labelText;
}

/// 图表绘制时带上的画线配置（来自 `KLineChart` 的画线参数）。
class DrawingPaintConfig {
  const DrawingPaintConfig({
    required this.controller,
    required this.colors,
    required this.labels,
    required this.text,
  });

  final DrawingController controller;
  final DrawingColors colors;
  final DrawingLabels labels;
  final ChartText text;
}

/// 一帧的画线绘制器。画在主图矩形内（裁掉右轴、量图、副图），在 K 线之上、宿主图层和十字光标之下。
class DrawingPainter {
  DrawingPainter({
    required this.canvas,
    required this.projection,
    required this.colors,
    required this.labels,
    required this.text,
    required this.formatPrice,
  });

  final Canvas canvas;
  final DrawingProjection projection;
  final DrawingColors colors;
  final DrawingLabels labels;
  final ChartText text;
  final String Function(double price) formatPrice;

  final Paint _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final Paint _fill = Paint();

  Rect get _rect => projection.rect;

  void paintAll(DrawingController controller) {
    if (!controller.visible) return;
    canvas.save();
    canvas.clipRect(_rect);
    final selectedId = controller.selectedId;
    for (final d in controller.drawings) {
      paintDrawing(d, selected: d.id == selectedId);
    }
    _paintDraft(controller);
    canvas.restore();
  }

  /// 新建中：点数够了画完整形状，否则用虚线连起已点的点。
  void _paintDraft(DrawingController controller) {
    final tool = controller.tool;
    if (tool == null) return;
    final points = [...controller.draft, if (controller.preview != null) controller.preview!];
    if (points.isEmpty) return;
    final style = controller.style;
    if (points.length == tool.pointCount) {
      paintDrawing(
        Drawing(
          id: '',
          tool: tool,
          anchors: completeAnchors(tool, points),
          style: style,
          fibLevels: controller.fibLevels,
        ),
        selected: true,
      );
      return;
    }
    final xy = [for (final a in points) projection.toScreen(a)];
    for (var i = 1; i < xy.length; i++) {
      _dashed(xy[i - 1], xy[i], style.color, style.width);
    }
    for (final p in xy) {
      _handle(p, style.color);
    }
  }

  void paintDrawing(Drawing d, {required bool selected}) {
    final shape = shapeOf(d, projection);
    final pts = [for (final a in d.anchors) projection.toScreen(a)];
    final color = d.style.color;
    final width = d.style.width;
    switch (d.tool) {
      case DrawingTool.horizontalLine:
        final (a, b) = shape.segments.first;
        _line(a, b, color, width);
        final s = formatPrice(d.anchors[0].price);
        text.drawVCenterLeft(
            canvas, s, _rect.right - 4 - text.measure(s), a.dy - text.lineHeight / 2 - 2, color);
      case DrawingTool.verticalLine || DrawingTool.trendLine || DrawingTool.ray:
        final (a, b) = shape.segments.first;
        _line(a, b, color, width);
      case DrawingTool.rectangle:
        final r = shape.areas.first;
        canvas.drawRect(r, _fill..color = color.withValues(alpha: color.a * 0.12));
        canvas.drawRect(r, _strokeOf(color, width));
      case DrawingTool.fibRetracement:
        _paintFib(d, pts);
      case DrawingTool.priceRange:
        _paintRange(d, pts);
      case DrawingTool.longPosition || DrawingTool.shortPosition:
        _paintPosition(d, pts);
      case DrawingTool.gannFan:
        _paintGann(d, pts);
      case DrawingTool.pitchfork:
        _paintPitchfork(d, pts);
      case DrawingTool.elliottWave:
        _paintElliott(d, pts);
    }
    if (!selected) return;
    for (var i = 0; i < shape.handles.length; i++) {
      final handleColor = !d.tool.isPosition || i == 0
          ? color
          : i == 1
              ? colors.profit
              : colors.loss;
      _handle(shape.handles[i], handleColor);
    }
  }

  // ───────────────────────── 各工具 ─────────────────────────

  void _paintFib(Drawing d, List<Offset> pts) {
    final color = d.style.color;
    final (left, right) = fibSpan(pts[0], pts[1], _rect);
    final levels = fibLevelPrices(d.anchors[0].price, d.anchors[1].price, d.fibLevels)
        .map((e) => (e.$1, e.$2, projection.priceToY(e.$2)))
        .toList()
      ..sort((a, b) => a.$3.compareTo(b.$3));
    for (var k = 1; k < levels.length; k++) {
      final top = levels[k - 1].$3;
      final bottom = levels[k].$3;
      final alpha = k.isOdd ? 0.10 : 0.05;
      canvas.drawRect(Rect.fromLTRB(left, top, right, bottom),
          _fill..color = color.withValues(alpha: color.a * alpha));
    }
    for (final (level, price, y) in levels) {
      final edge = level == 0 || level == 1;
      _line(Offset(left, y), Offset(right, y),
          edge ? color : color.withValues(alpha: color.a * 0.75), edge ? d.style.width : 1);
      text.drawVCenterLeft(canvas, '${_trim(level)} (${formatPrice(price)})', left + 4,
          y - text.lineHeight / 2 - 1, color);
    }
    _dashed(pts[0], pts[1], color.withValues(alpha: color.a * 0.6), 1);
  }

  void _paintRange(Drawing d, List<Offset> pts) {
    final up = d.anchors[1].price >= d.anchors[0].price;
    final color = up ? colors.profit : colors.loss;
    final box = Rect.fromPoints(pts[0], pts[1]);
    canvas.drawRect(box, _fill..color = color.withValues(alpha: color.a * 0.14));
    final mx = box.center.dx;
    final tip = Offset(mx, pts[1].dy);
    _line(Offset(mx, pts[0].dy), tip, color, 1);
    final head = up ? 5.0 : -5.0;
    _line(tip, tip + Offset(-5, head), color, 1);
    _line(tip, tip + Offset(5, head), color, 1);
    final stats = rangeStats(d.anchors[0], d.anchors[1], projection.timeline);
    final label = '${_signed(stats.diff, formatPrice)} (${_signed(stats.percent, _pct)}%)  '
        '${stats.bars.abs()} ${labels.bars}';
    final h = text.lineHeight + 6;
    final y = up ? box.top - h / 2 - 4 : box.bottom + h / 2 + 4;
    _pill(label, Offset(mx, y), color, anchor: _PillAnchor.center);
  }

  void _paintPosition(Drawing d, List<Offset> pts) {
    final long = d.tool == DrawingTool.longPosition;
    final entry = d.anchors[0];
    final target = d.anchors[1];
    final stop = d.anchors[2];
    final (left, right) = positionSpan(pts[0], pts[1]);
    final yE = pts[0].dy;
    final yT = pts[1].dy;
    final yS = pts[2].dy;
    void zone(double y, Color c) {
      final r = Rect.fromLTRB(left, math.min(yE, y), right, math.max(yE, y));
      canvas.drawRect(r, _fill..color = c.withValues(alpha: c.a * 0.15));
      canvas.drawRect(r, _strokeOf(c.withValues(alpha: c.a * 0.55), 1));
    }

    zone(yT, colors.profit);
    zone(yS, colors.loss);
    _dashed(Offset(left, yE), Offset(right, yE), d.style.color, d.style.width);

    // 目标、止损写在方框外侧，入场和盈亏比合成一个色块压在入场线上：方框再扁也不会叠字
    final s = positionStats(long: long, entry: entry.price, target: target.price, stop: stop.price);
    double outside(double y) => y < yE ? y - text.lineHeight / 2 - 3 : y + text.lineHeight / 2 + 3;
    text.drawVCenterLeft(
        canvas,
        '${labels.target} ${formatPrice(target.price)}  ${_signed(s.rewardPercent, _pct)}%',
        left,
        outside(yT),
        colors.profit);
    text.drawVCenterLeft(
        canvas,
        '${labels.stop} ${formatPrice(stop.price)}  ${_signed(-s.riskPercent, _pct)}%',
        left,
        outside(yS),
        colors.loss);
    _pill(
        '${labels.entry} ${formatPrice(entry.price)}  '
        '${labels.riskReward} ${s.ratio.toStringAsFixed(2)}',
        Offset(left + drawingHandleRadius + 4, yE),
        d.style.color,
        anchor: _PillAnchor.left);
  }

  void _paintGann(Drawing d, List<Offset> pts) {
    final color = d.style.color;
    final dir = pts[1] - pts[0];
    for (final (ratio, label, end) in gannFanRays(pts[0], pts[1], _rect)) {
      final main = ratio == 1;
      final c = main ? color : color.withValues(alpha: color.a * 0.5);
      _line(pts[0], end, c, main ? d.style.width : 1);
      final w = text.measure(label);
      final dx = dir.dx >= 0 ? -w - 3 : 3;
      final dy = dir.dy * ratio >= 0 ? -text.lineHeight / 2 - 2 : text.lineHeight / 2 + 2;
      text.drawVCenterLeft(canvas, label, end.dx + dx, end.dy + dy, c);
    }
  }

  void _paintPitchfork(Drawing d, List<Offset> pts) {
    final color = d.style.color;
    // 三条线都画到足够远，交给裁切；只算到图边的话，上下叉线出界的边不同时填充会缺一角
    final dir = (pts[1] + pts[2]) / 2 - pts[0];
    final far = dir.distance == 0 ? Offset.zero : dir * (_rect.longestSide * 4 / dir.distance);
    final channel = Path()
      ..moveTo(pts[1].dx, pts[1].dy)
      ..lineTo(pts[1].dx + far.dx, pts[1].dy + far.dy)
      ..lineTo(pts[2].dx + far.dx, pts[2].dy + far.dy)
      ..lineTo(pts[2].dx, pts[2].dy)
      ..close();
    canvas.drawPath(channel, _fill..color = color.withValues(alpha: color.a * 0.06));
    _line(pts[1], pts[2], color.withValues(alpha: color.a * 0.5), 1);
    _line(pts[1], pts[1] + far, color.withValues(alpha: color.a * 0.8), d.style.width);
    _line(pts[2], pts[2] + far, color.withValues(alpha: color.a * 0.8), d.style.width);
    _line(pts[0], pts[0] + far, color, d.style.width);
  }

  void _paintElliott(Drawing d, List<Offset> pts) {
    final color = d.style.color;
    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (var i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].dx, pts[i].dy);
    }
    canvas.drawPath(path, _strokeOf(color, d.style.width));
    final a = d.anchors;
    for (var i = 0; i < pts.length; i++) {
      final peak = (i == 0 || a[i].price >= a[i - 1].price) &&
          (i == a.length - 1 || a[i].price >= a[i + 1].price);
      final h = text.lineHeight + 4;
      final y = pts[i].dy + (peak ? -h / 2 - 5 : h / 2 + 5);
      _pill('$i', Offset(pts[i].dx, y), color, anchor: _PillAnchor.center);
    }
  }

  // ───────────────────────── 基础 ─────────────────────────

  Paint _strokeOf(Color color, double width) => _stroke
    ..color = color
    ..strokeWidth = width;

  void _line(Offset a, Offset b, Color color, double width) =>
      canvas.drawLine(a, b, _strokeOf(color, width));

  void _dashed(Offset a, Offset b, Color color, double width, {double on = 4, double off = 3}) {
    final total = (b - a).distance;
    if (total <= 0) return;
    final dir = (b - a) / total;
    final paint = _strokeOf(color, width)..strokeCap = StrokeCap.butt;
    for (var d = 0.0; d < total; d += on + off) {
      canvas.drawLine(a + dir * d, a + dir * math.min(d + on, total), paint);
    }
    paint.strokeCap = StrokeCap.round;
  }

  void _handle(Offset p, Color color) {
    canvas.drawCircle(p, drawingHandleRadius, _fill..color = colors.handleFill);
    canvas.drawCircle(p, drawingHandleRadius, _strokeOf(color, 1.5));
  }

  /// 实色圆角标签：[at] 是标签的锚点（左端中点、中心或右端中点）。
  void _pill(String s, Offset at, Color bg, {required _PillAnchor anchor}) {
    const padH = 5.0;
    final w = text.measure(s) + padH * 2;
    final h = text.lineHeight + 4;
    final left = switch (anchor) {
      _PillAnchor.left => at.dx,
      _PillAnchor.center => at.dx - w / 2,
      _PillAnchor.right => at.dx - w,
    };
    final r = Rect.fromLTWH(left, at.dy - h / 2, w, h);
    canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(3)), _fill..color = bg);
    text.drawVCenterLeft(canvas, s, left + padH, at.dy, colors.labelText);
  }

  static String _pct(double v) => v.toStringAsFixed(2);

  static String _signed(double v, String Function(double) format) =>
      v >= 0 ? '+${format(v)}' : '-${format(-v)}';

  /// 0.5 → "0.5"，1.0 → "1"，0.236 → "0.236"。
  static String _trim(double v) {
    final s = v.toStringAsFixed(3);
    return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
  }
}

enum _PillAnchor { left, center, right }
