// 画到主图的图元：副图策略的成交点一律画在主图；副图脚本里标了 `pane: "main"` 的图元画到主图，
// 按主图的规则参与（或不参与）价格区间，也不计入副图纵轴。期望位置用独立的写法算。
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:chartkit_flutter/chartkit_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

const _iv = 900000;
final _key = GlobalKey();

/// 覆盖率：像素在「背景 → 目标色」之间的比例，三个通道必须一致；目标色和背景接近的通道要保持背景色。
double _coverage(ui.Color p, ui.Color bg, ui.Color c) {
  final ratios = <double>[];
  for (final (pv, bv, cv) in [(p.r, bg.r, c.r), (p.g, bg.g, c.g), (p.b, bg.b, c.b)]) {
    if ((cv - bv).abs() < 0.2) {
      if ((pv - bv).abs() > (cv - bv).abs() + 0.05) return 0;
    } else {
      ratios.add((pv - bv) / (cv - bv));
    }
  }
  if (ratios.isEmpty) return 0;
  final lo = ratios.reduce((a, b) => a < b ? a : b), hi = ratios.reduce((a, b) => a > b ? a : b);
  return hi - lo > 0.15 ? 0 : lo.clamp(0.0, 1.0);
}

class _Image {
  _Image(this.image, this.bytes);

  final ui.Image image;
  final ByteData bytes;

  ui.Color at(int x, int y) {
    final o = (y * image.width + x) * 4;
    return ui.Color.fromARGB(255, bytes.getUint8(o), bytes.getUint8(o + 1), bytes.getUint8(o + 2));
  }

