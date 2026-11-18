import 'package:flutter/foundation.dart';

import '../model/time_frame.dart';
import 'number_format.dart';

/// 文案/数值格式化，由宿主注入（精度、时间、量纲）。默认时间按本地时区。
@immutable
class ChartFormatter {
  const ChartFormatter({
    this.price = defaultPrice,
    this.volume = defaultVolume,
    this.time = defaultTime,
    this.crosshairTime = defaultCrosshairTime,
  });

  final String Function(double value) price;
  final String Function(double value) volume;

  /// 底部时间轴刻度。
  final String Function(int epochMillis, TimeFrame timeFrame) time;

  /// 十字光标底部时间标签（比刻度更完整，含日期）。
  final String Function(int epochMillis, TimeFrame timeFrame) crosshairTime;

  static String defaultPrice(double v) => trimmed(v, 2);

  static String defaultVolume(double v) {
    if (v >= 1e9) return '${trimmed(v / 1e9, 2)}B';
    if (v >= 1e6) return '${trimmed(v / 1e6, 2)}M';
    if (v >= 1e3) return '${trimmed(v / 1e3, 2)}K';
    return trimmed(v, 2);
  }

  static String defaultTime(int epochMillis, TimeFrame _) {
    final d = DateTime.fromMillisecondsSinceEpoch(epochMillis);
    return '${pad2(d.hour)}:${pad2(d.minute)}';
  }

  static String defaultCrosshairTime(int epochMillis, TimeFrame _) {
    final d = DateTime.fromMillisecondsSinceEpoch(epochMillis);
    return '${pad2(d.month)}-${pad2(d.day)} ${pad2(d.hour)}:${pad2(d.minute)}';
  }
}
