import 'dart:math' as math;

import 'package:chartkit_flutter/src/indicator/moving_average.dart';
import 'package:flutter_test/flutter_test.dart';

const _tol = 1e-6;

void _expectSeries(List<double?> expected, List<double?> actual) {
  expect(actual.length, expected.length, reason: 'size mismatch');
  for (var i = 0; i < expected.length; i++) {
    final e = expected[i];
    if (e == null) {
      expect(actual[i], isNull, reason: 'index $i should be null');
    } else {
      expect(actual[i], closeTo(e, _tol), reason: 'index $i');
    }
  }
}

void main() {
  test('sma basic with leading nulls', () {
    _expectSeries([null, null, 2.0, 3.0, 4.0], sma([1, 2, 3, 4, 5], 3));
  });

  test('sma with non-positive period is all null', () {
    _expectSeries([null, null], sma([1, 2], 0));
  });

  test('ema is continuous and correct', () {
    // k = 2/3; ema0=1; ema1=1.66667; ema2=2.55556
    final out = ema([1, 2, 3], 2);
    expect(out.length, 3);
    expect(out[0], closeTo(1.0, _tol));
    expect(out[1], closeTo(1.6666667, _tol));
    expect(out[2], closeTo(2.5555556, _tol));
  });

  test('ema of empty input is empty', () {
    expect(ema(const [], 5), isEmpty);
  });

  test('boll middle band equals sma(n)', () {
    final src = <double>[2, 4, 6, 8, 10];
    final bands = boll(src, 3, 2.0);
    _expectSeries(sma(src, 3), bands.mb);
    _expectSeries([null, null, 4.0, 6.0, 8.0], bands.mb);
  });

  test('boll bands golden', () {
    final bands = boll([2, 4, 6, 8, 10], 3, 2.0);
    final md = math.sqrt(8.0 / 3.0); // 窗口 [2,4,6] 关于均值 4 的总体标准差
    expect(bands.up[2], closeTo(4.0 + 2 * md, _tol));
    expect(bands.dn[2], closeTo(4.0 - 2 * md, _tol));
    expect(bands.up[4], closeTo(8.0 + 2 * md, _tol));
    expect(bands.dn[4], closeTo(8.0 - 2 * md, _tol));
    expect(bands.up[1], isNull);
  });
}
