// 主图下方留空（KLineChart.mainBottomGap）默认不留：显式传 0 时，图表要和加这个参数之前的基线参考图逐像素一致。
// 比对的参考图都是在这个参数出现之前生成的：testdata/baseline/（9d3ee15）和 testdata/baseline_chart_tools/（c9a569b）。
// （baseline_chart_tools/01_all_on_candles 后来因为标签气泡翻转重新生成过，见 chart_tools_off_golden_test.dart。）
// 不传这个参数的情况由同目录的 default_off、script_off、chart_tools_off 三份基线测试覆盖（它们都不传 mainBottomGap）。
// 这里挑五个场景再显式传一次 0：默认蜡烛、长按十字光标加副图，以及画线、脚本图元、内置指标全开的三种配置。
import 'dart:math' as math;

import 'package:chartkit_flutter/chartkit_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../script/fixtures.dart';

final _key = GlobalKey();

Future<void> _match(String path) => expectLater(find.byKey(_key), matchesGoldenFile(path));

Future<void> _pump(WidgetTester tester, KLineChart chart, {required Size size}) async {
  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Center(
      child: RepaintBoundary(key: _key, child: SizedBox.fromSize(size: size, child: chart)),
    ),
  ));
}

/// 和 default_off_golden_test.dart 同一份合成数据。
List<Candle> _data(int n) => [
      for (var i = 0; i < n; i++)
        () {
          final base = 3500 + 30 * math.sin(i * 0.15) + 8 * math.cos(i * 0.9);
          final up = i % 3 != 0;
          return Candle(
            time: 1764720000000 + i * 60000,
            open: up ? base - 2 : base + 2,
            high: base + 5,
            low: base - 5,
            close: up ? base + 2 : base - 2,
            volume: 50.0 + (i * 37) % 100,
          );
        }(),
    ];

/// 和 chart_tools_off_golden_test.dart 同一组画线。
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
  test('mainBottomGap 默认是 0', () {
    expect(KLineChart(state: KLineChartState()).mainBottomGap, 0);
  });

  group('合成数据（testdata/baseline/，9d3ee15）', () {
    late KLineChartState state;

    setUp(() => state = KLineChartState(timeFrame: TimeFrame.m1)..setData(_data(240)));
    tearDown(() => state.dispose());

    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('默认蜡烛，显式 mainBottomGap: 0', (tester) async {
      await _pump(tester, KLineChart(state: state, entranceAnimation: false, mainBottomGap: 0),
          size: const Size(400, 420));
      await settle(tester);
      await _match('../../testdata/baseline/01_default_dark.png');
    });

    testWidgets('长按十字光标加副图，显式 mainBottomGap: 0', (tester) async {
      await _pump(
          tester,
          KLineChart(
              state: state, entranceAnimation: false, subIndicators: [Rsi()], mainBottomGap: 0),
          size: const Size(400, 420));
      await settle(tester);
      await tester.longPressAt(tester.getTopLeft(find.byKey(_key)) + const Offset(180, 140));
      await tester.pump();
      await _match('../../testdata/baseline/04_crosshair.png');
    });
  });

  group('画线、脚本图元、内置指标全开（testdata/baseline_chart_tools/，c9a569b）', () {
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
      await _pump(tester, chart, size: size);
      state.setViewport(candleWidth: 6);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
    }

    testWidgets('蜡烛、指标、画线、主图和副图脚本，显式 mainBottomGap: 0', (tester) async {
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
          mainBottomGap: 0,
        ),
      );
      await _match('../../testdata/baseline_chart_tools/01_all_on_candles.png');
    });

    testWidgets('分时、画线、脚本，显式 mainBottomGap: 0', (tester) async {
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
          mainBottomGap: 0,
        ),
      );
      await _match('../../testdata/baseline_chart_tools/02_all_on_timeline.png');
    });

    testWidgets('浅色、K 线改色、十字光标、右侧留白，显式 mainBottomGap: 0', (tester) async {
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
          mainBottomGap: 0,
        ),
        size: const Size(600, 420),
      );
      await tester.longPressAt(tester.getTopLeft(find.byKey(_key)) + const Offset(300, 120));
      await tester.pump();
      await _match('../../testdata/baseline_chart_tools/03_light_crosshair_blank.png');
    });
  });
}
