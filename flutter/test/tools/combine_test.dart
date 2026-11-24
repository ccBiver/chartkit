// 合成图：两个品种的 K 线按开盘时间对齐后加减乘除。
// 期望值由另一份独立实现按同样规则在真实 K 线上算出，见 testdata/chart_tools/combine/SOURCE.md。
import 'dart:convert';
import 'dart:io';

import 'package:chartkit_flutter/chartkit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

const _dir = 'testdata/chart_tools/combine';

List<Candle> _load(String name) => [
      for (final e in jsonDecode(File('$_dir/$name').readAsStringSync()) as List)
        Candle(
          time: e['time'] as int,
          open: (e['open'] as num).toDouble(),
          high: (e['high'] as num).toDouble(),
          low: (e['low'] as num).toDouble(),
          close: (e['close'] as num).toDouble(),
        ),
    ];

Candle _c(int t, double o, double h, double l, double c) =>
    Candle(time: t, open: o, high: h, low: l, close: c, volume: 5, turnover: 9);

void main() {
  group('逐根', () {
    test('开高低收各自运算，成交量、成交额为 0', () {
      final a = _c(1, 10, 12, 9, 11), b = _c(1, 2, 3, 1, 2);
      final add = combineCandle(a, b, CombineOp.add)!;
      expect([add.open, add.high, add.low, add.close], [12, 15, 10, 13]);
      expect(add.volume, 0);
      expect(add.turnover, 0);
      final mul = combineCandle(a, b, CombineOp.multiply)!;
      expect([mul.open, mul.high, mul.low, mul.close], [20, 36, 9, 22]);
    });

    test('最高最低取四个结果里的最大最小：相除和相减时 high/high 不一定最大', () {
      final a = _c(1, 10, 12, 9, 11), b = _c(1, 2, 6, 1, 2);
      final div = combineCandle(a, b, CombineOp.divide)!;
      // 开 5、高 2、低 9、收 5.5 → 最高 9、最低 2
      expect([div.open, div.high, div.low, div.close], [5, 9, 2, 5.5]);
      final sub = combineCandle(a, b, CombineOp.subtract)!;
      // 开 8、高 6、低 8、收 9 → 最高 9、最低 6
      expect([sub.open, sub.high, sub.low, sub.close], [8, 9, 6, 9]);
    });

    test('除以 0 得到非有限数时返回 null', () {
      expect(combineCandle(_c(1, 1, 1, 1, 1), _c(1, 0, 1, 1, 1), CombineOp.divide), isNull);
    });
  });

  group('对齐', () {
    test('只保留两边都有的开盘时间，缺的一边直接跳过', () {
      final a = [_c(1, 1, 1, 1, 1), _c(2, 2, 2, 2, 2), _c(4, 4, 4, 4, 4), _c(5, 5, 5, 5, 5)];
      final b = [_c(0, 1, 1, 1, 1), _c(2, 1, 1, 1, 1), _c(3, 1, 1, 1, 1), _c(5, 1, 1, 1, 1)];
      final r = combineCandles(a, b, CombineOp.subtract);
      expect([for (final c in r) c.time], [2, 5]);
      expect([for (final c in r) c.close], [1, 4]);
    });

    test('合成结果非有限的那根跳过，其余照常', () {
      final a = [_c(1, 1, 1, 1, 1), _c(2, 2, 2, 2, 2)];
      final b = [_c(1, 0, 0, 0, 0), _c(2, 1, 1, 1, 1)];
      expect([for (final c in combineCandles(a, b, CombineOp.divide)) c.time], [2]);
    });

    test('空输入', () {
      expect(combineCandles(const [], [_c(1, 1, 1, 1, 1)], CombineOp.add), isEmpty);
    });
  });

  group('和独立实现对照（真实 K 线）', () {
    for (final (name, a, b, expected) in [
      ('XAUUSD 和 UKOUSD 1 小时（UKOUSD 少 369 根）', 'xauusd_1h.json', 'ukousd_1h.json',
          'expected_xau_uko_1h.json'),
      ('XAUUSD 和 XAGAUD 15 分钟', 'xauusd_15m.json', 'xagaud_15m.json', 'expected_xau_xagaud_15m.json'),
    ]) {
      test(name, () {
        final expectedAll = jsonDecode(File('$_dir/$expected').readAsStringSync()) as Map<String, dynamic>;
        final ca = _load(a), cb = _load(b);
        for (final op in CombineOp.values) {
          final want = expectedAll[op.name] as List;
          final got = combineCandles(ca, cb, op);
          expect(got.length, want.length, reason: op.name);
          for (var i = 0; i < got.length; i++) {
            final w = (want[i] as List).cast<num>();
            final g = got[i];
            // 运算顺序一样，结果逐位相等
            expect([g.time, g.open, g.high, g.low, g.close], [for (final v in w) v],
                reason: '${op.name} #$i');
          }
        }
      });
    }
  });

  group('参考图', () {
    testWidgets('金油比 XAUUSD ÷ UKOUSD（1 小时）', (tester) async {
      final r = combineCandles(_load('xauusd_1h.json'), _load('ukousd_1h.json'), CombineOp.divide);
      final state = KLineChartState(timeFrame: TimeFrame.h1)..setData(r);
      addTearDown(state.dispose);
      await pumpChart(
          tester,
          state,
          KLineChart(
            state: state,
            entranceAnimation: false,
            showVolume: false,
            mainIndicators: [Ma()],
            formatter: ChartFormatter(price: (v) => v.toStringAsFixed(3)),
          ));
      await matchGolden('10_combine_gold_oil');
    });
  });
}
