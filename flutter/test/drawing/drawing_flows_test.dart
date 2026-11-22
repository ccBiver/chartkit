// F1-02 画线手势：每个工具走一遍新建（含吸附）、取消选中、选中、整体移动、拖端点、锁定、删除，
// 并确认图表原有的拖动、缩放、十字光标不受影响。
// F1-03 画线保存：画 10 条后序列化再读回，数据和画面完全一样；切周期后仍在原处。
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:chartkit_flutter/chartkit_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _minute = 60000;

List<Candle> _data(int n, {int interval = _minute}) => [
      for (var i = 0; i < n; i++)
        () {
          final base = 100 + 10 * math.sin(i * interval / _minute * 0.2);
          return Candle(
            time: i * interval,
            open: base,
            high: base + 2,
            low: base - 2,
            close: base + (i.isEven ? 1 : -1),
          );
        }(),
    ];

/// 各工具新建时点的位置：(K 线索引, 价格)。
const Map<DrawingTool, List<(int, double)>> _taps = {
  DrawingTool.horizontalLine: [(175, 104)],
  DrawingTool.verticalLine: [(175, 104)],
  DrawingTool.trendLine: [(166, 104), (190, 96)],
  DrawingTool.ray: [(166, 104), (190, 96)],
  DrawingTool.rectangle: [(166, 106), (190, 94)],
  DrawingTool.fibRetracement: [(166, 94), (190, 106)],
  DrawingTool.priceRange: [(166, 96), (190, 106)],
  // 头寸的入场会吸到第 173 根的最高价（价格区间中部），目标、止损才都留在主图内
  DrawingTool.longPosition: [(173, 100), (190, 108)],
  DrawingTool.shortPosition: [(173, 100), (190, 96)],
  DrawingTool.gannFan: [(166, 94), (178, 104)],
  DrawingTool.pitchfork: [(166, 100), (182, 106), (186, 94)],
  DrawingTool.elliottWave: [(162, 96), (167, 104), (172, 99), (178, 107), (183, 101), (189, 109)],
};

final _key = GlobalKey();

