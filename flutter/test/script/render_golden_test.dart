// 渲染参考图：每类图元至少一张（从真样本里只留这一类），外加全部样式的合成样本、
// 主图加副图、多个脚本叠加、深浅两种主题。参考图在 testdata/primitives/goldens/，
// 用 `flutter test --update-goldens test/script/render_golden_test.dart` 生成，生成后要人工看过。
import 'dart:convert';

import 'package:chartkit_flutter/chartkit_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

const _all = [
  'series', 'hlines', 'fills', 'markers', 'trades', 'bg', 'barColors', 'candles', 'lines', //
  'boxes', 'labels', 'tables',
];

/// 真样本只留 [keep] 里的字段，其余数组清空。[seriesKind] 给了就只留这种序列。
Map<String, dynamic> only(String id, Set<String> keep, {String? seriesKind}) {
  final j = jsonDecode(sampleJson(id)) as Map<String, dynamic>;
  for (final k in _all) {
    if (!keep.contains(k)) j[k] = [];
  }
  if (seriesKind != null) {
    j['series'] = [
      for (final s in j['series'] as List)
        if (s['kind'] == seriesKind) s,
    ];
  }
  return j;
}

final _key = GlobalKey();

void main() {
  final candles = loadKlines();
  final times = [for (final c in candles) c.time];
  late KLineChartState state;
  late ScriptOutputController scripts;

  setUp(() {
    state = KLineChartState(timeFrame: TimeFrame.m15)..setData(candles);
    scripts = ScriptOutputController(onAlignmentIssue: (i) => fail('$i'));
  });
  tearDown(() {
    scripts.dispose();
    state.dispose();
  });

  Future<void> render(WidgetTester tester, String name, Map<String, Object> outputs,
      {ChartTheme theme = ChartTheme.dark,
      double cw = 6,
      double scroll = 0,
      double blank = 0,
      Size size = const Size(400, 460)}) async {
    for (final e in outputs.entries) {
      final r = scripts.setJson(e.key, e.value);
      expect(r.ok, isTrue, reason: '${e.key} ${r.error}');
    }
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Center(
        child: RepaintBoundary(
          key: _key,
          child: SizedBox.fromSize(
            size: size,
            child: KLineChart(
              state: state,
              theme: theme,
              entranceAnimation: false,
              showVolume: false,
              blankScrollWidth: blank,
              scriptOutputs: scripts,
            ),
          ),
        ),
      ),
    ));
    state.setViewport(candleWidth: cw, scrollOffset: blank > 0 ? -blank : scroll);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await expectLater(
        find.byKey(_key), matchesGoldenFile('../../testdata/primitives/goldens/$name.png'));
  }

  group('one primitive kind per image', () {
    testWidgets(
        'series: line',
        (t) => render(t, '01_series_line', {
              'boll': only('boll', {'series'})
            }));
    testWidgets(
        'series: area',
        (t) => render(t, '02_series_area', {
              'wt': only('wt', {'series'}, seriesKind: 'area')
            }));
    testWidgets(
        'series: bar',
        (t) => render(t, '03_series_bar', {
              'macd': only('macd', {'series'}, seriesKind: 'bar')
            }));
    testWidgets(
        'series: dots',
        (t) => render(t, '04_series_dots', {
              'sar': only('sar', {'series'})
            }));
    testWidgets(
        'fills',
        (t) => render(t, '05_fills', {
              'boll': only('boll', {'series', 'fills'}),
              'rsi': only('rsi', {'hlines', 'fills'}),
            }));
    testWidgets(
        'hlines',
        (t) => render(t, '06_hlines', {
              'rsi': only('rsi', {'hlines'})
            }));
    testWidgets(
        'markers',
        (t) => render(
            t,
            '07_markers',
            {
              'cp': only('com-candlestick-patterns-identified-updated-', {'markers'})
            },
            cw: 9));
    testWidgets(
        'trades',
        (t) => render(
            t,
            '08_trades',
            {
              'st': only('com-supertrend-strategy', {'trades'})
            },
            cw: 4,
            scroll: 1200));
    testWidgets(
        'background',
        (t) => render(
            t,
            '09_bg',
            {
              'ict': only('com-ict-silver-bullet-backtest', {'bg'})
            },
            cw: 3));
    testWidgets(
        'bar colors',
        (t) => render(
            t,
            '10_bar_colors',
            {
              'st': only('com-supertrend-strategy', {'barColors'})
            },
            cw: 5,
            scroll: 400));
    testWidgets(
        'script candles',
        (t) => render(
            t,
            '11_candles',
            {
              'dc': only('com-decycler-high-low-breakout-schizoquant', {'candles'})
            },
            cw: 8));
    testWidgets(
        'lines',
        (t) => render(t, '12_lines', {
              'smc': only('smc', {'lines'})
            }));
    testWidgets(
        'boxes',
        (t) => render(
            t,
            '13_boxes',
            {
              'fvg': only('fvg', {'boxes'})
            },
            cw: 5));
    testWidgets(
        'labels',
        (t) => render(t, '14_labels', {
              'smc': only('smc', {'labels'})
            }));
    testWidgets(
        'tables',
        (t) => render(t, '15_tables', {
              'po3': only('opt-po3', {'tables'}),
              'tex': only('com-trend-exhaustion-continuation-map-bullby', {'tables'}),
            }));
  });

  group('every style', () {
    testWidgets('label styles and marker shapes',
        (t) => render(t, '16_styles_labels_markers', {'s': labelMarkerStyles(candles)}, cw: 11));

    testWidgets('line styles, extends, box text, table positions',
        (t) => render(t, '17_styles_lines_boxes_tables', {'s': lineBoxTableStyles(times)}, cw: 11));
  });

  group('combinations', () {
    const combo = ['boll', 'smc', 'fvg', 'rsi', 'com-trend-exhaustion-continuation-map-bullby'];
    testWidgets(
        '3 main + 2 sub, dark',
        (t) => render(t, '18_combo_dark', {for (final id in combo) id: sampleJson(id)},
            size: const Size(400, 640)));
    testWidgets(
        '3 main + 2 sub, light',
        (t) => render(t, '19_combo_light', {for (final id in combo) id: sampleJson(id)},
            theme: ChartTheme.light, size: const Size(400, 640)));
    testWidgets(
        'several main scripts stacked',
        (t) => render(
            t,
            '20_main_stack',
            {
              for (final id in ['boll', 'sar', 'com-supertrend-strategy', 'opt-po3'])
                id: sampleJson(id),
            },
            blank: 120));
    testWidgets('sub panes after built-in sub indicators, landscape', (t) async {
      for (final id in ['macd', 'wt']) {
        scripts.setJson(id, sampleJson(id));
      }
      await t.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Center(
          child: RepaintBoundary(
            key: _key,
            child: SizedBox(
              width: 820,
              height: 420,
              child: KLineChart(
                state: state,
                theme: ChartTheme.light,
                entranceAnimation: false,
                subIndicators: const [Kdj()],
                scriptOutputs: scripts,
              ),
            ),
          ),
        ),
      ));
      await t.pump(const Duration(seconds: 1));
      await expectLater(find.byKey(_key),
          matchesGoldenFile('../../testdata/primitives/goldens/21_with_builtin_sub_landscape.png'));
    });
  });
}
