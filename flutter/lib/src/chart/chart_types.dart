import 'package:flutter/widgets.dart';

/// 图表类型。
///
/// [timeLine] 是分时：收盘价折线加填充，不画主图指标和最高最低价标注。
/// [ohlc]（美国线）、[line]（折线图）、[area]（面积图）照常画主图指标；
/// 折线图和面积图只看收盘价，价格区间也只按收盘价算。
enum ChartMode {
  candle,
  timeLine,
  ohlc,
  line,
  area;

  /// 只画收盘价的类型（折线图、面积图）。
  bool get closeOnly => this == line || this == area;
}

/// 涨跌配色方案。
enum UpDownColor { greenUpRedDown, redUpGreenDown }

/// Logo 水印位置（默认主图中心，类 Binance 水印）。
enum LogoPosition {
  center(Alignment.center),
  topStart(AlignmentDirectional.topStart),
  topEnd(AlignmentDirectional.topEnd),
  bottomStart(AlignmentDirectional.bottomStart),
  bottomEnd(AlignmentDirectional.bottomEnd);

  const LogoPosition(this.alignment);

  final AlignmentGeometry alignment;
}

/// 十字光标 Y 轴行为：[snapToClose] 吸附到收盘价；[free] 跟随手指（右轴显示手指处价格）。
enum CrosshairMode { snapToClose, free }

/// 现价线/标签的取值方式。
enum LastPriceMode {
  /// 业内标准：恒取**最新成交价**（数据最后一根的收盘价），与滚动位置无关。
  /// 现价落在可见价格区间之外时，标签贴到主图上/下边缘。
  latest,

  /// 跟随**当前屏幕最右边那根可见 K 线**的收盘价：值与颜色都随之。
  rightmostVisible,
}

/// 十字光标/详情浮窗的消失方式：
///  - [onRelease] 松手即消失。浮窗内买卖行不可点击，改为点击蜡烛上的标记跳转。
///  - [persistent] 松手不消失，点击空白或拖动/缩放图表才消失。浮窗买卖行可点击跳转。
enum CrosshairDismiss { onRelease, persistent }

/// 十字光标的触发方式。
enum CrosshairTrigger {
  /// 仅长按。
  longPress,

  /// 单击或长按（单击空白处显示，再次单击关闭）。
  tapOrLongPress,
}

/// 盘口买一/卖一贴纸数据：贴在现价标签左侧，卖一在上、买一在下。
/// 价格 <= 0 的一侧不显示；颜色为空时用涨跌色（买=涨色，卖=跌色）。
@immutable
class ChartOrderbook {
  const ChartOrderbook({
    required this.bid,
    required this.ask,
    this.bidLabel = 'B',
    this.askLabel = 'S',
    this.bidColor,
    this.askColor,
  });

  final double bid;
  final double ask;
  final String bidLabel;
  final String askLabel;
  final Color? bidColor;
  final Color? askColor;
}

/// 买卖标记（覆盖物）。[time] 落在所属 K 线的时间区间内即可。
/// 买入标记画在 K 线下方、卖出画在上方。
@immutable
class TradeMark {
  const TradeMark({required this.time, required this.isBuy, this.price, this.count});

  final int time;
  final bool isBuy;
  final double? price;

  /// 该 K 线该方向的成交笔数。
  final int? count;
}

/// 十字光标详情浮窗的字段标签（可本地化覆盖；默认英文缩写）。
@immutable
class ChartLabels {
  const ChartLabels({
    this.time = 'Time',
    this.open = 'O',
    this.high = 'H',
    this.low = 'L',
    this.close = 'C',
    this.change = 'Chg',
    this.changePct = 'Chg%',
    this.amplitude = 'Amp',
    this.volume = 'Vol',
    this.turnover = 'Turnover',
    this.buy = 'Buy',
    this.sell = 'Sell',
  });

  final String time;
  final String open;
  final String high;
  final String low;
  final String close;
  final String change;
  final String changePct;
  final String amplitude;
  final String volume;
  final String turnover;
  final String buy;
  final String sell;
}

/// 详情浮窗的一行：标签 + 数据。[color]/[labelColor] 为空则用默认文字色；
/// [onTap] 非空则该行可点击（如买卖记录跳转）。
@immutable
class CrosshairDetailRow {
  const CrosshairDetailRow(this.label, this.value, {this.color, this.labelColor, this.onTap});

  final String label;
  final String value;
  final Color? color;
  final Color? labelColor;
  final VoidCallback? onTap;
}