void main() {
  late KLineChartState state;
  late DrawingController drawings;
  late int saves;

  setUp(() {
    saves = 0;
    state = KLineChartState(timeFrame: TimeFrame.m1)..setData(_data(200));
    drawings = DrawingController(
      style: const DrawingStyle(color: Color(0xFF3B82F6)),
      onChanged: () => saves++,
    );
  });
  tearDown(() {
    drawings.dispose();
    state.dispose();
  });

  Future<void> pump(WidgetTester tester, DrawingController controller) async {
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: RepaintBoundary(
          key: _key,
          child: SizedBox(
            width: 400,
            height: 400,
            child:
                KLineChart(state: state, entranceAnimation: false, drawingController: controller),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  KLineChartMapper mapper() => state.mapper.value!;
  Offset origin(WidgetTester tester) => tester.getTopLeft(find.byKey(_key));

  /// 锚点的屏幕位置（数据从 0 开始、1 分钟一根，时间 / 60000 就是索引）。
  Offset screenOf(WidgetTester tester, DrawingAnchor a) {
    final index = a.time ~/ state.timeFrame.millis;
    return origin(tester) + Offset(mapper().indexToX(index), mapper().priceToY(a.price));
  }

  /// 线身上一个离端点足够远的点。
  Offset bodyPoint(WidgetTester tester, Drawing d) {
    final rect = mapper().mainRect;
    final p = [for (final a in d.anchors) screenOf(tester, a)];
    final o = origin(tester);
    return switch (d.tool) {
      DrawingTool.horizontalLine => Offset(o.dx + rect.left + rect.width * 0.2, p[0].dy),
      DrawingTool.verticalLine => Offset(p[0].dx, o.dy + rect.top + rect.height * 0.2),
      DrawingTool.pitchfork => (p[0] + (p[1] + p[2]) / 2) / 2,
      _ => (p[0] + p[1]) / 2,
    };
  }

  /// 端点 0 的屏幕位置。
  Offset handle0(WidgetTester tester, Drawing d) {
    final rect = mapper().mainRect;
    final p = screenOf(tester, d.anchors[0]);
    final o = origin(tester);
    return switch (d.tool) {
      DrawingTool.horizontalLine => Offset(o.dx + rect.center.dx, p.dy),
      DrawingTool.verticalLine => Offset(p.dx, o.dy + rect.center.dy),
      _ => p,
    };
  }

  Future<void> tap(WidgetTester tester, Offset at) async {
    await tester.tapAt(at);
    await tester.pump();
  }

  Future<Drawing> create(WidgetTester tester, DrawingTool tool, {bool snapFirst = false}) async {
    drawings.tool = tool;
    final points = _taps[tool]!;
    for (var k = 0; k < points.length; k++) {
      final (index, price) = points[k];
      final at = snapFirst && k == 0
          ? origin(tester) +
              Offset(mapper().indexToX(index), mapper().priceToY(state.candles[index].high) - 5)
          : origin(tester) + Offset(mapper().indexToX(index), mapper().priceToY(price));
      await tap(tester, at);
    }
    return drawings.drawings.last;
  }

  group('F1-02 gestures for every tool', () {
    for (final tool in DrawingTool.values) {
      testWidgets(tool.name, (tester) async {
        await pump(tester, drawings);
        final blank = origin(tester) + Offset(12, mapper().mainRect.bottom - 8);

        // 新建：点数对、第一个点吸到最高价、建完选中并退出工具
        final created = await create(tester, tool, snapFirst: true);
        expect(drawings.drawings.length, 1);
        expect(created.tool, tool);
        expect(created.anchors[0].price, state.candles[_taps[tool]![0].$1].high, reason: 'magnet');
        expect(drawings.selectedId, created.id);
        expect(drawings.tool, isNull);
        expect(saves, 1);
        expect(state.crosshairIndex, -1);

        // 点空白取消选中，点线身选中
        await tap(tester, blank);
        expect(drawings.selectedId, isNull);
        await tap(tester, bodyPoint(tester, created));
        expect(drawings.selectedId, created.id);

        // 整体移动：横向 16 像素 = 2 根，纵向跟手（往下拖，第一个点吸在最高价，离主图上沿近）；图表不滚动
        final priceDelta = mapper().yToPrice(mapper().priceToY(100) + 24) -
            mapper().yToPrice(mapper().priceToY(100));
        await tester.dragFrom(bodyPoint(tester, created), const Offset(16, 24));
        await tester.pump();
        final moved = drawings.drawings.single;
        for (var i = 0; i < moved.anchors.length; i++) {
          expect(moved.anchors[i].time, created.anchors[i].time + 2 * _minute, reason: 'time $i');
          expect(moved.anchors[i].price, closeTo(created.anchors[i].price + priceDelta, 1e-6),
              reason: 'price $i');
        }
        expect(state.scrollOffset, 0);
        expect(saves, 2);

        // 拖端点 0：只改它（头寸的止损时间跟着入场走），图表不滚动
        await tester.dragFrom(handle0(tester, moved), const Offset(-16, 20));
        await tester.pump();
        final reshaped = drawings.drawings.single;
        expect(reshaped.anchors[0], isNot(moved.anchors[0]));
        for (var i = 1; i < moved.anchors.length; i++) {
          if (tool.isPosition && i == 2) {
            expect(reshaped.anchors[2].time, reshaped.anchors[0].time);
            expect(reshaped.anchors[2].price, moved.anchors[2].price);
          } else {
            expect(reshaped.anchors[i], moved.anchors[i], reason: 'anchor $i');
          }
        }
        expect(state.scrollOffset, 0);
        expect(saves, 3);

        // 锁定后拖不动
        drawings.setLocked(reshaped.id, true);
        final locked = drawings.drawings.single;
        await tester.dragFrom(bodyPoint(tester, locked), const Offset(16, -24));
        await tester.pump(const Duration(seconds: 2));
        expect(drawings.drawings.single.anchors, locked.anchors);
        drawings.setLocked(reshaped.id, false);
        state.setViewport(scrollOffset: 0);
        await tester.pump();

        // 删除
        expect(drawings.removeSelected(), isTrue);
        await tester.pump();
        expect(drawings.drawings, isEmpty);

        // 十字光标照常：长按出现，点击消失
        await tester.longPressAt(origin(tester) + const Offset(200, 120));
        await tester.pump();
        expect(state.crosshairIndex, greaterThanOrEqualTo(0));
        await tap(tester, blank);
        expect(state.crosshairIndex, -1);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('pinch and pan elsewhere still move the chart while a drawing is selected',
        (tester) async {
      await pump(tester, drawings);
      final d = await create(tester, DrawingTool.trendLine);
      expect(drawings.selectedId, d.id);
      final width = state.candleWidth;
      final center = origin(tester) + Offset(60, mapper().mainRect.bottom - 30);
      final a = await tester.startGesture(center - const Offset(20, 0), pointer: 1);
      final b = await tester.startGesture(center + const Offset(20, 0), pointer: 2);
      await tester.pump();
      for (var i = 0; i < 5; i++) {
        await a.moveBy(const Offset(-8, 0));
        await b.moveBy(const Offset(8, 0));
        await tester.pump();
      }
      await a.up();
      await b.up();
      await tester.pump();
      expect(state.candleWidth, isNot(width));
      expect(drawings.drawings.single, d);
      expect(drawings.selectedId, d.id);
    });
  });

  group('F1-03 save and restore', () {
    Future<Uint8List> capture(WidgetTester tester) async {
      final boundary = _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final bytes = await tester.runAsync(() async {
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        image.dispose();
        return data!.buffer.asUint8List();
      });
      return bytes!;
    }

    testWidgets('ten drawings survive JSON and a timeframe round trip', (tester) async {
      await pump(tester, drawings);
      // 10 条：多种工具，改样式、锁定、改斐波那契档位；锚点都落在 5 的倍数分钟上，方便切到 5 分钟图后核对
      const tools = [
        DrawingTool.horizontalLine,
        DrawingTool.verticalLine,
        DrawingTool.trendLine,
        DrawingTool.ray,
        DrawingTool.rectangle,
        DrawingTool.fibRetracement,
        DrawingTool.longPosition,
        DrawingTool.shortPosition,
        DrawingTool.gannFan,
        DrawingTool.pitchfork,
      ];
      for (var k = 0; k < tools.length; k++) {
        drawings.tool = tools[k];
        for (var j = 0; j < tools[k].pointCount; j++) {
          final index = 165 + ((k + j * 3) % 6) * 5;
          final price = 92.0 + ((k * 7 + j * 5) % 16);
          await tap(
              tester, origin(tester) + Offset(mapper().indexToX(index), mapper().priceToY(price)));
        }
      }
      expect(drawings.drawings.length, 10);
      final ids = [for (final d in drawings.drawings) d.id];
      drawings.setStyle(ids[2], const DrawingStyle(color: Color(0xFFEA3943), width: 3));
      drawings.setStyle(ids[4], const DrawingStyle(color: Color(0x8016C784), width: 2));
      drawings.setLocked(ids[3], true);
      drawings.setFibLevels(ids[5], const [0.382, 0.5, 0.618, 1.618]);
      drawings.select(null);
      await tester.pump();
      final before = await capture(tester);
      final original = drawings.drawings;

      // 序列化再读回：数据完全一样，画面逐像素一样
      final saved = jsonEncode(drawings.toJson());
      final restored = DrawingController(style: const DrawingStyle(color: Color(0xFF000000)));
      addTearDown(restored.dispose);
      restored.loadJson(jsonDecode(saved));
      expect(restored.drawings, original);
      await pump(tester, restored);
      await tester.pump();
      expect(await capture(tester), before);

      // 切到 5 分钟图：锚点不变，选中项的范围按时间落在对应的 5 分钟 K 线上
      state.changeTimeFrame(TimeFrame.m5);
      state.setData(_data(40, interval: 5 * _minute));
      await tester.pump();
      await tester.pump();
      expect(restored.drawings, original);
      final trend = original[2];
      restored.select(trend.id);
      await tester.pump();
      await tester.pump();
      final xs = [for (final a in trend.anchors) mapper().indexToX(a.time ~/ (5 * _minute))];
      final bounds = restored.selectionBounds.value!;
      expect(bounds.left, closeTo(xs.reduce(math.min) - 4, 0.5));
      expect(bounds.right, closeTo(xs.reduce(math.max) + 4, 0.5));

      // 切回 1 分钟图：画面和保存前逐像素一样
      restored.select(null);
      state.changeTimeFrame(TimeFrame.m1);
      state.setData(_data(200));
      await tester.pump();
      await tester.pump();
      expect(await capture(tester), before);
    });
  });
}
