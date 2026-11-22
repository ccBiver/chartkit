import 'dart:convert';
import 'dart:ui';

import 'package:chartkit_flutter/chartkit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

const _blue = Color(0xFF3B82F6);
const _style = DrawingStyle(color: _blue);

Drawing _sample(DrawingTool tool) => Drawing(
      id: tool.name,
      tool: tool,
      anchors: [
        for (var i = 0; i < Drawing.anchorCountOf(tool); i++)
          DrawingAnchor(1700000000000 + i * 60000, 3537.22 + i),
      ],
      style: const DrawingStyle(color: Color(0x80F0A020), width: 2),
    );

void main() {
  group('serialization', () {
    test('every tool survives a JSON round trip', () {
      for (final tool in DrawingTool.values) {
        final d = _sample(tool);
        final back = Drawing.fromJson(jsonDecode(jsonEncode(d.toJson())));
        expect(back, d, reason: tool.name);
      }
    });

    test('lock state and fibonacci levels are kept', () {
      final d = _sample(DrawingTool.fibRetracement)
          .copyWith(locked: true, fibLevels: const [0.382, 0.618, 1.618]);
      final json = d.toJson();
      expect(json['locked'], true);
      expect(json['fib'], [0.382, 0.618, 1.618]);
      expect(Drawing.fromJson(jsonDecode(jsonEncode(json))), d);
    });

    test('anchor counts follow the tool, positions carry entry, target and stop', () {
      for (final tool in DrawingTool.values) {
        expect(Drawing.anchorCountOf(tool), tool.isPosition ? 3 : tool.pointCount);
      }
      expect(DrawingTool.elliottWave.pointCount, 6);
      expect(DrawingTool.pitchfork.pointCount, 3);
      expect(DrawingTool.horizontalLine.pointCount, 1);
    });

    test('broken or unknown entries are skipped, not fatal', () {
      final good = _sample(DrawingTool.trendLine).toJson();
      final bad = [
        null,
        'x',
        {...good, 'tool': 'laser'},
        {...good, 'id': 3},
        {...good, 'color': '#fff'},
        {
          ...good,
          'points': [
            [1, 2],
          ],
        },
        {
          ...good,
          'points': [
            [1, 'a'],
            [2, 3],
          ],
        },
      ];
      for (final b in bad) {
        expect(Drawing.fromJson(b), isNull, reason: '$b');
      }
      final c = DrawingController(style: _style);
      addTearDown(c.dispose);
      c.loadJson({
        'version': 1,
        'drawings': [...bad, good],
      });
      expect(c.drawings.single.id, 'trendLine');
    });

    test('a bad width falls back to 1', () {
      final json = {..._sample(DrawingTool.ray).toJson(), 'width': -3};
      expect(Drawing.fromJson(json)!.style.width, 1);
    });
  });

  group('DrawingController', () {
    late DrawingController c;
    late int saves;

    setUp(() {
      saves = 0;
      c = DrawingController(style: _style, onChanged: () => saves++);
    });
    tearDown(() => c.dispose());

    test('placing the last point creates, selects and leaves the tool', () {
      c.tool = DrawingTool.trendLine;
      c.addDraftPoint(const DrawingAnchor(1, 10));
      expect(c.draft.length, 1);
      expect(c.drawings, isEmpty);
      expect(saves, 0);
      c.addDraftPoint(const DrawingAnchor(2, 20));
      expect(c.drawings.single.anchors, const [DrawingAnchor(1, 10), DrawingAnchor(2, 20)]);
      expect(c.drawings.single.style, _style);
      expect(c.selectedId, c.drawings.single.id);
      expect(c.tool, isNull);
      expect(c.draft, isEmpty);
      expect(saves, 1);
    });

    test('switching tools drops the unfinished drawing', () {
      c.tool = DrawingTool.pitchfork;
      c.addDraftPoint(const DrawingAnchor(1, 10));
      c.tool = DrawingTool.ray;
      expect(c.draft, isEmpty);
      c.cancelDraft();
      expect(c.tool, DrawingTool.ray);
    });

    test('hiding deselects and stops drawing, data stays', () {
      c.add(_sample(DrawingTool.rectangle));
      c.select('rectangle');
      c.tool = null;
      c.select('rectangle');
      c.visible = false;
      expect(c.selectedId, isNull);
      expect(c.drawings.length, 1);
      c.tool = DrawingTool.trendLine;
      expect(c.visible, isTrue);
    });

    test('remove, clear, lock and style report a change to save', () {
      c.add(_sample(DrawingTool.trendLine));
      c.add(_sample(DrawingTool.ray));
      expect(saves, 2);
      c.select('ray');
      expect(c.removeSelected(), isTrue);
      expect(c.removeSelected(), isFalse);
      expect(c.drawings.map((d) => d.id), ['trendLine']);
      c.setLocked('trendLine', true);
      expect(c.drawings.single.locked, isTrue);
      c.setStyle('trendLine', const DrawingStyle(color: Color(0xFFEA3943), width: 3));
      expect(c.drawings.single.style.width, 3);
      c.setStyle('trendLine', const DrawingStyle(color: Color(0xFFEA3943), width: 3));
      expect(saves, 5, reason: 'unchanged style is not a change');
      c.clear();
      expect(c.drawings, isEmpty);
      expect(saves, 6);
      c.clear();
      expect(saves, 6);
    });

    test('toJson and loadJson restore a symbol\'s drawings', () {
      for (final tool in DrawingTool.values) {
        c.add(_sample(tool));
      }
      final saved = jsonEncode(c.toJson());
      final other = DrawingController(style: _style);
      addTearDown(other.dispose);
      other.loadJson(jsonDecode(saved));
      expect(other.drawings, c.drawings);
      other.loadJson(null);
      expect(other.drawings, isEmpty);
    });

    test('new fibonacci drawings take the controller\'s levels', () {
      c.fibLevels = const [0.5, 0.618];
      c.tool = DrawingTool.fibRetracement;
      c.addDraftPoint(const DrawingAnchor(1, 10));
      c.addDraftPoint(const DrawingAnchor(2, 20));
      expect(c.drawings.single.fibLevels, [0.5, 0.618]);
    });
  });
}
