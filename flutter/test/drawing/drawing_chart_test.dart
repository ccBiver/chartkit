import 'dart:math' as math;

import 'package:chartkit_flutter/chartkit_flutter.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _minute = 60000;

List<Candle> _data(int n, {int interval = _minute}) => [
      for (var i = 0; i < n; i++)
        () {
          final base = 100 + 10 * math.sin(i * 0.2);
          return Candle(
            time: i * interval,
            open: base,
            high: base + 2,
            low: base - 2,
            close: base + (i.isEven ? 1 : -1),
          );
        }(),
    ];

void main() {
  late KLineChartState state;
  late DrawingController drawings;
  late int saves;

  setUp(() {
    saves = 0;
    state = KLineChartState(timeFrame: TimeFrame.m1)..setData(_data(200));
    drawings = DrawingController(
      style: const DrawingStyle(color: Color(0xFF3B82F6)),
      magnet: false,
      onChanged: () => saves++,
    );
  });
  tearDown(() {
    drawings.dispose();
    state.dispose();
  });

  Future<void> pump(WidgetTester tester, {Size size = const Size(400, 400), Widget? wrap}) async {
    final chart = KLineChart(state: state, entranceAnimation: false, drawingController: drawings);
    await tester.pumpWidget(MaterialApp(
      home: Center(child: SizedBox.fromSize(size: size, child: wrap ?? chart)),
    ));
    await tester.pump();
  }

  KLineChartMapper mapper() => state.mapper.value!;
  Offset origin(WidgetTester tester) => tester.getTopLeft(find.byType(KLineChart));

  /// 第 [index] 根、价格 [price] 处的全局坐标。
  Offset at(WidgetTester tester, int index, double price) =>
      origin(tester) + Offset(mapper().indexToX(index), mapper().priceToY(price));

  Future<void> tapAt(WidgetTester tester, int index, double price) async {
    await tester.tapAt(at(tester, index, price));
    await tester.pump();
  }

  /// 画一条从 (165, 104) 到 (190, 96) 的趋势线。
  Future<Drawing> trendLine(WidgetTester tester) async {
    drawings.tool = DrawingTool.trendLine;
    await tapAt(tester, 165, 104);
    await tapAt(tester, 190, 96);
    return drawings.drawings.single;
  }

  testWidgets('a two-point tool is created by two taps', (tester) async {
    await pump(tester);
    drawings.tool = DrawingTool.trendLine;
    await tapAt(tester, 165, 104);
    expect(drawings.draft.length, 1);
    expect(drawings.drawings, isEmpty);
    await tapAt(tester, 190, 96);
    final d = drawings.drawings.single;
    expect(d.anchors[0].time, state.candles[165].time);
    expect(d.anchors[0].price, closeTo(104, 0.01));
    expect(d.anchors[1].time, state.candles[190].time);
    expect(d.anchors[1].price, closeTo(96, 0.01));
    expect(drawings.selectedId, d.id, reason: 'the new drawing is selected');
    expect(drawings.tool, isNull);
    expect(saves, 1);
    expect(state.crosshairIndex, -1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('every tool is created with its own number of taps', (tester) async {
    await pump(tester);
    for (final tool in DrawingTool.values) {
      drawings.tool = tool;
      for (var k = 0; k < tool.pointCount; k++) {
        expect(drawings.drawings.where((d) => d.tool == tool), isEmpty, reason: tool.name);
        await tapAt(tester, 160 + k * 6, k.isEven ? 105 : 95);
      }
      expect(drawings.drawings.where((d) => d.tool == tool).length, 1, reason: tool.name);
    }
    expect(drawings.drawings.length, 12);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the magnet snaps a new point onto a nearby high', (tester) async {
    drawings.magnet = true;
    await pump(tester);
    final c = state.candles[180];
    drawings.tool = DrawingTool.horizontalLine;
    await tester.tapAt(at(tester, 180, c.high) - const Offset(0, 6));
    await tester.pump();
    expect(drawings.drawings.single.anchors.single, DrawingAnchor(c.time, c.high));
  });

  testWidgets('long press in creation mode previews the point instead of the crosshair',
      (tester) async {
    await pump(tester);
    drawings.tool = DrawingTool.horizontalLine;
    final gesture = await tester.startGesture(at(tester, 170, 104));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    expect(drawings.preview, isNotNull);
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(state.crosshairIndex, -1);
    expect(drawings.drawings.single.anchors.single.price,
        closeTo(mapper().yToPrice(mapper().priceToY(104) + 20), 0.01));
    expect(drawings.preview, isNull);
  });

  testWidgets('tap selects a drawing, tap on blank deselects', (tester) async {
    await pump(tester);
    final d = await trendLine(tester);
    await tester.tapAt(origin(tester) + const Offset(40, 30));
    await tester.pump();
    expect(drawings.selectedId, isNull);
    // 线身中点
    await tester.tapAt((at(tester, 165, 104) + at(tester, 190, 96)) / 2);
    await tester.pump();
    expect(drawings.selectedId, d.id);
    expect(drawings.selectionBounds.value, isNotNull);
    await tester.tapAt(origin(tester) + const Offset(40, 30));
    await tester.pump();
    expect(drawings.selectedId, isNull);
    expect(drawings.selectionBounds.value, isNull);
  });

  testWidgets('dragging an end point reshapes without scrolling the chart', (tester) async {
    await pump(tester);
    final d = await trendLine(tester);
    final saved = saves;
    final y = mapper().priceToY(96);
    await tester.dragFrom(at(tester, 190, 96), const Offset(-40, 30));
    await tester.pump();
    final moved = drawings.drawings.single;
    expect(moved.anchors[0], d.anchors[0]);
    expect(moved.anchors[1].time, state.candles[185].time);
    expect(moved.anchors[1].price, closeTo(mapper().yToPrice(y + 30), 0.01));
    expect(state.scrollOffset, 0);
    expect(saves, saved + 1);
  });

  testWidgets('dragging the body moves the whole drawing', (tester) async {
    await pump(tester);
    final d = await trendLine(tester);
    final mid = (at(tester, 165, 104) + at(tester, 190, 96)) / 2;
    final priceDelta = mapper().yToPrice(mapper().priceToY(100) - 24) - 100;
    await tester.dragFrom(mid, const Offset(16, -24));
    await tester.pump();
    final moved = drawings.drawings.single;
    expect(moved.anchors[0].time, state.candles[167].time);
    expect(moved.anchors[1].time, state.candles[192].time);
    expect(moved.anchors[0].price, closeTo(d.anchors[0].price + priceDelta, 0.01));
    expect(moved.anchors[1].price, closeTo(d.anchors[1].price + priceDelta, 0.01));
    expect(state.scrollOffset, 0);
  });

  testWidgets('dragging elsewhere still scrolls; a locked drawing does not move', (tester) async {
    await pump(tester);
    final d = await trendLine(tester);
    await tester.dragFrom(origin(tester) + const Offset(40, 290), const Offset(120, 0));
    await tester.pump(const Duration(seconds: 2));
    expect(state.scrollOffset, greaterThan(0));
    expect(drawings.drawings.single, d);

    state.setViewport(scrollOffset: 0);
    await tester.pump();
    drawings.setLocked(d.id, true);
    await tester.dragFrom(at(tester, 190, 96), const Offset(-40, 30));
    await tester.pump(const Duration(seconds: 2));
    expect(drawings.drawings.single.anchors, d.anchors);
    expect(drawings.selectedId, d.id);
  });

  testWidgets('delete and clear remove drawings from the chart', (tester) async {
    await pump(tester);
    await trendLine(tester);
    drawings.tool = DrawingTool.rectangle;
    await tapAt(tester, 170, 108);
    await tapAt(tester, 180, 100);
    expect(drawings.drawings.length, 2);
    expect(drawings.removeSelected(), isTrue);
    await tester.pump();
    expect(drawings.drawings.single.tool, DrawingTool.trendLine);
    drawings.clear();
    await tester.pump();
    expect(drawings.drawings, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hidden drawings cannot be hit and taps fall through to the chart', (tester) async {
    await pump(tester);
    await trendLine(tester);
    drawings.select(null);
    drawings.visible = false;
    await tester.pump();
    await tester.tapAt((at(tester, 165, 104) + at(tester, 190, 96)) / 2);
    await tester.pump();
    expect(drawings.selectedId, isNull);
    expect(drawings.drawings.length, 1);
  });

  testWidgets('a long press without a tool still shows the crosshair', (tester) async {
    await pump(tester);
    await trendLine(tester);
    drawings.select(null);
    await tester.longPressAt(origin(tester) + const Offset(60, 60));
    await tester.pump();
    expect(state.crosshairIndex, greaterThanOrEqualTo(0));
  });

  testWidgets('anchors stay on their time after switching the timeframe', (tester) async {
    await pump(tester);
    final d = await trendLine(tester);
    // 换成 5 分钟图：同一段时间，数据密度变成 1/5
    state.changeTimeFrame(TimeFrame.m5);
    state.setData(_data(200, interval: 5 * _minute).sublist(0, 60));
    await tester.pump();
    await tester.pump();
    expect(drawings.drawings.single, d);
    final bounds = drawings.selectionBounds.value!;
    // 第 165 分钟 = 5 分钟图的第 33 根，第 190 分钟 = 第 38 根
    expect(bounds.left, closeTo(mapper().indexToX(33) - 4, 0.01));
    expect(bounds.right, closeTo(mapper().indexToX(38) + 4, 0.01));
  });

  testWidgets('works in a wide landscape chart', (tester) async {
    await pump(tester, size: const Size(800, 360));
    drawings.tool = DrawingTool.longPosition;
    await tapAt(tester, 150, 100);
    await tapAt(tester, 190, 108);
    final d = drawings.drawings.single;
    expect(d.anchors.length, 3);
    expect(d.anchors[1].price, greaterThan(d.anchors[0].price));
    expect(d.anchors[2].price, lessThan(d.anchors[0].price));
    expect(tester.takeException(), isNull);
  });

  testWidgets('dragging a drawing inside a list does not scroll the page', (tester) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await pump(
      tester,
      size: const Size(400, 600),
      wrap: ListView(controller: scroll, children: [
        SizedBox(
          height: 400,
          child: KLineChart(state: state, entranceAnimation: false, drawingController: drawings),
        ),
        const SizedBox(height: 800),
      ]),
    );
    final d = await trendLine(tester);
    await tester.dragFrom((at(tester, 165, 104) + at(tester, 190, 96)) / 2, const Offset(0, -60));
    await tester.pump();
    expect(scroll.offset, 0);
    expect(drawings.drawings.single.anchors[0].price, greaterThan(d.anchors[0].price));
  });

  testWidgets('swapping or removing the controller is safe', (tester) async {
    await pump(tester);
    await trendLine(tester);
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: SizedBox(
          width: 400,
          height: 400,
          child: KLineChart(state: state, entranceAnimation: false),
        ),
      ),
    ));
    await tester.pump();
    drawings.clear(); // 已不再监听：不应触发重绘异常
    await tester.tapAt(origin(tester) + const Offset(100, 100));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
