import 'dart:math' as math;
import 'dart:ui';

import '../indicator/indicator.dart';
import 'chart_layout.dart';
import 'chart_renderer.dart';
import 'chart_types.dart';
import 'number_format.dart';

/// 成交量、副图、时间轴与十字光标的绘制。
extension ChartRendererPanes on ChartRenderer {
  /// 成交量窗格：涨跌着色的量柱 + 右轴量纲刻度（顶=峰值，底=0）。
  void drawVolume() {
    final l = layout;
    if (l.volBottom <= l.volTop) return;
    var vMax = 0.0;
    for (var i = l.firstIndex; i <= l.lastIndex; i++) {
      vMax = math.max(vMax, candles[i].volume);
    }
    if (vMax <= 0 || !vMax.isFinite) vMax = 1;
    final bw = bodyWidth;
    for (var i = l.firstIndex; i <= revealLast; i++) {
      final c = candles[i];
      final h = c.volume / vMax * (l.volBottom - l.volTop);
      final color = (c.isBullish ? up : down).withValues(alpha: theme.volumeUpAlpha);
      rect(color, Rect.fromLTWH(l.centerX(i) - bw / 2, l.volBottom - h, bw, h));
    }
    _axisValue(abbrevNum(vMax), l.volTop + text.scaledFontSize);
    _axisValue('0', l.volBottom - 3 * unit);
  }

  /// 副图窗格：[ids] 与 `layout.subPanes` 一一对应，按 id 从 [series] 取数据
  /// （而非下标：删除/重算瞬间避免「新窗格配到旧数据」的错位闪烁）。
  void drawSubPanes(List<String> ids, List<IndicatorSeries> series, int focusIndex) {
    for (var p = 0; p < layout.subPanes.length && p < ids.length; p++) {
      final pane = layout.subPanes[p];
      if (pane.height < 1) continue;
      final s = series.where((e) => e.id == ids[p]).firstOrNull;
      if (s != null) _drawSubPane(pane, s, focusIndex);
    }
  }

