import 'dart:ui';

import 'package:chartkit_flutter/chartkit_flutter.dart';
import 'package:chartkit_flutter/src/chart/chart_layout.dart';
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

/// 每个字符 6 逻辑像素的假测量，便于断言自适应右轴。
double _measure(String s) => s.length * 6.0;

ChartLayout _layout({
  List<Candle>? candles,
  Size size = const Size(400, 318),
  double candleWidth = 8,
  double scrollOffset = 0,
  double blankScrollRatio = 0,
  double blankScrollWidth = 0,
  bool showVolume = true,
  List<double> subWeights = const [],
  List<IndicatorSeries> mainSeries = const [],
  String Function(double)? formatPrice,
}) =>
    ChartLayout.compute(
      size: size,
      candles: candles ?? _data(200),
      candleWidth: candleWidth,
      scrollOffset: scrollOffset,
      dims: _dims,
      showVolume: showVolume,
      blankScrollRatio: blankScrollRatio,
      blankScrollWidth: blankScrollWidth,
      subWeights: subWeights,
      mainSeries: mainSeries,
      measureText: _measure,
      formatPrice: formatPrice ?? (v) => v.toStringAsFixed(2),
      labelPad: 4,
    );

void main() {
  group('PaneSplit', () {
    test('main + volume fill the chart height when there are no sub panes', () {
      final s =
          PaneSplit.compute(chartHeight: 300, dims: _dims, showVolume: true, subWeights: const []);
      expect(s.mainBottom, closeTo(300 * (1 - 0.16), 1e-9));
      expect(s.volTop, closeTo(s.mainBottom + 6, 1e-9));
      expect(s.volBottom, closeTo(300, 1e-9));
      expect(s.subPaneHeights, isEmpty);
    });

    test('without volume the main pane takes everything', () {
      final s =
          PaneSplit.compute(chartHeight: 300, dims: _dims, showVolume: false, subWeights: const []);
      expect(s.mainBottom, 300);
      expect(s.volBottom, s.volTop);
    });

    test('each sub pane takes fraction + legend row, scaled by its weight', () {
      final s = PaneSplit.compute(
          chartHeight: 300, dims: _dims, showVolume: true, subWeights: const [1, 0.5]);
      expect(s.subFullHeight, closeTo(54, 1e-9));
      expect(s.subPaneHeights[0], closeTo(54 + 16, 1e-9));
      expect(s.subPaneHeights[1], closeTo((54 + 16) * 0.5, 1e-9));
      final subTotal = 70 + 35 + 6 * 1.5;
      expect(s.mainBottom, closeTo(300 - 48 - subTotal, 1e-9));
    });

    test('too many sub panes are scaled so they take at most half the chart', () {
      final s = PaneSplit.compute(
          chartHeight: 300, dims: _dims, showVolume: false, subWeights: const [1, 1, 1, 1]);
      expect(s.subFullHeight * 4, closeTo(150, 1e-9));
    });
  });

  group('ChartLayout', () {
    test('anchors the latest candle to the right edge at zero offset', () {
      final l = _layout();
      expect(l.lastIndex, 199);
      expect(l.rightFloat, 199);
      expect(l.centerX(199), closeTo(l.chartWidth - 4, 1e-9));
      expect(l.firstIndex, 199 - (l.chartWidth / 8).ceil());
    });

    test('right axis grows to fit the widest price label', () {
      final narrow = _layout(formatPrice: (v) => v.toStringAsFixed(0));
      expect(narrow.rightAxisWidth, _dims.rightAxisWidth);
      final wide = _layout(formatPrice: (v) => v.toStringAsFixed(8));
      expect(wide.rightAxisWidth, greaterThan(_dims.rightAxisWidth));
      expect(wide.rightAxisWidth, closeTo(_measure(wide.priceMax.toStringAsFixed(8)) + 8, 6.1));
      expect(wide.chartWidth, 400 - wide.rightAxisWidth);
    });

    test('scroll offset is clamped to the data range', () {
      final l = _layout(scrollOffset: 1e9);
      expect(l.offset, l.maxOffset);
      expect(l.maxOffset, closeTo(200 * 8 - l.chartWidth, 1e-9));
      expect(l.firstIndex, 0);
      expect(_layout(scrollOffset: -50).offset, 0);
    });

    test('blank scroll ratio allows dragging the latest candle off the right edge', () {
      final l = _layout(scrollOffset: -1e9, blankScrollRatio: 0.5);
      expect(l.minOffset, closeTo(-l.chartWidth * 0.5, 1e-9));
      expect(l.offset, l.minOffset);
      expect(l.centerX(199), lessThan(l.chartWidth / 2 + 8));
    });

    test('blank scroll width is an absolute allowance that overrides the ratio', () {
      final l = _layout(scrollOffset: -1e9, blankScrollWidth: 160, blankScrollRatio: 0.1);
      expect(l.minOffset, -160);
      expect(l.centerX(199), closeTo(l.chartWidth - 160 - 4, 1e-9));
      final capped = _layout(scrollOffset: -1e9, blankScrollWidth: 1e6);
      expect(capped.minOffset, closeTo(-capped.chartWidth * 0.9, 1e-9));
    });

    test('visibleExtremes finds the highest high and lowest low in range', () {
      final candles = _data(10);
      final spiky = [
        ...candles.sublist(0, 4),
        candles[4].copyWith(high: 999),
        ...candles.sublist(5, 7),
        candles[7].copyWith(low: 1),
        ...candles.sublist(8),
      ];
      expect(visibleExtremes(spiky, 0, 9), (high: 4, low: 7));
      expect(visibleExtremes(spiky, 5, 6), (high: 6, low: 5));
      expect(visibleExtremes(spiky, 3, 2), isNull);
    });

    test('price range covers visible candles with 6% padding', () {
      final l = _layout();
      final lo = 99.0 + l.firstIndex, hi = 102.0 + 199;
      expect(l.priceMin, closeTo(lo - (hi - lo) * 0.06, 1e-9));
      expect(l.priceMax, closeTo(hi + (hi - lo) * 0.06, 1e-9));
    });

    test('price range includes main indicator lines', () {
      final values = List<double?>.filled(200, null)..[199] = 5000;
      final l = _layout(mainSeries: [
        IndicatorSeries('X', Pane.main, [IndicatorLine('X', values)]),
      ]);
      expect(l.priceMax, greaterThan(5000));
    });

    test('flat data still yields a non-degenerate price range', () {
      final flat = [
        for (var i = 0; i < 5; i++) Candle(time: i, open: 1, high: 1, low: 1, close: 1),
      ];
      final l = _layout(candles: flat);
      expect(l.priceMax - l.priceMin, greaterThan(0.5));
      expect(l.maxOffset, 0);
    });

    test('priceToY and yToPrice are inverses and span the main pane', () {
      final l = _layout();
      expect(l.priceToY(l.priceMax), closeTo(l.mainTop, 1e-9));
      expect(l.priceToY(l.priceMin), closeTo(l.mainBottom, 1e-9));
      expect(l.yToPrice(l.priceToY(250)), closeTo(250, 1e-9));
    });

    test('indexAtX inverts centerX and allows the blank right slot', () {
      final l = _layout();
      expect(l.indexAtX(l.centerX(150)), 150);
      expect(l.indexAtX(-1e6), 0);
      final blank = _layout(scrollOffset: -80, blankScrollRatio: 0.5);
      expect(blank.indexAtX(blank.chartWidth - 1), greaterThan(199));
    });

    test('sub panes stack below the volume pane and stay above the time axis', () {
      final l = _layout(subWeights: const [1, 1]);
      expect(l.subPanes.length, 2);
      expect(l.subPanes[0].top, closeTo(l.volBottom + 6, 1e-9));
      expect(l.subPanes[1].top, closeTo(l.subPanes[0].bottom + 6, 1e-9));
      expect(l.subPanes[1].bottom, closeTo(l.chartHeight, 1e-9));
      expect(l.subPanes[0].contentTop, l.subPanes[0].top + 16);
    });
  });

  group('KLineChartMapper', () {
    test('exposes the frame geometry and compares by value', () {
      final candles = _data(200);
      final a = KLineChartMapper(_layout(candles: candles), candles);
      final b = KLineChartMapper(_layout(candles: candles), candles);
      final c = KLineChartMapper(_layout(candles: candles, scrollOffset: 40), candles);
      expect(a, b);
      expect(a == c, isFalse);
      expect(a.itemCount, 200);
      expect(a.latestPrice, candles.last.close);
      expect(a.mainRect.top, 0);
      expect(a.yToPrice(a.priceToY(180)), closeTo(180, 1e-9));
      expect(a.xToIndex(a.indexToX(190)), 190);
      expect(a.indexVisible(199), isTrue);
      expect(a.indexVisible(0), isFalse);
      expect(a.containsY(a.mainRect.bottom + 1), isFalse);
      expect(a.clampY(-10), a.mainRect.top);
    });
  });
}
