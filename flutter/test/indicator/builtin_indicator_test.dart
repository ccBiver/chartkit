import 'dart:math' as math;

import 'package:chartkit_flutter/chartkit_flutter.dart';
import 'package:chartkit_flutter/src/indicator/moving_average.dart';
import 'package:flutter_test/flutter_test.dart';

const _tol = 1e-6;

/// 测试用 candle：仅关心 close/high/low/volume。
Candle _c(double close, {double? high, double? low, double vol = 0}) => Candle(
      time: 0,
      open: close,
      high: high ?? close,
      low: low ?? close,
      close: close,
      volume: vol,
    );

List<Candle> _closes(List<double> v) => v.map(_c).toList();

void main() {
  test('ma pane and values', () {
    final s = Ma(periods: const [3]).compute(_closes([1, 2, 3, 4, 5]));
    expect(s.pane, Pane.main);
    expect(s.lines[0].name, 'MA3');
    expect(s.lines[0].values, [null, null, 2.0, 3.0, 4.0]);
  });

  test('rsi golden: wilder smoothing, close to close', () {
    final s = Rsi(periods: const [2]).compute(_closes([10, 11, 10, 11, 12, 11]));
    final v = s.lines.single.values;
    expect(v[0], isNull);
    expect(v[1], isNull);
    expect(v[2], closeTo(50.0, _tol));
    expect(v[3], closeTo(75.0, _tol));
    expect(v[4], closeTo(87.5, _tol));
    expect(v[5], closeTo(43.75, _tol));
  });

  test('kdj seeds at 50 when rsv is 50', () {
    final s = const Kdj().compute([_c(10, high: 12, low: 8)]);
    for (final line in s.lines) {
      expect(line.values[0], closeTo(50.0, _tol));
    }
  });

  test('kdj J == 3K - 2D invariant', () {
    final data = [
      _c(10, high: 12, low: 8),
      _c(11, high: 13, low: 9),
      _c(9, high: 11, low: 7),
      _c(12, high: 14, low: 10),
      _c(13, high: 15, low: 11),
    ];
    final s = const Kdj().compute(data);
    final k = s.lines[0].values, d = s.lines[1].values, j = s.lines[2].values;
    for (var i = 0; i < data.length; i++) {
      expect(j[i], closeTo(3 * k[i]! - 2 * d[i]!, _tol), reason: 'J invariant at $i');
    }
  });

  test('macd wiring and histogram style', () {
    final data = [for (var i = 1; i <= 10; i++) _c(i.toDouble())];
    final s = const Macd().compute(data);
    expect(s.pane, Pane.sub);
    expect(s.lines.map((e) => e.name), ['DIF', 'DEA', 'MACD']);
    expect(s.lines[2].style, LineStyle.histogram);
    final close = data.map((e) => e.close).toList();
    final e12 = ema(close, 12), e26 = ema(close, 26);
    final dif = s.lines[0].values, dea = s.lines[1].values, bar = s.lines[2].values;
    for (var i = 0; i < close.length; i++) {
      expect(dif[i], closeTo(e12[i] - e26[i], _tol), reason: 'dif@$i');
      expect(bar[i], closeTo(2.0 * (dif[i]! - dea[i]!), _tol), reason: 'bar@$i');
    }
    expect(dif.last! > 0, isTrue);
  });

  test('macd on empty input yields three empty lines', () {
    final s = const Macd().compute(const []);
    expect(s.lines.length, 3);
    expect(s.size, 0);
  });

  test('boll indicator has three bands', () {
    final s = const Boll(period: 3, k: 2.0).compute(_closes([2, 4, 6, 8, 10]));
    expect(s.lines.map((e) => e.name), ['UP', 'MB', 'DN']);
    expect(s.lines[1].values[2], closeTo(4.0, _tol));
  });

  test('wr golden', () {
    final data = [
      _c(10, high: 12, low: 8),
      _c(11, high: 13, low: 9),
      _c(9, high: 14, low: 7),
    ];
    final v = Wr(periods: const [3]).compute(data).lines.single.values;
    expect(v[0], closeTo(50.0, _tol));
    expect(v[1], closeTo(40.0, _tol));
    expect(v[2], closeTo(5.0 / 7.0 * 100.0, _tol));
  });

  test('obv golden', () {
    final data = [_c(10, vol: 100), _c(11, vol: 200), _c(10, vol: 150), _c(12, vol: 300)];
    expect(const Obv().compute(data).lines.single.values, [0.0, 200.0, 50.0, 350.0]);
  });

  test('sar uses points style and has one-bar warmup', () {
    final data = [
      _c(10, high: 11, low: 9),
      _c(11, high: 12, low: 10),
      _c(12, high: 13, low: 11),
      _c(13, high: 14, low: 12),
    ];
    final s = const Sar().compute(data);
    expect(s.pane, Pane.main);
    expect(s.lines[0].style, LineStyle.points);
    expect(s.lines[0].values[0], isNull);
    expect(s.lines[0].values.skip(1).every((e) => e != null), isTrue);
  });

  test('volma averages volume', () {
    final data = [_c(1, vol: 10), _c(1, vol: 20), _c(1, vol: 30)];
    final s = VolMa(periods: const [2]).compute(data);
    expect(s.lines.single.values, [null, 15.0, 25.0]);
  });

  /// 增量计算前提：最后 lookback 根重算的末值 == 全量末值。
  test('lookback window matches full last value', () {
    final data = [
      for (var i = 0; i < 300; i++)
        () {
          final p = 50.0 + 10.0 * math.sin(i * 0.1);
          return _c(p, high: p + 1, low: p - 1, vol: 100.0 + i);
        }(),
    ];
    final inds = <Indicator>[
      Ma(periods: const [7, 30]), Ema(), const Boll(), const Macd(), const Kdj(), Rsi(), Wr(),
      VolMa(), //
    ];
    for (final ind in inds) {
      if (ind.lookback >= data.length) continue;
      final full = ind.compute(data);
      final tail = ind.compute(data.sublist(data.length - ind.lookback));
      for (var li = 0; li < full.lines.length; li++) {
        final a = full.lines[li].values.last;
        final b = tail.lines[li].values.last;
        if (a == null) {
          expect(b, isNull);
        } else {
          expect(b, closeTo(a, 1e-2), reason: '${ind.id} line$li last');
        }
      }
    }
  });
}
