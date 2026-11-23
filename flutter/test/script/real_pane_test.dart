// 真样本里带 pane: "main" 的图元（来自副图脚本里的 force_overlay）：
// 1. 副图纵轴只按留在副图的内容算，全部 1000 根上的范围和服务端脚本引擎修复后的输出里这个窗格的数值范围一致；
// 2. 画到主图的曲线、自绘 K 线不会把主图价格区间撑出 K 线的范围；
// 3. 这些图元画在主图对应 K 线的位置。做法：同一份输出渲染两次，第二次只把目标图元的颜色改成 0（不画，
//    价格区间不受影响），两张图的差异就是这个图元画出来的地方，再和独立公式算出的位置比。
import 'dart:convert';
import 'dart:typed_data';

import 'package:chartkit_flutter/chartkit_flutter.dart';
import 'package:chartkit_flutter/src/script/script_align.dart' show ResolvedScript;
import 'package:chartkit_flutter/src/script/script_painter.dart'
    show scriptMainRange, scriptSubRange;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

const _tex = 'com-trend-exhaustion-continuation-map-bullby';
const _srv = 'com-signed-realized-variance-trend-backquant';
const _htf = 'com-macd-with-htf-panels-theultimator5';
const _kalman = 'com-innovation-adaptive-kalman-filter-oscill';
const _abo = 'com-adaptive-breakout-oscillator-schizoquant';

final _key = GlobalKey();
const _size = Size(400, 560);

/// 两张图里不一样的像素的外框；没有不一样的返回 null。
Rect? _diff(ByteData a, ByteData b, int width) {
  var l = 1 << 30, t = 1 << 30, r = -1, btm = -1;
  for (var i = 0; i < a.lengthInBytes; i += 4) {
    var d = 0;
    for (var c = 0; c < 3; c++) {
      final v = (a.getUint8(i + c) - b.getUint8(i + c)).abs();
      if (v > d) d = v;
    }
    if (d <= 3) continue;
    final p = i ~/ 4, x = p % width, y = p ~/ width;
    if (x < l) l = x;
    if (x > r) r = x;
    if (y < t) t = y;
    if (y > btm) btm = y;
  }
  return r < 0 ? null : Rect.fromLTRB(l.toDouble(), t.toDouble(), r + 1.0, btm + 1.0);
}

