// 对齐：期望的下标和像素坐标都用独立的写法算（线性扫描、直接套公式），不调被测的换算函数。
// K 线是测试环境的真 15m 数据：每天 21:45 后休市 5 根，周末休市 197 根。
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:chartkit_flutter/chartkit_flutter.dart';
import 'package:chartkit_flutter/src/script/script_align.dart' show ResolvedScript;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

const _iv = 900000;

/// 独立算法：时间 → 本地下标。
int expectedIndex(List<int> times, int from, int to, int count, int t) {
  final toIndex = times.indexOf(to);
  final fromIndex = toIndex - (count - 1);
  if (t > to) return toIndex + ((t - to) / _iv).floor();
  if (t < from) return fromIndex + ((t - from) / _iv).floor();
  var k = -1;
  for (var i = 0; i <= toIndex; i++) {
    if (times[i] <= t) k = i;
  }
  return k < 0 ? fromIndex + ((t - times[0]) / _iv).floor().clamp(fromIndex - times.length, 0) : k;
}

Map<String, dynamic> _output({
  required int from,
  required int to,
  required int count,
  String pane = 'main',
  List<String> palette = const ['', '#FF00FFFF', '#0000FFFF', '#FFFF00FF', '#FF8000FF'],
  List<Map<String, dynamic>> lines = const [],
  List<Map<String, dynamic>> hlines = const [],
  List<Map<String, dynamic>> series = const [],
}) =>
    {
      'v': 1,
      'script': {'id': 'probe', 'name': 'Probe'},
      'symbol': 'XAUUSD',
      'period': '15m',
      'pane': pane,
      'precision': null,
      'bars': {'from': from, 'to': to, 'count': count, 'intervalMs': _iv},
      'palette': palette,
      'series': series,
      'hlines': hlines,
      'fills': [],
      'markers': [],
      'trades': [],
      'bg': [],
      'barColors': [],
      'candles': [],
      'lines': lines,
      'boxes': [],
      'labels': [],
      'tables': [],
      'inputs': [],
      'warnings': [],
    };

/// 一条竖线：t1 = t2，从 p1 画到 p2（默认贯穿整个主图）。
Map<String, dynamic> _vline(int t, int color, {double p1 = 100000, double p2 = 0}) => {
      't1': t, 'p1': p1, 't2': t, 'p2': p2, 'extend': 'none', 'color': color, 'style': 'solid', //
      'width': 2,
    };

final _key = GlobalKey();

class _Probe {
  _Probe(this.state, this.scripts);

  final KLineChartState state;
  final ScriptOutputController scripts;
  late ui.Image image;
  late ByteData pixels;

