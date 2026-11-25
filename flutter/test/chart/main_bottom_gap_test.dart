// 主图下方给宿主控件留空白（KLineChart.mainBottomGap）：布局、mapper 给出的位置、空白里不画东西、
// 手势不归图表，以及「总高加上空白 = 原来的图 + 中间插一段空白」。

import 'package:chartkit_flutter/chartkit_flutter.dart';
import 'package:chartkit_flutter/src/chart/chart_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../script/fixtures.dart';
import '../tools/harness.dart';

List<Candle> _data(int n) => [
      for (var i = 0; i < n; i++)
        Candle(
          time: i * 60000,
          open: 100.0 + i,
          high: 102.0 + i,
          low: 99.0 + i,
          close: 101.0 + i,
          volume: 10,
        ),
    ];

const _dims = ChartDims();
const _gap = 34.0;

ChartLayout _layout({
  double gap = 0,
  double height = 500,
  bool volume = true,
  List<double> subs = const [1, 1],
}) =>
    ChartLayout.compute(
      size: Size(400, height),
      candles: _data(200),
      candleWidth: 8,
      scrollOffset: 0,
      dims: _dims,
      showVolume: volume,
      blankScrollRatio: 0,
      subWeights: subs,
      mainSeries: const [],
      measureText: (s) => s.length * 6.0,
      formatPrice: (v) => v.toStringAsFixed(2),
      labelPad: 4,
      mainBottomGap: gap,
    );

