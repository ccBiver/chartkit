import 'dart:convert';
import 'dart:io';

import 'package:chartkit_flutter/chartkit_flutter.dart';

/// testdata/primitives 下的样本：脚本引擎在测试环境 XAUUSD 15m K 线上的真输出（见 testdata/primitives/SOURCE.md）。
const primitivesDir = 'testdata/primitives';

/// 样本输出的脚本 id。
const sampleScripts = [
  'boll',
  'smc',
  'com-supertrend-strategy',
  'com-ict-silver-bullet-backtest',
  'com-decycler-high-low-breakout-schizoquant',
  'opt-po3',
  'fvg',
  'com-candlestick-patterns-identified-updated-',
  'com-machine-learning-adaptive-supertrend-alg',
  'sar',
  'macd',
  'rsi',
  'wt',
  'com-trend-exhaustion-continuation-map-bullby',
  'com-signed-realized-variance-trend-backquant',
  'st-macd',
];

/// 测试环境的 15m K 线（含每天和周末的休市空档）。
List<Candle> loadKlines() {
  final json = jsonDecode(File('$primitivesDir/klines_15m.json').readAsStringSync()) as Map;
  return [
    for (final b in json['bars'] as List)
      Candle(
        time: (b['time'] as num).toInt(),
        open: (b['open'] as num).toDouble(),
        high: (b['high'] as num).toDouble(),
        low: (b['low'] as num).toDouble(),
        close: (b['close'] as num).toDouble(),
        volume: (b['volume'] as num).toDouble(),
      ),
  ];
}

String sampleJson(String id, {bool protojson = false}) =>
    File('$primitivesDir/${protojson ? '15m-protojson' : '15m'}/$id.json').readAsStringSync();

ScriptOutput loadSample(String id, {bool protojson = false}) {
  final r = parseScriptOutput(sampleJson(id, protojson: protojson));
  if (r.output == null) throw StateError('$id: ${r.error}');
  return r.output!;
}

/// 全部标签样式（20 种）和标记形状（13 种）、5 种位置、6 档尺寸，画在最后 30 根上。
Map<String, dynamic> labelMarkerStyles(List<Candle> candles) {
  final times = [for (final c in candles) c.time];
  final base = times.length - 34;
  final labelStyles = [
    'label_up', 'label_down', 'label_left', 'label_right', 'label_center', 'label_upper_left', //
    'label_upper_right', 'label_lower_left', 'label_lower_right', 'none', 'circle', 'square',
    'diamond', 'triangleup', 'triangledown', 'arrowup', 'arrowdown', 'cross', 'xcross', 'flag',
  ];
  final shapes = [
    'triangleup', 'triangledown', 'circle', 'cross', 'xcross', 'diamond', 'square', 'arrowup', //
    'arrowdown', 'flag', 'labelup', 'labeldown', 'char',
  ];
  final sizes = ['tiny', 'small', 'normal', 'large', 'huge', 'auto'];
  final locations = ['abovebar', 'belowbar', 'absolute', 'top', 'bottom'];
  final visible = candles.sublist(base);
  final hi = visible.map((c) => c.high).reduce((a, b) => a > b ? a : b);
  final lo = visible.map((c) => c.low).reduce((a, b) => a < b ? a : b);
  return _synthetic(times, labels: [
    for (var i = 0; i < labelStyles.length; i++)
      {
        't': times[base + 4 + (i % 10) * 3], 'p': lo + (hi - lo) * (i < 10 ? 0.8 : 0.25), //
        'yloc': 'price',
        'text': 'L$i', 'style': labelStyles[i], 'color': 1 + i % 3, 'textColor': 4,
        'size': sizes[i % 6], 'align': ['left', 'center', 'right'][i % 3],
      },
  ], markers: [
    for (var i = 0; i < shapes.length; i++)
      {
        'title': shapes[i], 'shape': shapes[i], 'location': locations[i % 5], //
        'size': sizes[i % 6], if (shapes[i] == 'char') 'char': '★', 'text': 'M$i', 'textColor': 5,
        'points': [
          [
            times[base + 1 + i * 2],
            locations[i % 5] == 'abovebar'
                ? candles[base + 1 + i * 2].high
                : locations[i % 5] == 'belowbar'
                    ? candles[base + 1 + i * 2].low
                    : locations[i % 5] == 'absolute'
                        ? (hi + lo) / 2
                        : null,
            1 + i % 3,
          ],
        ],
      },
  ]);
}

