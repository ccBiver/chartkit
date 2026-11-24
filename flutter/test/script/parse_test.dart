import 'dart:convert';
import 'dart:ui';

import 'package:chartkit_flutter/chartkit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

/// 把解析结果还原成和 JSON 同构的普通值，用来比较两份输出解析出来是否一样。
Object? describe(ScriptOutput o) => {
      'id': o.scriptId,
      'name': o.scriptName,
      'pane': o.pane.name,
      'precision': o.precision,
      'bars': [o.bars.from, o.bars.to, o.bars.count, o.bars.intervalMs],
      'palette': [for (final c in o.palette) c?.toARGB32()],
      'series': [
        for (final s in o.series)
          [
            s.id, s.kind.name, s.title, s.visible, s.color, s.colors?.toList(), //
            [for (final v in s.values) v.isNaN ? null : v],
            s.width, s.style.name, s.step, s.breakGaps, s.base, s.variant.name, s.shape.name,
            s.size, s.trackPrice, s.legend,
          ],
      ],
      'hlines': [
        for (final h in o.hlines)
          [h.id, h.title, h.price, h.color, h.style.name, h.width, h.visible],
      ],
      'fills': [
        for (final f in o.fills) [f.a, f.b, f.color, f.colors?.toList()],
      ],
      'markers': [
        for (final m in o.markers)
          [
            m.title, m.shape.name, m.location.name, m.size.name, m.char, m.text, m.textColor, //
            m.times.toList(), [for (final p in m.prices) p.isNaN ? null : p], m.colors.toList(),
          ],
      ],
      'trades': [
        for (final t in o.trades)
          [t.time, t.price, t.side.name, t.kind.name, t.qty, t.id, t.comment],
      ],
      'bg': [
        for (final g in o.bg)
          [
            g.mainPane,
            for (final r in g.runs) [r.t1, r.t2, r.color],
          ],
      ],
      'barColors': [
        for (final g in o.barColors)
          [
            for (final r in g) [r.t1, r.t2, r.color]
          ],
      ],
      'candles': [
        for (final c in o.candles)
          [
            c.title,
            c.bars,
            c.open.toList(),
            c.high.toList(),
            c.low.toList(),
            c.close.toList(),
            c.color,
            c.colors?.toList()
          ].map((e) => e is List<double> ? [for (final v in e) v.isNaN ? null : v] : e).toList(),
      ],
      'lines': [
        for (final l in o.lines)
          [l.t1, l.p1, l.t2, l.p2, l.extend.name, l.color, l.style.name, l.width],
      ],
      'boxes': [
        for (final b in o.boxes)
          [
            b.t1, b.top, b.t2, b.bottom, b.extend.name, b.bg, b.borderColor, b.borderWidth, //
            b.borderStyle.name, b.text?.text, b.text?.color, b.text?.size.name, b.text?.halign.name,
            b.text?.valign.name,
            b.text?.points,
          ],
      ],
      'labels': [
        for (final l in o.labels)
          [
            l.time, l.price.isNaN ? null : l.price, l.yloc.name, l.text, l.style.name, l.color, //
            l.textColor, l.size.name, l.points, l.align.name, l.tooltip,
          ],
      ],
      'tables': [
        for (final t in o.tables)
          [
            t.position.name, t.columns, t.rows, t.bg, t.frameColor, t.frameWidth, t.borderColor, //
            t.borderWidth,
            [
              for (final c in t.cells)
                [c.column, c.row, c.text, c.textColor, c.bg, c.size.name, c.points, c.halign.name]
            ],
          ],
      ],
      'inputs': [
        for (final i in o.inputs)
          [i.id, i.type, i.title, i.defaultValue, i.min, i.max, i.step, i.options, i.group],
      ],
    };

Map<String, dynamic> _raw(String id) => jsonDecode(sampleJson(id)) as Map<String, dynamic>;

