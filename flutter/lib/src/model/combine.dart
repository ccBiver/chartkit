import 'dart:math' as math;

import 'candle.dart';

/// 合成图的运算。
enum CombineOp {
  add,
  subtract,
  multiply,
  divide;

  double apply(double a, double b) => switch (this) {
        add => a + b,
        subtract => a - b,
        multiply => a * b,
        divide => a / b,
      };
}

/// 两根同一开盘时间的 K 线合成一根：开高低收各自运算，
/// 最高、最低再取四个结果里的最大、最小，保证 K 线成立。
/// 成交量、成交额为 0。结果里有非有限数（如除以 0）时返回 null。
Candle? combineCandle(Candle a, Candle b, CombineOp op) {
  final o = op.apply(a.open, b.open);
  final h = op.apply(a.high, b.high);
  final l = op.apply(a.low, b.low);
  final c = op.apply(a.close, b.close);
  if (!o.isFinite || !h.isFinite || !l.isFinite || !c.isFinite) return null;
  return Candle(
    time: a.time,
    open: o,
    high: math.max(math.max(o, c), math.max(h, l)),
    low: math.min(math.min(o, c), math.min(h, l)),
    close: c,
  );
}

/// 两个品种的 K 线按开盘时间对齐后合成一组新 K 线（[a] op [b]，如金银比是 XAUUSD ÷ XAGUSD）。
///
/// 只保留两边都有的开盘时间，某一边缺的那根直接跳过，不补值；
/// 合成结果有非有限数的那根也跳过。两组输入都要按时间升序，输出同样升序。
/// 这是数据处理，和画图无关，以后可以挪到 App 侧。
List<Candle> combineCandles(List<Candle> a, List<Candle> b, CombineOp op) {
  final out = <Candle>[];
  var i = 0, j = 0;
  while (i < a.length && j < b.length) {
    final ta = a[i].time, tb = b[j].time;
    if (ta < tb) {
      i++;
    } else if (tb < ta) {
      j++;
    } else {
      final c = combineCandle(a[i], b[j], op);
      if (c != null) out.add(c);
      i++;
      j++;
    }
  }
  return out;
}
