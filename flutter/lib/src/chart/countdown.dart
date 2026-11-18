import '../model/candle.dart';
import '../model/time_frame.dart';
import 'number_format.dart';

/// 当根 K 线的剩余时间文本（`mm:ss`，≥1 小时为 `HH:mm:ss`）；无数据时为 null。
///
/// 周期优先取数据自身最后两根的间隔（不依赖宿主设置的周期），只有一根时退回 [timeFrame]。
String? candleCountdown(List<Candle> candles, TimeFrame timeFrame, int nowMillis) {
  if (candles.isEmpty) return null;
  final n = candles.length;
  final gap = n >= 2 ? candles[n - 1].time - candles[n - 2].time : 0;
  final period = gap > 0 ? gap : timeFrame.millis;
  final remain = candles.last.time + period - nowMillis;
  final seconds = remain <= 0 ? 0 : remain ~/ 1000;
  final hh = seconds ~/ 3600;
  final mmss = '${pad2(seconds % 3600 ~/ 60)}:${pad2(seconds % 60)}';
  return hh > 0 ? '${pad2(hh)}:$mmss' : mmss;
}
