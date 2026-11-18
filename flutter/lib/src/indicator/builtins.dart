import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../model/candle.dart';
import 'chart_registry.dart';
import 'indicator.dart';
import 'moving_average.dart';

List<double> _closes(List<Candle> candles) => [for (final c in candles) c.close];

int _maxPeriod(List<int> periods) => periods.isEmpty ? 1 : math.max(1, periods.reduce(math.max));

/// 最近 n 根（含第 i 根）的最高价 / 最低价。
({double hh, double ll}) _highLow(List<Candle> candles, int i, int n) {
  final start = math.max(0, i - n + 1);
  var hh = candles[start].high;
  var ll = candles[start].low;
  for (var x = start; x <= i; x++) {
    if (candles[x].high > hh) hh = candles[x].high;
    if (candles[x].low < ll) ll = candles[x].low;
  }
  return (hh: hh, ll: ll);
}

/// 内置指标的基类：按「类型 + 参数」判等。
/// 这样宿主在 `build()` 里内联写 `[Ma(), const Macd()]` 时，每次重建得到的是「相等」的指标，
/// 图表不会误判为指标变更而丢弃增量缓存。
abstract class BuiltinIndicator extends Indicator {
  const BuiltinIndicator();

  /// 参与判等的全部参数。
  @protected
  List<Object> get params;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BuiltinIndicator &&
          other.runtimeType == runtimeType &&
          listEquals(other.params, params);

  @override
  int get hashCode => Object.hash(runtimeType, Object.hashAll(params));
}

/// MA：主图多周期简单均线（默认 7 / 30）。
class Ma extends BuiltinIndicator {
  Ma({List<int> periods = const [7, 30]}) : periods = List.unmodifiable(periods);

  final List<int> periods;

  @override
  List<Object> get params => periods;

  @override
  String get id => 'MA';
  @override
  Pane get pane => Pane.main;
  @override
  int get lookback => _maxPeriod(periods); // SMA 精确

  @override
  IndicatorSeries compute(List<Candle> candles) {
    final close = _closes(candles);
    return IndicatorSeries(id, pane, [
      for (final p in periods) IndicatorLine('MA$p', sma(close, p)),
    ]);
  }
}

/// EMA：主图多周期指数均线（默认 5 / 10 / 30）。连续无断点。
class Ema extends BuiltinIndicator {
  Ema({List<int> periods = const [5, 10, 30]}) : periods = List.unmodifiable(periods);

  final List<int> periods;

  @override
  List<Object> get params => periods;

  @override
  String get id => 'EMA';
  @override
  Pane get pane => Pane.main;
  @override
  int get lookback => _maxPeriod(periods) * 10; // 递归：×10 衰减到浮点精度

  @override
  IndicatorSeries compute(List<Candle> candles) {
    final close = _closes(candles);
    return IndicatorSeries(id, pane, [
      for (final p in periods) IndicatorLine('EMA$p', ema(close, p)),
    ]);
  }
}

/// BOLL：主图布林带（默认 20, 2，标准口径）。
class Boll extends BuiltinIndicator {
  const Boll({this.period = 20, this.k = 2.0});

  final int period;
  final double k;

  @override
  List<Object> get params => [period, k];

  @override
  String get id => 'BOLL';
  @override
  Pane get pane => Pane.main;
  @override
  int get lookback => math.max(1, period); // 精确

  @override
  IndicatorSeries compute(List<Candle> candles) {
    final bands = boll(_closes(candles), period, k);
    return IndicatorSeries(id, pane, [
      IndicatorLine('UP', bands.up),
      IndicatorLine('MB', bands.mb),
      IndicatorLine('DN', bands.dn),
    ]);
  }
}

/// MACD：副图。DIF=EMA(fast)−EMA(slow)，DEA=EMA(DIF, signal)，柱=mult·(DIF−DEA)。
class Macd extends BuiltinIndicator {
  const Macd({this.fast = 12, this.slow = 26, this.signal = 9, this.multiplier = 2.0});

  final int fast;
  final int slow;
  final int signal;
  final double multiplier;

  @override
  List<Object> get params => [fast, slow, signal, multiplier];

  @override
  String get id => 'MACD';
  @override
  Pane get pane => Pane.sub;
  @override
  int get lookback => (slow + signal) * 10;

