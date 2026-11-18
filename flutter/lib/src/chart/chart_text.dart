import 'dart:collection';

import 'package:flutter/painting.dart';

/// 画布文字绘制助手：带 LRU 缓存的 [TextPainter]，逐帧重复绘制同一标签时不重新排版。
///
/// - [drawBaselineLeft]：文本基线落在给定 y，左边缘在给定 x。
/// - [drawVCenterLeft]：文本竖直中心落在给定 y，左边缘在给定 x（右轴/光标标签）。
///
/// 用完需 [dispose]。
class ChartText {
  ChartText({
    required double fontSize,
    this.textScaler = TextScaler.noScaling,
    this.fontFamily,
    this.cacheSize = 128,
  }) : _style = TextStyle(inherit: false, fontSize: fontSize, fontFamily: fontFamily) {
    scaledFontSize = textScaler.scale(fontSize);
    lineHeight = _layout('0', const Color(0xFF000000)).height;
  }

  final TextScaler textScaler;
  final String? fontFamily;
  final int cacheSize;
  final TextStyle _style;
  final LinkedHashMap<(String, Color), TextPainter> _cache = LinkedHashMap();
  final Map<String, double> _widths = {};

  /// 已应用系统字体缩放的字号。
  late final double scaledFontSize;

  /// 单行行高。
  late final double lineHeight;

  /// 文本宽度。
  double measure(String text) {
    final cached = _widths[text];
    if (cached != null) return cached;
    if (_widths.length >= cacheSize * 4) _widths.clear();
    return _widths[text] = _layout(text, const Color(0xFF000000)).width;
  }

  /// 基线语义绘制：基线在 [baselineY]，左边缘在 [left]。
  void drawBaselineLeft(
    Canvas canvas,
    String text,
    double left,
    double baselineY,
    Color color, {
    double alpha = 1,
  }) {
    final tp = _layout(text, _fade(color, alpha));
    final baseline = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    tp.paint(canvas, Offset(left, baselineY - baseline));
  }

  /// 竖直居中绘制：竖直中心在 [yCenter]，左边缘在 [left]。
  void drawVCenterLeft(Canvas canvas, String text, double left, double yCenter, Color color) {
    final tp = _layout(text, color);
    tp.paint(canvas, Offset(left, yCenter - tp.height / 2));
  }

  void dispose() {
    for (final tp in _cache.values) {
      tp.dispose();
    }
    _cache.clear();
    _widths.clear();
  }

  // 透明度量化到 1/16，避免淡入淡出过程中每帧都生成新的缓存项
  static Color _fade(Color color, double alpha) =>
      alpha >= 1 ? color : color.withValues(alpha: color.a * (alpha * 16).round() / 16);

  TextPainter _layout(String text, Color color) {
    final key = (text, color);
    final hit = _cache.remove(key);
    if (hit != null) return _cache[key] = hit; // 移到队尾（最近使用）
    if (_cache.length >= cacheSize) {
      _cache.remove(_cache.keys.first)?.dispose();
    }
    final tp = TextPainter(
      text: TextSpan(text: text, style: _style.copyWith(color: color)),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: 1,
    )..layout();
    return _cache[key] = tp;
  }
}
