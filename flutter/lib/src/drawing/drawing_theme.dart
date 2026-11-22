import 'dart:ui';

import 'package:flutter/foundation.dart';

/// 画线的公共配色。线本身的颜色在每条画线的 `DrawingStyle` 里；这里是各工具共用的几种颜色。
/// 为空的项取图表主题：盈利区取涨色、亏损区取跌色、端点填充取背景色、色块上的文字取现价标签文字色。
@immutable
class DrawingTheme {
  const DrawingTheme({this.profit, this.loss, this.handleFill, this.labelText});

  /// 头寸的盈利区、价格区间测量向上时的颜色。
  final Color? profit;

  /// 头寸的亏损区、价格区间测量向下时的颜色。
  final Color? loss;

  /// 选中时端点圆点的填充色。
  final Color? handleFill;

  /// 实色标签（盈亏比、测量结果、波浪编号）上的文字颜色。
  final Color? labelText;
}

/// 画线上的文字（可本地化覆盖；默认英文）。
@immutable
class DrawingLabels {
  const DrawingLabels({
    this.entry = 'Entry',
    this.target = 'Target',
    this.stop = 'Stop',
    this.riskReward = 'R:R',
    this.bars = 'bars',
  });

  final String entry;
  final String target;
  final String stop;

  /// 盈亏比前缀。
  final String riskReward;

  /// 价格区间测量里「N 根」的单位。
  final String bars;
}
