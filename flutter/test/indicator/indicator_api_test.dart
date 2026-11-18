import 'package:chartkit_flutter/chartkit_flutter.dart';
import 'package:chartkit_flutter/src/indicator/indicator_engine.dart';
import 'package:flutter_test/flutter_test.dart';

Candle _c(double close, {int time = 0}) =>
    Candle(time: time, open: close, high: close, low: close, close: close);

/// 记录 compute 被调用时的输入长度，用来区分「全量」与「窗口」重算。
class _SpyIndicator extends Indicator {
  _SpyIndicator(this._lookback);
  final int _lookback;
  final List<int> calls = [];

  @override
  String get id => 'SPY';
  @override
  Pane get pane => Pane.sub;
  @override
  int get lookback => _lookback;

  @override
  IndicatorSeries compute(List<Candle> candles) {
    calls.add(candles.length);
    return IndicatorSeries(id, pane, [
      IndicatorLine('SPY', candles.map<double?>((e) => e.close).toList()),
    ]);
  }
}

void main() {
  tearDown(ChartRegistry.clear);

  test('formula factory creates an indicator', () {
    final tp = indicator(
      'TP',
      compute: (candles) => [
        IndicatorLine('TP', [for (final c in candles) (c.high + c.low + c.close) / 3.0]),
      ],
    );
    final s = tp.compute([_c(3), _c(6)]);
    expect(s.id, 'TP');
    expect(s.pane, Pane.sub);
    expect(s.lines.single.values, [3.0, 6.0]);
  });

  test('registry register / get / clear', () {
    expect(ChartRegistry.get('MACD'), isNull);
    Indicators.registerDefaults();
    expect(ChartRegistry.get('MACD'), isNotNull);
    expect(ChartRegistry.get('RSI'), isNotNull);
    expect(ChartRegistry.get('SAR'), isNotNull);
    expect(ChartRegistry.all().length, 10);
    ChartRegistry.unregister('MACD');
    expect(ChartRegistry.get('MACD'), isNull);
    ChartRegistry.clear();
    expect(ChartRegistry.all(), isEmpty);
  });

  test('series requires equal length lines', () {
    expect(
      () => IndicatorSeries('BAD', Pane.sub, const [
        IndicatorLine('a', [1.0, 2.0]),
        IndicatorLine('b', [1.0]),
      ]),
      throwsArgumentError,
    );
  });

  test('series lines are unmodifiable', () {
    final s = IndicatorSeries('X', Pane.sub, const [
      IndicatorLine('a', [1.0])
    ]);
    expect(() => s.lines.add(const IndicatorLine('b', [2.0])), throwsUnsupportedError);
  });

  test('builtin indicators compare by type and parameters', () {
    expect(Ma(), Ma());
    expect(Ma(periods: const [5]), isNot(Ma()));
    expect(const Macd(), const Macd(fast: 12));
    expect(const Macd(fast: 10), isNot(const Macd()));
    expect(Ma(periods: const [14]), isNot(Wr(periods: const [14])));
    expect(Ma().hashCode, Ma().hashCode);
  });

  group('incrementalCompute', () {
    List<Candle> data(int n) => [for (var i = 0; i < n; i++) _c(i.toDouble(), time: i)];

    test('empty data yields no series', () {
      expect(incrementalCompute([_SpyIndicator(3)], const [], const [], const []), isEmpty);
    });

    test('first run is a full compute', () {
      final spy = _SpyIndicator(3);
      incrementalCompute([spy], data(10), const [], const []);
      expect(spy.calls, [10]);
    });

    test('updating the last candle recomputes only the lookback window', () {
      final spy = _SpyIndicator(3);
      final d1 = data(10);
      final s1 = incrementalCompute([spy], d1, const [], const []);
      final d2 = [...d1.sublist(0, 9), _c(99, time: 9)];
      final s2 = incrementalCompute([spy], d2, d1, s1);
      expect(spy.calls, [10, 3]);
      expect(s2.single.lines.single.values.length, 10);
      expect(s2.single.lines.single.values.last, 99.0);
      expect(s2.single.lines.single.values[8], 8.0);
    });

    test('appending one candle extends the series by one', () {
      final spy = _SpyIndicator(3);
      final d1 = data(10);
      final s1 = incrementalCompute([spy], d1, const [], const []);
      final d2 = [...d1, _c(10, time: 10)];
      final s2 = incrementalCompute([spy], d2, d1, s1);
      expect(spy.calls, [10, 3]);
      expect(s2.single.lines.single.values.length, 11);
      expect(s2.single.lines.single.values.last, 10.0);
    });

    test('prepending history forces a full compute', () {
      final spy = _SpyIndicator(3);
      final d1 = data(10);
      final s1 = incrementalCompute([spy], d1, const [], const []);
      final d2 = [_c(-1, time: -1), ...d1];
      incrementalCompute([spy], d2, d1, s1);
      expect(spy.calls, [10, 11]);
    });

    test('unbounded lookback always recomputes fully', () {
      final spy = _SpyIndicator(Indicator.fullRecompute);
      final d1 = data(10);
      final s1 = incrementalCompute([spy], d1, const [], const []);
      incrementalCompute([spy], [...d1, _c(10, time: 10)], d1, s1);
      expect(spy.calls, [10, 11]);
    });
  });
}
