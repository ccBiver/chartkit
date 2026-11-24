// 多图：同一页放 4 个 KLineChart。各图互不影响、小尺寸下不溢出不重叠、4 个同时滚动和更新的帧耗时。
// 格子怎么排是 App 的事，这里用 2×2 的 GridView 代替：竖屏 430 宽、横屏 900×420。
import 'dart:ui' as ui;

import 'package:chartkit_flutter/chartkit_flutter.dart';
import 'package:chartkit_flutter/src/chart/chart_painter.dart';
import 'package:chartkit_flutter/src/chart/crosshair_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../script/fixtures.dart';
import 'harness.dart';

/// 15 分钟 K 线合成更大周期（只用来造几份不同的数据）。
List<Candle> aggregate(List<Candle> src, int ms) {
  final out = <Candle>[];
  for (final c in src) {
    final t = c.time - c.time % ms;
    if (out.isNotEmpty && out.last.time == t) {
      final p = out.removeLast();
      out.add(Candle(
          time: t,
          open: p.open,
          high: p.high > c.high ? p.high : c.high,
          low: p.low < c.low ? p.low : c.low,
          close: c.close));
    } else {
      out.add(Candle(time: t, open: c.open, high: c.high, low: c.low, close: c.close));
    }
  }
  return out;
}

class _Cell {
  _Cell(this.state, this.scripts, this.key);

  final KLineChartState state;
  final ScriptOutputController scripts;
  final GlobalKey key;
}

