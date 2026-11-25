import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;

import '../model/candle.dart';

/// 指标所在窗格：主图叠加 或 独立副图。
enum Pane { main, sub }

/// 单条输出的绘制风格：折线 / 柱状 / 散点（如 SAR）。
enum LineStyle { line, histogram, points }

/// 指标的一条输出序列，与 K 线列表**等长、按索引对齐**。
/// [values] 中的 `null` 表示该位置无值（如均线前置窗口）；渲染层**跨 null 不连线**，
/// 而不是画到 0。
@immutable
class IndicatorLine {
  const IndicatorLine(this.name, this.values, {this.style = LineStyle.line});

  final String name;
  final List<double?> values;
  final LineStyle style;

  IndicatorLine copyWith({List<double?>? values}) =>
      IndicatorLine(name, values ?? this.values, style: style);
}

/// 两条线之间的填充（如 BOLL 上下轨之间的底色）。[upper]、[lower] 是 [IndicatorSeries.lines] 的下标。
/// 只对主图指标生效，画在蜡烛和指标线的下面；两条线在某根都有值才填。
@immutable
class IndicatorFill {
  const IndicatorFill({required this.upper, required this.lower, required this.color});

  final int upper;
  final int lower;
  final Color color;

  @override
  bool operator ==(Object other) =>
      other is IndicatorFill && other.upper == upper && other.lower == lower && other.color == color;

  @override
  int get hashCode => Object.hash(upper, lower, color);
}

/// 一个指标的完整计算结果：可包含多条线/柱（如 MACD = DIF + DEA + 柱）。
@immutable
class IndicatorSeries {
  /// 所有线必须等长，保证渲染层按索引对齐时不越界；否则抛 [ArgumentError]。
  /// [fill] 非空时在它指定的两条线之间填色（见 [IndicatorFill]）。
  IndicatorSeries(this.id, this.pane, List<IndicatorLine> lines, {this.fill})
      : lines = List.unmodifiable(lines) {
    final n = size;
    if (lines.any((l) => l.values.length != n)) {
      throw ArgumentError('IndicatorSeries[$id]: all lines must have the same length ($n)');
    }
  }

  final String id;
  final Pane pane;
  final List<IndicatorLine> lines;

  /// 两条线之间的填充；为空时不填。
  final IndicatorFill? fill;

  int get size => lines.isEmpty ? 0 : lines.first.values.length;

  IndicatorSeries copyWith({List<IndicatorLine>? lines}) =>
      IndicatorSeries(id, pane, lines ?? this.lines, fill: fill);
}

/// 指标计算单元。无副作用：输入 K 线，输出独立的 [IndicatorSeries]，**不写回 Candle**。
///
/// 扩展方式：继承本类并 `ChartRegistry.register`，或用 [indicator] 由一个公式直接创建。
abstract class Indicator {
  const Indicator();

  /// [lookback] 的默认值：每次全量重算。
  static const int fullRecompute = 0x7FFFFFFF;

  /// 唯一标识，用于注册/查找/选择副图。
  String get id;

  /// 主图叠加还是独立副图。
  Pane get pane;

  /// 末根增量重算窗口：计算「最新一根」的指标值所需的回看根数。
  ///  - 有限回看（MA/BOLL）：= 周期数，结果精确；
  ///  - 递归型（EMA/MACD/KDJ/RSI）：取周期的若干倍，使种子影响衰减到浮点精度内；
  ///  - 默认 [fullRecompute]：每次全量重算（适合依赖全历史的指标）。
  int get lookback => fullRecompute;

  /// 全量计算：输出与 [candles] 等长、按索引对齐的 [IndicatorSeries]。
  IndicatorSeries compute(List<Candle> candles);
}

class _FormulaIndicator extends Indicator {
  const _FormulaIndicator(this.id, this.pane, this.lookback, this._formula);

  @override
  final String id;
  @override
  final Pane pane;
  @override
  final int lookback;
  final List<IndicatorLine> Function(List<Candle> candles) _formula;

  @override
  IndicatorSeries compute(List<Candle> candles) => IndicatorSeries(id, pane, _formula(candles));
}

/// 用一个公式快速创建指标：
///
/// ```dart
/// final tp = indicator('TP', compute: (candles) => [
///   IndicatorLine('TP', [for (final c in candles) (c.high + c.low + c.close) / 3]),
/// ]);
/// ```
Indicator indicator(
  String id, {
  Pane pane = Pane.sub,
  int lookback = Indicator.fullRecompute,
  required List<IndicatorLine> Function(List<Candle> candles) compute,
}) =>
    _FormulaIndicator(id, pane, lookback, compute);
