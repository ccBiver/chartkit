import '../model/candle.dart';
import 'indicator.dart';

/// 指标计算：仅「更新末根」或「追加一根」时走增量——只对最后 [Indicator.lookback] 根重算并取末值，
/// 拼接到上次结果上；其余情况（首屏 / 切周期 / 头部加载更多 / 指标变更）全量重算。
///
/// 纯函数：[prevData]/[prevSeries] 由调用方缓存并传入。调用方需保证 [prevSeries] 是由
/// **同一批指标实例**算出的（指标参数变了应清空缓存）。
List<IndicatorSeries> incrementalCompute(
  List<Indicator> indicators,
  List<Candle> data,
  List<Candle> prevData,
  List<IndicatorSeries> prevSeries,
) {
  if (data.isEmpty) return const [];
  if (!_canIncrement(indicators, data, prevData, prevSeries)) {
    return [for (final ind in indicators) ind.compute(data)];
  }
  final sameSize = data.length == prevData.length;
  return [
    for (var i = 0; i < indicators.length; i++)
      _incrementOne(indicators[i], data, prevSeries[i], sameSize),
  ];
}

bool _canIncrement(
  List<Indicator> indicators,
  List<Candle> data,
  List<Candle> prevData,
  List<IndicatorSeries> prevSeries,
) {
  if (prevData.isEmpty || prevSeries.length != indicators.length) return false;
  for (var i = 0; i < indicators.length; i++) {
    if (indicators[i].id != prevSeries[i].id) return false;
  }
  final grow = data.length - prevData.length;
  if (grow < 0 || grow > 1) return false; // 仅末根更新 / 追加一根
  if (data.first.time != prevData.first.time) return false; // 非头部插入 / 非重置
  final pLast = prevData.length - 1;
  if (data[pLast].time != prevData[pLast].time) return false; // 上次末根仍在原位
  return pLast < 1 || data[pLast - 1].time == prevData[pLast - 1].time;
}

IndicatorSeries _incrementOne(
  Indicator ind,
  List<Candle> data,
  IndicatorSeries prev,
  bool sameSize,
) {
  final lb = ind.lookback;
  if (lb <= 0 || lb >= data.length) return ind.compute(data);
  // 用最后 lb 根重算，取每条线的末值（lb 足够大时末值即为精确值）
  final win = ind.compute(data.sublist(data.length - lb));
  if (win.lines.length != prev.lines.length || prev.size != data.length - (sameSize ? 0 : 1)) {
    return ind.compute(data);
  }
  return prev.copyWith(lines: [
    for (var li = 0; li < prev.lines.length; li++)
      prev.lines[li].copyWith(values: [
        ...sameSize
            ? prev.lines[li].values.take(prev.lines[li].values.length - 1)
            : prev.lines[li].values,
        win.lines[li].values.last,
      ]),
  ]);
}
