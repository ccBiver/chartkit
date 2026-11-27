// 方框左端在窗格左边以外时，方框文字从窗格左边开始画（带原来的内边距），拖动时一直留在屏幕里；
// 方框可见部分放不下整段文字时照旧被方框右边裁掉；方框整个在屏幕外时不画。竖直位置、颜色、字号不变。
// 方框左端在屏幕里时文字位置不变，由现有参考图测试覆盖（逐像素不变）。
import 'package:chartkit_flutter/chartkit_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tools/harness.dart';
import 'fixtures.dart';

const _yellow = Color(0xFFFFFF00);

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

  Map<String, dynamic> script(int k1, int k2, double top, double bottom, String halign) => {
        'v': 1,
        'script': {'id': 'box', 'name': 'Box'},
        'symbol': 'XAUUSD',
        'period': '15m',
        'pane': 'main',
        'precision': null,
        'bars': {'from': t.first, 'to': t.last, 'count': n, 'intervalMs': 900000},
        'palette': ['', '#FFFF00FF'],
        'series': [],
        'hlines': [],
        'fills': [],
        'markers': [],
        'trades': [],
        'bg': [],
        'barColors': [],
        'candles': [],
        'lines': [],
        'boxes': [
          {
            't1': t[k1], 'top': top, 't2': t[k2], 'bottom': bottom, 'extend': 'none', 'bg': 0, //
            'border': {'color': 0, 'width': 0, 'style': 'solid'},
            'text': {
              'text': 'WWWWWW', 'color': 1, 'size': 'large', 'halign': halign,
              'valign': 'center', //
            },
          },
        ],
        'labels': [],
        'tables': [],
        'inputs': [],
        'warnings': [],
      };

  KLineChart chart() => KLineChart(
        state: state,
        entranceAnimation: false,
        showVolume: false,
        showHighLow: false,
        mainIndicators: const [],
        scriptOutputs: scripts,
      );

  /// 文字（纯黄像素）的左右上下界，没有时返回 null。
  Rect? extent(Pixels px) {
    double? l, r, tp, b;
    for (var y = 0.0; y < px.height / px.ratio; y += 1 / px.ratio) {
      for (var x = 0.0; x < px.width / px.ratio; x += 1 / px.ratio) {
        if (px.at(x, y) != _yellow) continue;
        l = l == null || x < l ? x : l;
        r = r == null || x > r ? x : r;
        tp = tp == null || y < tp ? y : tp;
        b = b == null || y > b ? y : b;
      }
    }
    return l == null ? null : Rect.fromLTRB(l, tp!, r!, b!);
  }

  /// 放一个从第 [k1] 根到第 [k2] 根的方框，返回文字范围和方框左右端的 x。
  Future<(Rect?, double, double)> place(WidgetTester tester, int k1, int k2,
      {String halign = 'left', double scroll = 0}) async {
    scripts.setJson('box', script(k1, k2, 0, 0, halign));
    await pumpChart(tester, state, chart(), cw: 6, scroll: scroll);
    final m = state.mapper.value!;
    final mid = (m.mainContentTop + m.mainRect.bottom) / 2;
    scripts.setJson('box', script(k1, k2, m.yToPrice(mid - 20), m.yToPrice(mid + 20), halign));
    await tester.pump();
    await tester.pump();
    return (extent(await capture(tester)), m.indexToX(k1), m.indexToX(k2));
  }

  testWidgets('方框左端在屏幕里：文字从方框左端加内边距开始', (tester) async {
    final (text, left, _) = await place(tester, n - 40, n - 5);
    expect(left, greaterThan(20));
    expect(text, isNotNull);
    expect(text!.left, inInclusiveRange(left + 3, left + 6));
  });

  testWidgets('方框左端在屏幕外：文字从窗格左边加内边距开始，完整可见，竖直位置不变', (tester) async {
    final (inside, _, _) = await place(tester, n - 40, n - 5);
    final (text, left, _) = await place(tester, n - 200, n - 5);
    expect(left, lessThan(-100));
    expect(text, isNotNull);
    expect(text!.left, inInclusiveRange(2, 5));
    expect(text.width, closeTo(inside!.width, 1.5));
    expect(text.top, closeTo(inside.top, 0.5));
    expect(text.bottom, closeTo(inside.bottom, 0.5));
  });

  testWidgets('拖动时文字一直贴着窗格左边', (tester) async {
    for (final scroll in [0.0, -30.0, -90.0]) {
      final (text, left, _) = await place(tester, n - 200, n - 5, scroll: scroll);
      expect(left, lessThan(-100), reason: '$scroll');
      expect(text!.left, inInclusiveRange(2, 5), reason: '$scroll');
    }
  });

  testWidgets('居中的文字：方框中心在屏幕外时也退到窗格左边', (tester) async {
    final (text, left, right) = await place(tester, n - 300, n - 50, halign: 'center');
    expect((left + right) / 2, lessThan(0));
    expect(text, isNotNull);
    expect(text!.left, inInclusiveRange(2, 5));
  });

  testWidgets('靠右的文字放得下时位置不变', (tester) async {
    final (text, left, right) = await place(tester, n - 200, n - 20, halign: 'right');
    expect(left, lessThan(0));
    expect(text!.right, inInclusiveRange(right - 6, right - 3));
  });

  testWidgets('方框可见部分放不下整段文字：从窗格左边开始，被方框右边裁掉', (tester) async {
    final (full, _, _) = await place(tester, n - 40, n - 5);
    // 找一个右端只进屏幕十几像素的方框
    final m = state.mapper.value!;
    final k2 = m.xToIndex(15);
    final (text, left, right) = await place(tester, n - 300, k2);
    expect(left, lessThan(0));
    expect(right, lessThan(full!.width));
    expect(text, isNotNull);
    expect(text!.left, inInclusiveRange(2, 5));
    expect(text.right, lessThanOrEqualTo(right));
  });

  testWidgets('方框整个在屏幕外：不画', (tester) async {
    final (text, _, right) = await place(tester, n - 400, n - 300);
    expect(right, lessThan(0));
    expect(text, isNull);
  });
}