void main() {
  final m15 = loadKlines();
  final frames = [
    (TimeFrame.m15, m15),
    (TimeFrame.h1, aggregate(m15, 3600000)),
    (TimeFrame.h4, aggregate(m15, 4 * 3600000)),
    (TimeFrame.m15, m15.sublist(0, 700)),
  ];
  late List<_Cell> cells;
  late ChartReplayController replay;
  late DrawingController shared;

  setUp(() {
    cells = [
      for (final (tf, data) in frames)
        _Cell(KLineChartState(timeFrame: tf)..setData(data), ScriptOutputController(), GlobalKey()),
    ];
    // 主图脚本只能用在 15 分钟的格子（样本是 15 分钟算的）
    cells[0].scripts.setJson('smc', sampleJson('smc'));
    cells[0].scripts.setJson('rsi', sampleJson('rsi'));
    replay = ChartReplayController(source: cells[2].state);
    shared = DrawingController(style: const DrawingStyle(color: Color(0xFFF59E0B)));
    shared.add(Drawing(
      id: 'h',
      tool: DrawingTool.horizontalLine,
      anchors: [DrawingAnchor(m15[600].time, 3550)],
      style: const DrawingStyle(color: Color(0xFFF59E0B), width: 2),
    ));
  });
  tearDown(() {
    replay.dispose();
    shared.dispose();
    for (final c in cells) {
      c.scripts.dispose();
      c.state.dispose();
    }
  });

  Widget grid(Size size, {bool log3 = false, ChartTheme theme = ChartTheme.dark}) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            key: shotKey,
            child: SizedBox.fromSize(
              size: size,
              child: GridView.count(
                crossAxisCount: 2,
                childAspectRatio: (size.width / 2) / (size.height / 2),
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  for (var i = 0; i < 4; i++)
                    KLineChart(
                      key: cells[i].key,
                      state: cells[i].state,
                      theme: theme,
                      entranceAnimation: false,
                      mainIndicators: [Ma()],
                      subIndicators: const [Macd()],
                      scriptOutputs: i == 0 ? cells[i].scripts : null,
                      drawingController: i < 2 ? shared : null,
                      replay: i == 2 ? replay : null,
                      logScale: log3 && i == 3,
                    ),
                ],
              ),
            ),
          ),
        ),
      );

  Future<void> pumpGrid(WidgetTester tester, Size size, {bool log3 = false}) async {
    await tester.binding.setSurfaceSize(Size(size.width, size.height + 40));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(grid(size, log3: log3));
    for (final c in cells) {
      c.state.setViewport(candleWidth: 5);
    }
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
  }

  Rect cellRect(WidgetTester tester, int i) {
    final origin = tester.getTopLeft(find.byKey(shotKey));
    return tester.getRect(find.byKey(cells[i].key)).shift(-origin);
  }

  /// 每格里不同的像素数。
  Future<List<int>> cellDiffs(WidgetTester tester, Pixels a, Pixels b) async {
    return [
      for (var i = 0; i < 4; i++)
        () {
          final r = cellRect(tester, i);
          var n = 0;
          for (var y = r.top; y < r.bottom; y += 1 / a.ratio) {
            for (var x = r.left; x < r.right; x += 1 / a.ratio) {
              if (a.at(x, y) != b.at(x, y)) n++;
            }
          }
          return n;
        }(),
    ];
  }

  group('互不影响', () {
    testWidgets('滚动、十字光标、回放、对数坐标只改自己那一格', (tester) async {
      const size = Size(430, 760);
      await pumpGrid(tester, size);
      var before = await capture(tester);
      final o = tester.getTopLeft(find.byKey(shotKey));

      Future<void> expectOnly(int cell, String what) async {
        await tester.pump();
        await tester.pump();
        final after = await capture(tester);
        final d = await cellDiffs(tester, before, after);
        for (var i = 0; i < 4; i++) {
          if (i == cell) {
            expect(d[i], greaterThan(0), reason: '$what：第 $i 格应该变');
          } else {
            expect(d[i], 0, reason: '$what：第 $i 格不该变');
          }
        }
        before = after;
      }

      await tester.dragFrom(o + cellRect(tester, 0).center, const Offset(80, 0));
      await tester.pump(const Duration(seconds: 2));
      await expectOnly(0, '拖第 0 格');

      await tester.longPressAt(o + cellRect(tester, 1).center);
      await expectOnly(1, '长按第 1 格');

      replay.start();
      await tester.pump();
      await tester.tapAt(o + cellRect(tester, 2).center);
      expect(replay.phase, ReplayPhase.active);
      await expectOnly(2, '第 2 格进回放');

      await tester.pumpWidget(grid(size, log3: true));
      await expectOnly(3, '第 3 格开对数');

      // 实时行情只推到第 0 格
      final last = cells[0].state.candles.last;
      cells[0].state.appendOrUpdate(Candle(
          time: last.time, open: last.open, high: last.high + 20, low: last.low, close: last.high + 20));
      await expectOnly(0, '第 0 格来行情');
      expect(tester.takeException(), isNull);
    });

    testWidgets('两格共用一个画线控制器时两格都显示画线', (tester) async {
      await pumpGrid(tester, const Size(430, 760));
      final a = await capture(tester);
      shared.visible = false;
      await tester.pump();
      final b = await capture(tester);
      final d = await cellDiffs(tester, a, b);
      expect(d[0], greaterThan(0));
      expect(d[1], greaterThan(0));
      expect(d[2], 0);
      expect(d[3], 0);
    });

    testWidgets('App 可以用现有接口做十字线联动：一格的光标时间换成另一格的下标', (tester) async {
      await pumpGrid(tester, const Size(430, 760));
      // 第 0 格（15m）长按，第 1 格（1h）跟到同一时刻所在的那根
      final c = cells[0].state;
      final other = cells[1].state;
      void follow() {
        final i = c.crosshairIndex;
        if (i < 0 || i >= c.candles.length) return other.clearCrosshair();
        final t = c.candles[i].time;
        final list = other.candles;
        var k = list.length - 1;
        while (k > 0 && list[k].time > t) {
          k--;
        }
        final m = other.mapper.value!;
        other.setCrosshair(k, m.indexToX(k), -1);
      }

      c.addListener(follow);
      addTearDown(() => c.removeListener(follow));
      await tester.longPressAt(tester.getTopLeft(find.byKey(shotKey)) + cellRect(tester, 0).center);
      await tester.pump();
      final t = c.candles[c.crosshairIndex].time;
      final k = other.crosshairIndex;
      expect(other.candles[k].time, lessThanOrEqualTo(t));
      expect(other.candles[k].time + 3600000, greaterThan(t));
    });
  });

  group('小尺寸', () {
    for (final (name, size) in [
      ('竖屏 430 宽 4 格', const Size(430, 760)),
      ('横屏 900×420 4 格', const Size(900, 420)),
    ]) {
      testWidgets('$name：不报溢出，图例、浮窗、副图都在自己那一格里', (tester) async {
        await pumpGrid(tester, size);
        // 一格开十字光标浮窗
        await tester.longPressAt(tester.getTopLeft(find.byKey(shotKey)) + cellRect(tester, 0).center);
        await tester.pump();
        expect(tester.takeException(), isNull);
        for (var i = 0; i < 4; i++) {
          final cell = tester.getRect(find.byKey(cells[i].key));
          final m = cells[i].state.mapper.value!;
          // 主图至少占绘图区（去掉时间轴）高度的四分之一（PaneSplit 的约定），右轴不超过格子宽度的 35%
          final plot = cell.height - const ChartDims().bottomAxisHeight;
          expect(m.mainRect.height, greaterThanOrEqualTo(plot / 4), reason: '第 $i 格主图');
          // ignore: avoid_print
          print('SIZE $name 第 $i 格 ${cell.size}：主图高 ${m.mainRect.height.toStringAsFixed(1)}，'
              '右轴宽 ${(m.size.width - m.mainRect.width).toStringAsFixed(1)}');
          expect(m.size.width - m.mainRect.width, lessThan(cell.width * 0.35), reason: '第 $i 格右轴');
          // 图例在主图里
          final legend = find.descendant(
              of: find.byKey(cells[i].key), matching: find.byType(Wrap));
          for (final e in legend.evaluate()) {
            final r = tester.getRect(find.byWidget(e.widget));
            expect(r.bottom, lessThanOrEqualTo(cell.top + m.mainRect.bottom), reason: '第 $i 格图例');
            expect(r.right, lessThanOrEqualTo(cell.right), reason: '第 $i 格图例');
          }
        }
        // 浮窗在第 0 格里
        final cell0 = tester.getRect(find.byKey(cells[0].key));
        final panel = find.descendant(of: find.byKey(cells[0].key), matching: find.byType(CrosshairPanel));
        expect(panel, findsOneWidget);
        final r = tester.getRect(panel);
        expect(cell0.contains(r.topLeft) && cell0.contains(r.bottomRight), isTrue,
            reason: '浮窗 $r 超出第 0 格 $cell0');
      });
    }
  });

  group('参考图', () {
    testWidgets('竖屏 430 宽 4 格', (tester) async {
      await pumpGrid(tester, const Size(430, 760));
      await tester.longPressAt(tester.getTopLeft(find.byKey(shotKey)) + cellRect(tester, 1).center);
      await tester.pump();
      await matchGolden('08_multi_portrait_430');
    });
    testWidgets('横屏 900×420 4 格', (tester) async {
      await pumpGrid(tester, const Size(900, 420));
      await tester.longPressAt(tester.getTopLeft(find.byKey(shotKey)) + cellRect(tester, 1).center);
      await tester.pump();
      await matchGolden('09_multi_landscape_900');
    });
  });

  group('帧耗时', () {
    for (final (label, size) in [
      ('竖屏 430×760', const Size(430, 760)),
      ('横屏 900×420', const Size(900, 420)),
    ]) {
      testWidgets('4 格同时滚动并收到行情，$label', (tester) async {
        await pumpGrid(tester, size);
        final painters = [
          for (final c in cells)
            tester
                .widgetList<CustomPaint>(
                    find.descendant(of: find.byKey(c.key), matching: find.byType(CustomPaint)))
                .map((w) => w.painter)
                .whereType<KLineChartPainter>()
                .single,
        ];
        final sizes = [for (var i = 0; i < 4; i++) cellRect(tester, i).size];
        final update = <double>[], paint = <double>[], pump = <double>[];
        for (var i = 0; i < 80; i++) {
          final sw = Stopwatch()..start();
          for (final c in cells) {
            final last = c.state.candles.last;
            c.state.appendOrUpdate(Candle(
                time: last.time,
                open: last.open,
                high: last.high + 0.1,
                low: last.low,
                close: last.close + (i.isEven ? 0.1 : -0.1)));
            c.state.setViewport(scrollOffset: i.toDouble());
          }
          final u = sw.elapsedMicroseconds / 1000;
          sw
            ..reset()
            ..start();
          for (var k = 0; k < 4; k++) {
            final recorder = ui.PictureRecorder();
            painters[k].paint(Canvas(recorder), sizes[k]);
            recorder.endRecording().dispose();
          }
          final p = sw.elapsedMicroseconds / 1000;
          sw
            ..reset()
            ..start();
          await tester.pump();
          final f = sw.elapsedMicroseconds / 1000;
          if (i >= 20) {
            update.add(u);
            paint.add(p);
            pump.add(f);
          }
        }
        String stats(List<double> ms) {
          final s = List.of(ms)..sort();
          double q(double p) => s[((s.length - 1) * p).round()];
          return 'median ${q(0.5).toStringAsFixed(2)} ms, p90 ${q(0.9).toStringAsFixed(2)} ms, '
              'max ${s.last.toStringAsFixed(2)} ms (n=${s.length})';
        }

        // ignore: avoid_print
        print('BENCH multi, $label, 4 charts (MA + MACD + volume; cell 0 also 1 main + 1 sub script)\n'
            '  4 updates (incl. incremental indicators): ${stats(update)}\n'
            '  4 paints recorded: ${stats(paint)}\n'
            '  whole frame via tester.pump (build + layout + paint, no raster): ${stats(pump)}');
      });
    }
  });
}
