import 'dart:math' as math;

/// 指标计算的纯函数工具。全部无副作用，便于单测。

/// 简单移动平均 SMA(period)。前 period-1 个位置为 null（无值，不连线）。
List<double?> sma(List<double> src, int period) {
  final out = List<double?>.filled(src.length, null);
  if (period <= 0) return out;
  var sum = 0.0;
  for (var i = 0; i < src.length; i++) {
    sum += src[i];
    if (i >= period) sum -= src[i - period];
    if (i >= period - 1) out[i] = sum / period;
  }
  return out;
}

/// 指数移动平均 EMA(period)，系数 k = 2/(period+1)，以 src[0] 播种。全程非空、连续。
List<double> ema(List<double> src, int period) {
  if (src.isEmpty) return const [];
  final k = 2.0 / (period + 1);
  final out = List<double>.filled(src.length, 0);
  var prev = src[0];
  out[0] = prev;
  for (var i = 1; i < src.length; i++) {
    prev += k * (src[i] - prev);
    out[i] = prev;
  }
  return out;
}

/// 标准 Bollinger Band：中轨 MB = SMA(period)，MD 为以 MB 为均值的总体标准差（÷period），
/// 上轨 UP = MB + k·MD，下轨 DN = MB − k·MD。三条等长，前 period-1 为 null。
({List<double?> up, List<double?> mb, List<double?> dn}) boll(
  List<double> src,
  int period,
  double k,
) {
  final mb = sma(src, period);
  final up = List<double?>.filled(src.length, null);
  final dn = List<double?>.filled(src.length, null);
  for (var i = 0; i < src.length; i++) {
    final mean = mb[i];
    if (mean == null) continue;
    var sq = 0.0;
    for (var j = i - period + 1; j <= i; j++) {
      final d = src[j] - mean;
      sq += d * d;
    }
    final md = math.sqrt(sq / period);
    up[i] = mean + k * md;
    dn[i] = mean - k * md;
  }
  return (up: up, mb: mb, dn: dn);
}
