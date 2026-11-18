import 'package:chartkit_flutter/chartkit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bullish and change', () {
    const up = Candle(time: 0, open: 100, high: 110, low: 99, close: 105);
    expect(up.isBullish, isTrue);
    expect(up.change, closeTo(5.0, 1e-9));
    expect(up.changeRate, closeTo(0.05, 1e-9));

    const down = Candle(time: 0, open: 100, high: 101, low: 90, close: 95);
    expect(down.isBullish, isFalse);
    expect(down.changeRate, closeTo(-0.05, 1e-9));
  });

  test('change rate is safe on zero open', () {
    const c = Candle(time: 0, open: 0, high: 0, low: 0, close: 0);
    expect(c.changeRate, 0.0);
  });

  test('candle value equality and copyWith', () {
    const a = Candle(time: 1, open: 1, high: 2, low: 0, close: 1.5, volume: 3);
    final b = a.copyWith(close: 1.8);
    expect(b.close, 1.8);
    expect(b.time, 1);
    expect(a.close, 1.5);
    expect(a, const Candle(time: 1, open: 1, high: 2, low: 0, close: 1.5, volume: 3));
    expect(a == b, isFalse);
  });

  test('timeframe open alignment', () {
    expect(TimeFrame.m15.openTimeOf(1000000), 900000);
    expect(TimeFrame.h1.openTimeOf(3599999), 0);
  });
}