  Future<void> pump(WidgetTester tester, {double blank = 0}) async {
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: RepaintBoundary(
          key: _key,
          child: SizedBox(
            width: 400,
            height: 420,
            child: KLineChart(
              state: state,
              entranceAnimation: false,
              showVolume: false,
              blankScrollWidth: blank,
              scriptOutputs: scripts,
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> capture(WidgetTester tester) async {
    await tester.pump();

    await tester.runAsync(() async {
      final boundary = _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      image = await boundary.toImage();
      pixels = (await image.toByteData())!;
    });
  }

  ui.Color pixel(int x, int y) {
    final o = (y * image.width + x) * 4;
    return ui.Color.fromARGB(
        255, pixels.getUint8(o), pixels.getUint8(o + 1), pixels.getUint8(o + 2));
  }

  /// 第 [y] 行上颜色接近 [c] 的像素的覆盖率加权中心（像素中心记为 x + 0.5）。
  double? columnOf(ui.Color c, int y) {
    var sum = 0.0, weight = 0.0;
    final bg = pixel(2, y);
    for (var x = 0; x < image.width; x++) {
      final p = pixel(x, y);
      final w = _coverage(p, bg, c);
      if (w <= 0.05) continue;
      sum += (x + 0.5) * w;
      weight += w;
    }
    return weight == 0 ? null : sum / weight;
  }

  /// 第 [x] 列上的覆盖率加权中心。
  double? rowOf(ui.Color c, int x) {
    var sum = 0.0, weight = 0.0;
    final bg = pixel(x, 2);
    for (var y = 0; y < image.height; y++) {
      final w = _coverage(pixel(x, y), bg, c);
      if (w <= 0.05) continue;
      sum += (y + 0.5) * w;
      weight += w;
    }
    return weight == 0 ? null : sum / weight;
  }

  static double _coverage(ui.Color p, ui.Color bg, ui.Color c) {
    // 三个通道都按「背景 → 目标色」的比例算覆盖率，必须一致；目标色和背景接近的通道要保持背景色
    final ratios = <double>[];
    for (final (pv, bv, cv) in [(p.r, bg.r, c.r), (p.g, bg.g, c.g), (p.b, bg.b, c.b)]) {
      if ((cv - bv).abs() < 0.2) {
        if ((pv - bv).abs() > (cv - bv).abs() + 0.05) return 0;
      } else {
        ratios.add((pv - bv) / (cv - bv));
      }
    }
    if (ratios.isEmpty) return 0;
    final lo = ratios.reduce((a, b) => a < b ? a : b), hi = ratios.reduce((a, b) => a > b ? a : b);
    if (hi - lo > 0.15) return 0; // 颜色不对，不是这条线
    return lo.clamp(0.0, 1.0);
  }
}

void main() {
  final candles = loadKlines();
  final times = [for (final c in candles) c.time];
  final n = candles.length;

  group('indices (independent linear scan)', () {
    test('every object of every sample lands on the expected local bar', () {
      var checked = 0;
      for (final id in sampleScripts) {
        final o = loadSample(id);
        final a = alignScriptOutput(o, candles, intervalMs: _iv).alignment!;
        final r = ResolvedScript(o, a);
        int exp(int t) => expectedIndex(times, o.bars.from, o.bars.to, o.bars.count, t);
        for (var j = 0; j < o.lines.length; j++) {
          expect(r.segK1[j], exp(o.lines[j].t1), reason: '$id line $j');
          expect(r.segK2[j], exp(o.lines[j].t2), reason: '$id line $j');
        }
        for (var j = 0; j < o.boxes.length; j++) {
          expect([r.boxK1[j], r.boxK2[j]], [exp(o.boxes[j].t1), exp(o.boxes[j].t2)],
              reason: '$id box $j');
        }
        for (var j = 0; j < o.labels.length; j++) {
          expect(r.labelK[j], exp(o.labels[j].time), reason: '$id label $j');
        }
        for (var j = 0; j < o.trades.length; j++) {
          expect(r.tradeK[j], exp(o.trades[j].time), reason: '$id trade $j');
        }
        for (var g = 0; g < o.markers.length; g++) {
          for (var j = 0; j < o.markers[g].length; j++) {
            expect(r.markerK[g][j], exp(o.markers[g].times[j]), reason: '$id marker $g/$j');
          }
        }
        for (var g = 0; g < o.bg.length; g++) {
          for (var j = 0; j < o.bg[g].length; j++) {
            expect([r.bgRuns[g][j * 2], r.bgRuns[g][j * 2 + 1]],
                [exp(o.bg[g][j].t1), exp(o.bg[g][j].t2)]);
          }
        }
        checked += o.lines.length * 2 + o.boxes.length * 2 + o.labels.length + o.trades.length;
      }
      expect(checked, greaterThan(1500));
    });

    test('times inside session gaps, past the last bar and before the first', () {
      final o = parseScriptOutput(_output(from: times[500], to: times[999], count: 500)).output!;
      final a = alignScriptOutput(o, candles, intervalMs: _iv).alignment!;
      expect(a.toIndex, 999);
      expect(a.fromIndex, 500);
      // 每天 21:45 那根（下标 907）之后休市 5 根：空档里的时间都落在 907
      for (final m in [1, 15, 16, 30, 74]) {
        final t = times[907] + m * 60000;
        expect(a.indexOfTime(t), expectedIndex(times, o.bars.from, o.bars.to, 500, t));
        expect(a.indexOfTime(t), 907);
      }
      expect(times[908] - times[907], 5 * _iv);
      expect(a.indexOfTime(times[908]), 908);
      // 周末空档（539 之后 197 根）
      expect(a.indexOfTime(times[539] + 86400000), 539);
      // 越过最后一根：按周期往右数
      expect(a.indexOfTime(times[999] + 18 * _iv), 1017);
      expect(a.indexOfTime(times[999] + 18 * _iv + 60000), 1017);
      // 早于 bars.from：按周期往左数，不看本地真实 K 线（本地这段有休市空档）
      expect(a.indexOfTime(times[500] - 5 * _iv), 495);
      expect(a.indexOfTime(times[500] - 5 * _iv - 1), 494);
      // 第 540 根紧跟在周末空档后面：往左按周期数，落到的不是本地真实的第 535 根的时间
      final o2 = parseScriptOutput(_output(from: times[540], to: times[999], count: 460)).output!;
      final a2 = alignScriptOutput(o2, candles, intervalMs: _iv).alignment!;
      final t = times[540] - 5 * _iv;
      expect(a2.indexOfTime(t), 535);
      expect(a2.indexOfTime(t), expectedIndex(times, o2.bars.from, o2.bars.to, 460, t));
      expect(times[535], isNot(t), reason: 'the rule is by interval, not by local bars');
    });
  });

  group('status', () {
    test('missing bars.to: not drawn, reported once, drawn after the bar arrives', () async {
      final issues = <ScriptAlignmentIssue>[];
      final c = ScriptOutputController(onAlignmentIssue: issues.add);
      final next = times.last + _iv;
      c.setJson('x', _output(from: times[1], to: next, count: 1000));
      c.attachCandles(candles, intervalMs: _iv);
      expect(c.resolved(), isEmpty);
      c.resolved();
      c.deliverIssues();
      expect(issues.single.problem, ScriptAlignmentProblem.missingLastBar);
      final more = [...candles, Candle(time: next, open: 1, high: 2, low: 0.5, close: 1.5)];
      c.attachCandles(more, intervalMs: _iv);
      expect(c.resolved().single.$2.alignment.toIndex, 1000);
      c.deliverIssues();
      expect(issues.length, 1);
      c.dispose();
    });

    test('bar count mismatch and period mismatch are reported', () {
      final c = ScriptOutputController();
      c.setJson('a', _output(from: times[0], to: times[999], count: 900));
      c.attachCandles(candles, intervalMs: _iv);
      expect(c.alignmentOf('a')!.issue!.problem, ScriptAlignmentProblem.barsMismatch);
      c.setJson('a', _output(from: times[0], to: times[999], count: 1000));
      expect(c.alignmentOf('a')!.alignment, isNotNull);
      c.attachCandles(candles, intervalMs: 3600000);
      expect(c.alignmentOf('a')!.issue!.problem, ScriptAlignmentProblem.periodMismatch);
      c.dispose();
    });

    test('local list shorter than the output: values line up by position from bars.to', () {
      final o = loadSample('rsi');
      final local = candles.sublist(300);
      final c = ScriptOutputController()..setOutput('rsi', o);
      c.attachCandles(local, intervalMs: _iv);
      expect(c.alignmentOf('rsi')!.alignment!.fromIndex, -300);
      for (final k in [0, 1, 100, 450, 699]) {
        final original = times.indexOf(local[k].time);
        final v = o.series.single.values[original];
        expect(c.valuesAt(k).single.value, v.isNaN ? null : v, reason: 'local $k');
      }
      c.dispose();
    });

    test('a live bar after bars.to keeps the alignment; extrapolation stays relative to bars.to',
        () {
      final o = loadSample('opt-po3');
      final live = [
        ...candles,
        Candle(time: times.last + _iv, open: 1, high: 2, low: 0.5, close: 1.5)
      ];
      final a = alignScriptOutput(o, live, intervalMs: _iv).alignment!;
      expect(a.toIndex, 999);
      expect(a.indexOfTime(o.lines.first.t1), 999 + (o.lines.first.t1 - o.bars.to) ~/ _iv);
    });

    test('valuesAt matches the JSON by time', () {
      final c = ScriptOutputController();
      for (final id in ['boll', 'macd']) {
        c.setJson(id, sampleJson(id));
      }
      c.attachCandles(candles, intervalMs: _iv);
      final raw = jsonDecode(sampleJson('macd')) as Map;
      for (final k in [0, 33, 500, 999]) {
        final macd = c.valuesAt(k).where((v) => v.scriptId == 'macd').toList();
        expect(macd.map((v) => v.title), ['Histogram', 'MACD', 'Signal']);
        expect(macd[1].value, (raw['series'][1]['values'] as List)[k]);
      }
      expect(c.valuesAt(5000).every((v) => v.value == null), isTrue);
      c.dispose();
    });
  });

  group('pixels (independent formula)', () {
    late KLineChartState state;
    late ScriptOutputController scripts;
    late _Probe probe;

    setUp(() {
      state = KLineChartState(timeFrame: TimeFrame.m15)..setData(candles);
      scripts = ScriptOutputController();
      probe = _Probe(state, scripts);
    });
    tearDown(() {
      scripts.dispose();
      state.dispose();
    });

    /// 独立公式：滚动 [scroll] 时第 k 根中心的 x。
    double xOf(int k, double scroll) {
      final m = state.mapper.value!;
      final cw = m.candleWidth;
      final rightFloat = (n - 1) - scroll / cw;
      return m.mainRect.right - (rightFloat - k + 0.5) * cw;
    }

    double yOf(double price) {
      final m = state.mapper.value!;
      // 映射区间取自图上两个已知价位：独立于被测的 valueToY
      final y1 = m.priceToY(3000), y2 = m.priceToY(4000);
      return y1 + (price - 3000) / 1000 * (y2 - y1);
    }

    const magenta = ui.Color(0xFFFF00FF),
        blue = ui.Color(0xFF0000FF),
        yellow = ui.Color(0xFFFFFF00);
    const orange = ui.Color(0xFFFF8000);

    testWidgets('a time inside a daily gap is drawn on the bar before the gap', (tester) async {
      scripts.setJson(
          'p',
          _output(from: times[0], to: times[999], count: 1000, lines: [
            _vline(times[907] + 30 * 60000, 1), // 21:45 那根之后的空档里
            _vline(times[908], 2), // 空档后第一根
            _vline(times[925], 3),
          ]));
      await probe.pump(tester);
      const scroll = 69 * 8.0; // 默认每根 8：把第 930 根放在右边缘
      state.setViewport(scrollOffset: scroll);
      await probe.capture(tester);
      final row = (state.mapper.value!.mainRect.center.dy).round();
      for (final (color, k) in [(magenta, 907), (blue, 908), (yellow, 925)]) {
        expect(probe.columnOf(color, row), closeTo(xOf(k, scroll), 0.5), reason: 'bar $k');
      }
    });

    testWidgets('points past the last bar are drawn in the blank area, k bars to the right',
        (tester) async {
      scripts.setJson(
          'p',
          _output(from: times[0], to: times[999], count: 1000, lines: [
            _vline(times[999] + 3 * _iv, 1),
            _vline(times[999] + 12 * _iv, 2),
          ]));
      await probe.pump(tester, blank: 150);
      state.setViewport(scrollOffset: -150);
      await probe.capture(tester);
      final row = state.mapper.value!.mainRect.center.dy.round();
      expect(probe.columnOf(magenta, row), closeTo(xOf(1002, -150), 0.5));
      expect(probe.columnOf(blue, row), closeTo(xOf(1011, -150), 0.5));
    });

    testWidgets('points before bars.from are counted left by interval', (tester) async {
      scripts.setJson(
          'p',
          _output(from: times[500], to: times[999], count: 500, lines: [
            _vline(times[500] - 4 * _iv, 1),
            _vline(times[500], 2),
          ]));
      await probe.pump(tester);
      const scroll = 470 * 8.0; // 默认每根 8：把第 529 根放在右边缘
      state.setViewport(scrollOffset: scroll);
      await probe.capture(tester);
      final row = state.mapper.value!.mainRect.center.dy.round();
      expect(probe.columnOf(magenta, row), closeTo(xOf(496, scroll), 0.5));
      expect(probe.columnOf(blue, row), closeTo(xOf(500, scroll), 0.5));
    });

    testWidgets('horizontal lines sit on their price', (tester) async {
      scripts.setJson(
          'p',
          _output(from: times[0], to: times[999], count: 1000, hlines: [
            {
              'id': 'h0',
              'title': '',
              'price': 3540,
              'color': 4,
              'style': 'solid',
              'width': 2,
              'visible': true
            },
          ]));
      await probe.pump(tester);
      await probe.capture(tester);
      expect(probe.rowOf(orange, 20), closeTo(yOf(3540), 0.5));
    });

    testWidgets('a series is drawn bar by bar from bars.from, ignoring time gaps', (tester) async {
      // 每根的值都是 3500 + 下标 × 0（水平），只在第 905..910 根（跨过 21:45 的休市空档）有值
      final values = List<double?>.filled(1000, null);
      for (var i = 905; i <= 910; i++) {
        values[i] = 3520;
      }
      scripts.setJson(
          'p',
          _output(from: times[0], to: times[999], count: 1000, series: [
            {
              'id': 's', 'kind': 'dots', 'title': '', 'visible': true, 'color': 2,
              'values': values, //
              'shape': 'circle', 'size': 4,
            },
          ]));
      await probe.pump(tester);
      state.setViewport(candleWidth: 16, scrollOffset: 80 * 16.0);
      await probe.capture(tester);
      final y = yOf(3520);
      for (var i = 905; i <= 910; i++) {
        final x = xOf(i, 80 * 16.0);
        // 避开 K 线影线（在 x 处），取圆点里偏右 2 像素的那一列
        expect(probe.rowOf(blue, x.floor() + 2), closeTo(y, 0.5), reason: 'dot $i');
      }
      // 相邻两根的点相隔正好一根宽，不管中间休市多久
      final x907 = xOf(907, 80 * 16.0), x908 = xOf(908, 80 * 16.0);
      expect(x908 - x907, closeTo(16, 1e-9));
      expect(probe.columnOf(blue, y.round()), isNotNull);
    });
  });
}
