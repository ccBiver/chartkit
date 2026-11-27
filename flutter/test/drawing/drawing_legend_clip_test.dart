// 主图开了图例留位（reserveMainLegend）时，画线裁在图例下面：价位略高于可见范围的水平线、
// 从那里斜着进价格区的趋势线，都不画进图例那一条。图例留位关着时裁剪区和原来一样，由现有基线和参考图测试覆盖。
import 'package:chartkit_flutter/chartkit_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../script/fixtures.dart';
import '../tools/harness.dart';

void main() {
  final candles = loadKlines();
  final n = candles.length;
  late KLineChartState state;
  late DrawingController drawings;

  setUp(() {
    state = KLineChartState(timeFrame: TimeFrame.m15)..setData(candles);
    drawings = DrawingController(style: const DrawingStyle(color: Color(0xFFFF00FF)));
  });
  tearDown(() {
    drawings.dispose();
    state.dispose();
  });

  for (final (name, log, gap) in [
    ('只开图例留位', false, 0.0),
    ('同时开 mainBottomGap', false, 34.0),
    ('同时开对数坐标', true, 0.0),
  ]) {
    testWidgets('$name：水平线和趋势线不画进图例那一条，进了价格区的部分照常画', (tester) async {
      await pumpChart(
          tester,
          state,
          KLineChart(
            state: state,
            entranceAnimation: false,
            showVolume: false,
            mainIndicators: [Ma()],
            reserveMainLegend: true,
            logScale: log,
            mainBottomGap: gap,
            drawingController: drawings,
          ),
          cw: 6);
      final empty = await capture(tester);
      final m = state.mapper.value!;
      expect(m.mainContentTop, greaterThan(10));
      final price = m.yToPrice(m.mainContentTop / 2);
      final inside = m.yToPrice(m.mainContentTop + 40);
      drawings
        ..add(Drawing(
          id: 'h',
          tool: DrawingTool.horizontalLine,
          anchors: [DrawingAnchor(candles[n - 30].time, price)],
          style: const DrawingStyle(color: Color(0xFFFF00FF), width: 2),
        ))
        ..add(Drawing(
          id: 't',
          tool: DrawingTool.trendLine,
          anchors: [
            DrawingAnchor(candles[n - 40].time, price),
            DrawingAnchor(candles[n - 10].time, inside)
          ],
          style: const DrawingStyle(color: Color(0xFFFF00FF), width: 2),
        ));
      await tester.pump();
      final drawn = await capture(tester);
      expect(state.mapper.value!.priceToY(price), lessThan(m.mainContentTop));
      var inStrip = 0, below = 0;
      for (var y = 0.0; y < m.mainContentTop + 30; y += 1 / empty.ratio) {
        for (var x = 0.0; x < m.mainRect.right; x += 1 / empty.ratio) {
          if (empty.at(x, y) == drawn.at(x, y)) continue;
          if (y < m.mainContentTop) {
            inStrip++;
          } else {
            below++;
          }
        }
      }
      expect(inStrip, 0, reason: '图例那一条里不画');
      expect(below, greaterThan(20), reason: '趋势线进了价格区的部分照常画');
    });
  }
}