void main() {
  group('布局', () {
    test('默认 0：和不传一样，空白矩形高度为 0', () {
      final l = _layout();
      expect(l.mainBottomGap, 0);
      expect(l.mainBottomGapRect, Rect.fromLTWH(0, l.mainBottom, 400, 0));
      expect(l.mainBottomGapRect.isEmpty, isTrue);
    });

    test('总高加上空白：主图、成交量、副图都和原来一样高，成交量和副图整体下移空白的高度', () {
      final a = _layout(height: 500);
      final b = _layout(height: 500 + _gap, gap: _gap);
      expect(b.mainBottomGap, _gap);
      expect(b.mainBottom, a.mainBottom);
      expect(b.mainRect, a.mainRect);
      expect(b.volTop, a.volTop + _gap);
      expect(b.volBottom, a.volBottom + _gap);
      expect(b.subPanes.length, 2);
      for (var p = 0; p < 2; p++) {
        expect(b.subPanes[p].top, closeTo(a.subPanes[p].top + _gap, 1e-9));
        expect(b.subPanes[p].height, closeTo(a.subPanes[p].height, 1e-9));
        expect(b.subPanes[p].contentHeight, closeTo(a.subPanes[p].contentHeight, 1e-9));
      }
      expect(b.mainBottomGapRect, Rect.fromLTWH(0, b.mainBottom, 400, _gap));
      // 空白紧跟主图，成交量窗格在空白下面
      expect(b.mainBottomGapRect.bottom, lessThanOrEqualTo(b.volTop));
    });

    test('总高不变时主图让出空白的高度，其余窗格按去掉空白后的高度分', () {
      final a = _layout(height: 500);
      final b = _layout(height: 500, gap: _gap);
      expect(b.subPanes.last.bottom, closeTo(a.subPanes.last.bottom, 1e-9));
      expect(b.chartHeight, a.chartHeight);
      expect(b.mainBottom + _gap, lessThan(b.volTop + 1e-9));
    });

    test('没有成交量和副图时空白在主图和时间轴之间', () {
      final l = _layout(gap: _gap, volume: false, subs: const []);
      expect(l.mainBottom + _gap, closeTo(l.chartHeight, 1e-9));
      expect(l.mainBottomGapRect.bottom, closeTo(l.chartHeight, 1e-9));
    });

    test('副图收起动画中空白高度不变', () {
      final l = _layout(gap: _gap, subs: const [1, 0.3]);
      expect(l.mainBottomGap, _gap);
      expect(l.volTop, l.mainBottom + _gap + _dims.paneGap);
    });

    test('最多占绘图区高度的 40%', () {
      final l = _layout(gap: 1000, height: 300);
      final plot = 300 - _dims.bottomAxisHeight;
      expect(l.mainBottomGap, closeTo(plot * ChartLayout.maxMainBottomGapRatio, 1e-9));
      expect(l.mainBottom, greaterThan(0));
    });
  });

  group('组件', () {
    final candles = loadKlines();
    late KLineChartState state;
    late ScriptOutputController scripts;

    setUp(() {
      // 默认测试画面 800×600 放不下 600 + 34 高的图
      TestWidgetsFlutterBinding.instance.platformDispatcher.views.first.physicalSize =
          const Size(800, 800) * 3;
      state = KLineChartState(timeFrame: TimeFrame.m15)..setData(candles);
      scripts = ScriptOutputController(onAlignmentIssue: (i) => fail('$i'));
      scripts.setJson('macd', sampleJson('macd'));
    });
    tearDown(() {
      TestWidgetsFlutterBinding.instance.platformDispatcher.views.first.resetPhysicalSize();
      scripts.dispose();
      state.dispose();
    });

    KLineChart chart({double gap = 0, ValueChanged<double?>? onPrice}) => KLineChart(
          state: state,
          entranceAnimation: false,
          mainIndicators: [Ma()],
          subIndicators: [Rsi()],
          scriptOutputs: scripts,
          mainBottomGap: gap,
          crosshairMode: CrosshairMode.free,
          orderbookProvider: () => const ChartOrderbook(bid: 3500, ask: 3501),
          onCrosshairPriceChange: onPrice,
        );

    testWidgets('总高加上空白后，主图下沿附近以外的画面和原来逐像素一样（空白以下整体下移）', (tester) async {
      await pumpChart(tester, state, chart(), size: const Size(400, 600));
      final a = await capture(tester);
      final ma = state.mapper.value!;
      expect(ma.mainBottomGapRect.height, 0);
      await pumpChart(tester, state, chart(gap: _gap), size: const Size(400, 600 + _gap));
      final b = await capture(tester);
      final mb = state.mapper.value!;
      expect(mb.mainRect, ma.mainRect);
      expect(mb.mainBottomGapRect, Rect.fromLTWH(0, ma.mainRect.bottom, 400, _gap));
      // 主图下沿上下各 12 像素不比：网格最下面一档的价格标签原来跨在下沿上，留了空白后整个移进主图
      final r = a.ratio;
      final cut = (ma.mainRect.bottom * r).round();
      final shift = (_gap * r).round();
      final skip = (12 * r).round();
      var diff = 0;
      for (var y = 0; y < a.height; y++) {
        if ((y - cut).abs() < skip) continue;
        final yb = y < cut ? y : y + shift;
        for (var x = 0; x < a.width; x++) {
          if (a.bytes.getUint32((y * a.width + x) * 4) != b.bytes.getUint32((yb * b.width + x) * 4)) {
            diff++;
          }
        }
      }
      expect(diff, 0);
    });

    testWidgets('空白里只有背景色：十字光标竖线、横线、价签、盘口贴纸都不进去', (tester) async {
      final prices = <double?>[];
      await pumpChart(tester, state, chart(gap: _gap, onPrice: prices.add), size: const Size(400, 600));
      final m = state.mapper.value!;
      final gap = m.mainBottomGapRect;
      final o = tester.getTopLeft(find.byKey(shotKey));
      // 现价贴到主图下沿：把价格区间往上拖，让最新价落到可见区下方
      // 长按在主图里，再把手指挪进空白
      final g = await tester.startGesture(o + Offset(200, m.mainRect.bottom - 10));
      await tester.pump(const Duration(milliseconds: 600));
      await g.moveTo(o + Offset(200, gap.center.dy));
      await tester.pump();
      expect(state.crosshairIndex, greaterThanOrEqualTo(0));
      expect(prices.last, isNull, reason: '手指在空白里不给价格');
      final px = await capture(tester);
      final bg = ChartTheme.dark.background;
      var other = 0;
      for (var y = gap.top; y < gap.bottom; y += 1 / px.ratio) {
        for (var x = 0.0; x < gap.width; x += 1 / px.ratio) {
          if (px.at(x, y) != bg) other++;
        }
      }
      expect(other, 0);
      await g.up();
    });

    testWidgets('从空白里开始的拖动、长按、点击不归图表；主图里照常', (tester) async {
      await pumpChart(tester, state, chart(gap: _gap), size: const Size(400, 600));
      final m = state.mapper.value!;
      final o = tester.getTopLeft(find.byKey(shotKey));
      final inGap = o + m.mainBottomGapRect.center;
      final before = state.scrollOffset;
      await tester.dragFrom(inGap, const Offset(80, 0));
      await tester.pump(const Duration(seconds: 1));
      expect(state.scrollOffset, before);
      await tester.longPressAt(inGap);
      await tester.pump();
      expect(state.crosshairIndex, -1);
      await tester.dragFrom(o + Offset(200, m.mainRect.center.dy), const Offset(80, 0));
      await tester.pump(const Duration(seconds: 1));
      expect(state.scrollOffset, isNot(before));
    });

    testWidgets('宿主按 mapper 给的位置把控件叠在图上，点击落到宿主控件', (tester) async {
      var taps = 0;
      await tester.pumpWidget(frame(
        Stack(children: [
          Positioned.fill(child: chart(gap: _gap)),
          ValueListenableBuilder<KLineChartMapper?>(
            valueListenable: state.mapper,
            builder: (context, m, _) {
              if (m == null) return const SizedBox.shrink();
              return Positioned.fromRect(
                rect: m.mainBottomGapRect,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => taps++,
                  child: const ColoredBox(color: Color(0xFF223344)),
                ),
              );
            },
          ),
        ]),
        size: const Size(400, 600),
      ));
      await tester.pump();
      await tester.pump();
      final m = state.mapper.value!;
      await tester.tapAt(tester.getTopLeft(find.byKey(shotKey)) + m.mainBottomGapRect.center);
      expect(taps, 1);
    });

    testWidgets('宿主控件在图表后面时，空白里的点击也穿过图表落到它', (tester) async {
      var taps = 0;
      await tester.pumpWidget(frame(
        Stack(children: [
          Positioned.fill(
            child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => taps++),
          ),
          Positioned.fill(child: chart(gap: _gap)),
        ]),
        size: const Size(400, 600),
      ));
      await tester.pump();
      await tester.pump();
      final m = state.mapper.value!;
      final o = tester.getTopLeft(find.byKey(shotKey));
      await tester.tapAt(o + m.mainBottomGapRect.center);
      expect(taps, 1);
      await tester.tapAt(o + m.mainRect.center);
      expect(taps, 1, reason: '主图里的点击归图表');
    });

    testWidgets('和回放、对数坐标、图例留位同时打开', (tester) async {
      final replay = ChartReplayController(source: state);
      addTearDown(replay.dispose);
      await pumpChart(
          tester,
          state,
          KLineChart(
            state: state,
            entranceAnimation: false,
            mainIndicators: [Ma()],
            subIndicators: [Rsi()],
            scriptOutputs: scripts,
            logScale: true,
            reserveMainLegend: true,
            replay: replay,
            mainBottomGap: _gap,
          ),
          size: const Size(400, 600));
      replay
        ..start()
        ..select(900);
      await tester.pump();
      await tester.pump();
      final m = state.mapper.value!;
      expect(m.itemCount, 901);
      expect(m.logScale, isTrue);
      expect(m.mainBottomGapRect.height, _gap);
      expect(m.mainContentTop, greaterThan(0));
      expect(tester.takeException(), isNull);
      await matchGolden('14_main_bottom_gap_combo');
    });
  });

  group('参考图', () {
    testWidgets('主图下方留 34 的空白：成交量、内置副图、脚本副图在空白下面', (tester) async {
      tester.view.physicalSize = const Size(800, 800) * tester.view.devicePixelRatio;
      addTearDown(tester.view.resetPhysicalSize);
      final state = KLineChartState(timeFrame: TimeFrame.m15)..setData(loadKlines());
      final scripts = ScriptOutputController(onAlignmentIssue: (i) => fail('$i'));
      addTearDown(scripts.dispose);
      addTearDown(state.dispose);
      scripts.setJson('macd', sampleJson('macd'));
      await pumpChart(
          tester,
          state,
          KLineChart(
            state: state,
            entranceAnimation: false,
            mainIndicators: [Ma()],
            subIndicators: [Rsi()],
            scriptOutputs: scripts,
            mainBottomGap: _gap,
          ),
          size: const Size(400, 600 + _gap));
      await tester.longPressAt(tester.getTopLeft(find.byKey(shotKey)) + const Offset(200, 150));
      await tester.pump();
      await matchGolden('15_main_bottom_gap');
    });
  });
}
