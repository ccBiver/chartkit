// 在空值处断开的曲线（gaps: "break"）上，前后都是空值（或到头）的单个值：不画，也不算进主图价格区间和副图纵轴。
// 点、柱和跨空值连线（gaps: "connect"）的曲线不受影响。
import 'package:chartkit_flutter/chartkit_flutter.dart';
import 'package:chartkit_flutter/src/script/script_painter.dart' show scriptMainRange, scriptSubRange;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tools/harness.dart';
import 'fixtures.dart';

void main() {
  final candles = loadKlines();
  final n = candles.length;
  late KLineChartState state;
  late ScriptOutputController scripts;

  setUp(() {
    state = KLineChartState(timeFrame: TimeFrame.m15)..setData(candles);
    scripts = ScriptOutputController(onAlignmentIssue: (i) => fail('$i'));
  });
  tearDown(() {
    scripts.dispose();
    state.dispose();
  });

  Map<String, dynamic> series(String kind, List<double?> values,
          {String gaps = 'break', bool step = false, double base = 0}) =>
      {
        'id': 's', 'kind': kind, 'title': 'S', 'visible': true, 'color': 1, 'width': 3, //
        'style': 'solid', 'step': step, 'gaps': gaps, 'base': base, 'values': values,
      };

  Map<String, dynamic> script(String pane, List<Map<String, dynamic>> s) => {
        'v': 1,
        'script': {'id': 'lone', 'name': 'Lone'},
        'symbol': 'XAUUSD',
        'period': '15m',
        'pane': pane,
        'precision': null,
        'bars': {'from': candles.first.time, 'to': candles.last.time, 'count': n, 'intervalMs': 900000},
        'palette': ['', '#FF00FFFF'],
        'series': s,
        'hlines': [], 'fills': [], 'markers': [], 'trades': [], 'bg': [], 'barColors': [], //
        'candles': [], 'lines': [], 'boxes': [], 'labels': [], 'tables': [], 'inputs': [],
        'warnings': [],
      };

  /// 第 0 根 0（开头孤立）、第 500 根 9000（中间孤立）、第 600、601 根 3000、3001（连续两个）、末根 50（结尾孤立）。
  List<double?> values() {
    final v = List<double?>.filled(n, null);
    v[0] = 0;
    v[500] = 9000;
    v[600] = 3000;
    v[601] = 3001;
    v[n - 1] = 50;
    return v;
  }

  ({double min, double max})? mainRange(Map<String, dynamic> json) {
    expect(scripts.setJson('x', json).ok, isTrue);
    scripts.attachCandles(candles, intervalMs: 900000);
    return scriptMainRange(scripts.resolved(), 0, n - 1);
  }

  ({double min, double max})? subRange(Map<String, dynamic> json) {
    expect(scripts.setJson('x', json).ok, isTrue);
    scripts.attachCandles(candles, intervalMs: 900000);
    return scriptSubRange(scripts.resolved().single.$2, 0, n - 1);
  }

  group('价格区间和副图纵轴', () {
    test('断开的曲线：开头、中间、结尾的孤立值都不算，连续两个照常算', () {
      expect(mainRange(script('main', [series('line', values())])), (min: 3000, max: 3001));
      expect(subRange(script('sub', [series('line', values())])), (min: 3000, max: 3001));
    });

    test('断开的面积和阶梯线同样处理；面积的基线只在有线段时才算', () {
      expect(mainRange(script('main', [series('area', values())])), (min: 3000, max: 3001));
      expect(mainRange(script('main', [series('line', values(), step: true)])), (min: 3000, max: 3001));
      expect(subRange(script('sub', [series('area', values(), base: -10)])), (min: -10, max: 3001));
      final only = List<double?>.filled(n, null)..[500] = 9000;
      expect(subRange(script('sub', [series('area', only, base: -10)])), isNull);
    });

    test('跨空值连线的曲线和点不受影响', () {
      expect(mainRange(script('main', [series('line', values(), gaps: 'connect')])), (min: 0, max: 9000));
      expect(mainRange(script('main', [series('dots', values())])), (min: 0, max: 9000));
      expect(subRange(script('sub', [series('dots', values())])), (min: 0, max: 9000));
    });

    test('一组数里只要相邻有值就不算孤立：和后一根、前一根连着都行', () {
      final v = List<double?>.filled(n, null)
        ..[0] = 10
        ..[1] = 11
        ..[n - 2] = 20
        ..[n - 1] = 21;
      expect(mainRange(script('main', [series('line', v)])), (min: 10, max: 21));
    });
  });

  group('画', () {
    Future<Pixels> shot(WidgetTester tester, List<double?> v, {String kind = 'line'}) async {
      final mid = (candles[n - 20].high + candles[n - 20].low) / 2;
      final vals = [for (final x in v) x == null ? null : mid + x];
      scripts.setJson('x', script('main', [series(kind, vals)]));
      await pumpChart(
          tester,
          state,
          KLineChart(state: state, entranceAnimation: false, showVolume: false, scriptOutputs: scripts),
          cw: 10);
      return capture(tester);
    }

    testWidgets('孤立值不画，两个连续值画成一段', (tester) async {
      final none = await shot(tester, List<double?>.filled(n, null));
      final lone = await shot(tester, List<double?>.filled(n, null)..[n - 20] = 0);
      expect(none.diffCount(lone), 0);
      final pair = await shot(tester, List<double?>.filled(n, null)
        ..[n - 20] = 0
        ..[n - 19] = 1);
      expect(none.diffCount(pair), greaterThan(20));
      final loneArea = await shot(tester, List<double?>.filled(n, null)..[n - 20] = 0, kind: 'area');
      expect(none.diffCount(loneArea), 0);
    });
  });

  group('真样本：ML 超级趋势（第 1 根是 0，第 2 到 130 根为空（下标 1 到 129），linebr）', () {
    testWidgets('滚到最早一屏，主图价格区间不再被拉到 0', (tester) async {
      const id = 'com-machine-learning-adaptive-supertrend-alg';
      final o = loadSample(id);
      final p0 = o.series.firstWhere((s) => s.id == 'p0');
      expect(p0.breakGaps, isTrue);
      expect(p0.values[0], 0);
      expect([for (var i = 1; i < 130; i++) p0.values[i]].every((v) => v.isNaN), isTrue);
      scripts.setJson('ml', sampleJson(id));
      await pumpChart(
          tester,
          state,
          KLineChart(state: state, entranceAnimation: false, showVolume: false, scriptOutputs: scripts),
          size: const Size(430, 760),
          cw: 7,
          scroll: 1e9);
      final m = state.mapper.value!;
      expect(m.firstIndex, 0);
      var lo = double.infinity;
      for (var i = m.firstIndex; i <= m.lastIndex; i++) {
        if (candles[i].low < lo) lo = candles[i].low;
      }
      final bottom = m.yToPrice(m.mainRect.bottom);
      // 修之前是 -244.87
      expect(bottom, greaterThan(3000));
      expect(bottom, lessThanOrEqualTo(lo));
    });
  });
}
