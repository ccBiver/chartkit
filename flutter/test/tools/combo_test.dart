// 图表工具和画线、脚本图元同时打开的组合。
import 'package:chartkit_flutter/chartkit_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../script/fixtures.dart';
import 'harness.dart';

void main() {
  final candles = loadKlines();
  late KLineChartState state;
  late ScriptOutputController scripts;
  late DrawingController drawings;
  late ChartReplayController replay;

  setUp(() {
    state = KLineChartState(timeFrame: TimeFrame.m15)..setData(candles);
    scripts = ScriptOutputController(onAlignmentIssue: (i) => fail('$i'));
    drawings = DrawingController(style: const DrawingStyle(color: Color(0xFF3B82F6)));
    replay = ChartReplayController(source: state);
    drawings
      ..add(Drawing(
        id: 't',
        tool: DrawingTool.trendLine,
        anchors: [
          DrawingAnchor(candles[930].time, candles[930].low),
          DrawingAnchor(candles[985].time, candles[985].high)
        ],
        style: const DrawingStyle(color: Color(0xFF3B82F6), width: 2),
      ))
      ..add(Drawing(
        id: 'f',
        tool: DrawingTool.fibRetracement,
        anchors: [DrawingAnchor(candles[945].time, 3520), DrawingAnchor(candles[975].time, 3580)],
        style: const DrawingStyle(color: Color(0xFF8B5CF6)),
      ));
  });
  tearDown(() {
    replay.dispose();
    drawings.dispose();
    scripts.dispose();
    state.dispose();
  });

  testWidgets('对数坐标 + 画线 + 主图脚本图元 + 副图脚本', (tester) async {
    scripts.setJson('smc', sampleJson('smc'));
    scripts.setJson('boll', sampleJson('boll'));
    scripts.setJson('macd', sampleJson('macd'));
    await pumpChart(
        tester,
        state,
        KLineChart(
          state: state,
          entranceAnimation: false,
          showVolume: false,
          logScale: true,
          drawingController: drawings,
          scriptOutputs: scripts,
        ),
        size: const Size(400, 520));
    expect(tester.takeException(), isNull);
    await matchGolden('11_combo_log_drawings_scripts');
  });

  testWidgets('美国线 + 对数坐标 + 回放 + 画线 + 主图和副图脚本，同时打开', (tester) async {
    scripts.setJson('st', sampleJson('com-supertrend-strategy'));
    scripts.setJson('tex', sampleJson('com-trend-exhaustion-continuation-map-bullby'));
    await pumpChart(
        tester,
        state,
        KLineChart(
          state: state,
          mode: ChartMode.ohlc,
          entranceAnimation: false,
          showVolume: false,
          logScale: true,
          mainIndicators: [Ma()],
          subIndicators: [Rsi()],
          drawingController: drawings,
          scriptOutputs: scripts,
          replay: replay,
          blankScrollWidth: 50,
          initialBlankScroll: true,
        ),
        size: const Size(400, 600),
        cw: 8,
        scroll: -50);
    replay.start();
    await tester.pump();
    final m = state.mapper.value!;
    await tester.tapAt(tester.getTopLeft(find.byKey(shotKey)) + Offset(m.indexToX(965), 80));
    await tester.pump();
    expect(replay.cursorIndex, 965);
    expect(drawings.drawings.length, 2, reason: '选起点的点击不会新建画线');
    for (var i = 0; i < 5; i++) {
      replay.next();
      await tester.pump();
    }
    // 回放中照样能长按看十字光标
    await tester.longPressAt(tester.getTopLeft(find.byKey(shotKey)) + const Offset(200, 120));
    await tester.pump();
    expect(state.mapper.value!.logScale, isTrue);
    expect(state.mapper.value!.itemCount, 971);
    expect(tester.takeException(), isNull);
    await matchGolden('12_combo_everything');
  });

  testWidgets('面积图 + 带自绘 K 线和 K 线改色的主图脚本：改色不作用在面积图上，自绘 K 线照画', (tester) async {
    scripts.setJson('d', sampleJson('com-decycler-high-low-breakout-schizoquant'));
    await pumpChart(
        tester,
        state,
        KLineChart(
          state: state,
          mode: ChartMode.area,
          entranceAnimation: false,
          showVolume: false,
          scriptOutputs: scripts,
        ));
    expect(tester.takeException(), isNull);
    await matchGolden('13_combo_area_script');
  });
}
