// BOLL 填充（Boll.fillColor）默认不填：显式传 null 时，图表要和加这个参数之前的基线参考图逐像素一致。
// 比对 testdata/baseline/02_light_indicators.png（9d3ee15 生成，MA + BOLL + 两个副图 + 最高最低价 + 买卖标记）。
// 不传这个参数的情况由同目录 default_off、script_off、empty_controller 三份基线测试覆盖（它们的 Boll 都不传 fillColor）。
import 'dart:math' as math;

import 'package:chartkit_flutter/chartkit_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 和 default_off_golden_test.dart 同一份合成数据。
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

void main() {
  test('Boll 的 fillColor 默认是 null', () {
    expect(const Boll().fillColor, isNull);
  });

  testWidgets('浅色、MA + BOLL、两个副图、最高最低价、买卖标记，显式 fillColor: null', (tester) async {
    final state = KLineChartState(timeFrame: TimeFrame.m1)..setData(_data(240));
    addTearDown(state.dispose);
    final c = state.candles;
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Center(
        child: RepaintBoundary(
          key: _key,
          child: SizedBox(
            width: 400,
            height: 420,
            child: KLineChart(
              state: state,
              theme: ChartTheme.light,
              entranceAnimation: false,
              // ignore: avoid_redundant_argument_values
              mainIndicators: [Ma(), const Boll(fillColor: null)],
              subIndicators: const [Macd(), Kdj()],
              showHighLow: true,
              tradeMarks: [
                TradeMark(
                    time: c[c.length - 12].time,
                    isBuy: true,
                    price: c[c.length - 12].low,
                    count: 2),
                TradeMark(time: c[c.length - 5].time, isBuy: false, price: c[c.length - 5].high),
              ],
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(
        find.byKey(_key), matchesGoldenFile('../../testdata/baseline/02_light_indicators.png'));
  });
}
