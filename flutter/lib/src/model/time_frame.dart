/// K 线周期。[millis] 为该周期对应的毫秒数，用于实时归并（判断 tick 属于当前根还是新根）。
enum TimeFrame {
  m1(60000),
  m5(300000),
  m15(900000),
  m30(1800000),
  h1(3600000),
  h2(7200000),
  h4(14400000),
  h6(21600000),
  h12(43200000),
  d1(86400000),
  w1(604800000),

  /// 近似 30 天，仅用于 tick 归并的粗略判断。
  mn1(2592000000);

  const TimeFrame(this.millis);

  final int millis;

  /// 给定时间戳所属周期的起始时间戳（按 UTC 对齐）。
  int openTimeOf(int timestamp) => timestamp - (timestamp % millis);
}
