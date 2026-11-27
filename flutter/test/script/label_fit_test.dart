// 脚本标签的气泡样式按价位区摆：箭头尖在价位区里、气泡往上或往下伸出价位区（被图例那一条或主图底边裁掉）时，
// 翻到箭头尖另一侧画；箭头尖不在价位区里时整个不画。价位区上沿开了图例留位时是图例下沿，没开时是主图窗格顶。
// 脚本自己的副图按副图窗格的上下沿，同样处理（参考图 21_with_builtin_sub_landscape 里有这种情况）。
// 没被裁的气泡画法不变，由现有参考图测试覆盖（逐像素不变）。
import 'package:chartkit_flutter/chartkit_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tools/harness.dart';
import 'fixtures.dart';

const _magenta = Color(0xFFFF00FF);

void main() {
  final candles = loadKlines();
  final n = candles.length;
  final t = [for (final c in candles) c.time];
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

  /// 一份只有标签的主图脚本：每项是（第几根、价位、样式）。
  Map<String, dynamic> script(List<(int, double, String)> labels) => {
        'v': 1,
        'script': {'id': 'fit', 'name': 'Fit'},
        'symbol': 'XAUUSD',
        'period': '15m',
        'pane': 'main',
        'precision': null,
        'bars': {'from': t.first, 'to': t.last, 'count': n, 'intervalMs': 900000},
        'palette': ['', '#FF00FFFF', '#FFFFFFFF'],
        'series': [],
        'hlines': [],
        'fills': [],
        'markers': [],
        'trades': [],
        'bg': [],
        'barColors': [],
        'candles': [],
        'lines': [],
        'boxes': [],
        'labels': [
          for (final (k, p, style) in labels)
            {
              't': t[k], 'p': p, 'yloc': 'price', 'text': 'Label', 'style': style, //
              'color': 1, 'textColor': 2, 'size': 'small', 'align': 'center',
            },
        ],
        'tables': [],
        'inputs': [],
        'warnings': [],
      };

  KLineChart chart({bool legend = true, double gap = 0}) => KLineChart(
        state: state,
        entranceAnimation: false,
        showVolume: false,
        showHighLow: false,
        mainIndicators: const [],
        scriptOutputs: scripts,
        reserveMainLegend: legend,
        mainBottomGap: gap,
      );

  final k = n - 30;

  /// 锚点那一根左右各 40 像素内，洋红（气泡底色）在锚点上方、下方各有多少像素。
  (int, int) sides(Pixels px, double ax, double ay) {
    var above = 0, below = 0;
    for (var y = 0.0; y < px.height / px.ratio; y += 1 / px.ratio) {
      for (var x = ax - 40; x < ax + 40; x += 1 / px.ratio) {
        if (px.at(x, y) != _magenta) continue;
        if (y < ay) {
          above++;
        } else {
          below++;
        }
      }
    }
    return (above, below);
  }

  /// 在 [y] 处放一个 [style] 的标签，返回截图和锚点。
  Future<(Pixels, Offset)> place(
      WidgetTester tester, String style, double Function(KLineChartMapper m) y,
      {bool legend = true, double gap = 0}) async {
    scripts.setJson('fit', script([]));
    await pumpChart(tester, state, chart(legend: legend, gap: gap), cw: 6);
    final m = state.mapper.value!;
    final ay = y(m);
    scripts.setJson('fit', script([(k, m.yToPrice(ay), style)]));
    await tester.pump();
    await tester.pump();
    final m2 = state.mapper.value!;
    // 标签不算进价格区间：价位仍落在原来的像素上
    expect(m2.priceToY(m.yToPrice(ay)), closeTo(ay, 1e-6));
    return (await capture(tester), Offset(m2.indexToX(k), ay));
  }

  /// 气泡在锚点上方时，从锚点到气泡上沿的高度（箭头加气泡），在主图中间量。
  Future<double> reach(WidgetTester tester) async {
    final (px, a) =
        await place(tester, 'label_down', (m) => (m.mainContentTop + m.mainRect.bottom) / 2);
    var y = a.dy;
    // 文字那几行中间是文字色，左右的内边距仍是底色：整行有洋红就算气泡
    while (y > 0 &&
        [for (var x = a.dx - 30; x <= a.dx + 30; x++) px.at(x, y - 1)].contains(_magenta)) {
      y -= 1 / px.ratio;
    }
    return a.dy - y;
  }

  group('往上伸的气泡碰到价位区上沿', () {
    testWidgets('放得下时照常往上画，放不下时翻到下面画（箭头朝上）', (tester) async {
      final up = await reach(tester);
      expect(up, inInclusiveRange(12, 40));
      // 刚好放得下：照常在上方
      var (px, a) = await place(tester, 'label_down', (m) => m.mainContentTop + up + 1);
      var (above, below) = sides(px, a.dx, a.dy);
      expect(above, greaterThan(100));
      expect(below, 0);
      // 差两像素放不下：翻到下方
      (px, a) = await place(tester, 'label_down', (m) => m.mainContentTop + up - 2);
      (above, below) = sides(px, a.dx, a.dy);
      expect(above, 0);
      expect(below, greaterThan(100));
      // 箭头尖在锚点：锚点正下方两像素是洋红，两侧五像素外还不是（箭头往下变宽）
      expect(px.at(a.dx, a.dy + 2), _magenta);
      expect(px.at(a.dx + 5, a.dy + 1), isNot(_magenta));
    });

    testWidgets('锚点紧贴图例下沿：翻下来后图例那一条里一个像素都没画', (tester) async {
      scripts.setJson('fit', script([]));
      await pumpChart(tester, state, chart(), cw: 6);
      final empty = await capture(tester);
      final (px, a) = await place(tester, 'label_down', (m) => m.mainContentTop + 2);
      final m = state.mapper.value!;
      var strip = 0;
      for (var y = 0.0; y < m.mainContentTop; y += 1 / px.ratio) {
        for (var x = 0.0; x < m.mainRect.right; x += 1 / px.ratio) {
          if (px.at(x, y) != empty.at(x, y)) strip++;
        }
      }
      expect(strip, 0);
      expect(sides(px, a.dx, a.dy).$2, greaterThan(100));
    });

    testWidgets('没开图例留位时按主图窗格顶算', (tester) async {
      final (px, a) = await place(tester, 'label_down', (m) => m.mainRect.top + 3, legend: false);
      expect(state.mapper.value!.mainContentTop, state.mapper.value!.mainRect.top);
      final (above, below) = sides(px, a.dx, a.dy);
      expect(above, 0);
      expect(below, greaterThan(100));
    });

    for (final (from, side) in [('label_lower_right', -1), ('label_lower_left', 1)]) {
      testWidgets('$from 翻成往下伸的同侧样式，左右方向不变', (tester) async {
        final (px, a) = await place(tester, from, (m) => m.mainContentTop + 3);
        final (above, below) = sides(px, a.dx, a.dy);
        expect(above, 0);
        expect(below, greaterThan(100));
        // 气泡仍在锚点的同一侧（左或右）
        var l = 0, r = 0;
        for (var y = a.dy; y < a.dy + 30; y++) {
          for (var d = 3.0; d < 40; d++) {
            if (px.at(a.dx - d, y) == _magenta) l++;
            if (px.at(a.dx + d, y) == _magenta) r++;
          }
        }
        expect(side < 0 ? l : r, greaterThan(50));
        expect(side < 0 ? r : l, 0);
      });
    }
  });

  group('往下伸的气泡碰到主图底边', () {
    for (final (style, gap) in [
      ('label_up', 0.0),
      ('label_up', 34.0),
      ('label_upper_right', 0.0),
      ('label_upper_left', 0.0),
    ]) {
      testWidgets('$style${gap > 0 ? '，开 mainBottomGap' : ''}：翻到上面画', (tester) async {
        final (px, a) = await place(tester, style, (m) => m.mainRect.bottom - 3, gap: gap);
        expect(state.mapper.value!.mainBottomGapRect.height, gap);
        final (above, below) = sides(px, a.dx, a.dy);
        expect(above, greaterThan(100));
        expect(below, 0);
      });
    }

    testWidgets('离底边够远时照常往下画', (tester) async {
      final (px, a) = await place(tester, 'label_up', (m) => m.mainRect.bottom - 40);
      final (above, below) = sides(px, a.dx, a.dy);
      expect(above, 0);
      expect(below, greaterThan(100));
    });
  });

  group('锚点不在价位区里：整个不画', () {
    for (final (name, legend, y) in [
      ('锚点在图例那一条里、气泡往下伸', true, (KLineChartMapper m) => m.mainContentTop - 3),
      ('锚点在主图底边以下（价位低于可见范围）、气泡往上伸', true, (KLineChartMapper m) => m.mainRect.bottom + 3),
      ('没开图例留位，锚点高于主图窗格顶', false, (KLineChartMapper m) => m.mainRect.top - 3),
    ]) {
      testWidgets(name, (tester) async {
        scripts.setJson('fit', script([]));
        await pumpChart(tester, state, chart(legend: legend), cw: 6);
        final empty = await capture(tester);
        final m = state.mapper.value!;
        final p = m.yToPrice(y(m));
        final style = y(m) > m.mainRect.bottom ? 'label_down' : 'label_up';
        scripts.setJson('fit', script([(k, p, style), (k + 10, p, 'label_left')]));
        await tester.pump();
        await tester.pump();
        expect((await capture(tester)).diffCount(empty), 0);
      });
    }
  });

  testWidgets('左、右、居中的气泡竖直方向跨着锚点，不翻；锚点在价位区里照画', (tester) async {
    for (final style in ['label_left', 'label_right', 'label_center']) {
      final (px, a) = await place(tester, style, (m) => m.mainContentTop + 2);
      final (above, below) = sides(px, a.dx, a.dy);
      expect(below, greaterThan(20), reason: style);
      // 上半截照旧被图例下沿裁掉，锚点上方只剩两像素
      expect(above, lessThan(below), reason: style);
    }
  });

  testWidgets('标记里的 labelup/labeldown 不受影响', (tester) async {
    // 标记形状的气泡不走这个规则：锚点在图例那一条里时仍按原样画（被裁剪的部分照旧）
    final j = script([]);
    scripts.setJson('fit', j);
    await pumpChart(tester, state, chart(), cw: 6);
    final empty = await capture(tester);
    final m = state.mapper.value!;
    j['markers'] = [
      {
        'title': 'm', 'shape': 'labelup', 'location': 'absolute', 'size': 'small', 'text': 'M', //
        'points': [
          [t[k], m.yToPrice(m.mainContentTop - 3), 1],
        ],
      },
    ];
    scripts.setJson('fit', j);
    await tester.pump();
    await tester.pump();
    expect((await capture(tester)).diffCount(empty), greaterThan(50));
  });
}
