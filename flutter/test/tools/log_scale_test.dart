// 对数坐标：换算、价格区间、刻度、现价、十字光标、画线和脚本图元的位置，副图不受影响。
import 'dart:math' as math;
import 'dart:ui';

import 'package:chartkit_flutter/chartkit_flutter.dart';
import 'package:chartkit_flutter/src/chart/chart_layout.dart';
import 'package:chartkit_flutter/src/drawing/drawing_geometry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../script/fixtures.dart';
import 'harness.dart';

/// 价格从 100 涨到约 10000 的合成 K 线：线性刻度下前半段被压成一条线。
List<Candle> _growth(int n) => [
      for (var i = 0; i < n; i++)
        () {
          final base = 100 * math.pow(100, i / (n - 1)).toDouble();
          final up = i % 3 != 0;
          return Candle(
            time: 1764720000000 + i * 900000,
            open: base * (up ? 0.99 : 1.01),
            high: base * 1.02,
            low: base * 0.98,
            close: base * (up ? 1.01 : 0.99),
            volume: 10.0 + i % 7,
          );
        }(),
    ];

ChartLayout _layout(List<Candle> candles,
        {bool log = true,
        List<IndicatorSeries> main = const [],
        ({double min, double max})? Function(int, int)? extra}) =>
    ChartLayout.compute(
      size: const Size(400, 318),
      candles: candles,
      candleWidth: 400 / candles.length,
      scrollOffset: 0,
      dims: const ChartDims(),
      showVolume: false,
      blankScrollRatio: 0,
      subWeights: const [],
      mainSeries: main,
      measureText: (s) => s.length * 6.0,
      formatPrice: (v) => v.toStringAsFixed(2),
      labelPad: 4,
      extraMainRange: extra,
      logScale: log,
    );

/// 一份主图脚本：一条水平线和一条曲线，对齐到 [candles] 全部。
Map<String, dynamic> _mainScript(List<Candle> candles, {required double hline}) => {
      'v': 1,
      'script': {'id': 'log', 'name': 'Log'},
      'symbol': 'XAUUSD',
      'period': '15m',
      'pane': 'main',
      'precision': null,
      'bars': {
        'from': candles.first.time,
        'to': candles.last.time,
        'count': candles.length,
        'intervalMs': 900000
      },
      'palette': ['', '#FF00FFFF', '#00FFFFFF'],
      'series': [
        {
          'id': 's', 'kind': 'line', 'title': 'S', 'visible': true, 'color': 2, 'width': 2, //
          'style': 'solid', 'step': false, 'gaps': 'connect',
          'values': [for (final c in candles) c.close * 1.05],
        },
      ],
      'hlines': [
        {
          'id': 'h', 'title': 'H', 'price': hline, 'color': 1, 'style': 'solid', 'width': 1, //
          'visible': true,
        },
      ],
      'fills': [], 'markers': [], 'trades': [], 'bg': [], 'barColors': [], 'candles': [], //
      'lines': [], 'boxes': [], 'labels': [], 'tables': [], 'inputs': [], 'warnings': [],
    };

