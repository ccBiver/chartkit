// 图表工具默认关闭：画线、脚本图元和内置指标全开，但不传图表工具的新参数时，
// 要和 feat/flutter-port 的 c9a569b（合并画线和脚本图元之后）逐像素一致。
// 参考图在 testdata/baseline_chart_tools/，是在 c9a569b 上用同一份测试 `--update-goldens` 生成的；
// 这里只用 c9a569b 就有的参数。
// 这些用例都不传 mainBottomGap（默认 0，不留空）：参考图生成于这个参数出现之前，必须逐像素不变。
import 'package:chartkit_flutter/chartkit_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../script/fixtures.dart';

final _key = GlobalKey();

Future<void> _match(String name) =>
    expectLater(find.byKey(_key), matchesGoldenFile('../../testdata/baseline_chart_tools/$name.png'));

List<Drawing> _drawings(List<Candle> c) => [
      Drawing(
        id: 't',
        tool: DrawingTool.trendLine,
        anchors: [DrawingAnchor(c[930].time, c[930].low), DrawingAnchor(c[985].time, c[985].high)],
        style: const DrawingStyle(color: Color(0xFF3B82F6)),
      ),
      Drawing(
        id: 'h',
        tool: DrawingTool.horizontalLine,
        anchors: [DrawingAnchor(c[960].time, 3550)],
        style: const DrawingStyle(color: Color(0xFFF59E0B)),
      ),
      Drawing(
        id: 'f',
        tool: DrawingTool.fibRetracement,
        anchors: [DrawingAnchor(c[945].time, 3520), DrawingAnchor(c[975].time, 3580)],
        style: const DrawingStyle(color: Color(0xFF8B5CF6)),
      ),
    ];

void main() {
  final candles = loadKlines();
  late KLineChartState state;
  late ScriptOutputController scripts;
  late DrawingController drawings;

  setUp(() {
    state = KLineChartState(timeFrame: TimeFrame.m15)..setData(candles);
    scripts = ScriptOutputController(onAlignmentIssue: (i) => fail('$i'));
    drawings = DrawingController(style: const DrawingStyle(color: Color(0xFF3B82F6)));
    for (final d in _drawings(candles)) {
      drawings.add(d);
    }
  });
  tearDown(() {
    drawings.dispose();
    scripts.dispose();
    state.dispose();
  });

  Future<void> pump(WidgetTester tester, KLineChart chart,
      {Size size = const Size(400, 520)}) async {
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Center(
        child: RepaintBoundary(key: _key, child: SizedBox.fromSize(size: size, child: chart)),
      ),
    ));
    state.setViewport(candleWidth: 6);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
  }

  testWidgets('candles with indicators, drawings, main and sub scripts', (tester) async {
    scripts.setJson('smc', sampleJson('smc'));
    scripts.setJson('macd', sampleJson('macd'));
    await pump(
      tester,
      KLineChart(
        state: state,
        entranceAnimation: false,
        mainIndicators: [Ma()],
        subIndicators: [Rsi()],
        drawingController: drawings,
        scriptOutputs: scripts,
      ),
    );
    await _match('01_all_on_candles');
  });

  testWidgets('time line mode with drawings and scripts', (tester) async {
    scripts.setJson('boll', sampleJson('boll'));
    scripts.setJson('tex', sampleJson('com-trend-exhaustion-continuation-map-bullby'));
    await pump(
      tester,
      KLineChart(
        state: state,
        entranceAnimation: false,
        mode: ChartMode.timeLine,
        drawingController: drawings,
        scriptOutputs: scripts,
      ),
    );
    await _match('02_all_on_timeline');
  });

  testWidgets('light theme, bar colors, crosshair and blank area', (tester) async {
    scripts.setJson('st', sampleJson('com-supertrend-strategy'));
    await pump(
      tester,
      KLineChart(
        state: state,
        theme: ChartTheme.light,
        entranceAnimation: false,
        blankScrollWidth: 60,
        initialBlankScroll: true,
        showHighLow: true,
        subIndicators: const [Macd()],
        drawingController: drawings,
        scriptOutputs: scripts,
      ),
      size: const Size(600, 420),
    );
    await tester.longPressAt(tester.getTopLeft(find.byKey(_key)) + const Offset(300, 120));
    await tester.pump();
    await _match('03_light_crosshair_blank');
  });
}
