import 'dart:ui';

import 'package:flutter/foundation.dart';

/// 画线工具。[pointCount] 是新建时要点的点数。
///
/// 枚举名会写进序列化结果（[Drawing.toJson]），只能往后加，不能改名。
enum DrawingTool {
  horizontalLine(1),
  verticalLine(1),
  trendLine(2),
  ray(2),
  rectangle(2),
  fibRetracement(2),
  priceRange(2),
  longPosition(2),
  shortPosition(2),
  gannFan(2),
  pitchfork(3),
  elliottWave(6);

  const DrawingTool(this.pointCount);

  final int pointCount;

  bool get isPosition => this == longPosition || this == shortPosition;

  static DrawingTool? byName(String? name) {
    for (final t in values) {
      if (t.name == name) return t;
    }
    return null;
  }
}

/// 斐波那契回撤的默认档位。
const List<double> defaultFibLevels = [0, 0.236, 0.382, 0.5, 0.618, 0.786, 1];

/// 斐波那契回撤可选的全部档位（含扩展位），供调用方做「显示哪几档」的选择界面。
const List<double> allFibLevels = [
  0, 0.236, 0.382, 0.5, 0.618, 0.786, 1, 1.272, 1.618, 2, 2.618, //
];

/// 画线锚点：K 线开盘时间（毫秒）+ 价格。与屏幕坐标无关，缩放、平移、切周期后仍落在同一时间和价位。
@immutable
class DrawingAnchor {
  const DrawingAnchor(this.time, this.price);

  final int time;
  final double price;

  DrawingAnchor copyWith({int? time, double? price}) =>
      DrawingAnchor(time ?? this.time, price ?? this.price);

  @override
  bool operator ==(Object other) =>
      other is DrawingAnchor && other.time == time && other.price == price;

  @override
  int get hashCode => Object.hash(time, price);

  @override
  String toString() => 'DrawingAnchor($time, $price)';
}

/// 一条画线的样式。颜色由调用方给，库里不设默认色。
@immutable
class DrawingStyle {
  const DrawingStyle({required this.color, this.width = 1}) : assert(width > 0);

  final Color color;

  /// 线宽（逻辑像素）。
  final double width;

  DrawingStyle copyWith({Color? color, double? width}) =>
      DrawingStyle(color: color ?? this.color, width: width ?? this.width);

  @override
  bool operator ==(Object other) =>
      other is DrawingStyle && other.color == color && other.width == width;

  @override
  int get hashCode => Object.hash(color, width);
}

/// 一条画线（不可变）。
///
/// [anchors] 的个数等于 [DrawingTool.pointCount]，只有多头/空头头寸是 3 个：
/// 入场、目标、止损（新建时点 2 下：入场和目标，止损按 1:1 自动放在入场另一侧，之后可以拖）。
@immutable
class Drawing {
  Drawing({
    required this.id,
    required this.tool,
    required List<DrawingAnchor> anchors,
    required this.style,
    this.locked = false,
    List<double>? fibLevels,
  })  : anchors = List.unmodifiable(anchors),
        fibLevels = List.unmodifiable(fibLevels ?? defaultFibLevels),
        assert(anchors.length == anchorCountOf(tool));

  final String id;
  final DrawingTool tool;
  final List<DrawingAnchor> anchors;
  final DrawingStyle style;

  /// 锁定后不能拖动（仍可选中、删除、改样式）。
  final bool locked;

  /// 斐波那契回撤显示的档位，其他工具忽略。
  final List<double> fibLevels;

  /// [tool] 建好之后的锚点个数。
  static int anchorCountOf(DrawingTool tool) => tool.isPosition ? 3 : tool.pointCount;

  Drawing copyWith({
    List<DrawingAnchor>? anchors,
    DrawingStyle? style,
    bool? locked,
    List<double>? fibLevels,
  }) =>
      Drawing(
        id: id,
        tool: tool,
        anchors: anchors ?? this.anchors,
        style: style ?? this.style,
        locked: locked ?? this.locked,
        fibLevels: fibLevels ?? this.fibLevels,
      );

  /// 序列化。颜色存 ARGB 整数，锚点存 `[时间, 价格]`。
  Map<String, Object?> toJson() => {
        'id': id,
        'tool': tool.name,
        'points': [
          for (final a in anchors) [a.time, a.price],
        ],
        'color': style.color.toARGB32(),
        'width': style.width,
        if (locked) 'locked': true,
        if (tool == DrawingTool.fibRetracement) 'fib': fibLevels,
      };

  /// 反序列化；字段缺失、类型不对或工具不认识时返回 null（调用方跳过这一条即可）。
  static Drawing? fromJson(Object? json) {
    if (json is! Map) return null;
    final tool = DrawingTool.byName(json['tool'] as String?);
    final id = json['id'];
    final points = json['points'];
    final color = json['color'];
    if (tool == null || id is! String || points is! List || color is! int) return null;
    final anchors = <DrawingAnchor>[];
    for (final p in points) {
      if (p is! List || p.length != 2) return null;
      final t = p[0];
      final v = p[1];
      if (t is! num || v is! num || !v.isFinite) return null;
      anchors.add(DrawingAnchor(t.toInt(), v.toDouble()));
    }
    if (anchors.length != anchorCountOf(tool)) return null;
    final width = json['width'];
    final fib = json['fib'];
    return Drawing(
      id: id,
      tool: tool,
      anchors: anchors,
      style: DrawingStyle(
        color: Color(color),
        width: width is num && width > 0 ? width.toDouble() : 1,
      ),
      locked: json['locked'] == true,
      fibLevels: fib is List
          ? [
              for (final l in fib)
                if (l is num) l.toDouble()
            ]
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Drawing &&
          other.id == id &&
          other.tool == tool &&
          listEquals(other.anchors, anchors) &&
          other.style == style &&
          other.locked == locked &&
          listEquals(other.fibLevels, fibLevels);

  @override
  int get hashCode =>
      Object.hash(id, tool, Object.hashAll(anchors), style, locked, Object.hashAll(fibLevels));

  @override
  String toString() => 'Drawing($id, ${tool.name}, $anchors)';
}
