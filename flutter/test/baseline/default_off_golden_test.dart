// F1-05 默认关闭：不传画线参数时的图表要和基线（feat/flutter-port 9d3ee15）逐像素一致。
// 参考图在 testdata/baseline/，是在基线提交上用同一份测试 `--update-goldens` 生成的；
// 这里只用基线就有的参数，所以这份文件在基线和本分支上都能跑。
import 'dart:math' as math;

import 'package:chartkit_flutter/chartkit_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

final _key = GlobalKey();

Future<void> _pump(WidgetTester tester, KLineChartState state, KLineChart chart,
    {Size size = const Size(400, 420)}) async {
  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Center(
      child: RepaintBoundary(key: _key, child: SizedBox.fromSize(size: size, child: chart)),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _match(String name) =>
    expectLater(find.byKey(_key), matchesGoldenFile('../../testdata/baseline/$name.png'));

void main() {
  late KLineChartState state;

  setUp(() => state = KLineChartState(timeFrame: TimeFrame.m1)..setData(_data(240)));
  tearDown(() => state.dispose());

  testWidgets('default dark candles', (tester) async {
    await _pump(tester, state, KLineChart(state: state, entranceAnimation: false));
    await _match('01_default_dark');
  });

  testWidgets('light theme with indicators, high/low and trade marks', (tester) async {
    final c = state.candles;
    await _pump(
      tester,
      state,
      KLineChart(
        state: state,
        theme: ChartTheme.light,
        entranceAnimation: false,
        mainIndicators: [Ma(), const Boll()],
        subIndicators: const [Macd(), Kdj()],
        showHighLow: true,
        tradeMarks: [
          TradeMark(
              time: c[c.length - 12].time, isBuy: true, price: c[c.length - 12].low, count: 2),
          TradeMark(time: c[c.length - 5].time, isBuy: false, price: c[c.length - 5].high),
        ],
      ),
    );
    await _match('02_light_indicators');
  });

  testWidgets('time line mode', (tester) async {
    await _pump(
      tester,
      state,
      KLineChart(state: state, entranceAnimation: false, mode: ChartMode.timeLine),
    );
    await _match('03_timeline');
  });

  testWidgets('persistent crosshair after a long press', (tester) async {
    await _pump(
      tester,
      state,
      KLineChart(state: state, entranceAnimation: false, subIndicators: [Rsi()]),
    );
    await tester.longPressAt(tester.getTopLeft(find.byKey(_key)) + const Offset(180, 140));
    await tester.pump();
    await _match('04_crosshair');
  });

  testWidgets('scrolled with blank area, orderbook sticker and overlay painter', (tester) async {
    await _pump(
      tester,
      state,
      KLineChart(
        state: state,
        entranceAnimation: false,
        blankScrollRatio: 0.3,
        orderbookProvider: () => const ChartOrderbook(bid: 3501.5, ask: 3502.5),
        overlayPainter: (canvas, size, m) {
          final y = m.priceToY(3510);
          canvas.drawLine(
              Offset(0, y), Offset(m.mainRect.right, y), Paint()..color = const Color(0xFF3B82F6));
        },
      ),
    );
    await tester.dragFrom(
        tester.getTopLeft(find.byKey(_key)) + const Offset(200, 100), const Offset(-60, 0));
    await tester.pump(const Duration(seconds: 2));
    await _match('05_blank_orderbook_overlay');
  });

  testWidgets('landscape, snap crosshair by tap, rightmost-visible last price', (tester) async {
    await _pump(
      tester,
      state,
      KLineChart(
        state: state,
        entranceAnimation: false,
        crosshairMode: CrosshairMode.snapToClose,
        crosshairTrigger: CrosshairTrigger.tapOrLongPress,
        lastPriceMode: LastPriceMode.rightmostVisible,
        mainIndicators: [Ema()],
        subIndicators: const [Macd()],
      ),
      size: const Size(800, 360),
    );
    await tester.tapAt(tester.getTopLeft(find.byKey(_key)) + const Offset(500, 120));
    await tester.pump();
    await _match('06_landscape_snap');
  });

  testWidgets('skeleton while empty', (tester) async {
    final empty = KLineChartState();
    addTearDown(empty.dispose);
    await _pump(tester, empty, KLineChart(state: empty));
    await _match('07_skeleton');
  });
}