void main() {
  group('换算', () {
    final candles = _growth(200);

    test('对数刻度下等比的价格间距相同，yToPrice 是反函数', () {
      final l = _layout(candles);
      expect(l.logScale, isTrue);
      final d1 = l.priceToY(200) - l.priceToY(400);
      final d2 = l.priceToY(1000) - l.priceToY(2000);
      expect(d1, closeTo(d2, 1e-9));
      for (final p in [150.0, 999.5, 7777.0]) {
        expect(l.yToPrice(l.priceToY(p)), closeTo(p, p * 1e-12));
      }
    });

    test('线性刻度的换算不变', () {
      final l = _layout(candles, log: false);
      for (final p in [150.0, 5000.0]) {
        expect(l.priceToY(p), ChartLayout.valueToY(p, l.mainTop, l.mainBottom, l.priceMin, l.priceMax));
      }
    });

    test('价格区间：上下各留对数跨度的 6%', () {
      final l = _layout(candles);
      var lo = double.infinity, hi = 0.0;
      for (var i = l.firstIndex; i <= l.lastIndex; i++) {
        lo = math.min(lo, candles[i].low);
        hi = math.max(hi, candles[i].high);
      }
      double lg(double v) => math.log(v) / math.ln10;
      final span = lg(hi) - lg(lo);
      expect(lg(l.priceMin), closeTo(lg(lo) - span * 0.06, 1e-9));
      expect(lg(l.priceMax), closeTo(lg(hi) + span * 0.06, 1e-9));
    });

    test('非正数不计入价格区间：指标和脚本里的 0 不会把轴拉下去', () {
      final zeros = [for (var i = 0; i < candles.length; i++) i == candles.length - 1 ? 0.0 : null];
      final withZero =
          _layout(candles, main: [IndicatorSeries('z', Pane.main, [IndicatorLine('z', zeros)])]);
      final plain = _layout(candles);
      expect(withZero.priceMin, plain.priceMin);
      final extra = _layout(candles, extra: (a, b) => (min: 0, max: 1));
      expect(extra.priceMin, plain.priceMin);
      // 线性刻度照旧算进去
      final linear = _layout(candles, log: false, extra: (a, b) => (min: 0, max: 1));
      expect(linear.priceMin, lessThan(0));
    });

    test('整理成一个价时上下各放 2%', () {
      final flat = [
        for (var i = 0; i < 20; i++)
          Candle(time: i * 60000, open: 50, high: 50, low: 50, close: 50),
      ];
      final l = _layout(flat);
      final pad = math.pow(1.02, 1.12).toDouble();
      expect(l.priceMax / 50, closeTo(pad, 1e-9));
      expect(50 / l.priceMin, closeTo(pad, 1e-9));
    });

    test('画线整体拖动：对数刻度按比例', () {
      final d = Drawing(
        id: 'r',
        tool: DrawingTool.rectangle,
        anchors: const [DrawingAnchor(0, 100), DrawingAnchor(60000, 200)],
        style: const DrawingStyle(color: Color(0xFF000000)),
      );
      final moved = translateDrawing(d, DrawingTimeline(candles, 900000), 0, 0, priceFactor: 1.5);
      expect([for (final a in moved.anchors) a.price], [150, 300]);
    });
  });

  group('组件', () {
    final candles = loadKlines();
    late KLineChartState state;

    setUp(() => state = KLineChartState(timeFrame: TimeFrame.m15)..setData(candles));
    tearDown(() => state.dispose());

    testWidgets('主图映射、网格标签、现价和十字光标读数都按对数换算', (tester) async {
      final prices = <double?>[];
      await pumpChart(
          tester,
          state,
          KLineChart(
            state: state,
            entranceAnimation: false,
            showVolume: false,
            logScale: true,
            onCrosshairPriceChange: prices.add,
          ));
      final m = state.mapper.value!;
      expect(m.logScale, isTrue);
      // 现价线：收盘价所在的像素是现价线颜色
      final last = candles.last;
      final px = await capture(tester);
      final color = last.isBullish ? ChartTheme.dark.candleUp : ChartTheme.dark.candleDown;
      expect(px.coverage(1, m.priceToY(last.close), color, ChartTheme.dark.background),
          greaterThan(0.4));
      // 十字光标在主图中间：读数是对数换算的价，不是线性插值的价
      final y = (m.mainRect.top + m.mainRect.bottom) / 2;
      await tester.longPressAt(tester.getTopLeft(find.byKey(shotKey)) + Offset(150, y));
      await tester.pump();
      final top = m.yToPrice(m.mainRect.top), bottom = m.yToPrice(m.mainRect.bottom);
      expect(prices.last, closeTo(math.sqrt(top * bottom), 1e-6));
      expect((prices.last! - (top + bottom) / 2).abs(), greaterThan(1e-6));
    });

    testWidgets('不开对数时 mapper 的 logScale 为 false', (tester) async {
      await pumpChart(tester, state, KLineChart(state: state, entranceAnimation: false));
      expect(state.mapper.value!.logScale, isFalse);
    });

    testWidgets('画线的水平线和脚本的水平线、曲线都落在对数换算的位置上', (tester) async {
      final drawings = DrawingController(style: const DrawingStyle(color: Color(0xFFFFFF00)));
      final scripts = ScriptOutputController(onAlignmentIssue: (i) => fail('$i'));
      addTearDown(drawings.dispose);
      addTearDown(scripts.dispose);
      final growth = _growth(1000);
      state.setData(growth);
      drawings.add(Drawing(
        id: 'h',
        tool: DrawingTool.horizontalLine,
        anchors: [DrawingAnchor(growth[990].time, 7000)],
        style: const DrawingStyle(color: Color(0xFFFFFF00), width: 2),
      ));
      expect(scripts.setJson('log', _mainScript(growth, hline: 8500)).ok, isTrue);
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
          cw: 2);
      final m = state.mapper.value!;
      final px = await capture(tester);
      const x = 60.0;
      expect(px.coverage(x, m.priceToY(7000), const Color(0xFFFFFF00), ChartTheme.dark.background),
          greaterThan(0.5));
      expect(px.coverage(x, m.priceToY(8500), const Color(0xFFFF00FF), ChartTheme.dark.background),
          greaterThan(0.3));
      // 曲线：值是收盘价 × 1.05，在第 i 根的中心
      final i = m.lastIndex - 100;
      expect(
          px.coverage(m.indexToX(i), m.priceToY(growth[i].close * 1.05), const Color(0xFF00FFFF),
              ChartTheme.dark.background),
          greaterThan(0.3));
      // 线性刻度的同一价格在别的位置上：确认测的是对数换算
      final linearY = ChartLayout.valueToY(
          7000, m.mainRect.top, m.mainRect.bottom, m.yToPrice(m.mainRect.bottom), m.yToPrice(0));
      expect((linearY - m.priceToY(7000)).abs(), greaterThan(5));
    });

    testWidgets('副图、成交量不受影响', (tester) async {
      final scripts = ScriptOutputController(onAlignmentIssue: (i) => fail('$i'));
      addTearDown(scripts.dispose);
      scripts.setJson('macd', sampleJson('macd'));
      Future<Pixels> shot(bool log) async {
        await pumpChart(
            tester,
            state,
            KLineChart(
              state: state,
              entranceAnimation: false,
              logScale: log,
              subIndicators: [Rsi()],
              scriptOutputs: scripts,
            ));
        return capture(tester);
      }

      final a = await shot(false);
      final ma = state.mapper.value!;
      final b = await shot(true);
      final mb = state.mapper.value!;
      expect(ma.mainRect, mb.mainRect, reason: '右轴宽度一样时才能逐行比');
      // 主图以下（成交量、RSI、脚本副图）逐像素一样；主图不一样
      final from = ((ma.mainRect.bottom + 2) * a.ratio).ceil();
      var diffBelow = 0, diffMain = 0;
      for (var y = 0; y < a.height; y++) {
        for (var x = 0; x < a.width; x++) {
          final o = (y * a.width + x) * 4;
          if (a.bytes.getUint32(o) == b.bytes.getUint32(o)) continue;
          if (y >= from) {
            diffBelow++;
          } else {
            diffMain++;
          }
        }
      }
      expect(diffBelow, 0);
      expect(diffMain, greaterThan(0));
    });
  });

  group('参考图', () {
    testWidgets('100 涨到 10000：线性和对数', (tester) async {
      final state = KLineChartState(timeFrame: TimeFrame.m15)..setData(_growth(200));
      addTearDown(state.dispose);
      for (final log in [false, true]) {
        await pumpChart(
            tester,
            state,
            KLineChart(
                state: state,
                entranceAnimation: false,
                showVolume: false,
                logScale: log,
                mainIndicators: [Ma()]),
            cw: 2);
        await matchGolden(log ? '06_growth_log' : '05_growth_linear');
      }
    });
  });
}
