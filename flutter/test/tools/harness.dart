// 图表工具测试共用：把图包进带 key 的 RepaintBoundary、取像素、对参考图。
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:chartkit_flutter/chartkit_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

final shotKey = GlobalKey();

Widget frame(Widget child, {Size size = const Size(400, 460)}) => MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Center(
        child: RepaintBoundary(key: shotKey, child: SizedBox.fromSize(size: size, child: child)),
      ),
    );

/// 渲染 [chart]，把视口设成每根 [cw]、偏移 [scroll]，等动画走完。
Future<void> pumpChart(WidgetTester tester, KLineChartState state, Widget chart,
    {Size size = const Size(400, 460), double cw = 6, double scroll = 0}) async {
  await tester.pumpWidget(frame(chart, size: size));
  state.setViewport(candleWidth: cw, scrollOffset: scroll);
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();
}

Future<void> matchGolden(String name) => expectLater(
    find.byKey(shotKey), matchesGoldenFile('../../testdata/chart_tools/goldens/$name.png'));

/// 一帧的像素（RGBA）。
/// 按设备像素比截图，[at] 用逻辑坐标取。
class Pixels {
  Pixels(this.width, this.height, this.bytes, this.ratio);

  final int width;
  final int height;
  final ByteData bytes;
  final double ratio;

  Color at(double x, double y) {
    final xi = (x * ratio).floor().clamp(0, width - 1);
    final yi = (y * ratio).floor().clamp(0, height - 1);
    final o = (yi * width + xi) * 4;
    return Color.fromARGB(
        bytes.getUint8(o + 3), bytes.getUint8(o), bytes.getUint8(o + 1), bytes.getUint8(o + 2));
  }

  /// (x, y) 上下各 [r] 个设备像素内有接近 [c] 的颜色（细线落在像素边界上时颜色会变淡）。
  bool hasNear(double x, double y, Color c, {int r = 1, double tol = 0.08}) {
    for (var d = -r; d <= r; d++) {
      if (near(at(x, y + d / ratio), c, tol)) return true;
    }
    return false;
  }

  /// (x, y) 上下各 [r] 个设备像素内 [c] 盖在 [bg] 上的最大覆盖率（0..1）。
  /// 按每个通道反推 (像素 - 背景) / (颜色 - 背景)；通道之间对不上的像素（别的颜色）算 0。
  double coverage(double x, double y, Color c, Color bg, {int r = 1}) {
    var best = 0.0;
    for (var d = -r; d <= r; d++) {
      final p = at(x, y + d / ratio);
      final est = <double>[];
      for (final (pv, cv, bv) in [(p.r, c.r, bg.r), (p.g, c.g, bg.g), (p.b, c.b, bg.b)]) {
        if ((cv - bv).abs() < 0.1) {
          if ((pv - bv).abs() > (cv - bv).abs() + 0.05) est.add(-1);
          continue;
        }
        est.add((pv - bv) / (cv - bv));
      }
      if (est.isEmpty || est.any((e) => e < 0)) continue;
      final lo = est.reduce((a, b) => a < b ? a : b), hi = est.reduce((a, b) => a > b ? a : b);
      if (hi - lo > 0.2) continue;
      if (lo > best) best = lo;
    }
    return best;
  }

  /// 两帧不同的像素个数。
  int diffCount(Pixels other) {
    var n = 0;
    for (var i = 0; i < bytes.lengthInBytes; i += 4) {
      if (bytes.getUint32(i) != other.bytes.getUint32(i)) n++;
    }
    return n;
  }
}

Future<Pixels> capture(WidgetTester tester, {GlobalKey? key}) async {
  late Pixels px;
  await tester.runAsync(() async {
    final boundary = (key ?? shotKey).currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final ratio = tester.view.devicePixelRatio;
    final ui.Image image = await boundary.toImage(pixelRatio: ratio);
    px = Pixels(image.width, image.height, (await image.toByteData())!, ratio);
    image.dispose();
  });
  return px;
}

/// 颜色接近（每个通道差不超过 [tol]，0..1）。
bool near(Color a, Color b, [double tol = 0.08]) =>
    (a.r - b.r).abs() <= tol && (a.g - b.g).abs() <= tol && (a.b - b.b).abs() <= tol;

const _arrays = [
  'series', 'hlines', 'fills', 'markers', 'trades', 'bg', 'barColors', 'candles', 'lines', //
  'boxes', 'labels', 'tables',
];

/// 脚本输出只留 [keep] 里的图元数组，其余清空。
Map<String, dynamic> onlyFields(String json, Set<String> keep) {
  final j = jsonDecode(json) as Map<String, dynamic>;
  for (final k in _arrays) {
    if (!keep.contains(k)) j[k] = [];
  }
  return j;
}
