// 基准：对数坐标和各图表类型的一帧绘制耗时、回放每走一根的耗时、合成 K 线的耗时。
// 绘制耗时是在 PictureRecorder 上录绘制指令的时间，不含 GPU 光栅化。
// `flutter test` 跑在 JIT（debug）模式下，数字比 release 慢，只用来比较和找量级。不对耗时做断言。
import 'dart:ui' as ui;

import 'package:chartkit_flutter/chartkit_flutter.dart';
import 'package:chartkit_flutter/src/chart/chart_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../script/fixtures.dart';

String _stats(List<double> ms) {
  final s = List.of(ms)..sort();
  double q(double p) => s[((s.length - 1) * p).round()];
  return 'median ${q(0.5).toStringAsFixed(2)} ms, p90 ${q(0.9).toStringAsFixed(2)} ms, '
      'max ${s.last.toStringAsFixed(2)} ms (n=${s.length})';
}

void main() {
  const size = Size(430, 760);
  final candles = loadKlines();

  Future<KLineChartPainter> pump(WidgetTester tester, Widget chart, GlobalKey key) async {
    await tester.binding.setSurfaceSize(size);
    await tester.pumpWidget(MaterialApp(home: KeyedSubtree(key: key, child: chart)));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    return tester
        .widgetList<CustomPaint>(find.descendant(of: find.byKey(key), matching: find.byType(CustomPaint)))
        .map((w) => w.painter)
        .whereType<KLineChartPainter>()
        .single;
  }

  double frame(KLineChartPainter painter) {
    final recorder = ui.PictureRecorder();
    final sw = Stopwatch()..start();
    painter.paint(Canvas(recorder), size);
    final ms = sw.elapsedMicroseconds / 1000;
    recorder.endRecording().dispose();
    return ms;
  }

  testWidgets('一帧绘制：图表类型 × 对数坐标（MA、BOLL、MACD，每次挪 1 像素）', (tester) async {
    final lines = <String>[];
    // 第一组先整轮跑一遍预热（JIT），不记
    final runs = [
      (ChartMode.candle, false, true),
      for (final mode in [ChartMode.candle, ChartMode.ohlc, ChartMode.line, ChartMode.area])
        for (final log in [false, true]) (mode, log, false),
    ];
    for (final (mode, log, warmUp) in runs) {
      {
        final state = KLineChartState(timeFrame: TimeFrame.m15)..setData(candles);
        final painter = await pump(
            tester,
            KLineChart(
              state: state,
              mode: mode,
              logScale: log,
              entranceAnimation: false,
              mainIndicators: [Ma(), const Boll()],
              subIndicators: const [Macd()],
            ),
            GlobalKey());
        state.setViewport(candleWidth: 6);
        final ms = <double>[];
        for (var i = 0; i < 70; i++) {
          state.setViewport(scrollOffset: i.toDouble());
          final t = frame(painter);
          if (i >= 20) ms.add(t);
        }
        if (!warmUp) lines.add('  ${mode.name}${log ? ' + log' : ''}: ${_stats(ms)}');
        state.dispose();
      }
    }
    // ignore: avoid_print
    print('BENCH chart tools frame 430x760\n${lines.join('\n')}');
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('回放每走一根：next() 加一帧绘制（MA、BOLL、MACD，2 个主图 + 1 个副图脚本）', (tester) async {
    final state = KLineChartState(timeFrame: TimeFrame.m15)..setData(candles);
    final scripts = ScriptOutputController()
      ..setJson('boll', sampleJson('boll'))
      ..setJson('smc', sampleJson('smc'))
      ..setJson('tex', sampleJson('com-trend-exhaustion-continuation-map-bullby'));
    final replay = ChartReplayController(source: state);
    final key = GlobalKey();
    await pump(
        tester,
        KLineChart(
          state: state,
          entranceAnimation: false,
          mainIndicators: [Ma(), const Boll()],
          subIndicators: const [Macd()],
          scriptOutputs: scripts,
          replay: replay,
        ),
        key);
    replay
      ..start()
      ..select(800);
    await tester.pump();
    KLineChartPainter painter() => tester
        .widgetList<CustomPaint>(find.descendant(of: find.byKey(key), matching: find.byType(CustomPaint)))
        .map((w) => w.painter)
        .whereType<KLineChartPainter>()
        .single;
    final p = painter();
    final step = <double>[], draw = <double>[];
    for (var i = 0; i < 120; i++) {
      final sw = Stopwatch()..start();
      replay.next();
      final s = sw.elapsedMicroseconds / 1000;
      final d = frame(p);
      if (i >= 20) {
        step.add(s);
        draw.add(d);
      }
    }
    // ignore: avoid_print
    print('BENCH replay step 430x760\n'
        '  next() incl. incremental indicators: ${_stats(step)}\n'
        '  frame after each step (script layers re-recorded): ${_stats(draw)}');
    replay.dispose();
    scripts.dispose();
    state.dispose();
    await tester.binding.setSurfaceSize(null);
  });

  test('合成 1000 根 K 线', () {
    final other = [
      for (final c in candles)
        Candle(time: c.time, open: c.open / 80, high: c.high / 80, low: c.low / 80, close: c.close / 80),
    ];
    for (var i = 0; i < 5; i++) {
      combineCandles(candles, other, CombineOp.divide);
    }
    final ms = <double>[];
    for (var i = 0; i < 30; i++) {
      final sw = Stopwatch()..start();
      combineCandles(candles, other, CombineOp.divide);
      ms.add(sw.elapsedMicroseconds / 1000);
    }
    // ignore: avoid_print
    print('BENCH combineCandles 1000 bars: ${_stats(ms)}');
  });
}