/// 6 种线型、4 种延伸、方框文字的 9 种对齐、表格的 9 个位置，画在最后 30 根上。
Map<String, dynamic> lineBoxTableStyles(List<int> times) {
  final base = times.length - 30;
  final segStyles = ['solid', 'dashed', 'dotted', 'arrow_left', 'arrow_right', 'arrow_both'];
  final extend = ['none', 'left', 'right', 'both'];
  final positions = [
    'top_left', 'top_center', 'top_right', 'middle_left', 'middle_center', 'middle_right', //
    'bottom_left', 'bottom_center', 'bottom_right',
  ];
  return _synthetic(times, lines: [
    for (var i = 0; i < segStyles.length; i++)
      {
        't1': times[base + 2], 'p1': 3590 - i * 8, 't2': times[base + 12], 'p2': 3580 - i * 8, //
        'extend': 'none', 'color': 1 + i % 3, 'style': segStyles[i], 'width': 1 + i % 3,
      },
    for (var i = 0; i < extend.length; i++)
      {
        't1': times[base + 14], 'p1': 3505 - i * 6, 't2': times[base + 18], 'p2': 3500 - i * 6, //
        'extend': extend[i], 'color': 2 + i % 2, 'style': 'solid', 'width': 1,
      },
  ], boxes: [
    for (var i = 0; i < 3; i++)
      for (var v = 0; v < 3; v++)
        {
          't1': times[base + 16 + i * 4], 'top': 3600 - v * 25, 't2': times[base + 19 + i * 4], //
          'bottom': 3580 - v * 25, 'extend': 'none', 'bg': 6,
          'border': {
            'color': 1 + (i + v) % 3,
            'width': 1,
            'style': ['solid', 'dashed', 'dotted'][v]
          },
          'text': {
            'text': 'B', 'color': 4, 'size': 'small', 'halign': ['left', 'center', 'right'][i], //
            'valign': ['top', 'center', 'bottom'][v],
          },
        },
    {
      't1': times[base + 20], 'top': 3530, 't2': times[base + 22], 'bottom': 3522,
      'extend': 'right', //
      'bg': 6, 'border': {'color': 3, 'width': 1, 'style': 'solid'},
    },
  ], tables: [
    for (var i = 0; i < positions.length; i++)
      {
        'position': positions[i], 'columns': 2, 'rows': 2, 'bg': 6, //
        'frame': {'color': 4, 'width': 1}, 'border': {'color': 4, 'width': 1},
        'cells': [
          [0, 0, 'T$i', 4, 0, 'tiny', 'left'],
          [1, 1, 'x', 5, 1, 'tiny', 'right'],
        ],
      },
  ]);
}

/// 一份主图的合成输出，对齐到真 K 线的全部 1000 根。
Map<String, dynamic> _synthetic(List<int> times,
        {List<Map<String, dynamic>> labels = const [],
        List<Map<String, dynamic>> markers = const [],
        List<Map<String, dynamic>> lines = const [],
        List<Map<String, dynamic>> boxes = const [],
        List<Map<String, dynamic>> tables = const []}) =>
    {
      'v': 1,
      'script': {'id': 'styles', 'name': 'Styles'},
      'symbol': 'XAUUSD',
      'period': '15m',
      'pane': 'main',
      'precision': null,
      'bars': {'from': times.first, 'to': times.last, 'count': times.length, 'intervalMs': 900000},
      'palette': ['', '#2962FFFF', '#F23645FF', '#089981FF', '#FFFFFFFF', '#FFB74DFF', '#7E57C240'],
      'series': [],
      'hlines': [],
      'fills': [],
      'markers': markers,
      'trades': [],
      'bg': [],
      'barColors': [],
      'candles': [],
      'lines': lines,
      'boxes': boxes,
      'labels': labels,
      'tables': tables,
      'inputs': [],
      'warnings': [],
    };