  /// 矩形 [r] 里颜色是 [c] 的像素：(覆盖率加权的中心 x, 最低一行 y, 最高一行 y, 个数)。
  ({double cx, int top, int bottom, int count}) find(ui.Color c, Rect r, ui.Color bg) {
    var sx = 0.0, w = 0.0, top = 1 << 30, bottom = -1, n = 0;
    for (var y = r.top.floor(); y < r.bottom.ceil(); y++) {
      for (var x = r.left.floor(); x < r.right.ceil(); x++) {
        final k = _coverage(at(x, y), bg, c);
        if (k < 0.3) continue;
        sx += (x + 0.5) * k;
        w += k;
        n++;
        if (y < top) top = y;
        if (y > bottom) bottom = y;
      }
    }
    return (cx: w == 0 ? double.nan : sx / w, top: top, bottom: bottom, count: n);
  }
}

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

  // 涨跌色换成测试里好找的颜色；分时模式不画蜡烛，主图上就只有成交点用这两个颜色
  final theme = ChartTheme.dark.copyWith(
    candleUp: const Color(0xFF00FF00),
    candleDown: const Color(0xFFFF00FF),
  );
  const sellColor = ui.Color(0xFFFF00FF);

  Future<_Image> pump(WidgetTester tester,
      {ChartMode mode = ChartMode.candle, ChartTheme? chartTheme, String? golden}) async {
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Center(
        child: RepaintBoundary(
          key: _key,
          child: SizedBox(
            width: 400,
            height: 560,
            child: KLineChart(
              state: state,
              theme: chartTheme ?? ChartTheme.dark,
              mode: mode,
              entranceAnimation: false,
              showVolume: false,
              scriptOutputs: scripts,
            ),
          ),
        ),
      ),
    ));
    state.setViewport(candleWidth: 5, scrollOffset: 30 * 5.0); // 右边缘是第 969 根
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(tester.takeException(), isNull);
    if (golden != null) {
      await expectLater(
          find.byKey(_key), matchesGoldenFile('../../testdata/primitives/goldens/$golden.png'));
    }
    late _Image img;
    await tester.runAsync(() async {
      final boundary = _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      img = _Image(image, (await image.toByteData())!);
    });
    return img;
  }

  /// 独立公式：第 k 根中心的 x、价格的 y。
  double xOf(int k) {
    final m = state.mapper.value!;
    final rightFloat = (candles.length - 1) - state.scrollOffset / m.candleWidth;
    return m.mainRect.right - (rightFloat - k + 0.5) * m.candleWidth;
  }

  double yOf(double price) {
    final m = state.mapper.value!;
    final y1 = m.priceToY(3000), y2 = m.priceToY(4000);
    return y1 + (price - 3000) / 1000 * (y2 - y1);
  }

  group('strategy trades of a sub-pane script', () {
    testWidgets('are drawn on the main chart at their bar and price', (tester) async {
      scripts.setJson('st-macd', sampleJson('st-macd'));
      final img = await pump(tester, mode: ChartMode.timeLine, chartTheme: theme);
      final raw = (jsonDecode(sampleJson('st-macd'))['trades'] as List)
          .where((t) => t['t'] == times[961])
          .toList();
      expect(raw.map((t) => t['side']).toSet(), {'sell'},
          reason: 'bar 961 has one sell (exit + entry)');
      final price = (raw.first['price'] as num).toDouble();
      final x = xOf(961), y = yOf(price);
      final main = state.mapper.value!.mainRect;
      expect(y, inExclusiveRange(main.top, main.bottom));
      final bg = img.at(2, 2);
      final hit = img.find(sellColor, Rect.fromLTRB(x - 8, y - 14, x + 8, y + 4), bg);
      expect(hit.count, greaterThan(5));
      expect(hit.cx, closeTo(x, 0.5));
      // 卖出：三角朝下，尖在成交价
      expect(hit.bottom + 0.5, closeTo(y, 1.5));
      // 副图里没有成交点
      final sub = Rect.fromLTRB(0, main.bottom + 1, main.right, 560.0 - 20);
      expect(img.find(sellColor, sub, img.at(2, main.bottom.ceil() + 30)).count, 0);
    });

    testWidgets('do not stretch the sub pane: its scale follows its own series', (tester) async {
      scripts.setJson('st-macd', sampleJson('st-macd'));
      final img = await pump(tester, golden: '22_sub_strategy_trades_on_main');
      final main = state.mapper.value!.mainRect;
      final subTop = main.bottom, subBottom = 560.0 - 18; // 时间轴以上
      // MACD 线（#4C8DFF）在副图里上下铺开；若成交价（3500 上下）算进纵轴，它会被压成一条线
      const macd = ui.Color(0xFF4C8DFF);
      final hit = img.find(macd, Rect.fromLTRB(0, subTop + 20, main.right, subBottom),
          img.at(2, subBottom.floor() - 2));
      expect(hit.count, greaterThan(50));
      expect(hit.bottom - hit.top, greaterThan((subBottom - subTop - 20) * 0.5));
    });
  });

  group('elements marked pane: "main" in a sub-pane script', () {
    Map<String, dynamic> synthetic() {
      final lastVisible = 969;
      final first = lastVisible - 70;
      final hi = candles
          .sublist(first, lastVisible + 1)
          .map((c) => c.high)
          .reduce((a, b) => a > b ? a : b);
      final lo =
          candles.sublist(first, lastVisible + 1).map((c) => c.low).reduce((a, b) => a < b ? a : b);
      final mid = (hi + lo) / 2;
      return {
        'v': 1,
        'script': {'id': 'mix', 'name': 'Mixed panes'},
        'symbol': 'XAUUSD',
        'period': '15m',
        'pane': 'sub',
        'precision': null,
        'bars': {'from': times.first, 'to': times.last, 'count': 1000, 'intervalMs': _iv},
        'palette': [
          '',
          '#FF00FFFF',
          '#0000FFFF',
          '#FFFF00FF',
          '#00FF00FF',
          '#FF8000FF',
          '#80808040'
        ],
        'series': [
          {
            'id': 'own', 'kind': 'line', 'title': 'Own', 'visible': true, 'color': 2, //
            'values': [for (var i = 0; i < 1000; i++) (i % 50) * 2.0], 'width': 2, 'style': 'solid',
            'step': false, 'gaps': 'connect',
          },
          {
            'id': 'up',
            'kind': 'line',
            'title': 'Overlay',
            'visible': true,
            'color': 1,
            'pane': 'main',
            'values': [for (final c in candles) c.close + 60],
            'width': 2,
            'style': 'solid',
            'step': false,
            'gaps': 'connect',
          },
        ],
        'hlines': [
          {
            'id': 'h',
            'title': 'Mid',
            'price': mid,
            'color': 3,
            'style': 'dashed',
            'width': 1,
            'visible': true,
            'pane': 'main'
          },
        ],
        'fills': [
          {
            'between': ['up', 'h'],
            'color': 6,
            'pane': 'main'
          },
        ],
        'markers': [
          {
            'title': 'm', 'shape': 'diamond', 'location': 'abovebar', 'size': 'normal',
            'pane': 'main', //
            'points': [
              [times[950], candles[950].high, 5],
            ],
          },
        ],
        'trades': [],
        'bg': [
          {
            'runs': [
              [times[930], times[934], 6],
            ],
            'pane': 'main',
          },
        ],
        'barColors': [],
        'candles': [
          {
            'title': 'c', 'bars': false, 'pane': 'main', 'color': 4, //
            'open': [for (var i = 0; i < 1000; i++) i >= 955 && i <= 958 ? lo + 2 : null],
            'high': [for (var i = 0; i < 1000; i++) i >= 955 && i <= 958 ? lo + 8 : null],
            'low': [for (var i = 0; i < 1000; i++) i >= 955 && i <= 958 ? lo - 4 : null],
            'close': [for (var i = 0; i < 1000; i++) i >= 955 && i <= 958 ? lo + 6 : null],
          },
        ],
        'lines': [
          {
            't1': times[905],
            'p1': hi,
            't2': times[925],
            'p2': lo,
            'extend': 'none',
            'color': 4,
            'style': 'arrow_right',
            'width': 2,
            'pane': 'main'
          },
        ],
        'boxes': [
          {
            't1': times[940], 'top': mid + 10, 't2': times[948], 'bottom': mid - 10,
            'extend': 'none', //
            'bg': 6, 'border': {'color': 5, 'width': 1, 'style': 'solid'}, 'pane': 'main',
            'text': {
              'text': 'OB',
              'color': 5,
              'size': 'small',
              'halign': 'center',
              'valign': 'center'
            },
          },
        ],
        'labels': [
          {
            't': times[962],
            'p': lo,
            'yloc': 'price',
            'text': 'L',
            'style': 'label_up',
            'color': 5,
            'textColor': 3,
            'size': 'small',
            'align': 'center',
            'pane': 'main'
          },
        ],
        'tables': [
          {
            'position': 'top_left', 'columns': 1, 'rows': 1, 'bg': 6, 'pane': 'main', //
            'frame': {'color': 5, 'width': 1}, 'border': {'color': 0, 'width': 0},
            'cells': [
              [0, 0, 'MAIN', 5, 0, 'small', 'left'],
            ],
          },
          {
            'position': 'top_right', 'columns': 1, 'rows': 1, 'bg': 6, //
            'frame': {'color': 2, 'width': 1}, 'border': {'color': 0, 'width': 0},
            'cells': [
              [0, 0, 'SUB', 2, 0, 'small', 'left'],
            ],
          },
        ],
        'inputs': [],
        'warnings': [],
      };
    }

    test('the field is parsed on every kind; other values warn and are ignored', () {
      final r = parseScriptOutput(synthetic());
      expect(r.warnings, isEmpty);
      final o = r.output!;
      expect([for (final s in o.series) s.mainPane], [false, true]);
      expect(o.hlines.single.mainPane, isTrue);
      expect(o.fills.single.mainPane, isTrue);
      expect(o.markers.single.mainPane, isTrue);
      expect(o.bg.single.mainPane, isTrue);
      expect(o.candles.single.mainPane, isTrue);
      expect(o.lines.single.mainPane, isTrue);
      expect(o.boxes.single.mainPane, isTrue);
      expect(o.labels.single.mainPane, isTrue);
      expect([for (final t in o.tables) t.mainPane], [true, false]);
      final bad = synthetic();
      (bad['series'] as List)[1]['pane'] = 'overlay';
      final rb = parseScriptOutput(bad);
      expect(rb.output!.series[1].mainPane, isFalse);
      expect(rb.warnings.single, contains('pane "overlay"'));
    });

    testWidgets('are drawn on the main chart and only the right ones widen the price range',
        (tester) async {
      scripts.setJson('mix', synthetic());
      final img = await pump(tester, golden: '23_sub_elements_on_main');
      final m = state.mapper.value!;
      // 标了 main 的曲线（收盘价 + 60）进主图价格区间
      final visibleMax = [for (var i = m.firstIndex; i <= m.lastIndex; i++) candles[i].close + 60]
          .reduce((a, b) => a > b ? a : b);
      expect(m.yToPrice(m.mainRect.top), greaterThanOrEqualTo(visibleMax));
      // 它画在主图第 960 根、价格 close + 60 的位置
      final x = xOf(960), y = yOf(candles[960].close + 60);
      final hit = img.find(
          const ui.Color(0xFFFF00FF), Rect.fromLTRB(x - 1, y - 6, x + 1, y + 6), img.at(2, 2));
      expect(hit.count, greaterThan(0));
      expect((hit.top + hit.bottom) / 2 + 0.5, closeTo(y, 1.5));
      // 副图纵轴只按自己的序列（0～98）算：蓝线上下铺开
      final hitOwn = img.find(
          const ui.Color(0xFF0000FF),
          Rect.fromLTRB(0, m.mainRect.bottom + 20, m.mainRect.right, 560.0 - 18),
          img.at(2, 560 - 22));
      expect(hitOwn.bottom - hitOwn.top, greaterThan((560 - 18 - m.mainRect.bottom - 20) * 0.6));
      // 主图上没有自己的序列，副图上没有标了 main 的曲线
      expect(
          img
              .find(const ui.Color(0xFF0000FF),
                  Rect.fromLTRB(0, 20, m.mainRect.right, m.mainRect.bottom - 2), img.at(2, 2))
              .count,
          0);
      expect(
          img
              .find(const ui.Color(0xFFFF00FF),
                  Rect.fromLTRB(0, m.mainRect.bottom + 2, m.mainRect.right, 540), img.at(2, 540))
              .count,
          0);
    });

    testWidgets('valuesAt reports the pane each series is drawn on', (tester) async {
      scripts.setJson('mix', synthetic());
      await pump(tester);
      final v = scripts.valuesAt(960);
      expect(
          {for (final e in v) e.seriesId: e.pane}, {'own': ScriptPane.sub, 'up': ScriptPane.main});
    });

    test('in a main-pane script the field changes nothing', () {
      final j = synthetic()..['pane'] = 'main';
      final o = parseScriptOutput(j).output!;
      final c = ScriptOutputController()..setOutput('m', o);
      addTearDown(c.dispose);
      c.attachCandles(candles, intervalMs: _iv);
      expect(c.valuesAt(960).map((e) => e.pane).toSet(), {ScriptPane.main});
      expect(c.subPaneIds, isEmpty);
    });
  });
}
