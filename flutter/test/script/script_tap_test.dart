// 脚本图元点选（KLineChart.onScriptTap）：点到标记、成交、标签、线段、水平线、方框时回调，带类型、序号、锚点和点击位置；
// 命中范围比图形大一圈；重叠时按「点状图元 > 线 > 方框，同类取最近，一样近取画在上面的」选一个；
// 画线、回放、常驻十字光标先处理点击；不传回调时点击行为不变。
import 'package:chartkit_flutter/chartkit_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tools/harness.dart';
import 'fixtures.dart';

void main() {
  final candles = loadKlines();
  final n = candles.length;
  final t = [for (final c in candles) c.time];
  late KLineChartState state;
  late ScriptOutputController scripts;
  late List<ScriptHit> hits;

  setUp(() {
    state = KLineChartState(timeFrame: TimeFrame.m15)..setData(candles);
    scripts = ScriptOutputController(onAlignmentIssue: (i) => fail('$i'));
    hits = [];
  });
  tearDown(() {
    scripts.dispose();
    state.dispose();
  });

  Map<String, dynamic> script({
    String pane = 'main',
    List<Map<String, dynamic>> markers = const [],
    List<Map<String, dynamic>> trades = const [],
    List<Map<String, dynamic>> labels = const [],
    List<Map<String, dynamic>> lines = const [],
    List<Map<String, dynamic>> hlines = const [],
    List<Map<String, dynamic>> boxes = const [],
    List<Map<String, dynamic>> series = const [],
  }) =>
      {
        'v': 1,
        'script': {'id': 'tap', 'name': 'Tap'},
        'symbol': 'XAUUSD',
        'period': '15m',
        'pane': pane,
        'precision': null,
        'bars': {'from': t.first, 'to': t.last, 'count': n, 'intervalMs': 900000},
        'palette': ['', '#FF00FFFF', '#00FFFFFF', '#FFFFFFFF'],
        'series': series,
        'hlines': hlines,
        'fills': [],
        'markers': markers,
        'trades': trades,
        'bg': [],
        'barColors': [],
        'candles': [],
        'lines': lines,
        'boxes': boxes,
        'labels': labels,
        'tables': [],
        'inputs': [],
        'warnings': [],
      };

  Map<String, dynamic> marker(int k, double p) => {
        'title': 'm', 'shape': 'circle', 'location': 'absolute', 'size': 'small', //
        'points': [
          [t[k], p, 1],
        ],
      };
  Map<String, dynamic> hline(String id, double p) => {
        'id': id, 'title': id, 'price': p, 'color': 1, 'style': 'solid', 'width': 1,
        'visible': true, //
      };
  Map<String, dynamic> box(int k1, int k2, double top, double bottom) => {
        't1': t[k1], 'top': top, 't2': t[k2], 'bottom': bottom, 'extend': 'none', 'bg': 2, //
        'border': {'color': 1, 'width': 1, 'style': 'solid'},
      };
  Map<String, dynamic> label(int k, double p, String text) => {
        't': t[k], 'p': p, 'yloc': 'price', 'text': text, 'style': 'label_down', //
        'color': 1, 'textColor': 3, 'size': 'small', 'align': 'center',
      };

  KLineChart chart({
    bool tap = true,
    DrawingController? drawings,
    CrosshairTrigger trigger = CrosshairTrigger.tapOrLongPress,
    CrosshairDismiss dismiss = CrosshairDismiss.persistent,
    List<TradeMark> tradeMarks = const [],
    ValueChanged<TradeMark>? onTradeMarkTap,
  }) =>
      KLineChart(
        state: state,
        entranceAnimation: false,
        showVolume: false,
        mainIndicators: const [],
        scriptOutputs: scripts,
        drawingController: drawings,
        crosshairTrigger: trigger,
        crosshairDismiss: dismiss,
        tradeMarks: tradeMarks,
        onTradeMarkTap: onTradeMarkTap,
        onScriptTap: tap ? hits.add : null,
      );

  KLineChartMapper mapper() => state.mapper.value!;

  /// 主图中间的价位，往下 [dy] 像素。
  double priceAt(double dy) {
    final m = mapper();
    return m.yToPrice((m.mainContentTop + m.mainRect.bottom) / 2 + dy);
  }

  Offset at(int k, double price) => Offset(mapper().indexToX(k), mapper().priceToY(price));

  /// 先画一次空图拿到坐标，再设上 [json]。
  Future<void> show(WidgetTester tester, Map<String, dynamic> Function() json,
      {KLineChart Function()? build}) async {
    scripts.setJson('tap', script());
    await pumpChart(tester, state, (build ?? chart)(), cw: 6);
    final r = scripts.setJson('tap', json());
    expect(r.ok, isTrue, reason: '${r.error}');
    await tester.pump();
    await tester.pump();
  }

  Future<void> tap(WidgetTester tester, Offset local) async {
    final origin = tester.getTopLeft(find.byType(KLineChart));
    await tester.tapAt(origin + local);
    await tester.pump(const Duration(milliseconds: 500));
  }

  final k = n - 25;

  group('各类图元', () {
    testWidgets('标记：类型、组序号、点序号、时间、价格、点击位置', (tester) async {
      late double p;
      await show(tester, () {
        p = priceAt(0);
        return script(markers: [
          marker(k - 10, priceAt(60)),
          {
            ...marker(k, p),
            'points': [
              [t[k - 5], priceAt(-60), 1],
              [t[k], p, 1],
            ],
          },
        ]);
      });
      await tap(tester, at(k, p));
      expect(hits, hasLength(1));
      final h = hits.single;
      expect(h.kind, ScriptHitKind.marker);
      expect(h.scriptId, 'tap');
      expect((h.index, h.point), (1, 1));
      expect(h.time, t[k]);
      expect(h.price, p);
      expect(h.pane, ScriptPane.main);
      expect((h.position - at(k, p)).distance, lessThan(0.01));
      expect(h.output.markers[h.index].times[h.point!], t[k]);
      expect(state.crosshairIndex, -1, reason: '点到图元时不唤出十字光标');
    });

    testWidgets('成交：带 id 和成交价', (tester) async {
      late double p;
      await show(tester, () {
        p = priceAt(0);
        return script(trades: [
          {'t': t[k], 'price': p, 'side': 'buy', 'kind': 'entry', 'qty': 1, 'id': 'L1'},
        ]);
      });
      await tap(tester, at(k, p) + const Offset(0, 4));
      expect(hits.single.kind, ScriptHitKind.trade);
      expect((hits.single.id, hits.single.time, hits.single.price), ('L1', t[k], p));
    });

    testWidgets('标签：点在气泡上（锚点上方）', (tester) async {
      late double p;
      await show(tester, () {
        p = priceAt(0);
        return script(labels: [label(k, p, 'Signal')]);
      });
      await tap(tester, at(k, p) - const Offset(0, 14));
      expect(hits.single.kind, ScriptHitKind.label);
      expect((hits.single.index, hits.single.time, hits.single.price), (0, t[k], p));
      expect(hits.single.output.labels[0].text, 'Signal');
    });

    testWidgets('线段：点在线身中段，带两端', (tester) async {
      late double p1, p2;
      await show(tester, () {
        p1 = priceAt(-40);
        p2 = priceAt(40);
        return script(lines: [
          {
            't1': t[k - 20], 'p1': p1, 't2': t[k], 'p2': p2, 'extend': 'none', //
            'color': 1, 'style': 'dashed', 'width': 1,
          },
        ]);
      });
      await tap(tester, (at(k - 20, p1) + at(k, p2)) / 2);
      final h = hits.single;
      expect(h.kind, ScriptHitKind.line);
      expect((h.time, h.price, h.time2, h.price2), (t[k - 20], p1, t[k], p2));
    });

    testWidgets('水平线：带 id 和价格，没有时间', (tester) async {
      late double p;
      await show(tester, () {
        p = priceAt(0);
        return script(hlines: [hline('R1', priceAt(-50)), hline('P', p)]);
      });
      await tap(tester, at(k - 30, p));
      final h = hits.single;
      expect((h.kind, h.index, h.id, h.price, h.time), (ScriptHitKind.hline, 1, 'P', p, null));
    });

    testWidgets('方框：点在框里，带上下沿和两端时间', (tester) async {
      late double top, bottom;
      await show(tester, () {
        top = priceAt(-30);
        bottom = priceAt(30);
        return script(boxes: [box(k - 20, k, top, bottom)]);
      });
      await tap(tester, at(k - 10, priceAt(0)));
      final h = hits.single;
      expect(h.kind, ScriptHitKind.box);
      expect((h.time, h.price, h.time2, h.price2), (t[k - 20], top, t[k], bottom));
    });

    testWidgets('脚本副图里的图元：pane 是 sub', (tester) async {
      await show(tester, () => script(pane: 'sub', hlines: [hline('Z', 50), hline('Top', 80)]));
      // 副图窗格长出来的动画
      await tester.pump(const Duration(seconds: 1));
      // 在主图下面找水平线画出来的那一行（洋红）
      final px = await capture(tester);
      final m = mapper();
      final rows = [
        for (var y = m.mainRect.bottom + 1; y < px.height / px.ratio; y += 1 / px.ratio)
          if (px.at(100, y) == const Color(0xFFFF00FF)) y,
      ];
      expect(rows, isNotEmpty);
      // 最下面那条是价位低的 Z
      await tap(tester, Offset(100, rows.last + 2));
      final h = hits.single;
      expect((h.pane, h.kind, h.id, h.price), (ScriptPane.sub, ScriptHitKind.hline, 'Z', 50.0));
      // 两条线中间、离哪条都远：不回调
      await tap(tester, Offset(100, (rows.first + rows.last) / 2));
      expect(hits, hasLength(1));
    });
  });

  group('命中范围和重叠', () {
    testWidgets('离标记形状 10 像素以内算点到，20 像素外不算', (tester) async {
      late double p;
      await show(tester, () {
        p = priceAt(0);
        return script(markers: [marker(k, p)]);
      });
      // 小号圆半径 4.5，外放 12
      await tap(tester, at(k, p) + const Offset(14, 0));
      expect(hits, hasLength(1));
      await tap(tester, at(k, p) + const Offset(0, 24));
      expect(hits, hasLength(1));
    });

    testWidgets('标记压在方框里：标记优先；点在方框别处是方框', (tester) async {
      late double p;
      await show(tester, () {
        p = priceAt(0);
        return script(
            markers: [marker(k - 10, p)], boxes: [box(k - 20, k, priceAt(-30), priceAt(30))]);
      });
      await tap(tester, at(k - 10, p));
      expect(hits.last.kind, ScriptHitKind.marker);
      await tap(tester, at(k - 3, p));
      expect(hits.last.kind, ScriptHitKind.box);
    });

    testWidgets('水平线穿过方框：线优先', (tester) async {
      late double p;
      await show(tester, () {
        p = priceAt(0);
        return script(hlines: [hline('P', p)], boxes: [box(k - 20, k, priceAt(-30), priceAt(30))]);
      });
      await tap(tester, at(k - 10, p) + const Offset(0, 3));
      expect(hits.single.kind, ScriptHitKind.hline);
    });

    testWidgets('两条水平线都在范围内：取近的', (tester) async {
      late double a, b;
      await show(tester, () {
        a = priceAt(-6);
        b = priceAt(6);
        return script(hlines: [hline('A', a), hline('B', b)]);
      });
      await tap(tester, at(k, priceAt(4)));
      expect(hits.single.id, 'B');
      await tap(tester, at(k, priceAt(-5)));
      expect(hits.last.id, 'A');
    });

    testWidgets('两个标签叠在一起：取后画的（在上面的）', (tester) async {
      late double p;
      await show(tester, () {
        p = priceAt(0);
        return script(labels: [label(k, p, 'First'), label(k, p, 'Second')]);
      });
      await tap(tester, at(k, p) - const Offset(0, 14));
      expect(hits.single.index, 1);
    });

    testWidgets('两个脚本的图元叠在一起：取后设置的脚本', (tester) async {
      late double p;
      await show(tester, () {
        p = priceAt(0);
        return script(markers: [marker(k, p)]);
      });
      scripts.setJson('second', {
        ...script(markers: [marker(k, p)]),
        'script': {'id': 'second', 'name': 'Second'},
      });
      await tester.pump();
      await tap(tester, at(k, p));
      expect(hits.single.scriptId, 'second');
    });
  });

  group('和其他手势的先后', () {
    testWidgets('不传回调：点在图元上照常唤出十字光标', (tester) async {
      late double p;
      await show(tester, () {
        p = priceAt(0);
        return script(markers: [marker(k, p)]);
      }, build: () => chart(tap: false));
      await tap(tester, at(k, p));
      expect(state.crosshairIndex, isNot(-1));
    });

    testWidgets('传了回调、点在空白：照常唤出十字光标，不回调', (tester) async {
      await show(tester, () => script(markers: [marker(k, priceAt(0))]));
      await tap(tester, at(k - 20, priceAt(80)));
      expect(hits, isEmpty);
      expect(state.crosshairIndex, isNot(-1));
    });

    testWidgets('常驻十字光标显示时：这次点击只关掉光标', (tester) async {
      late double p;
      await show(tester, () {
        p = priceAt(0);
        return script(markers: [marker(k, p)]);
      });
      await tap(tester, at(k - 20, priceAt(80)));
      expect(state.crosshairIndex, isNot(-1));
      await tap(tester, at(k, p));
      expect(hits, isEmpty);
      expect(state.crosshairIndex, -1);
      await tap(tester, at(k, p));
      expect(hits, hasLength(1));
    });

    testWidgets('长按图元：照常唤出十字光标，不回调', (tester) async {
      late double p;
      await show(tester, () {
        p = priceAt(0);
        return script(markers: [marker(k, p)]);
      });
      final origin = tester.getTopLeft(find.byType(KLineChart));
      await tester.longPressAt(origin + at(k, p));
      await tester.pump();
      expect(hits, isEmpty);
    });

    testWidgets('画线工具选着时：点击给画线落点，不回调', (tester) async {
      final drawings = DrawingController(style: const DrawingStyle(color: Color(0xFF00FF00)));
      addTearDown(drawings.dispose);
      late double p;
      await show(tester, () {
        p = priceAt(0);
        return script(markers: [marker(k, p)]);
      }, build: () => chart(drawings: drawings));
      drawings.tool = DrawingTool.horizontalLine;
      await tap(tester, at(k, p));
      expect(hits, isEmpty);
      expect(drawings.drawings, hasLength(1));
    });

    testWidgets('画线和脚本水平线重合：画线优先（选中画线）；选中时点空白只取消选中', (tester) async {
      final drawings = DrawingController(style: const DrawingStyle(color: Color(0xFF00FF00)));
      addTearDown(drawings.dispose);
      late double p;
      await show(tester, () {
        p = priceAt(0);
        return script(hlines: [hline('P', p)]);
      }, build: () => chart(drawings: drawings));
      drawings.add(Drawing(
        id: 'd',
        tool: DrawingTool.horizontalLine,
        anchors: [DrawingAnchor(t[k], p)],
        style: const DrawingStyle(color: Color(0xFF00FF00)),
      ));
      await tester.pump();
      await tap(tester, at(k, p));
      expect(drawings.selectedId, 'd');
      expect(hits, isEmpty);
      // 选中画线时点空白：这次只取消选中
      await tap(tester, at(k - 20, priceAt(60)));
      expect(drawings.selectedId, isNull);
      expect(hits, isEmpty);
      // 没有画线挡着时点脚本水平线：回调
      drawings.remove('d');
      await tester.pump();
      await tap(tester, at(k - 20, p));
      expect(hits.single.id, 'P');
    });

    testWidgets('买卖标记：点到脚本图元时不再触发 onTradeMarkTap，点同一根的别处照常触发', (tester) async {
      final marks = <TradeMark>[];
      late double p;
      await show(tester, () {
        p = priceAt(0);
        return script(markers: [marker(k, p)]);
      },
          build: () => chart(
                dismiss: CrosshairDismiss.onRelease,
                tradeMarks: [TradeMark(time: t[k], isBuy: true, price: candles[k].low)],
                onTradeMarkTap: marks.add,
              ));
      await tap(tester, at(k, p));
      expect((hits.length, marks.length), (1, 0));
      await tap(tester, at(k, priceAt(80)));
      expect((hits.length, marks.length), (1, 1));
    });
  });

  testWidgets('传不传回调，画面逐像素一样', (tester) async {
    Map<String, dynamic> json() => script(
          markers: [marker(k, priceAt(0))],
          labels: [label(k - 5, priceAt(20), 'L')],
          hlines: [hline('P', priceAt(-20))],
          boxes: [box(k - 20, k - 10, priceAt(-30), priceAt(30))],
        );
    await show(tester, json, build: () => chart(tap: false));
    final a = await capture(tester);
    await show(tester, json);
    final b = await capture(tester);
    expect(a.diffCount(b), 0);
  });
}
