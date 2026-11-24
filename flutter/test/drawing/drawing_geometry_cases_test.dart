// F1-01 画线几何：12 个工具各 3 组锚点，期望坐标在 testdata/drawing/geometry_cases.json，
// 由 gen_geometry_cases.py 照定义独立算出（不看 Dart 代码）。误差不超过 0.5 像素。
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:chartkit_flutter/chartkit_flutter.dart';
import 'package:chartkit_flutter/src/drawing/drawing_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

const _tolerance = 0.5;

void main() {
  final json = jsonDecode(File('testdata/drawing/geometry_cases.json').readAsStringSync()) as Map;
  final proj = json['projection'] as Map;
  final interval = proj['intervalMillis'] as int;
  final projection = DrawingProjection(
    rect:
        Rect.fromLTWH(0, 0, (proj['width'] as num).toDouble(), (proj['height'] as num).toDouble()),
    timeline: DrawingTimeline([
      for (var i = 0; i < (proj['candles'] as int); i++)
        Candle(time: i * interval, open: 150, high: 150, low: 150, close: 150),
    ], interval),
    rightFloat: (proj['rightFloat'] as num).toDouble(),
    candleWidth: (proj['candleWidth'] as num).toDouble(),
    priceMin: (proj['priceMin'] as num).toDouble(),
    priceMax: (proj['priceMax'] as num).toDouble(),
  );

  List<double> nums(Object? list) => [for (final v in list! as List) (v as num).toDouble()];

  void expectClose(List<double> actual, List<double> expected, String what) {
    expect(actual.length, expected.length, reason: what);
    for (var i = 0; i < actual.length; i++) {
      expect((actual[i] - expected[i]).abs(), lessThanOrEqualTo(_tolerance),
          reason: '$what[$i]: got ${actual[i]}, want ${expected[i]}');
    }
  }

  final cases = json['cases'] as List;
  test('there are 3 cases for each of the 12 tools', () {
    for (final tool in DrawingTool.values) {
      expect(cases.where((c) => (c as Map)['tool'] == tool.name).length, 3, reason: tool.name);
    }
  });

  for (final c in cases.cast<Map>()) {
    test(c['name'] as String, () {
      final tool = DrawingTool.byName(c['tool'] as String)!;
      final anchors = [
        for (final a in c['anchors'] as List)
          DrawingAnchor(((a as List)[0] as num).toInt() * interval, (a[1] as num).toDouble()),
      ];
      final shape = shapeOf(
        Drawing(
          id: 'x',
          tool: tool,
          anchors: anchors,
          style: const DrawingStyle(color: Color(0xFF000000)),
        ),
        projection,
      );
      final e = c['expect'] as Map;
      final handles = e['handles'] as List;
      final segments = e['segments'] as List;
      final areas = e['areas'] as List;
      expect(shape.handles.length, handles.length, reason: 'handles');
      for (var i = 0; i < handles.length; i++) {
        expectClose([shape.handles[i].dx, shape.handles[i].dy], nums(handles[i]), 'handle $i');
      }
      expect(shape.segments.length, segments.length, reason: 'segments');
      for (var i = 0; i < segments.length; i++) {
        final (a, b) = shape.segments[i];
        expectClose([a.dx, a.dy, b.dx, b.dy], nums(segments[i]), 'segment $i');
      }
      expect(shape.areas.length, areas.length, reason: 'areas');
      for (var i = 0; i < areas.length; i++) {
        final r = shape.areas[i];
        expectClose([r.left, r.top, r.right, r.bottom], nums(areas[i]), 'area $i');
      }
      final stats = e['stats'] as Map?;
      if (stats != null) {
        final s = positionStats(
          long: tool == DrawingTool.longPosition,
          entry: anchors[0].price,
          target: anchors[1].price,
          stop: anchors[2].price,
        );
        expect(s.reward, closeTo((stats['reward'] as num).toDouble(), 1e-9));
        expect(s.risk, closeTo((stats['risk'] as num).toDouble(), 1e-9));
        expect(s.ratio, closeTo((stats['ratio'] as num).toDouble(), 1e-9));
      }
    });
  }
}
