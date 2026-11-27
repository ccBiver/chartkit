import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'script_output.dart';

/// 点选命中范围：在图元画出来的形状外再放宽这么多逻辑像素，照顾手指。
const double scriptHitSlop = 12;

/// 点到的脚本图元的类型，和输出里的数组一一对应。
enum ScriptHitKind {
  /// `markers` 里的一个点。
  marker,

  /// `trades` 里的一笔成交。
  trade,

  /// `labels`。
  label,

  /// `lines`（线段）。
  line,

  /// `hlines`（水平价位线）。
  hline,

  /// `boxes`。
  box,
}

/// `KLineChart.onScriptTap` 回调的内容：点到的是哪个脚本的哪个图元。
///
/// 用 [kind] 和 [index]（以及标记的 [point]）到 [output] 的对应数组里取原图元，例如
/// `hit.output.labels[hit.index]`；`markers` 是 `hit.output.markers[hit.index]` 这一组里的第 [point] 个点。
@immutable
class ScriptHit {
  const ScriptHit({
    required this.scriptId,
    required this.output,
    required this.kind,
    required this.index,
    required this.pane,
    required this.position,
    this.point,
    this.id,
    this.time,
    this.price,
    this.time2,
    this.price2,
  });

  /// 设置这份输出时用的 id（`ScriptOutputController.setJson` 的第一个参数）。
  final String scriptId;

  /// 这份脚本输出。
  final ScriptOutput output;

  final ScriptHitKind kind;

  /// 图元在输出对应数组里的序号。
  final int index;

  /// 只对 [ScriptHitKind.marker]：组内第几个点。
  final int? point;

  /// 图元自带的 id：水平线的 `id`、成交的 `id`；其余类型为 null。
  final String? id;

  /// 点在哪个窗格：主图，或脚本自己的副图。
  final ScriptPane pane;

  /// 锚点时间（毫秒）：标记、成交、标签是它所在的那根；线段是 `t1`，方框是 `t1`。水平线为 null。
  final int? time;

  /// 锚点价格：标记的价位（`top`/`bottom` 位置的标记没有价位，为 null）、成交价、标签的 `p`、
  /// 水平线的 `price`、线段的 `p1`、方框的 `top`。
  final double? price;

  /// 线段的 `t2`、方框的 `t2`；其余为 null。
  final int? time2;

  /// 线段的 `p2`、方框的 `bottom`；其余为 null。
  final double? price2;

  /// 点击位置（图表本地坐标）。
  final Offset position;

  @override
  String toString() => 'ScriptHit($scriptId, ${kind.name}#$index${point == null ? '' : '.$point'})';
}
