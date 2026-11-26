// 主图开了图例留位（reserveMainLegend）时，按价位定位的脚本图元裁在图例下面：
// 略高于可见范围的水平线、方框、线段、标签、标记（这些不算进主图价格区间）不画进图例那一条；背景色仍铺到窗格顶，表格仍贴窗格的边。
// 图例留位关着时图例下沿就是主图顶，裁剪区和原来一样，由现有基线和参考图测试覆盖（逐像素不变）。
import 'package:chartkit_flutter/chartkit_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tools/harness.dart';
import 'fixtures.dart';

const _magenta = Color(0xFFFF00FF);
const _bgRun = Color(0xFF00FF00);

void main() {
  final candles = loadKlines();
  final n = candles.length;
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

  /// 一份主图脚本。[price] 是图例那一条中间对应的价位（略高于可见范围），[inside] 是价格区里的一个价位：
  /// 水平线和标记整个在图例那一条里；线段、方框从那里一直跨到价格区里面。
  Map<String, dynamic> script({
    double? price,
    double? inside,
    bool bg = false,
    bool table = false,
  }) {
    final t = [for (final c in candles) c.time];
    return {
      'v': 1,
      'script': {'id': 'clip', 'name': 'Clip'},
      'symbol': 'XAUUSD',
      'period': '15m',
      'pane': 'main',
      'precision': null,
      'bars': {'from': t.first, 'to': t.last, 'count': n, 'intervalMs': 900000},
      'palette': ['', '#FF00FFFF', '#00FF00FF', '#FFFFFFFF'],
      // 不放曲线：曲线会算进主图价格区间，价位就不会落在图例那一条里了
      'series': [],
      'hlines': [
        if (price != null)
          {
            'id': 'h', 'title': 'H', 'price': price, 'color': 1, 'style': 'solid', 'width': 2, //
            'visible': true,
          },
      ],
      'fills': [],
      'markers': [
        if (price != null)
          {
            'title': 'm', 'shape': 'circle', 'location': 'absolute', 'size': 'normal', //
            'points': [
              [t[n - 20], price, 1],
            ],
          },
      ],
      'trades': [],
      'bg': [
        if (bg)
          {
            'runs': [
              [t[n - 30], t[n - 20], 2],
            ],
          },
      ],
      'barColors': [],
      'candles': [],
      'lines': [
        if (price != null)
          {
            't1': t[n - 35], 'p1': price, 't2': t[n - 5], 'p2': inside ?? price, 'extend': 'none', //
            'color': 1, 'style': 'solid', 'width': 2,
          },
      ],
      'boxes': [
        if (price != null)
          {
            't1': t[n - 28], 'top': price, 't2': t[n - 22], 'bottom': inside ?? price, //
            'extend': 'none', 'bg': 1, 'border': {'color': 1, 'width': 1, 'style': 'solid'},
          },
      ],
      'labels': [
        if (price != null)
          {
            't': t[n - 12], 'p': price, 'yloc': 'price', 'text': 'L', 'style': 'label_down', //
            'color': 1, 'textColor': 3, 'size': 'normal', 'align': 'center',
          },
      ],
      'tables': [
        if (table)
          {
            'position': 'top_right', 'columns': 1, 'rows': 1, 'bg': 2, //
            'frame': {'color': 1, 'width': 1}, 'border': {'color': 1, 'width': 1},
            'cells': [
              [0, 0, 'TABLE', 3, 0, 'normal', 'center'],
            ],
          },
      ],
      'inputs': [],
      'warnings': [],
    };
  }

  KLineChart chart({bool legend = true, bool log = false, double gap = 0}) => KLineChart(
        state: state,
        entranceAnimation: false,
        showVolume: false,
        mainIndicators: [Ma()],
        scriptOutputs: scripts,
        reserveMainLegend: legend,
        logScale: log,
        mainBottomGap: gap,
      );

  /// 主图顶到图例下沿之间（图例那一条）两张图不同的像素数。
  int stripDiff(Pixels a, Pixels b, double contentTop, double right) {
    var n = 0;
    for (var y = 0.0; y < contentTop; y += 1 / a.ratio) {
      for (var x = 0.0; x < right; x += 1 / a.ratio) {
        if (a.at(x, y) != b.at(x, y)) n++;
      }
    }
    return n;
  }

  for (final (name, log, gap) in [
    ('只开图例留位', false, 0.0),
    ('同时开 mainBottomGap', false, 34.0),
    ('同时开对数坐标', true, 0.0),
  ]) {
    testWidgets('$name：略高于可见范围的水平线、线段、方框、标签、标记不画进图例那一条', (tester) async {
      scripts.setJson('clip', script());
      await pumpChart(tester, state, chart(log: log, gap: gap), cw: 6);
      final empty = await capture(tester);
      final m = state.mapper.value!;
      expect(m.mainContentTop, greaterThan(10));
      expect(m.logScale, log);
      expect(m.mainBottomGapRect.height, gap);
      // 图例那一条正中对应的价位：高于价格区上沿
      final price = m.yToPrice(m.mainContentTop / 2);
      final inside = m.yToPrice(m.mainContentTop + 40);
      expect(price, greaterThan(m.yToPrice(m.mainContentTop)));
      scripts.setJson('clip', script(price: price, inside: inside));
      await tester.pump();
      await tester.pump();
      final drawn = await capture(tester);
      // 价格区间没被这些图元撑大：价位仍在图例那一条里
      final m2 = state.mapper.value!;
      expect(m2.mainContentTop, m.mainContentTop);
      expect(m2.yToPrice(m2.mainContentTop), closeTo(m.yToPrice(m.mainContentTop), 1e-9));
      expect(m2.priceToY(price), lessThan(m2.mainContentTop));
      expect(stripDiff(empty, drawn, m.mainContentTop, m.mainRect.right), 0);
      // 图元确实画了：图例下沿往下几像素的方框、线段、标签这些都在
      var below = 0;
      for (var y = m.mainContentTop; y < m.mainContentTop + 12; y += 1 / empty.ratio) {
        for (var x = 0.0; x < m.mainRect.right; x += 1 / empty.ratio) {
          if (empty.at(x, y) != drawn.at(x, y)) below++;
        }
      }
      expect(below, greaterThan(50));
    });
  }

  testWidgets('背景色仍然铺到窗格顶（图例那一条里也有）', (tester) async {
    scripts.setJson('clip', script(bg: true));
    await pumpChart(tester, state, chart(), cw: 6);
    final m = state.mapper.value!;
    final px = await capture(tester);
    final x = (m.indexToX(n - 30) + m.indexToX(n - 20)) / 2;
    expect(px.at(x, 1), isNot(ChartTheme.dark.background));
    expect(px.coverage(x, 1, _bgRun, ChartTheme.dark.background, r: 0), greaterThan(0.1));
  });

  testWidgets('表格按窗格定位，图例留位时照常贴窗格顶', (tester) async {
    scripts.setJson('clip', script());
    await pumpChart(tester, state, chart(), cw: 6);
    final empty = await capture(tester);
    scripts.setJson('clip', script(table: true));
    await tester.pump();
    await tester.pump();
    final withTable = await capture(tester);
    final m = state.mapper.value!;
    expect(stripDiff(empty, withTable, m.mainContentTop, m.mainRect.right), greaterThan(20));
  });

  testWidgets('副图不受影响：开不开图例留位，副图脚本的窗格逐像素一样', (tester) async {
    scripts.setJson('rsi', sampleJson('rsi'));
    await pumpChart(tester, state, chart(legend: false), cw: 6);
    final a = await capture(tester);
    final top = state.mapper.value!.mainRect.bottom;
    await pumpChart(tester, state, chart(), cw: 6);
    final b = await capture(tester);
    expect(state.mapper.value!.mainRect.bottom, top);
    var diff = 0;
    for (var y = top + 2; y < a.height / a.ratio - 20; y += 1 / a.ratio) {
      for (var x = 0.0; x < a.width / a.ratio; x += 1 / a.ratio) {
        if (a.at(x, y) != b.at(x, y)) diff++;
      }
    }
    expect(diff, 0);
  });

  testWidgets('参考图：图例留位 + 一条略高于可见范围的水平线和方框', (tester) async {
    scripts.setJson('clip', script());
    await pumpChart(tester, state, chart(), cw: 6);
    final m = state.mapper.value!;
    scripts.setJson('clip',
        script(price: m.yToPrice(m.mainContentTop / 2), inside: m.yToPrice(m.mainContentTop + 40), bg: true));
    await tester.pump();
    await tester.pump();
    await matchGolden('18_script_clip_below_legend');
  });

  // 洋红只在价位图元里用：确认它出现在图例下面、没出现在图例那一条里
  testWidgets('洋红色只出现在图例下沿以下', (tester) async {
    scripts.setJson('clip', script());
    await pumpChart(tester, state, chart(), cw: 6);
    final m = state.mapper.value!;
    scripts.setJson('clip',
        script(price: m.yToPrice(m.mainContentTop / 2), inside: m.yToPrice(m.mainContentTop + 40)));
    await tester.pump();
    await tester.pump();
    final px = await capture(tester);
    var inStrip = 0, belowStrip = 0;
    for (var y = 0.0; y < m.mainContentTop + 10; y += 1 / px.ratio) {
      for (var x = 0.0; x < m.mainRect.right; x += 1 / px.ratio) {
        if (px.at(x, y) == _magenta) {
          if (y < m.mainContentTop) {
            inStrip++;
          } else {
            belowStrip++;
          }
        }
      }
    }
    expect(inStrip, 0);
    expect(belowStrip, greaterThan(20));
  });
}
