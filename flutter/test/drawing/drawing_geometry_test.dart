import 'dart:ui';

import 'package:chartkit_flutter/chartkit_flutter.dart';
import 'package:chartkit_flutter/src/drawing/drawing_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

const _minute = 60000;

/// 10 根 1 分钟 K 线，第 5 根之后休市 1 小时（模拟跳空）。
List<Candle> _candles() => [
      for (var i = 0; i < 10; i++)
        Candle(
          time: i * _minute + (i >= 5 ? 3600000 : 0),
          open: 100.0 + i,
          high: 102.0 + i,
          low: 98.0 + i,
          close: 101.0 + i,
        ),
    ];

/// 主图 0..400 × 0..200，最新一根贴右边（rightFloat=9），每根 20 像素，价格 90..130。
DrawingProjection _projection([List<Candle>? candles, int interval = _minute]) => DrawingProjection(
      rect: const Rect.fromLTRB(0, 0, 400, 200),
      timeline: DrawingTimeline(candles ?? _candles(), interval),
      rightFloat: 9,
      candleWidth: 20,
      priceMin: 90,
      priceMax: 130,
    );

Drawing _drawing(DrawingTool tool, List<DrawingAnchor> anchors) => Drawing(
      id: 'd',
      tool: tool,
      anchors: anchors,
      style: const DrawingStyle(color: Color(0xFF3B82F6)),
    );

