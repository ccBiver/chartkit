/// 数字格式化工具，行为与 Compose 版 NumberFormat.kt 保持一致。
library;

double _pow10(int digits) {
  var p = 1.0;
  for (var i = 0; i < digits; i++) {
    p *= 10;
  }
  return p;
}

/// 定点小数：始终保留 [digits] 位，且不会输出 "-0.00"。
String fixed(double v, int digits) {
  if (v.isNaN) return 'NaN';
  if (v.isInfinite) return v.isNegative ? '-∞' : '∞';
  final p = _pow10(digits);
  final scaled = (v.abs() * p).round();
  final unit = p.round();
  final frac = digits > 0 ? '.${(scaled % unit).toString().padLeft(digits, '0')}' : '';
  final sign = v < 0 && scaled != 0 ? '-' : '';
  return '$sign${scaled ~/ unit}$frac';
}

/// 四舍五入到 [digits] 位后去掉多余尾零（保留至少一位小数，如 `3.0`）。
String trimmed(double v, int digits) {
  if (v.isNaN) return '--';
  final p = _pow10(digits);
  return ((v * p).roundToDouble() / p).toString();
}

/// 左补零到 2 位。
String pad2(int n) => n < 10 ? '0$n' : '$n';

/// 大数缩写（成交量等）：1.20K / 3.40M / 5.60B。
String abbrevNum(double v) {
  final a = v.abs();
  if (a >= 1e9) return '${fixed(v / 1e9, 2)}B';
  if (a >= 1e6) return '${fixed(v / 1e6, 2)}M';
  if (a >= 1e3) return '${fixed(v / 1e3, 2)}K';
  return fixed(v, 2);
}
