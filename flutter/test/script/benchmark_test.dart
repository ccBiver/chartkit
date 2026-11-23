// 基准：一帧的绘制耗时（在 PictureRecorder 上录绘制指令的时间，不含 GPU 光栅化）。
// 同时开 3 个主图脚本 + 2 个副图脚本，其中 ML 超级趋势有 500 个标签，趋势衰竭有 227 个方框和 482 个标记。
// `flutter test` 跑在 JIT（debug）模式下，数字比 release 慢，只用来比较和找量级。不对耗时做断言。
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:chartkit_flutter/chartkit_flutter.dart';
import 'package:chartkit_flutter/src/chart/chart_painter.dart';
import 'package:chartkit_flutter/src/script/script_painter.dart' show ScriptTextCache;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

const _main = ['boll', 'smc', 'com-machine-learning-adaptive-supertrend-alg'];
const _sub = ['rsi', 'com-trend-exhaustion-continuation-map-bullby'];

String _stats(List<double> ms) {
  final s = List.of(ms)..sort();
  double q(double p) => s[((s.length - 1) * p).round()];
  return 'median ${q(0.5).toStringAsFixed(2)} ms, p90 ${q(0.9).toStringAsFixed(2)} ms, '
      'max ${s.last.toStringAsFixed(2)} ms (n=${s.length})';
}

void main() {
  test('parse time per output', () {
    final lines = <String>[];
    var total = 0.0;
    for (final id in [..._main, ..._sub]) {
      final text = sampleJson(id);
      for (var i = 0; i < 5; i++) {
        parseScriptOutput(jsonDecode(text));
      }
      final times = <double>[];
      for (var i = 0; i < 20; i++) {
        final sw = Stopwatch()..start();
        parseScriptOutput(jsonDecode(text));
        times.add(sw.elapsedMicroseconds / 1000);
      }
      times.sort();
      total += times[times.length ~/ 2];
      lines.add('  $id (${(text.length / 1024).toStringAsFixed(0)} KB): '
          'jsonDecode+parse median ${times[times.length ~/ 2].toStringAsFixed(2)} ms');
    }
    // ignore: avoid_print
    print('BENCH parse\n${lines.join('\n')}\n  sum of medians ${total.toStringAsFixed(2)} ms');
  });

  test('text layout of 500 labels with an empty cache (the extra cost of a first frame)', () {
    final o = loadSample('com-machine-learning-adaptive-supertrend-alg');
    final times = <double>[];
    for (var r = 0; r < 6; r++) {
      final cache = ScriptTextCache();
      final sw = Stopwatch()..start();
      for (final l in o.labels) {
        cache.layout(l.text, 12, const Color(0xFFFFFFFF));
      }
      times.add(sw.elapsedMicroseconds / 1000);
      cache.dispose();
    }
    // ignore: avoid_print
    print(
        'BENCH text layout of ${o.labels.length} labels, empty cache: ${_stats(times.sublist(1))}');
  });

  for (final (label, size, cw) in [
    ('portrait 430x900, candle 6', const Size(430, 900), 6.0),
    ('landscape 900x420, candle 3 (most bars visible)', const Size(900, 420), 3.0),
  ]) {
    testWidgets('frame time, $label', (tester) async {
      final state = KLineChartState(timeFrame: TimeFrame.m15)..setData(loadKlines());
      final scripts = ScriptOutputController();
      final key = GlobalKey();
      var withScripts = true;

      Future<KLineChartPainter> pump() async {
        await tester.binding.setSurfaceSize(size);
        await tester.pumpWidget(MaterialApp(
          home: KLineChart(
            key: key,
            state: state,
            entranceAnimation: false,
            scriptOutputs: withScripts ? scripts : null,
          ),
        ));
        state.setViewport(candleWidth: cw, scrollOffset: 0);
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();
        return tester
            .widgetList<CustomPaint>(
                find.descendant(of: find.byKey(key), matching: find.byType(CustomPaint)))
            .map((w) => w.painter)
            .whereType<KLineChartPainter>()
            .single;
      }

      double frame(KLineChartPainter painter) {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        final sw = Stopwatch()..start();
        painter.paint(canvas, size);
        final ms = sw.elapsedMicroseconds / 1000;
        recorder.endRecording().dispose();
        return ms;
      }

      List<double> run(KLineChartPainter painter, {required bool cold}) {
        final out = <double>[];
        for (var i = 0; i < 70; i++) {
          // 冷帧：每次挪 1 像素，所有图层都要重录；热帧：只动十字光标，图层直接重放
          if (cold) {
            state.setViewport(scrollOffset: i.toDouble());
          } else {
            state.setCrosshair(990 - i % 20, 100, 200);
          }
          final ms = frame(painter);
          if (i >= 20) out.add(ms);
        }
        return out;
      }

      for (final id in [..._main, ..._sub]) {
        scripts.setJson(id, sampleJson(id));
      }
      final painter = await pump();
      final visible = state.mapper.value!.lastIndex - state.mapper.value!.firstIndex + 1;
      final cold = run(painter, cold: true);
      state.setViewport(scrollOffset: 0);
      final warm = run(painter, cold: false);
      state.clearCrosshair();

      withScripts = false;
      final plain = await pump();
      final base = run(plain, cold: true);

      // ignore: avoid_print
      print('BENCH frame, $label, $visible bars visible\n'
          '  3 main + 2 sub, all layers re-recorded: ${_stats(cold)}\n'
          '  3 main + 2 sub, layers replayed (crosshair move): ${_stats(warm)}\n'
          '  no scripts: ${_stats(base)}');
      scripts.dispose();
      state.dispose();
      await tester.binding.setSurfaceSize(null);
    });
  }
}
