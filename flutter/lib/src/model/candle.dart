import 'package:flutter/foundation.dart';

/// 一根 K 线（不可变）。只承载行情数据，**不含任何屏幕坐标或指标值**
/// —— 坐标由渲染层实时计算，指标由 indicator 层独立产出并缓存。
@immutable
class Candle {
  const Candle({
    required this.time,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    this.volume = 0,
    this.turnover = 0,
  });

  /// 开盘时间戳（毫秒）。
  final int time;
  final double open;
  final double high;
  final double low;
  final double close;

  /// 成交量。
  final double volume;

  /// 成交额（计价币），可选。
  final double turnover;

  /// 是否上涨（收 >= 开）。
  bool get isBullish => close >= open;

  /// 涨跌额。
  double get change => close - open;

  /// 涨跌幅（比例，0.05 = 5%）；开盘价为 0 时返回 0。
  double get changeRate => open == 0 ? 0 : (close - open) / open;

  Candle copyWith({
    int? time,
    double? open,
    double? high,
    double? low,
    double? close,
    double? volume,
    double? turnover,
  }) =>
      Candle(
        time: time ?? this.time,
        open: open ?? this.open,
        high: high ?? this.high,
        low: low ?? this.low,
        close: close ?? this.close,
        volume: volume ?? this.volume,
        turnover: turnover ?? this.turnover,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Candle &&
          other.time == time &&
          other.open == open &&
          other.high == high &&
          other.low == low &&
          other.close == close &&
          other.volume == volume &&
          other.turnover == turnover;

  @override
  int get hashCode => Object.hash(time, open, high, low, close, volume, turnover);

  @override
  String toString() => 'Candle(time: $time, o: $open, h: $high, l: $low, c: $close, v: $volume)';
}
