import 'dart:math' as math;

import 'package:chartkit_flutter/chartkit_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _CountingIndicator extends Indicator {
  int fullComputes = 0;

  @override
  String get id => 'COUNT';
  @override
  Pane get pane => Pane.sub;

  @override
  IndicatorSeries compute(List<Candle> candles) {
    fullComputes++;
    return IndicatorSeries(id, pane, [
      IndicatorLine('COUNT', [for (final c in candles) c.close]),
    ]);
  }
}

List<Candle> _data(int n, {int startTime = 0}) => [
      for (var i = 0; i < n; i++)
        () {
          final base = 100 + 10 * math.sin(i * 0.2);
          return Candle(
            time: startTime + i * 60000,
            open: base,
            high: base + 2,
            low: base - 2,
            close: base + (i.isEven ? 1 : -1),
            volume: 100.0 + i,
          );
        }(),
    ];

Future<void> _pump(WidgetTester tester, Widget chart, {Size size = const Size(400, 400)}) =>
    tester.pumpWidget(
      MaterialApp(
        home: Center(child: SizedBox.fromSize(size: size, child: chart)),
      ),
    );

/// 推进到所有一次性动画结束（入场 / 副图卷帘）。分多帧推进：
/// 「收起 → 展开」是两段首尾相接的动画，单次大步长 pump 只会跑完第一段。
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  late KLineChartState state;

  setUp(() => state = KLineChartState());
  tearDown(() => state.dispose());

  testWidgets('shows the skeleton while empty, then renders data', (tester) async {
    await _pump(tester, KLineChart(state: state));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    expect(state.mapper.value, isNull);

    state.setData(_data(200));
    await tester.pump();
    await _settle(tester);
    expect(tester.takeException(), isNull);
    expect(state.mapper.value, isNotNull);
  });

  testWidgets('fills loose constraints instead of collapsing', (tester) async {
    state.setData(_data(200));
    await tester.pumpWidget(MaterialApp(
      home: Column(
        children: [
          const SizedBox(height: 40),
          Expanded(child: KLineChart(state: state, entranceAnimation: false)),
        ],
      ),
    ));
    await tester.pump();
    expect(tester.getSize(find.byType(KLineChart)), const Size(800, 560));
    expect(state.mapper.value!.size, const Size(800, 560));
  });

  testWidgets('swapping the state object recomputes indicators and resets the mapper',
      (tester) async {
    Widget chart(KLineChartState s) => KLineChart(
          state: s,
          entranceAnimation: false,
          mainIndicators: [
            Ma(periods: const [5])
          ],
        );
    final other = KLineChartState();
    addTearDown(other.dispose);
    state.setData(_data(200));
    other
        .setData([for (final c in _data(50)) c.copyWith(close: c.close + 900, high: c.high + 900)]);
    await _pump(tester, chart(state));
    await tester.pump();
    await _pump(tester, chart(other));
    await tester.pump(const Duration(milliseconds: 400));
    final legend = tester.widget<Text>(find.textContaining('MA5 ')).data!;
    expect(double.parse(legend.split(' ').last), greaterThan(900));
    expect(other.mapper.value!.itemCount, 50);
  });

  testWidgets('first data plays the entrance, later resets honour resetAnimation', (tester) async {
    await _pump(tester, KLineChart(state: state, resetAnimation: false));
    double opacity() => tester
        .widget<Opacity>(
            find.descendant(of: find.byType(KLineChart), matching: find.byType(Opacity)))
        .opacity;
    state.setData(_data(200));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(opacity(), inExclusiveRange(0, 1), reason: 'first load animates in');
    await _settle(tester);
    state.setData(_data(100));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(opacity(), 1, reason: 'reset animation is off');
  });

  testWidgets('reports null when the state clears the crosshair itself', (tester) async {
    final reported = <Candle?>[];
    state.setData(_data(200));
    await _pump(
      tester,
      KLineChart(state: state, entranceAnimation: false, onCrosshairChange: reported.add),
    );
    await tester.pump();
    final center = tester.getCenter(find.byType(KLineChart));
    await tester.longPressAt(center);
    await tester.pump();
    expect(reported.length, 1);
    state.setData(_data(200));
    await _settle(tester);
    expect(reported.last, isNull);
    await tester.longPressAt(center);
    await tester.pump();
    expect(reported.length, 3, reason: 'same index after a reset is reported again');
  });

  testWidgets('inline indicator lists keep the incremental path across rebuilds', (tester) async {
    final spy = _CountingIndicator();
    state.setData(_data(200));
    Widget chart() => KLineChart(
          state: state,
          entranceAnimation: false,
          mainIndicators: [Ma(), const Boll()],
          subIndicators: [const Macd(), spy],
        );
    await _pump(tester, chart());
    await tester.pump();
    final before = spy.fullComputes;
    await _pump(tester, chart());
    await _pump(tester, chart());
    await tester.pump();
    expect(spy.fullComputes, before);
  });

  testWidgets('reports the crosshair price and hides its axis label on request', (tester) async {
    final prices = <double?>[];
    state.setData(_data(200));
    await _pump(
      tester,
      KLineChart(
        state: state,
        entranceAnimation: false,
        showCrosshairPriceLabel: false,
        onCrosshairPriceChange: prices.add,
      ),
    );
    await tester.pump();
    final origin = tester.getTopLeft(find.byType(KLineChart));
    await tester.longPressAt(origin + const Offset(200, 120));
    await tester.pump();
    expect(prices.single, closeTo(state.mapper.value!.yToPrice(120), 1e-6));

    await tester.tapAt(origin + const Offset(200, 120));
    await tester.pump();
    expect(prices.last, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('crosshair below the main pane reports no price', (tester) async {
    final prices = <double?>[];
    state.setData(_data(200));
    await _pump(
      tester,
      KLineChart(state: state, entranceAnimation: false, onCrosshairPriceChange: prices.add),
    );
    await tester.pump();
    final origin = tester.getTopLeft(find.byType(KLineChart));
    await tester.longPressAt(origin + Offset(200, state.mapper.value!.mainRect.bottom + 20));
    await tester.pump();
    expect(prices, isEmpty);
  });

  testWidgets('snap mode reports the close of the focused candle', (tester) async {
    final prices = <double?>[];
    state.setData(_data(200));
    await _pump(
      tester,
      KLineChart(
        state: state,
        entranceAnimation: false,
        crosshairMode: CrosshairMode.snapToClose,
        onCrosshairPriceChange: prices.add,
      ),
    );
    await tester.pump();
    await tester.longPressAt(tester.getCenter(find.byType(KLineChart)));
    await tester.pump();
    expect(prices.single, state.candles[state.crosshairIndex].close);
  });

  testWidgets('a tap shows the crosshair when the trigger allows it', (tester) async {
    state.setData(_data(200));
    await _pump(
      tester,
      KLineChart(
        state: state,
        entranceAnimation: false,
        crosshairTrigger: CrosshairTrigger.tapOrLongPress,
      ),
    );
    await tester.pump();
    final center = tester.getCenter(find.byType(KLineChart));
    await tester.tapAt(center);
    await tester.pump();
    expect(state.crosshairIndex, greaterThanOrEqualTo(0));
    await tester.tapAt(center);
    await tester.pump();
    expect(state.crosshairIndex, -1);
  });

  testWidgets('a locked viewport ignores pan and zoom', (tester) async {
    var locked = true;
    state.setData(_data(500));
    await _pump(
      tester,
      KLineChart(state: state, entranceAnimation: false, isViewportLocked: () => locked),
    );
    await tester.pump();
    await tester.fling(find.byType(KLineChart), const Offset(150, 0), 2000);
    await tester.pump(const Duration(milliseconds: 300));
    expect(state.scrollOffset, 0);

    locked = false;
    await tester.drag(find.byType(KLineChart), const Offset(150, 0));
    await tester.pump();
    expect(state.scrollOffset, greaterThan(100));
    await _settle(tester);
  });

  testWidgets('the repaint listenable redraws the overlay', (tester) async {
    final repaint = ValueNotifier(0);
    addTearDown(repaint.dispose);
    var paints = 0;
    state.setData(_data(200));
    await _pump(
      tester,
      KLineChart(
        state: state,
        entranceAnimation: false,
        repaint: repaint,
        overlayPainter: (canvas, size, mapper) => paints++,
      ),
    );
    await tester.pump();
    final before = paints;
    await tester.pump();
    expect(paints, before, reason: 'idle frames do not repaint');
    repaint.value++;
    await tester.pump();
    expect(paints, before + 1);
  });

  testWidgets('extra crosshair rows are appended to the default ones', (tester) async {
    state.setData(_data(200));
    await _pump(
      tester,
      KLineChart(
        state: state,
        entranceAnimation: false,
        crosshairExtraRows: (candle) => const [CrosshairDetailRow('Avg', '123.4')],
      ),
    );
    await tester.pump();
    await tester.longPressAt(tester.getCenter(find.byType(KLineChart)));
    await tester.pump();
    expect(find.text('Chg%'), findsOneWidget);
    expect(find.text('Avg'), findsOneWidget);
    expect(find.text('123.4'), findsOneWidget);
  });

  testWidgets('countdown and orderbook stickers render and clean up their timer', (tester) async {
    var polled = 0;
    state.setData(_data(200));
    Widget chart({required bool countdown}) => KLineChart(
          state: state,
          entranceAnimation: false,
          showCountdown: countdown,
          orderbookProvider: () {
            polled++;
            return const ChartOrderbook(bid: 100.5, ask: 100.7, bidLabel: 'B', askLabel: 'S');
          },
        );
    await _pump(tester, chart(countdown: true));
    await tester.pump();
    final before = polled;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(polled, greaterThan(before), reason: 'countdown repaints every second');

    await _pump(tester, chart(countdown: false));
    await tester.pump();
    final idle = polled;
    await tester.pump(const Duration(seconds: 3));
    expect(polled, idle, reason: 'timer stops with the option');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a locked crosshair stays on its price when the price range changes', (tester) async {
    final prices = <double?>[];
    state.setData(_data(200));
    await _pump(
      tester,
      KLineChart(
        state: state,
        entranceAnimation: false,
        lockCrosshairPrice: true,
        showHighLow: true,
        onCrosshairPriceChange: prices.add,
      ),
    );
    await tester.pump();
    final origin = tester.getTopLeft(find.byType(KLineChart));
    await tester.longPressAt(origin + const Offset(200, 120));
    await tester.pump();
    final locked = prices.single!;
    expect(state.crosshairPrice, locked);

    // 末根暴涨：可见价格区间被撑大，同一屏幕位置对应的价格变了
    state.appendOrUpdate(state.candles.last.copyWith(high: 400, close: 380));
    await tester.pump();
    await tester.pump();
    expect(state.mapper.value!.yToPrice(120), isNot(closeTo(locked, 1)));
    expect(state.crosshairPrice, locked);
    expect(prices, [locked], reason: 'no new price is reported');
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unlocked crosshair follows the screen position', (tester) async {
    final prices = <double?>[];
    state.setData(_data(200));
    await _pump(
      tester,
      KLineChart(state: state, entranceAnimation: false, onCrosshairPriceChange: prices.add),
    );
    await tester.pump();
    await tester.longPressAt(tester.getTopLeft(find.byType(KLineChart)) + const Offset(200, 120));
    await tester.pump();
    expect(state.crosshairPrice, isNull);
    state.appendOrUpdate(state.candles.last.copyWith(high: 400, close: 380));
    await tester.pump();
    state.appendOrUpdate(state.candles.last.copyWith(volume: 1));
    await tester.pump();
    expect(prices.length, 2);
    expect(prices.last, isNot(closeTo(prices.first!, 1)));
  });

  testWidgets('the detail panel honours the extra margin', (tester) async {
    state.setData(_data(200));
    await _pump(
      tester,
      KLineChart(
        state: state,
        entranceAnimation: false,
        crosshairPanelMargin: const EdgeInsets.only(right: 60, top: 10),
      ),
    );
    await tester.pump();
    final origin = tester.getTopLeft(find.byType(KLineChart));
    await tester.longPressAt(origin + const Offset(100, 200));
    await tester.pump();
    final panel = tester
        .getRect(find.ancestor(of: find.text('Chg%'), matching: find.byType(Container)).first);
    final axis = 400 - state.mapper.value!.mainRect.width;
    expect(panel.right, closeTo(origin.dx + 400 - 8 - axis - 60, 1e-6));
    expect(panel.top, closeTo(origin.dy + 18 + 10, 1e-6));
  });

  testWidgets('renders every mode and option without errors', (tester) async {
    state.setData(_data(200));
    for (final mode in ChartMode.values) {
      await _pump(
        tester,
        KLineChart(
          key: ValueKey(mode),
          state: state,
          mode: mode,
          theme: ChartTheme.light.copyWith(
            crosshairVertical: const Color(0x1F000000),
            crosshairVerticalWidth: 8,
            lastPriceText: const Color(0xFF000000),
            highLowText: const Color(0xFF333333),
          ),
          upDownColor: UpDownColor.redUpGreenDown,
          lastPriceMode: LastPriceMode.rightmostVisible,
          crosshairMode: CrosshairMode.snapToClose,
          blankScrollRatio: 0.5,
          blankScrollWidth: 120,
          showHighLow: true,
          mainIndicators: [Ma(), Ema(), const Boll(), const Sar()],
          subIndicators: [const Macd(), const Kdj(), Rsi(), Wr(), const Obv(), VolMa()],
          tradeMarks: [
            TradeMark(time: state.candles[190].time, isBuy: true, price: 101, count: 2),
            TradeMark(time: state.candles[195].time, isBuy: false),
          ],
          logo: const FlutterLogo(),
          onToggleFullscreen: () {},
          overlayPainter: (canvas, size, mapper) => canvas.drawLine(
            Offset(0, mapper.priceToY(mapper.latestPrice)),
            Offset(size.width, mapper.priceToY(mapper.latestPrice)),
            Paint(),
          ),
        ),
      );
      await _settle(tester);
      expect(tester.takeException(), isNull, reason: '$mode');
    }
  });

  testWidgets('survives tiny and degenerate sizes', (tester) async {
    state.setData(_data(3));
    for (final size in const [Size(10, 10), Size(81, 61), Size(400, 20)]) {
      await _pump(tester, KLineChart(state: state, subIndicators: const [Macd()]), size: size);
      await _settle(tester);
      expect(tester.takeException(), isNull, reason: '$size');
    }
  });

  testWidgets('mapper round-trips price and index', (tester) async {
    state.setData(_data(200));
    await _pump(tester, KLineChart(state: state, entranceAnimation: false));
    await tester.pump();
    final mapper = state.mapper.value!;
    expect(mapper.itemCount, 200);
    expect(mapper.lastIndex, 199);
    expect(mapper.latestPrice, state.candles.last.close);
    expect(mapper.yToPrice(mapper.priceToY(101.5)), closeTo(101.5, 1e-9));
    expect(mapper.xToIndex(mapper.indexToX(180)), 180);
    expect(mapper.mainRect.bottom, lessThan(400));
  });

  testWidgets('horizontal drag scrolls back in history and flings', (tester) async {
    state.setData(_data(500));
    await _pump(tester, KLineChart(state: state, entranceAnimation: false));
    await tester.pump();
    await tester.drag(find.byType(KLineChart), const Offset(150, 0));
    await tester.pump();
    final afterDrag = state.scrollOffset;
    expect(afterDrag, greaterThan(100));

    await tester.fling(find.byType(KLineChart), const Offset(150, 0), 2000);
    await tester.pump();
    final afterRelease = state.scrollOffset;
    await tester.pump(const Duration(milliseconds: 300));
    expect(state.scrollOffset, greaterThan(afterRelease), reason: 'fling keeps scrolling');
    await _settle(tester);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('drag never scrolls past the newest candle when blank scroll is off', (tester) async {
    state.setData(_data(500));
    await _pump(tester, KLineChart(state: state, entranceAnimation: false, enableFling: false));
    await tester.pump();
    await tester.drag(find.byType(KLineChart), const Offset(-200, 0));
    await tester.pump();
    expect(state.scrollOffset, 0);
  });

  testWidgets('vertical drags are left to the parent scrollable', (tester) async {
    state.setData(_data(200));
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: ListView(
        controller: controller,
        children: [
          SizedBox(height: 400, child: KLineChart(state: state, entranceAnimation: false)),
          const SizedBox(height: 2000),
        ],
      ),
    ));
    await tester.pump();
    await tester.drag(find.byType(KLineChart), const Offset(0, -200));
    await tester.pump();
    expect(controller.offset, greaterThan(100));
    expect(state.scrollOffset, 0);
  });

  testWidgets('pinch zoom changes the candle width within bounds', (tester) async {
    state.setData(_data(500));
    await _pump(tester, KLineChart(state: state, entranceAnimation: false));
    await tester.pump();
    final center = tester.getCenter(find.byType(KLineChart));
    final a = await tester.startGesture(center - const Offset(20, 0), pointer: 1);
    final b = await tester.startGesture(center + const Offset(20, 0), pointer: 2);
    await tester.pump();
    for (var i = 0; i < 8; i++) {
      await a.moveBy(const Offset(-10, 0));
      await b.moveBy(const Offset(10, 0));
      await tester.pump();
    }
    await a.up();
    await b.up();
    await tester.pump();
    expect(state.candleWidth, greaterThan(8));
    expect(state.candleWidth, lessThanOrEqualTo(30));
    expect(tester.takeException(), isNull);
  });

  testWidgets('long press shows a persistent crosshair that a tap dismisses', (tester) async {
    final reported = <Candle?>[];
    state.setData(_data(200));
    await _pump(
      tester,
      KLineChart(state: state, entranceAnimation: false, onCrosshairChange: reported.add),
    );
    await tester.pump();
    final center = tester.getCenter(find.byType(KLineChart));
    await tester.longPressAt(center);
    await tester.pump();
    expect(state.crosshairIndex, greaterThanOrEqualTo(0));
    expect(reported.single, state.candles[state.crosshairIndex]);
    expect(find.text('Chg%'), findsOneWidget, reason: 'detail panel is visible');

    await tester.tapAt(center + const Offset(0, 100));
    await tester.pump();
    expect(state.crosshairIndex, -1);
    expect(reported.last, isNull);
    expect(find.text('Chg%'), findsNothing);
  });

  testWidgets('onRelease crosshair disappears when the finger lifts', (tester) async {
    state.setData(_data(200));
    await _pump(
      tester,
      KLineChart(
        state: state,
        entranceAnimation: false,
        crosshairDismiss: CrosshairDismiss.onRelease,
      ),
    );
    await tester.pump();
    final gesture = await tester.startGesture(tester.getCenter(find.byType(KLineChart)));
    await tester.pump(const Duration(milliseconds: 600));
    expect(state.crosshairIndex, greaterThanOrEqualTo(0));
    await gesture.up();
    await tester.pump();
    expect(state.crosshairIndex, -1);
  });

  testWidgets('tapping a trade mark reports it in onRelease mode', (tester) async {
    state.setData(_data(40));
    final mark = TradeMark(time: state.candles[30].time, isBuy: true, price: 100);
    TradeMark? tapped;
    await _pump(
      tester,
      KLineChart(
        state: state,
        entranceAnimation: false,
        crosshairDismiss: CrosshairDismiss.onRelease,
        tradeMarks: [mark],
        onTradeMarkTap: (m) => tapped = m,
      ),
    );
    await tester.pump();
    final mapper = state.mapper.value!;
    final origin = tester.getTopLeft(find.byType(KLineChart));
    await tester.tapAt(origin + Offset(mapper.indexToX(30), 100));
    await tester.pump();
    expect(tapped, same(mark));
  });

  testWidgets('onLoadMore fires once per data version near the oldest candle', (tester) async {
    var calls = 0;
    state.setData(_data(100));
    await _pump(
      tester,
      KLineChart(
          state: state, entranceAnimation: false, enableFling: false, onLoadMore: () => calls++),
    );
    await tester.pump();
    expect(calls, 0);
    await tester.drag(find.byType(KLineChart), const Offset(380, 0));
    await tester.pump();
    await tester.drag(find.byType(KLineChart), const Offset(380, 0));
    await tester.pump();
    await tester.pump();
    expect(calls, 1);

    final before = state.scrollOffset;
    state.prepend(_data(50, startTime: -50 * 60000));
    await tester.pump();
    expect(state.scrollOffset, before, reason: 'prepend keeps the visible position');
    expect(state.candles.length, 150);
  });

  testWidgets('sub panes animate in and out, moving the main pane', (tester) async {
    state.setData(_data(200));
    Widget chart(List<Indicator> subs) =>
        KLineChart(state: state, entranceAnimation: false, subIndicators: subs);

    await _pump(tester, chart(const []));
    await tester.pump();
    final plain = state.mapper.value!.mainRect.bottom;

    await _pump(tester, chart(const [Macd()]));
    await tester.pump(const Duration(milliseconds: 150));
    final growing = state.mapper.value!.mainRect.bottom;
    await _settle(tester);
    final withSub = state.mapper.value!.mainRect.bottom;
    expect(growing, lessThan(plain));
    expect(withSub, lessThan(growing));

    await _pump(tester, chart(const []));
    await _settle(tester);
    await tester.pump();
    expect(state.mapper.value!.mainRect.bottom, closeTo(plain, 1e-6));
  });

  testWidgets('legend shows main indicator values and updates on ticks', (tester) async {
    state.setData(_data(200));
    await _pump(
      tester,
      KLineChart(state: state, entranceAnimation: false, mainIndicators: [
        Ma(periods: const [5])
      ]),
    );
    await tester.pump();
    expect(find.textContaining('MA5 '), findsOneWidget);

    state.appendOrUpdate(state.candles.last.copyWith(close: 500, high: 500));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final legend = tester.widget<Text>(find.textContaining('MA5 ')).data!;
    expect(double.parse(legend.split(' ').last), greaterThan(150));
  });

  testWidgets('a throwing custom indicator is reported, not fatal', (tester) async {
    state.setData(_data(50));
    final broken = indicator('BROKEN', compute: (_) => throw StateError('boom'));
    await _pump(
        tester, KLineChart(state: state, entranceAnimation: false, subIndicators: [broken]));
    await _settle(tester);
    expect(tester.takeException(), isStateError);
    expect(find.byType(KLineChart), findsOneWidget);
  });

  testWidgets('reset replays the exit and entrance animation', (tester) async {
    state.setData(_data(200));
    await _pump(tester, KLineChart(state: state));
    await _settle(tester);
    double opacity() => tester
        .widget<Opacity>(
            find.descendant(of: find.byType(KLineChart), matching: find.byType(Opacity)))
        .opacity;
    expect(opacity(), 1);
    state.setData(_data(120));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 170));
    expect(opacity(), lessThan(1));
    await _settle(tester);
    expect(opacity(), 1);
  });
}
