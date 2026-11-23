import 'package:flutter/foundation.dart';

import '../model/candle.dart';
import 'script_output.dart';

/// 输出和本地 K 线对不上的原因（对不上时整份不画，等调用方重新拉）。
enum ScriptAlignmentProblem {
  /// 本地 K 线里没有 `bars.to` 那一根（本地数据比输出旧，或换了品种）。
  missingLastBar,

  /// 本地有 `bars.from` 那根，但从它到 `bars.to` 不是 `bars.count` 根（两边的 K 线不是同一份）。
  barsMismatch,

  /// 输出的周期和图表当前周期不一样。
  periodMismatch,
}

@immutable
class ScriptAlignmentIssue {
  const ScriptAlignmentIssue(this.scriptId, this.problem, this.bars, this.message);

  final String scriptId;
  final ScriptAlignmentProblem problem;
  final ScriptBars bars;
  final String message;

  @override
  String toString() => 'ScriptAlignmentIssue($scriptId, ${problem.name}: $message)';
}

/// 一份输出在本地 K 线上的位置。
///
/// 逐根序列：第 i 个值画在本地第 `fromIndex + i` 根（[fromIndex] 可以是负数：本地比输出少早期的 K 线时，
/// 前面那些值没有地方画）。对象的时间用 [indexOfTime] 换成本地下标。
@immutable
class ScriptAlignment {
  const ScriptAlignment._(this.bars, this.toIndex, this._times);

  final ScriptBars bars;

  /// 本地 K 线里 `bars.to` 那根的下标。
  final int toIndex;
  final Int64List _times;

  /// `bars.from` 对应的本地下标（可能是负数）。
  int get fromIndex => toIndex - (bars.count - 1);

  /// 本地下标 → 逐根序列的值下标；不在序列里时返回 -1。
  int valueIndex(int localIndex) {
    final i = localIndex - fromIndex;
    return i >= 0 && i < bars.count ? i : -1;
  }

  /// 时间 → 本地下标（可以越过两端，越过的按周期推）。
  ///
  /// - 晚于 `bars.to`：「`bars.to` 往右第 k 根」，k = (t - to) / intervalMs，向下取整。
  /// - 早于 `bars.from`：同理往左推。
  /// - 在两者之间：开盘时间不大于 t 的最近一根（落在休市空档里的时间取空档前那根）。
  ///   本地没有这么早的 K 线时（[fromIndex] 是负数），按周期从本地第一根往左推。
  int indexOfTime(int t) {
    final iv = bars.intervalMs;
    if (t > bars.to) return toIndex + _floorDiv(t - bars.to, iv);
    if (t < bars.from) return fromIndex + _floorDiv(t - bars.from, iv);
    final first = _times[0];
    if (t < first) {
      final k = _floorDiv(t - first, iv);
      return k < fromIndex ? fromIndex : k;
    }
    var lo = 0;
    var hi = toIndex;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_times[mid] <= t) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  static int _floorDiv(int a, int b) => a >= 0 ? a ~/ b : -((-a + b - 1) ~/ b);
}

/// 对齐结果：成功时 [alignment] 非空，否则 [issue] 说明原因。
typedef ScriptAlignResult = ({ScriptAlignment? alignment, ScriptAlignmentIssue? issue});

/// 把 [output] 对到本地 [candles] 上。按 SCHEMA「约定」：以 `bars.to` 那根为锚，往前连续数 `bars.count` 根，
/// 不按时间间隔推；本地也有 `bars.from` 那根时核对两者正好相隔 `count - 1` 根。
///
/// [intervalMs] 是图表当前周期，给了就和 `bars.intervalMs` 比对。
ScriptAlignResult alignScriptOutput(ScriptOutput output, List<Candle> candles, {int? intervalMs}) {
  final bars = output.bars;
  ScriptAlignResult fail(ScriptAlignmentProblem p, String msg) =>
      (alignment: null, issue: ScriptAlignmentIssue(output.scriptId, p, bars, msg));

  if (intervalMs != null && intervalMs != bars.intervalMs) {
    return fail(ScriptAlignmentProblem.periodMismatch,
        'output is ${output.period} (${bars.intervalMs}ms), chart is ${intervalMs}ms');
  }
  final to = _find(candles, bars.to);
  if (to < 0) {
    return fail(ScriptAlignmentProblem.missingLastBar, 'no local candle at bars.to=${bars.to}');
  }
  final from = to - (bars.count - 1);
  if (candles.isNotEmpty && candles.first.time <= bars.from) {
    if (from < 0 || candles[from].time != bars.from) {
      return fail(ScriptAlignmentProblem.barsMismatch,
          'local candles between bars.from and bars.to are not ${bars.count} bars');
    }
  }
  final times = Int64List(to + 1);
  for (var i = 0; i <= to; i++) {
    times[i] = candles[i].time;
  }
  return (alignment: ScriptAlignment._(bars, to, times), issue: null);
}

/// 开盘时间正好等于 [time] 的下标，没有时 -1。
int _find(List<Candle> candles, int time) {
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
  return -1;
}

/// 对齐后各个对象的本地下标，一份输出、一次对齐只算一次，画的时候直接用。
class ResolvedScript {
  ResolvedScript(this.output, this.alignment)
      : segK1 = _map(output.lines.length, (i) => alignment.indexOfTime(output.lines[i].t1)),
        segK2 = _map(output.lines.length, (i) => alignment.indexOfTime(output.lines[i].t2)),
        boxK1 = _map(output.boxes.length, (i) => alignment.indexOfTime(output.boxes[i].t1)),
        boxK2 = _map(output.boxes.length, (i) => alignment.indexOfTime(output.boxes[i].t2)),
        labelK = _map(output.labels.length, (i) => alignment.indexOfTime(output.labels[i].time)),
        tradeK = _map(output.trades.length, (i) => alignment.indexOfTime(output.trades[i].time)),
        markerK = [
          for (final m in output.markers) _map(m.length, (i) => alignment.indexOfTime(m.times[i])),
        ],
        bgRuns = [for (final runs in output.bg) _runs(runs, alignment)],
        barColorRuns = [for (final runs in output.barColors) _runs(runs, alignment)];

  final ScriptOutput output;
  final ScriptAlignment alignment;
  final Int32List segK1;
  final Int32List segK2;
  final Int32List boxK1;
  final Int32List boxK2;
  final Int32List labelK;
  final Int32List tradeK;
  final List<Int32List> markerK;

  /// 每组区间按 `[起, 止]` 两个下标平铺存放，颜色在 `output.bg` 里同一位置。
  final List<Int32List> bgRuns;
  final List<Int32List> barColorRuns;

  static Int32List _map(int n, int Function(int i) f) {
    final out = Int32List(n);
    for (var i = 0; i < n; i++) {
      out[i] = f(i);
    }
    return out;
  }

  static Int32List _runs(List<ScriptRun> runs, ScriptAlignment a) {
    final out = Int32List(runs.length * 2);
    for (var i = 0; i < runs.length; i++) {
      out[i * 2] = a.indexOfTime(runs[i].t1);
      out[i * 2 + 1] = a.indexOfTime(runs[i].t2);
    }
    return out;
  }
}
