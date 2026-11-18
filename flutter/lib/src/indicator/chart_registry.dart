import 'indicator.dart';

/// 指标注册表。内置指标与接入方自定义指标统一登记，按 id 查找（保持注册顺序）。
abstract final class ChartRegistry {
  static final Map<String, Indicator> _indicators = <String, Indicator>{};

  static void register(Indicator indicator) => _indicators[indicator.id] = indicator;

  static Indicator? get(String id) => _indicators[id];

  static List<Indicator> all() => List.unmodifiable(_indicators.values);

  static void unregister(String id) => _indicators.remove(id);

  static void clear() => _indicators.clear();
}