  @override
  IndicatorSeries compute(List<Candle> candles) {
    final close = _closes(candles);
    final emaFast = ema(close, fast);
    final emaSlow = ema(close, slow);
    final dif = [for (var i = 0; i < close.length; i++) emaFast[i] - emaSlow[i]];
    final dea = ema(dif, signal);
    final bar = [for (var i = 0; i < close.length; i++) multiplier * (dif[i] - dea[i])];
    return IndicatorSeries(id, pane, [
      IndicatorLine('DIF', dif),
      IndicatorLine('DEA', dea),
      IndicatorLine('MACD', bar, style: LineStyle.histogram),
    ]);
  }
}

/// KDJ：副图（默认 9,3,3）。K/D 以 50 播种，全程连续。
class Kdj extends BuiltinIndicator {
  const Kdj({this.n = 9, this.m1 = 3, this.m2 = 3});

  final int n;
  final int m1;
  final int m2;

  @override
  List<Object> get params => [n, m1, m2];

  @override
  String get id => 'KDJ';
  @override
  Pane get pane => Pane.sub;
  @override
  int get lookback => (n + m1 + m2) * 10;

  @override
  IndicatorSeries compute(List<Candle> candles) {
    final size = candles.length;
    final kList = List<double?>.filled(size, null);
    final dList = List<double?>.filled(size, null);
    final jList = List<double?>.filled(size, null);
    var prevK = 50.0;
    var prevD = 50.0;
    for (var i = 0; i < size; i++) {
      final r = _highLow(candles, i, n);
      final rsv = r.hh == r.ll ? 0.0 : (candles[i].close - r.ll) / (r.hh - r.ll) * 100.0;
      final kv = ((m1 - 1) * prevK + rsv) / m1;
      final dv = ((m2 - 1) * prevD + kv) / m2;
      kList[i] = kv;
      dList[i] = dv;
      jList[i] = 3 * kv - 2 * dv;
      prevK = kv;
      prevD = dv;
    }
    return IndicatorSeries(id, pane, [
      IndicatorLine('K', kList),
      IndicatorLine('D', dList),
      IndicatorLine('J', jList),
    ]);
  }
}

/// RSI：副图（默认 6/12/24）。涨跌取**收盘对收盘**，采用 **Wilder 平滑**。
class Rsi extends BuiltinIndicator {
  Rsi({List<int> periods = const [6, 12, 24]}) : periods = List.unmodifiable(periods);

  final List<int> periods;

  @override
  List<Object> get params => periods;

  @override
  String get id => 'RSI';
  @override
  Pane get pane => Pane.sub;
  @override
  int get lookback => _maxPeriod(periods) * 10;

  @override
  IndicatorSeries compute(List<Candle> candles) {
    final n = candles.length;
    final gains = List<double>.filled(n, 0);
    final losses = List<double>.filled(n, 0);
    for (var i = 1; i < n; i++) {
      final d = candles[i].close - candles[i - 1].close;
      gains[i] = math.max(d, 0);
      losses[i] = math.max(-d, 0);
    }
    return IndicatorSeries(id, pane, [
      for (final p in periods) IndicatorLine('RSI$p', _rsiLine(gains, losses, p)),
    ]);
  }

  static List<double?> _rsiLine(List<double> gains, List<double> losses, int p) {
    final n = gains.length;
    final out = List<double?>.filled(n, null);
    if (p <= 0 || n <= p) return out;
    var avgGain = 0.0;
    var avgLoss = 0.0;
    for (var i = 1; i <= p; i++) {
      avgGain += gains[i];
      avgLoss += losses[i];
    }
    avgGain /= p;
    avgLoss /= p;
    out[p] = _rsiFrom(avgGain, avgLoss);
    for (var i = p + 1; i < n; i++) {
      avgGain = (avgGain * (p - 1) + gains[i]) / p;
      avgLoss = (avgLoss * (p - 1) + losses[i]) / p;
      out[i] = _rsiFrom(avgGain, avgLoss);
    }
    return out;
  }

  static double _rsiFrom(double avgGain, double avgLoss) =>
      avgLoss == 0 ? 100.0 : 100.0 - 100.0 / (1.0 + avgGain / avgLoss);
}

/// 成交量均线：副图（默认 5/10）。柱由渲染层按涨跌着色，这里只算均线。
class VolMa extends BuiltinIndicator {
  VolMa({List<int> periods = const [5, 10]}) : periods = List.unmodifiable(periods);

  final List<int> periods;

  @override
  List<Object> get params => periods;

  @override
  String get id => 'VOLMA';
  @override
  Pane get pane => Pane.sub;
  @override
  int get lookback => _maxPeriod(periods);