void main() {
  group('DrawingTimeline', () {
    final tl = DrawingTimeline(_candles(), _minute);

    test('open times map to whole indices', () {
      for (var i = 0; i < 10; i++) {
        expect(tl.indexOf(tl.candles[i].time), i);
        expect(tl.timeAt(i.toDouble()), tl.candles[i].time);
      }
    });

    test('interpolates inside gaps and extrapolates outside the data', () {
      // 第 4 根（4 分）到第 5 根（65 分）之间隔了 61 分钟
      expect(tl.indexOf(4 * _minute + 30 * _minute), closeTo(4 + 30 / 61, 1e-9));
      expect(tl.indexOf(-3 * _minute), -3);
      expect(tl.indexOf(tl.candles.last.time + 5 * _minute), 14);
      expect(tl.timeAt(14), tl.candles.last.time + 5 * _minute);
      expect(tl.timeAt(-2), -2 * _minute);
    });

    test('round-trips arbitrary times', () {
      for (final t in [-500000, 0, 123456, 4 * _minute + 777, 3600000 + 6 * _minute, 99999999]) {
        expect(tl.timeAt(tl.indexOf(t)), t);
      }
    });

    test('an anchor keeps its time across timeframes', () {
      // 1 分钟图上 10:37 的锚点，换成 1 小时图后落在 10:00 与 11:00 两根之间的 37/60
      const hour = 3600000;
      final hourly = DrawingTimeline([
        for (var h = 0; h < 24; h++) Candle(time: h * hour, open: 1, high: 1, low: 1, close: 1),
      ], hour);
      const t = 10 * hour + 37 * _minute;
      expect(hourly.indexOf(t), closeTo(10 + 37 / 60, 1e-9));
      expect(hourly.timeAt(hourly.indexOf(t)), t);
    });
  });

  group('DrawingProjection', () {
    test('maps anchors to candle centres and prices to y', () {
      final p = _projection();
      expect(p.indexToX(9), 390);
      expect(p.indexToX(0), 210);
      expect(p.xToIndex(250), 2);
      expect(p.priceToY(130), 0);
      expect(p.priceToY(90), 200);
      expect(p.yToPrice(100), 110);
      final a = DrawingAnchor(p.timeline.candles[3].time, 110);
      expect(p.toScreen(a), const Offset(270, 100));
      expect(p.fromScreen(const Offset(275, 100)), a);
    });

    test('snap pulls the price onto a nearby OHLC value only within the radius', () {
      final p = _projection();
      final c = p.timeline.candles[3]; // 高 105 → y=125
      final near = p.snap(Offset(p.indexToX(3) + 4, p.priceToY(c.high) - 6), radius: 20);
      expect(near, DrawingAnchor(c.time, c.high));
      final far = p.snap(Offset(p.indexToX(3), p.priceToY(c.high) - 40), radius: 20);
      expect(far.price, closeTo(c.high + 8, 1e-9));
      final off = p.snap(Offset(p.indexToX(3), p.priceToY(c.high) - 6), radius: 0);
      expect(off.price, closeTo(c.high + 1.2, 1e-9));
    });

    test('snap in the blank area to the right extrapolates the time', () {
      final p = _projection(_candles(), _minute);
      final candles = p.timeline.candles;
      // rightFloat=9 贴右，往右没有留白；把视口挪出 3 根留白
      final blank = DrawingProjection(
        rect: p.rect,
        timeline: p.timeline,
        rightFloat: 12,
        candleWidth: 20,
        priceMin: 90,
        priceMax: 130,
      );
      final a = blank.snap(const Offset(390, 50));
      expect(a.time, candles.last.time + 3 * _minute);
    });
  });

  group('shapes', () {
    final p = _projection();
    final t = p.timeline.candles;

    test('ray extends to the pane edge', () {
      final end = rayEnd(const Offset(100, 100), const Offset(10, -5), p.rect);
      expect(end, const Offset(300, 0));
      expect(rayEnd(const Offset(100, 100), Offset.zero, p.rect), const Offset(100, 100));
      final d =
          _drawing(DrawingTool.ray, [DrawingAnchor(t[0].time, 110), DrawingAnchor(t[2].time, 115)]);
      final (a, b) = shapeOf(d, p).segments.single;
      expect(a, const Offset(210, 100));
      expect(b, const Offset(370, 0));
    });

    test('fibonacci levels run from 1 at the first point to 0 at the second', () {
      final prices = fibLevelPrices(100, 200, const [0, 0.5, 0.618, 1]);
      expect(prices[0], (0.0, 200.0));
      expect(prices[1], (0.5, 150.0));
      expect(prices[2].$2, closeTo(138.2, 1e-9));
      expect(prices[3], (1.0, 100.0));
      final d = _drawing(DrawingTool.fibRetracement, [
        DrawingAnchor(t[1].time, 100),
        DrawingAnchor(t[6].time, 120)
      ]).copyWith(fibLevels: const [0, 0.5, 1]);
      final shape = shapeOf(d, p);
      // 一条对角虚线 + 三档横线，横线在两点之间
      expect(shape.segments.length, 4);
      expect(shape.segments[2].$1, Offset(p.indexToX(1), p.priceToY(110)));
      expect(shape.segments[2].$2, Offset(p.indexToX(6), p.priceToY(110)));
    });

    test('gann fan has nine rays, the 1x1 passing through the second point', () {
      final rays = gannFanRays(const Offset(0, 200), const Offset(100, 100), p.rect);
      expect(rays.length, 9);
      final oneByOne = rays.firstWhere((r) => r.$1 == 1);
      expect(oneByOne.$3, const Offset(200, 0));
      final twoByOne = rays.firstWhere((r) => r.$1 == 2);
      expect(twoByOne.$3, const Offset(100, 0));
      expect(gannFanRays(const Offset(5, 5), const Offset(5, 5), p.rect), isEmpty);
    });

    test('pitchfork tines are parallel to the median', () {
      final ends = pitchforkEnds(
          const Offset(0, 100), const Offset(100, 50), const Offset(100, 150), p.rect);
      expect(ends.median, const Offset(400, 100));
      expect(ends.upper, const Offset(400, 50));
      expect(ends.lower, const Offset(400, 150));
    });

    test('position stats are measured in the trade direction', () {
      final long = positionStats(long: true, entry: 100, target: 110, stop: 95);
      expect(long.reward, 10);
      expect(long.risk, 5);
      expect(long.ratio, 2);
      expect(long.rewardPercent, 10);
      expect(long.riskPercent, 5);
      final short = positionStats(long: false, entry: 100, target: 85, stop: 105);
      expect(short.reward, 15);
      expect(short.risk, 5);
      expect(short.ratio, 3);
      expect(positionStats(long: true, entry: 100, target: 110, stop: 100).ratio, 0);
    });

    test('a new position gets a 1:1 stop on the far side of the entry', () {
      final entry = DrawingAnchor(t[2].time, 100);
      final long = completeAnchors(DrawingTool.longPosition, [entry, DrawingAnchor(t[6].time, 90)]);
      expect(long, [entry, DrawingAnchor(t[6].time, 110), DrawingAnchor(t[2].time, 90)]);
      final short =
          completeAnchors(DrawingTool.shortPosition, [entry, DrawingAnchor(t[6].time, 104)]);
      expect(short, [entry, DrawingAnchor(t[6].time, 96), DrawingAnchor(t[2].time, 104)]);
      final flat = completeAnchors(DrawingTool.longPosition, [entry, entry]);
      expect(flat[1].price, 101);
      expect(flat[2].price, 99);
    });

    test('range stats report difference, percent and bars', () {
      final s =
          rangeStats(DrawingAnchor(t[1].time, 100), DrawingAnchor(t[7].time, 103), p.timeline);
      expect(s.diff, 3);
      expect(s.percent, closeTo(3, 1e-9));
      expect(s.bars, 6);
    });
  });

  group('editing', () {
    final p = _projection();
    final t = p.timeline.candles;

    test('moving a handle changes only that anchor', () {
      final d = _drawing(
          DrawingTool.trendLine, [DrawingAnchor(t[0].time, 100), DrawingAnchor(t[5].time, 110)]);
      final moved = moveHandle(d, 1, DrawingAnchor(t[8].time, 120));
      expect(moved.anchors, [d.anchors[0], DrawingAnchor(t[8].time, 120)]);
    });

    test('horizontal and vertical lines move along one axis only', () {
      final h = _drawing(DrawingTool.horizontalLine, [DrawingAnchor(t[2].time, 100)]);
      expect(moveHandle(h, 0, DrawingAnchor(t[7].time, 120)).anchors.single,
          DrawingAnchor(t[2].time, 120));
      final v = _drawing(DrawingTool.verticalLine, [DrawingAnchor(t[2].time, 100)]);
      expect(moveHandle(v, 0, DrawingAnchor(t[7].time, 120)).anchors.single,
          DrawingAnchor(t[7].time, 100));
    });

    test('position handles: entry drags the stop time along, the stop moves only in price', () {
      final d = _drawing(DrawingTool.longPosition, [
        DrawingAnchor(t[2].time, 100),
        DrawingAnchor(t[6].time, 110),
        DrawingAnchor(t[2].time, 95),
      ]);
      final entry = moveHandle(d, 0, DrawingAnchor(t[3].time, 101));
      expect(entry.anchors[0], DrawingAnchor(t[3].time, 101));
      expect(entry.anchors[2], DrawingAnchor(t[3].time, 95));
      final stop = moveHandle(d, 2, DrawingAnchor(t[9].time, 90));
      expect(stop.anchors[2], DrawingAnchor(t[2].time, 90));
      final target = moveHandle(d, 1, DrawingAnchor(t[8].time, 115));
      expect(target.anchors[1], DrawingAnchor(t[8].time, 115));
    });

    test('translate shifts every anchor by whole bars and a price delta', () {
      final d = _drawing(DrawingTool.pitchfork, [
        DrawingAnchor(t[0].time, 100),
        DrawingAnchor(t[2].time, 110),
        DrawingAnchor(t[4].time, 105),
      ]);
      final moved = translateDrawing(d, p.timeline, 2, -3);
      // 第 4 根平移 2 根跨过了休市跳空，落到第 6 根的开盘时间
      expect(moved.anchors, [
        DrawingAnchor(t[2].time, 97),
        DrawingAnchor(t[4].time, 107),
        DrawingAnchor(t[6].time, 102),
      ]);
    });
  });

  group('hit testing', () {
    final p = _projection();
    final t = p.timeline.candles;
    final trend = _drawing(
        DrawingTool.trendLine, [DrawingAnchor(t[0].time, 110), DrawingAnchor(t[8].time, 110)]);

    test('handles win over the body, the body has a tolerance, far away misses', () {
      final shape = shapeOf(trend, p);
      expect(hitTestShape(shape, const Offset(212, 104))?.handle, 0);
      expect(hitTestShape(shape, const Offset(368, 98))?.handle, 1);
      expect(hitTestShape(shape, const Offset(290, 106))?.isBody, isTrue);
      expect(hitTestShape(shape, const Offset(290, 130)), isNull);
      expect(hitTestShape(shape, const Offset(212, 104), withHandles: false)?.isBody, isTrue);
    });

    test('filled tools are hit inside their area', () {
      final rect = _drawing(
          DrawingTool.rectangle, [DrawingAnchor(t[1].time, 120), DrawingAnchor(t[6].time, 100)]);
      expect(hitTestShape(shapeOf(rect, p), const Offset(280, 80))?.isBody, isTrue);
      expect(hitTestShape(shapeOf(rect, p), const Offset(280, 170)), isNull);
    });

    test('horizontal line is hit anywhere along its width', () {
      final h = _drawing(DrawingTool.horizontalLine, [DrawingAnchor(t[2].time, 100)]);
      final shape = shapeOf(h, p);
      expect(hitTestShape(shape, const Offset(5, 152))?.isBody, isTrue);
      expect(hitTestShape(shape, const Offset(200, 150))?.handle, 0);
    });

    test('elliott wave has six handles and five legs', () {
      final d = _drawing(DrawingTool.elliottWave, [
        for (var i = 0; i < 6; i++) DrawingAnchor(t[i].time, i.isEven ? 100 : 110),
      ]);
      final shape = shapeOf(d, p);
      expect(shape.handles.length, 6);
      expect(shape.segments.length, 5);
    });

    test('bounds cover every part of the shape', () {
      final shape = shapeOf(trend, p);
      expect(shape.bounds, Rect.fromLTRB(p.indexToX(0), 100, p.indexToX(8), 100));
    });
  });
}
