// 更新：整份替换输出时窗格不动、不出现空帧，只重录受影响的那个脚本的图层。
import 'dart:convert';

import 'package:chartkit_flutter/chartkit_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

/// 改一下某条序列的值，模拟引擎 5 秒后发来的新一份输出。
String _changed(String id, {double delta = 1}) {
  final j = jsonDecode(sampleJson(id)) as Map<String, dynamic>;
  for (final s in j['series'] as List) {
    final v = s['values'] as List;
    v[v.length - 1] = (v.last as num? ?? 0) + delta;
  }
  for (final b in j['boxes'] as List) {
    b['top'] = (b['top'] as num) + delta;
  }
  return jsonEncode(j);
}

void main() {
  late KLineChartState state;
  late ScriptOutputController scripts;
  final candles = loadKlines();

  setUp(() {
    state = KLineChartState(timeFrame: TimeFrame.m15)..setData(candles);
    scripts = ScriptOutputController();
    for (final id in ['boll', 'smc', 'rsi', 'macd']) {
      scripts.setJson(id, sampleJson(id));
    }
  });
  tearDown(() {
    scripts.dispose();
    state.dispose();
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SizedBox(
        width: 400,
        height: 700,
        child: KLineChart(state: state, entranceAnimation: false, scriptOutputs: scripts),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
  }

  Map<String, int> counts() => Map.of(scripts.debugPaintCounts);

  testWidgets('replacing a sub-pane script re-records only that pane', (tester) async {
    await pump(tester);
    final before = counts();
    final panes = state.mapper.value!.mainRect;
    scripts.setJson('rsi', _changed('rsi'));
    await tester.pump();
    final after = counts();
    expect(after['rsi'], before['rsi']! + 1);
    for (final id in ['boll', 'smc', 'macd']) {
      expect(after[id], before[id], reason: id);
    }
    expect(state.mapper.value!.mainRect, panes, reason: 'pane layout does not move');
    expect(scripts.subPaneIds, ['rsi', 'macd'], reason: 'the pane keeps its place');
  });

  testWidgets('replacing a main script that does not change the price range re-records only it',
      (tester) async {
    await pump(tester);
    final before = counts();
    scripts.setJson('smc', _changed('smc'));
    await tester.pump();
    final after = counts();
    expect(after['smc'], before['smc']! + 1);
    for (final id in ['boll', 'rsi', 'macd']) {
      expect(after[id], before[id], reason: id);
    }
  });

  testWidgets('a main script that widens the price range redraws the main pane only',
      (tester) async {
    await pump(tester);
    final before = counts();
    scripts.setJson('boll', _changed('boll', delta: 500));
    await tester.pump();
    final after = counts();
    expect(after['boll'], before['boll']! + 1);
    expect(after['smc'], before['smc']! + 1, reason: 'same pane, new price scale');
    expect(after['rsi'], before['rsi']);
    expect(after['macd'], before['macd']);
  });

  testWidgets('moving the crosshair or repainting replays layers without re-recording',
      (tester) async {
    await pump(tester);
    final before = counts();
    await tester.longPressAt(const Offset(200, 200));
    await tester.pump();
    expect(state.crosshairIndex, greaterThanOrEqualTo(0));
    expect(counts(), before);
  });

  testWidgets('the replacement shows up in the very next frame (no empty frame)', (tester) async {
    await pump(tester);
    // 取值接口在替换前后都有值，副图窗格数不变
    final last = (jsonDecode(sampleJson('rsi'))['series'][0]['values'] as List).last as num;
    scripts.setJson('rsi', _changed('rsi', delta: 3));
    expect(scripts.valuesAt(999).where((v) => v.scriptId == 'rsi'), isNotEmpty);
    await tester.pump();
    expect(scripts.valuesAt(999).firstWhere((v) => v.scriptId == 'rsi').value,
        closeTo(last + 3, 1e-9));
    expect(scripts.subPaneIds.length, 2);
  });

  testWidgets('removing a sub script collapses its pane; others stay', (tester) async {
    await pump(tester);
    final mainBottom = state.mapper.value!.mainRect.bottom;
    scripts.remove('rsi');
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(state.mapper.value!.mainRect.bottom, greaterThan(mainBottom));
    expect(scripts.subPaneIds, ['macd']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a new bar on the same open time does not realign', (tester) async {
    await pump(tester);
    final a = scripts.alignmentOf('boll')!.alignment;
    final last = candles.last;
    state.appendOrUpdate(Candle(
        time: last.time,
        open: last.open,
        high: last.high,
        low: last.low,
        close: last.close + 0.01));
    await tester.pump();
    expect(identical(scripts.alignmentOf('boll')!.alignment, a), isTrue);
  });
}