  void _drawSubPane(SubPaneRect pane, IndicatorSeries s, int focusIndex) {
    final l = layout;
    final range = _subRange(s);
    final contentBottom = pane.contentTop + pane.contentHeight;
    double subY(double v) =>
        ChartLayout.valueToY(v, pane.contentTop, contentBottom, range.min, range.max);

    // 内容按稳定态完整高度映射，再裁剪到当前可见高度：增/减副图时从头到脚显隐，而非压扁
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, pane.top, size.width, pane.bottom));
    line(theme.grid, Offset(0, pane.top), Offset(l.chartWidth, pane.top));
    _axisValue(formatter.price(range.max), pane.contentTop + text.scaledFontSize);
    _axisValue(formatter.price(range.min), contentBottom - 3 * unit);
    for (var li = 0; li < s.lines.length; li++) {
      final ln = s.lines[li];
      switch (ln.style) {
        case LineStyle.histogram:
          _histogram(ln.values, subY);
        case LineStyle.points:
          seriesPoints(ln.values, subY, theme.indicatorColor(li));
        case LineStyle.line:
          seriesLine(ln.values, subY, theme.indicatorColor(li));
      }
    }
    _subLegend(pane, s, focusIndex);
    canvas.restore();
  }

  /// 副图数值区间；含柱状线时纳入 0 基线。
  ({double min, double max}) _subRange(IndicatorSeries s) {
    final r =
        valueRange([for (final ln in s.lines) ln.values], layout.firstIndex, layout.lastIndex);
    var lo = r?.min ?? 0.0;
    var hi = r?.max ?? 1.0;
    if (s.lines.any((ln) => ln.style == LineStyle.histogram)) {
      lo = math.min(lo, 0);
      hi = math.max(hi, 0);
    }
    if (hi - lo < 1e-9) hi = lo + 1;
    return (min: lo, max: hi);
  }

  void _histogram(List<double?> values, double Function(double) subY) {
    final zeroY = subY(0);
    final bw = bodyWidth;
    for (var i = layout.firstIndex; i <= revealLast; i++) {
      final v = i < values.length ? values[i] : null;
      if (v == null || !v.isFinite) continue;
      final y = subY(v);
      final color = (v >= 0 ? up : down).withValues(alpha: 0.8);
      rect(
          color,
          Rect.fromLTRB(layout.centerX(i) - bw / 2, math.min(zeroY, y), layout.centerX(i) + bw / 2,
              math.max(zeroY, y)));
    }
  }

  /// 副图读数（聚焦根的各线当前值，按线着色），画在顶部独占的图例行内。
  void _subLegend(SubPaneRect pane, IndicatorSeries s, int focusIndex) {
    final yCenter = pane.top + dims.subLegendHeight / 2;
    var x = 6 * unit;
    for (var li = 0; li < s.lines.length; li++) {
      final values = s.lines[li].values;
      final v = focusIndex >= 0 && focusIndex < values.length ? values[focusIndex] : null;
      final label = '${s.lines[li].name} ${v == null ? '--' : formatter.price(v)}';
      text.drawVCenterLeft(canvas, label, x, yCenter, theme.indicatorColor(li));
      x += text.measure(label) + 12 * unit;
    }
  }

  void _axisValue(String s, double baselineY) => text.drawBaselineLeft(
      canvas, s, size.width - labelPad - text.measure(s), baselineY, theme.axisText);

  /// 底部时间轴：按像素间距均匀放刻度，锚定到 step 整数倍（拖动时平滑、不挤在一起）。
  void drawTimeAxis() {
    final l = layout;
    // 独立层：先用背景盖住可能溢出到此区域的内容（副图收缩瞬间），再画时间
    rect(theme.background, Rect.fromLTRB(0, l.chartHeight, size.width, size.height));
    final sample = formatter.time(candles[l.lastIndex].time, timeFrame);
    // 间距取「标签宽 + 间隙」与「图宽/3」的较大者 → 一屏最多 3 个、且不重叠
    final minGap = math.max(text.measure(sample) + 24 * unit, l.chartWidth / 3);
    final step = math.max(1, (minGap / l.candleWidth).ceil());
    final fadeMargin = 70 * unit;
    final start = (l.firstIndex / step).ceil() * step;
    for (var i = start; i <= l.lastIndex; i += step) {
      final label = formatter.time(candles[i].time, timeFrame);
      final w = text.measure(label);
      final x = l.centerX(i) - w / 2;
      // 按距左右边缘的余量做透明度过渡：靠边→透明，进入→不透明
      final room = math.min(x, l.chartWidth - (x + w));
      final alpha = (1 + room / fadeMargin).clamp(0.0, 1.0);
      if (alpha > 0.02) {
        text.drawBaselineLeft(canvas, label, x, size.height - 4 * unit, theme.axisText,
            alpha: alpha);
      }
    }
  }

  /// 十字光标。索引可落在右侧留白（> 末根）：此时无 K 线，水平线跟手指、时间按周期外推。
  void drawCrosshair({
    required int index,
    required double fingerY,
    required CrosshairMode mode,
    required bool hasSubPanes,
    bool showPriceLabel = true,
    double? lockedPrice,
  }) {
    final l = layout;
    if (index < l.firstIndex || index > l.rightFloat.ceil()) return;
    final x = l.centerX(index);
    final c = index < candles.length ? candles[index] : null;
    final useFinger = (c == null || mode == CrosshairMode.free) && fingerY >= 0;
    // 锁价时水平线贴住价位（夹在主图内），否则停在手指的屏幕位置
    final y = useFinger
        ? (lockedPrice != null
            ? l.priceToY(lockedPrice).clamp(l.mainTop, l.mainBottom).toDouble()
            : fingerY.clamp(0.0, l.chartHeight))
        : (c != null ? l.priceToY(c.close) : l.mainBottom);
    final bg = theme.crosshairLabelBg;
    final fg = theme.crosshairLabelText;

    final vColor = theme.crosshairVertical ?? theme.crosshair;
    final vWidth = theme.crosshairVerticalWidth;
    if (vWidth == null) {
      dashedLine(vColor, Offset(x, 0), Offset(x, l.chartHeight), 6, 6);
    } else {
      rect(vColor, Rect.fromLTRB(x - vWidth / 2, 0, x + vWidth / 2, l.chartHeight));
    }
    dashedLine(theme.crosshair, Offset(0, y), Offset(l.chartWidth, y), 6, 6);
    // 右轴价格：跟手指 → 手指处价格（仅主图区内）；吸附 → 收盘价
    if (!showPriceLabel) {
      // 价签由宿主自己的组件代替
    } else if (!useFinger && c != null) {
      rightLabel(y, formatter.price(c.close), bg, fg);
    } else if (useFinger && y <= l.mainBottom) {
      rightLabel(y, formatter.price(lockedPrice ?? l.yToPrice(y)), bg, fg);
    }
    final label = formatter.crosshairTime(c?.time ?? _extrapolatedTime(index), timeFrame);
    timeLabel(x, l.chartHeight + unit, size.height, label, bg, fg);
    // 有副图时，主图底沿再放一个时间标签，免得跑到最底部时间轴去对照
    if (hasSubPanes) {
      final half = labelHalfHeight;
      // 主图下方留了空白时整个标签放在主图里，不压进空白
      final center = l.mainBottomGap > 0 ? l.mainBottom - half : l.mainBottom;
      timeLabel(x, center - half, center + half, label, bg, fg);
    }
  }

  /// 留白区无 K 线：按数据自身的每根间隔外推时间（不依赖宿主设置的周期）。
  int _extrapolatedTime(int index) {
    final n = candles.length;
    final barMs =
        n >= 2 ? math.max(1, candles[n - 1].time - candles[n - 2].time) : timeFrame.millis;
    return candles.last.time + (index - (n - 1)) * barMs;
  }
}