void main() {
  final candles = loadKlines();
  final times = [for (final c in candles) c.time];
  final kHigh = candles.map((c) => c.high).reduce((a, b) => a > b ? a : b);
  final kLow = candles.map((c) => c.low).reduce((a, b) => a < b ? a : b);

  ResolvedScript resolved(String id) {
    final o = loadSample(id);
    return ResolvedScript(o, alignScriptOutput(o, candles, intervalMs: 900000).alignment!);
  }

  group('ranges', () {
    // 服务端脚本引擎修复 display 和 force_overlay 后，输出里各副图窗格的数值范围（保留两位小数）
    const engine = {
      _abo: (-81.24, 80.51),
      _kalman: (-100.0, 100.0),
      _htf: (-33.73, 17.27),
      'com-redk-indicator-amplifier-redk-i-amp': (-1.5, 101.5),
      _srv: (-0.88, 0.85),
      _tex: (-150.0, 100.0),
    };
    for (final e in engine.entries) {
      test('sub-pane scale of ${e.key} matches the engine output range', () {
        final r = scriptSubRange(resolved(e.key), 0, 999)!;
        expect(r.min, closeTo(e.value.$1, 0.005));
        expect(r.max, closeTo(e.value.$2, 0.005));
      });
    }

    test('curves and candles drawn on the main chart stay inside the K-line range', () {
      for (final id in [_tex, _srv, _htf, _kalman, _abo]) {
        final r = resolved(id);
        final m = scriptMainRange([(id, r, 0)], 0, 999);
        if (m == null) continue; // 只有对象画到主图，不参与价格区间
        expect(m.min, greaterThanOrEqualTo(kLow), reason: id);
        expect(m.max, lessThanOrEqualTo(kHigh), reason: id);
      }
      expect(scriptMainRange([(_tex, resolved(_tex), 0)], 0, 999), isNull,
          reason: 'boxes and markers do not take part in the price range');
    });
  });

  group('positions on the main chart', () {
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

    Future<ByteData> render(WidgetTester tester, Map<String, dynamic> json,
        {double blank = 0, double cw = 8}) async {
      scripts.setJson('s', jsonEncode(json));
      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: RepaintBoundary(
            key: _key,
            child: SizedBox.fromSize(
              size: _size,
              child: KLineChart(
                state: state,
                entranceAnimation: false,
                showVolume: false,
                blankScrollWidth: blank,
                scriptOutputs: scripts,
              ),
            ),
          ),
        ),
      ));
      // 可见约第 958..999 根；留白时把最新一根左移 [blank] 像素
      state.setViewport(candleWidth: cw, scrollOffset: -blank);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      late ByteData bytes;
      await tester.runAsync(() async {
        final boundary = _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage();
        bytes = (await image.toByteData())!;
      });
      return bytes;
    }

    /// 渲染 [id] 两次（第二次经 [hide] 改过），返回差异外框和主图矩形。
    Future<(Rect, Rect)> diff(
        WidgetTester tester, String id, void Function(Map<String, dynamic>) hide,
        {double blank = 0, double cw = 8}) async {
      final full = jsonDecode(sampleJson(id)) as Map<String, dynamic>;
      final a = await render(tester, full, blank: blank, cw: cw);
      final mainRect = state.mapper.value!.mainRect;
      final hidden = jsonDecode(sampleJson(id)) as Map<String, dynamic>;
      hide(hidden);
      final b = await render(tester, hidden, blank: blank, cw: cw);
      expect(state.mapper.value!.mainRect, mainRect, reason: 'hiding must not move the layout');
      final box = _diff(a, b, _size.width.toInt());
      expect(box, isNotNull, reason: 'the element must be drawn somewhere');
      return (box!, mainRect);
    }

    double xOf(int k) {
      final m = state.mapper.value!;
      // 用图上实际生效的滚动量（留白超过蜡烛区 90% 时会被夹住），由最新一根的位置反推右边缘的下标
      final rightFloat =
          (candles.length - 1) + (m.mainRect.right - m.indexToX(999)) / m.candleWidth - 0.5;
      return m.mainRect.right - (rightFloat - k + 0.5) * m.candleWidth;
    }

    double yOf(double price) {
      final m = state.mapper.value!;
      final y1 = m.priceToY(3000), y2 = m.priceToY(4000);
      return y1 + (price - 3000) / 1000 * (y2 - y1);
    }

    testWidgets('$_tex: a box (994..998, 3530.03..3503.21) on the main chart', (tester) async {
      final (box, main) = await diff(tester, _tex, (j) {
        final b = (j['boxes'] as List)[221] as Map;
        expect(b['pane'], 'main');
        expect([b['t1'], b['t2']], [times[994], times[998]]);
        b['bg'] = 0;
        b['border']['color'] = 0;
      });
      expect(box.bottom, lessThanOrEqualTo(main.bottom), reason: 'inside the main pane');
      expect(box.left, closeTo(xOf(994), 1.5));
      expect(box.right, closeTo(xOf(998), 1.5));
      expect(box.top, closeTo(yOf(3530.03), 1.5));
      expect(box.bottom, closeTo(yOf(3503.21), 1.5));
    });

    testWidgets('$_tex: markers and the table go to the main chart', (tester) async {
      final (box, main) = await diff(tester, _tex, (j) {
        for (final m in j['markers'] as List) {
          if (m['pane'] == 'main') {
            for (final p in m['points'] as List) {
              p[2] = 0;
            }
          }
        }
        for (final t in j['tables'] as List) {
          expect(t['pane'], 'main');
          t['bg'] = 0;
          t['frame']['color'] = 0;
          t['border']['color'] = 0;
          for (final c in t['cells'] as List) {
            c[3] = 0;
            c[4] = 0;
          }
        }
      });
      expect(box.bottom, lessThanOrEqualTo(main.bottom));
      expect(box.right, greaterThan(main.right - 60),
          reason: 'the table sits top right of the main pane');
      expect(box.top, lessThan(10));
    });

    testWidgets('$_srv: its candles are drawn on the main chart, bar by bar', (tester) async {
      final o = loadSample(_srv);
      final c = o.candles.single;
      expect(c.mainPane, isTrue);
      final (box, main) = await diff(tester, _srv, (j) {
        final cs = (j['candles'] as List).single as Map;
        cs['colors'] = List.filled(1000, 0);
        cs.remove('color');
      });
      expect(box.bottom, lessThanOrEqualTo(main.bottom));
      final m = state.mapper.value!;
      var hi = double.negativeInfinity, lo = double.infinity;
      for (var k = m.firstIndex; k <= m.lastIndex; k++) {
        // 颜色 0 的那根本来就不画；中心在左边缘外的那根影线被裁掉
        if (c.high[k].isNaN || c.colorAt(k) == 0 || xOf(k) < 0) continue;
        hi = hi > c.high[k] ? hi : c.high[k];
        lo = lo < c.low[k] ? lo : c.low[k];
      }
      expect(box.top, closeTo(yOf(hi), 1.5));
      expect(box.bottom, closeTo(yOf(lo), 1.5));
      expect(box.right, closeTo(xOf(999) + 8 * 0.375, 1.5), reason: 'last body edge');
    });

    testWidgets('$_htf: a histogram bar 40 bars past the last one (3546.962..3516.653)',
        (tester) async {
      // 这个脚本画到主图的 295 条线段都在最后一根右边第 20～118 根（大周期 K 线面板），要留白才看得到。
      // 线段不进主图价格区间，这个视野的价格上沿低于柱子的基线 3546.962，柱子顶端被裁在主图上沿。
      final (box, main) = await diff(tester, _htf, blank: 300, cw: 4, (j) {
        final l = (j['lines'] as List)[118] as Map;
        expect(l['pane'], 'main');
        expect([l['t1'], l['t2'], l['width']],
            [times[999] + 40 * 900000, times[999] + 40 * 900000, 3]);
        l['color'] = 0;
      });
      expect(box.bottom, lessThanOrEqualTo(main.bottom));
      expect(box.center.dx, closeTo(xOf(1039), 1));
      expect(box.width, closeTo(3, 1.5));
      expect(box.bottom, closeTo(yOf(3516.653), 1.5));
      expect(box.top, closeTo(yOf(3546.962) < main.top ? main.top : yOf(3546.962), 1.5));
    });

    testWidgets('$_kalman: the IAKF line (p8) is drawn on the main chart at its values',
        (tester) async {
      final o = loadSample(_kalman);
      final s = o.series.firstWhere((e) => e.id == 'p8');
      expect(s.mainPane, isTrue);
      final (box, main) = await diff(tester, _kalman, (j) {
        final p8 = (j['series'] as List).firstWhere((e) => e['id'] == 'p8') as Map;
        p8['colors'] = List.filled(1000, 0);
        p8.remove('color');
      });
      expect(box.bottom, lessThanOrEqualTo(main.bottom));
      final m = state.mapper.value!;
      var hi = double.negativeInfinity, lo = double.infinity;
      for (var k = m.firstIndex - 1; k <= m.lastIndex; k++) {
        final v = s.values[k];
        hi = hi > v ? hi : v;
        lo = lo < v ? lo : v;
      }
      // 线宽 2：外框比数值范围上下各多约 1 像素
      expect(box.top, closeTo(yOf(hi) - 1, 1.5));
      expect(box.bottom, closeTo(yOf(lo) + 1, 1.5));
      expect(box.right, closeTo(xOf(999) + 1, 1.5));
    });

    testWidgets('$_kalman: a circle label (bar 973, 3562.228, size 6 pt) on the main chart',
        (tester) async {
      final (box, main) = await diff(tester, _kalman, (j) {
        final l = (j['labels'] as List)[176] as Map;
        expect([l['pane'], l['t'], l['style'], l['size']], ['main', times[973], 'circle', '6']);
        l['color'] = 0;
      });
      expect(box.bottom, lessThanOrEqualTo(main.bottom));
      expect(box.center.dx, closeTo(xOf(973), 1));
      expect(box.center.dy, closeTo(yOf(3562.228), 1));
      expect(box.width, closeTo(6, 1.5), reason: 'numeric size 6 pt → radius 3');
    });

    testWidgets('$_kalman: background and table go to the main chart', (tester) async {
      final (box, main) = await diff(tester, _kalman, (j) {
        for (final b in j['bg'] as List) {
          if (b['pane'] == 'main') {
            for (final r in b['runs'] as List) {
              r[2] = 0;
            }
          }
        }
        for (final t in j['tables'] as List) {
          expect(t['pane'], 'main');
          t['bg'] = 0;
          t['frame']['color'] = 0;
          t['border']['color'] = 0;
          for (final c in t['cells'] as List) {
            c[3] = 0;
            c[4] = 0;
          }
        }
      });
      expect(box.bottom, lessThanOrEqualTo(main.bottom));
    });
  });
}
