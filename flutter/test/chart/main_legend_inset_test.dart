import 'dart:ui';

import 'package:chartkit_flutter/chartkit_flutter.dart';
import 'package:chartkit_flutter/src/chart/chart_layout.dart';
import 'package:chartkit_flutter/src/chart/chart_painter.dart' show mainLegendInset;
import 'package:chartkit_flutter/src/drawing/drawing_geometry.dart' show DrawingProjection;
import 'package:flutter/material.dart' show Center, MaterialApp, SizedBox;
import 'package:flutter_test/flutter_test.dart';

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

ChartLayout _layout({double inset = 0, Size size = const Size(400, 318)}) => ChartLayout.compute(
      size: size,
      candles: _data(200),
      candleWidth: 8,
      scrollOffset: 0,
      dims: _dims,
      showVolume: true,
      blankScrollRatio: 0,
      subWeights: const [],
      mainSeries: const [],
      measureText: (s) => s.length * 6.0,
      formatPrice: (v) => v.toStringAsFixed(2),
      labelPad: 4,
      mainContentInset: inset,
    );

void main() {
  group('mainLegendInset', () {
    test('关闭、分时、没有主图指标时不留', () {
      expect(mainLegendInset(reserve: false, mode: ChartMode.candle, rows: 2, dims: _dims), 0);
      expect(mainLegendInset(reserve: true, mode: ChartMode.timeLine, rows: 2, dims: _dims), 0);
      expect(mainLegendInset(reserve: true, mode: ChartMode.candle, rows: 0, dims: _dims), 0);
    });

    test('留的高度 = 图例顶距 + 行数 × 行高', () {
      expect(
        mainLegendInset(reserve: true, mode: ChartMode.candle, rows: 2, dims: _dims),
        _dims.mainLegendTop + 2 * _dims.mainLegendRowHeight,
      );
    });
  });

  group('ChartLayout.mainContentTop', () {
    test('默认不留：价格区从主图顶开始，和原来一样', () {
      final l = _layout();
      expect(l.mainContentTop, 0);
      expect(l.priceToY(l.priceMax), closeTo(0, 1e-9));
    });

    test('留位后价格区从图例下面开始，窗格本身不变', () {
      final l = _layout(inset: 33);
      expect(l.mainContentTop, 33);
      expect(l.mainRect.top, 0);
      expect(l.priceToY(l.priceMax), closeTo(33, 1e-9));
      expect(l.priceToY(l.priceMin), closeTo(l.mainBottom, 1e-9));
      final mid = (l.priceMax + l.priceMin) / 2;
      expect(l.yToPrice(l.priceToY(mid)), closeTo(mid, 1e-9));
    });

    test('图很矮时最多占主图高度的 40%', () {
      final l = _layout(inset: 1000);
      expect(
        l.mainContentTop,
        closeTo(l.mainBottom * ChartLayout.maxMainContentInsetRatio, 1e-9),
      );
    });

    test('画线换算和布局用同一条顶边', () {
      final l = _layout(inset: 33);
      final p = DrawingProjection.of(l, DrawingTimeline(_data(200), 60000));
      for (final price in [l.priceMin, 250.0, l.priceMax]) {
        expect(p.priceToY(price), closeTo(l.priceToY(price), 1e-9));
      }
      expect(p.yToPrice(100), closeTo(l.yToPrice(100), 1e-9));
    });

    test('mapper 对外给出价格区顶边，并参与相等比较', () {
      final candles = _data(200);
      final plain = KLineChartMapper(_layout(), candles);
      final inset = KLineChartMapper(_layout(inset: 33), candles);
      expect(plain.mainContentTop, 0);
      expect(inset.mainContentTop, 33);
      expect(inset.priceToY(inset.yToPrice(120)), closeTo(120, 1e-9));
      expect(plain == inset, isFalse);
    });
  });

  group('KLineChart.reserveMainLegend', () {
    Future<KLineChartMapper> pump(WidgetTester tester, {required bool reserve, ChartMode mode = ChartMode.candle}) async {
      final state = KLineChartState(timeFrame: TimeFrame.m1)..setData(_data(200));
      addTearDown(state.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: SizedBox(
            width: 400,
            height: 400,
            child: KLineChart(
              state: state,
              entranceAnimation: false,
              mode: mode,
              mainIndicators: [Ma(periods: const [5, 10, 30]), const Boll()],
              reserveMainLegend: reserve,
            ),
          ),
        ),
      ));
      await tester.pump();
      return state.mapper.value!;
    }

    testWidgets('默认关闭：价格区顶边是 0', (tester) async {
      final m = await pump(tester, reserve: false);
      expect(m.mainContentTop, 0);
    });

    testWidgets('打开后按两个主图指标留两行', (tester) async {
      final m = await pump(tester, reserve: true);
      expect(m.mainContentTop, _dims.mainLegendTop + 2 * _dims.mainLegendRowHeight);
    });

    testWidgets('分时模式不显示图例，也不留', (tester) async {
      final m = await pump(tester, reserve: true, mode: ChartMode.timeLine);
      expect(m.mainContentTop, 0);
    });
  });
}