/// 一份最小的合法输出，测试里在它上面改。
Map<String, dynamic> minimal() => {
      'v': 1,
      'script': {'id': 't', 'name': 'Test'},
      'symbol': 'XAUUSD',
      'period': '15m',
      'pane': 'sub',
      'precision': null,
      'bars': {'from': 0, 'to': 2700000, 'count': 4, 'intervalMs': 900000},
      'palette': ['', '#2962FFFF', '#F2364580'],
      'series': [
        {
          'id': 'p0', 'kind': 'line', 'title': 'A', 'visible': true, 'color': 1, //
          'values': [1, null, 3, 4], 'width': 2, 'style': 'solid', 'step': false, 'gaps': 'connect',
        },
      ],
      'hlines': [],
      'fills': [],
      'markers': [],
      'trades': [],
      'bg': [],
      'barColors': [],
      'candles': [],
      'lines': [],
      'boxes': [],
      'labels': [],
      'tables': [],
      'inputs': [],
      'warnings': [],
    };

void main() {
  group('real samples', () {
    test('every sample parses without warnings and keeps every element', () {
      for (final id in sampleScripts) {
        final raw = _raw(id);
        final r = parseScriptOutput(raw);
        expect(r.ok, isTrue, reason: '$id ${r.error}');
        expect(r.warnings, isEmpty, reason: id);
        final o = r.output!;
        expect(o.scriptId, raw['script']['id']);
        expect(o.pane.name, raw['pane']);
        expect(o.bars.count, raw['bars']['count']);
        expect(o.palette.length, (raw['palette'] as List).length);
        for (final k in [
          'series', 'hlines', 'fills', 'markers', 'trades', 'bg', 'barColors', 'candles', //
          'lines', 'boxes', 'labels', 'tables', 'inputs',
        ]) {
          final parsed = (describe(o)! as Map)[k] as List;
          expect(parsed.length, (raw[k] as List).length, reason: '$id.$k');
        }
      }
    });

    test('all 15 primitive kinds are covered by the samples', () {
      final seen = <String>{};
      for (final id in sampleScripts) {
        final o = loadSample(id);
        for (final s in o.series) {
          if (s.visible) seen.add('series.${s.kind.name}');
        }
        if (o.hlines.isNotEmpty) seen.add('hlines');
        if (o.fills.isNotEmpty) seen.add('fills');
        if (o.markers.isNotEmpty) seen.add('markers');
        if (o.trades.isNotEmpty) seen.add('trades');
        if (o.bg.isNotEmpty) seen.add('bg');
        if (o.barColors.isNotEmpty) seen.add('barColors');
        if (o.candles.isNotEmpty) seen.add('candles');
        if (o.lines.isNotEmpty) seen.add('lines');
        if (o.boxes.isNotEmpty) seen.add('boxes');
        if (o.labels.isNotEmpty) seen.add('labels');
        if (o.tables.isNotEmpty) seen.add('tables');
      }
      expect(seen, {
        'series.line', 'series.area', 'series.bar', 'series.dots', 'fills', 'hlines', 'markers', //
        'trades', 'bg', 'barColors', 'candles', 'lines', 'boxes', 'labels', 'tables',
      });
      expect({for (final id in sampleScripts) loadSample(id).pane}, ScriptPane.values.toSet());
    });

    test('spot values match the JSON', () {
      final rsi = loadSample('rsi');
      expect(rsi.precision, 2);
      expect(rsi.palette[1], const Color(0xFF9B7BF7));
      expect(rsi.palette[2], const Color(0x998A8F98));
      expect(rsi.colorOf(0), isNull);
      expect(rsi.hlines.map((h) => (h.price, h.style)), [
        (70.0, ScriptLineStyle.dashed),
        (50.0, ScriptLineStyle.dotted),
        (30.0, ScriptLineStyle.dashed),
      ]);
      expect(rsi.series.single.values[13].isNaN, isTrue);
      expect(rsi.series.single.values[14], 28.62069);
      final po3 = loadSample('opt-po3');
      expect(po3.tables.single.position, ScriptTablePosition.middleRight);
      expect(po3.tables.single.cells.first.text, '1D CANDLE PO3');
      expect(po3.lines.first.t1, 1795227300000);
      expect(po3.labels.first.style, ScriptLabelStyle.labelLeft);
      final st = loadSample('com-supertrend-strategy');
      expect(st.trades.first.side, ScriptTradeSide.sell);
      expect(st.trades.first.kind, ScriptTradeKind.entry);
      expect(st.fills.first.colors, isNotNull);
      expect(st.series[0].breakGaps, isTrue);
    });

    test('the protojson version (doubles, scientific notation, shuffled keys) parses the same', () {
      for (final id in sampleScripts) {
        final text = sampleJson(id, protojson: true);
        expect(text, contains('.0'), reason: id);
        final a = parseScriptOutput(sampleJson(id));
        final b = parseScriptOutput(text);
        expect(b.ok, isTrue, reason: '$id ${b.error}');
        expect(b.warnings, isEmpty, reason: id);
        expect(describe(b.output!), describe(a.output!), reason: id);
      }
      // 至少有一份的时间是科学计数法
      expect(
        [for (final id in sampleScripts) sampleJson(id, protojson: true)]
            .any((s) => s.contains('e+12')),
        isTrue,
      );
    });
  });

  group('robustness', () {
    test('doubles and numeric strings are read as numbers', () {
      final j = minimal()
        ..['bars'] = {'from': 0.0, 'to': 2.7e6, 'count': 4.0, 'intervalMs': '900000'}
        ..['series'] = [
          {
            ...minimal()['series'][0],
            'color': 1.0,
            'width': 2.0,
            'colors': [1.0, 2.0, 0.0, 1.0]
          },
        ];
      final o = parseScriptOutput(j).output!;
      expect(o.bars.to, 2700000);
      expect(o.bars.count, 4);
      expect(o.bars.intervalMs, 900000);
      expect(o.series.single.colors, [1, 2, 0, 1]);
      expect(o.series.single.width, 2);
    });

    test('unknown fields are skipped with one warning each', () {
      final j = minimal()
        ..['extra'] = {'a': 1}
        ..['series'] = [
          {...minimal()['series'][0], 'glow': true},
          {...minimal()['series'][0], 'id': 'p1', 'glow': false},
        ];
      final r = parseScriptOutput(j);
      expect(r.ok, isTrue);
      expect(r.output!.series.length, 2);
      expect(
          r.warnings, ['unknown field output.extra ignored', 'unknown field series.glow ignored']);
    });

    test('unknown enum values: cosmetic ones fall back, the rest skip that element only', () {
      final j = minimal()
        ..['series'] = [
          {...minimal()['series'][0], 'style': 'wavy'},
          {...minimal()['series'][0], 'id': 'p1', 'kind': 'heatmap'},
        ]
        ..['labels'] = [
          {
            't': 0,
            'p': 1,
            'yloc': 'price',
            'text': 'x',
            'style': 'label_sparkle',
            'color': 1,
            'textColor': 2,
            'size': 'gigantic',
            'align': 'center'
          },
        ]
        ..['markers'] = [
          {
            'title': 'm',
            'shape': 'star',
            'location': 'abovebar',
            'size': 'small',
            'points': [
              [0, 1, 1]
            ]
          },
          {
            'title': 'n',
            'shape': 'circle',
            'location': 'sideways',
            'size': 'small',
            'points': [
              [0, 1, 1]
            ]
          },
        ];
      final r = parseScriptOutput(j);
      expect(r.ok, isTrue);
      final o = r.output!;
      expect(o.series.single.id, 'p0', reason: 'unknown kind skips the series');
      expect(o.series.single.style, ScriptLineStyle.solid);
      expect(o.labels.single.style, ScriptLabelStyle.labelDown);
      expect(o.labels.single.size, ScriptSize.normal);
      expect(o.markers.single.title, 'n');
      expect(o.markers.single.location, ScriptMarkerLocation.abovebar);
      expect(r.warnings, hasLength(6));
      expect(r.warnings, contains('unknown series[1].kind "heatmap", element skipped'));
      expect(r.warnings, contains('unknown markers[1].location "sideways", using abovebar'));
    });

    test('a version other than 1 is refused as a whole', () {
      for (final v in [2, 0, null, '1x']) {
        final r = parseScriptOutput(minimal()..['v'] = v);
        expect(r.ok, isFalse);
        expect(r.error!.code, ScriptOutputErrorCode.unsupportedVersion, reason: '$v');
      }
      expect(parseScriptOutput(minimal()..['v'] = 1.0).ok, isTrue,
          reason: '1.0 from protojson is 1');
    });

    test('missing essentials, non-objects and bad JSON are explicit errors', () {
      expect(parseScriptOutput('{not json').error!.code, ScriptOutputErrorCode.notAnObject);
      expect(parseScriptOutput([1]).error!.code, ScriptOutputErrorCode.notAnObject);
      expect(
          parseScriptOutput(minimal()..remove('bars')).error!.code, ScriptOutputErrorCode.invalid);
      expect(parseScriptOutput(minimal()..['pane'] = 'side').error!.code,
          ScriptOutputErrorCode.invalid);
      expect(parseScriptOutput(minimal()..remove('palette')).error!.code,
          ScriptOutputErrorCode.invalid);
      expect(
          parseScriptOutput(minimal()..['script'] = {}).error!.code, ScriptOutputErrorCode.invalid);
    });

    test('bad colors and wrong lengths are drawn as nothing, with a warning', () {
      final j = minimal()
        ..['palette'] = ['', '#2962FFFF', 'red']
        ..['series'] = [
          {
            ...minimal()['series'][0],
            'color': 9,
            'values': [1, 2]
          },
        ];
      final r = parseScriptOutput(j);
      final s = r.output!.series.single;
      expect(s.color, 0);
      expect(s.values.length, 4);
      expect(s.values[2].isNaN, isTrue);
      expect(r.output!.palette[2], isNull);
      expect(r.warnings, hasLength(3));
    });

    test('numeric sizes (Pine v6 points, as number or string) are kept as points', () {
      final j = minimal()
        ..['labels'] = [
          {
            't': 0,
            'p': 1,
            'yloc': 'price',
            'text': 'a',
            'style': 'circle',
            'color': 1,
            'textColor': 2,
            'size': '6',
            'align': 'center'
          },
          {
            't': 0,
            'p': 1,
            'yloc': 'price',
            'text': 'b',
            'style': 'none',
            'color': 1,
            'textColor': 2,
            'size': 12.0,
            'align': 'center'
          },
          {
            't': 0,
            'p': 1,
            'yloc': 'price',
            'text': 'c',
            'style': 'none',
            'color': 1,
            'textColor': 2,
            'size': 'small',
            'align': 'center'
          },
        ]
        ..['tables'] = [
          {
            'position': 'top_right', 'columns': 1, 'rows': 1, 'bg': 0, //
            'cells': [
              [0, 0, 'x', 1, 0, '12', 'left'],
            ],
          },
        ];
      final r = parseScriptOutput(j);
      expect(r.warnings, isEmpty);
      expect(r.output!.labels.map((l) => l.points), [6, 12, null]);
      expect(r.output!.labels[2].size, ScriptSize.small);
      expect(r.output!.tables.single.cells.single.points, 12);
      final real = loadSample('com-innovation-adaptive-kalman-filter-oscill');
      expect(real.labels.map((l) => l.points).toSet(), containsAll(<double?>[4, 6]));
    });

    test('a fill that refers to an unknown id is skipped', () {
      final j = minimal()
        ..['fills'] = [
          {
            'between': ['p0', 'nope'],
            'color': 1
          },
          {
            'between': ['p0', 'p0'],
            'color': 1
          },
        ];
      final r = parseScriptOutput(j);
      expect(r.output!.fills.length, 1);
      expect(r.warnings.single, contains('unknown id'));
    });

    test('setJson with a refused output removes the old one and reports why', () {
      final c = ScriptOutputController();
      addTearDown(c.dispose);
      expect(c.setJson('rsi', sampleJson('rsi')).ok, isTrue);
      final r = c.setJson('rsi', minimal()..['v'] = 2);
      expect(r.error!.code, ScriptOutputErrorCode.unsupportedVersion);
      expect(c.scriptIds, isEmpty);
    });
  });
}