  @override
  IndicatorSeries compute(List<Candle> candles) {
    final vol = [for (final c in candles) c.volume];
    return IndicatorSeries(id, pane, [
      for (final p in periods) IndicatorLine('VOLMA$p', sma(vol, p)),
    ]);
  }
}

/// WR：威廉指标（副图，默认 14）。WR=(Hn−C)/(Hn−Ln)×100，区间 0..100。
class Wr extends BuiltinIndicator {
  Wr({List<int> periods = const [14]}) : periods = List.unmodifiable(periods);

  final List<int> periods;

  @override
  List<Object> get params => periods;

  @override
  String get id => 'WR';
  @override
  Pane get pane => Pane.sub;
  @override
  int get lookback => _maxPeriod(periods); // 仅依赖最近 n 根，精确

  @override
  IndicatorSeries compute(List<Candle> candles) => IndicatorSeries(id, pane, [
        for (final n in periods) IndicatorLine('WR$n', _line(candles, n)),
      ]);

  static List<double?> _line(List<Candle> candles, int n) {
    final out = List<double?>.filled(candles.length, null);
    for (var i = 0; i < candles.length; i++) {
      final r = _highLow(candles, i, n);
      out[i] = r.hh == r.ll ? 0.0 : (r.hh - candles[i].close) / (r.hh - r.ll) * 100.0;
    }
    return out;
  }
}

/// OBV：能量潮（副图，单线累计量）。依赖全历史，故全量重算。
class Obv extends BuiltinIndicator {
  const Obv();

  @override
  List<Object> get params => const [];

  @override
  String get id => 'OBV';
  @override
  Pane get pane => Pane.sub;

  @override
  IndicatorSeries compute(List<Candle> candles) {
    final out = List<double?>.filled(candles.length, null);
    var obv = 0.0;
    for (var i = 0; i < candles.length; i++) {
      if (i > 0) {
        final d = candles[i].close - candles[i - 1].close;
        if (d > 0) obv += candles[i].volume;
        if (d < 0) obv -= candles[i].volume;
      }
      out[i] = obv;
    }
    return IndicatorSeries(id, pane, [IndicatorLine('OBV', out)]);
  }
}

/// SAR：抛物线转向（主图散点）。路径相关（依赖历次转向），故全量重算。
class Sar extends BuiltinIndicator {
  const Sar({this.step = 0.02, this.maxAf = 0.2});

  final double step;
  final double maxAf;

  @override
  List<Object> get params => [step, maxAf];

  @override
  String get id => 'SAR';
  @override
  Pane get pane => Pane.main;

  @override
  IndicatorSeries compute(List<Candle> candles) {
    final n = candles.length;
    final out = List<double?>.filled(n, null);
    if (n >= 2) _fill(candles, out);
    return IndicatorSeries(id, pane, [IndicatorLine('SAR', out, style: LineStyle.points)]);
  }

  void _fill(List<Candle> candles, List<double?> out) {
    var up = candles[1].close >= candles[0].close;
    var af = step;
    var ep = up ? candles[1].high : candles[1].low;
    var sar = up ? candles[0].low : candles[0].high;
    for (var i = 1; i < candles.length; i++) {
      final prev = candles[i - 1];
      final prev2 = candles[i >= 2 ? i - 2 : i - 1];
      sar += af * (ep - sar);
      if (up) {
        sar = math.min(sar, math.min(prev.low, prev2.low));
        if (candles[i].low < sar) {
          up = false; // 转空
          sar = ep;
          ep = candles[i].low;
          af = step;
        } else if (candles[i].high > ep) {
          ep = candles[i].high;
          af = math.min(af + step, maxAf);
        }
      } else {
        sar = math.max(sar, math.max(prev.high, prev2.high));
        if (candles[i].high > sar) {
          up = true; // 转多
          sar = ep;
          ep = candles[i].high;
          af = step;
        } else if (candles[i].low < ep) {
          ep = candles[i].low;
          af = math.min(af + step, maxAf);
        }
      }
      out[i] = sar;
    }
  }
}

/// 一键注册全部内置指标。
abstract final class Indicators {
  static void registerDefaults() {
    final defaults = <Indicator>[
      Ma(), Ema(), const Boll(), const Sar(), const Macd(), //
      const Kdj(), Rsi(), Wr(), const Obv(), VolMa(),
    ];
    defaults.forEach(ChartRegistry.register);
  }
}
