// BOLL 上下轨之间的填充（Boll.fillColor）：默认不填；填充在蜡烛、指标线、画线下面；按连续有值的区间分段；
// 可见范围两边各多取一根、不进右轴；对数坐标、各图表类型、回放、图例留位、主图下方留空下的表现。
import 'dart:math' as math;

import 'package:chartkit_flutter/chartkit_flutter.dart';
import 'package:chartkit_flutter/src/chart/chart_layout.dart';
import 'package:chartkit_flutter/src/indicator/indicator_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../script/fixtures.dart';
import '../tools/harness.dart';

const _fill = Color(0x6600FFFF);
const _opaque = Color(0xFF00FFFF);
final _bg = ChartTheme.dark.background;

/// 价格从 100 涨到约 10000 的合成 K 线（对数和线性差得多）。
List<Candle> _growth(int n) => [
      for (var i = 0; i < n; i++)
        () {
          final base = 100 * math.pow(100, i / (n - 1)).toDouble() * (1 + 0.03 * math.sin(i * 0.7));
          final up = i % 3 != 0;
          return Candle(
            time: 1764720000000 + i * 900000,
            open: base * (up ? 0.99 : 1.01),
            high: base * 1.02,
            low: base * 0.98,
            close: base * (up ? 1.01 : 0.99),
          );
        }(),
    ];

/// 自定义的带填充指标：上下两条线，中间 [gap] 这几根没有值，[lone] 那一根前后都没有值。
class _Band extends Indicator {
  _Band({required this.gap, required this.lone});

  final Set<int> gap;
  final int lone;

  @override
  String get id => 'BAND';
  @override
  Pane get pane => Pane.main;
  @override
  IndicatorSeries compute(List<Candle> candles) {
    double? v(int i, double d) {
      if (gap.contains(i)) return null;
      if ((i == lone - 1 || i == lone + 1)) return null;
      return candles[i].close + d;
    }

    return IndicatorSeries(
      id,
      pane,
      [
        IndicatorLine('U', [for (var i = 0; i < candles.length; i++) v(i, 15)]),
        IndicatorLine('L', [for (var i = 0; i < candles.length; i++) v(i, -15)]),
      ],
      fill: const IndicatorFill(upper: 0, lower: 1, color: _opaque),
    );
  }
}

void main() {
  group('指标', () {
    test('默认不填：fill 为空，参数和原来一样', () {
      const b = Boll();
      expect(b.fillColor, isNull);
      expect(b.compute(loadKlines()).fill, isNull);
      expect(const Boll() == const Boll(period: 20, k: 2), isTrue);
    });

    test('传了颜色：填在上轨（第 0 条）和下轨（第 2 条）之间；颜色参与判等', () {
      const b = Boll(fillColor: _fill);
      expect(b.compute(loadKlines()).fill,
          const IndicatorFill(upper: 0, lower: 2, color: _fill));
      expect(b == const Boll(fillColor: _fill), isTrue);
      expect(b == const Boll(), isFalse);
      expect(b == const Boll(fillColor: _opaque), isFalse);
    });

    test('末根更新、追加一根走增量计算时填充保留', () {
      final data = loadKlines();
      const b = Boll(fillColor: _fill);
      final prev = [b.compute(data.sublist(0, 900))];
      final next = incrementalCompute([b], data.sublist(0, 901), data.sublist(0, 900), prev);
      expect(next.single.size, 901);
      expect(next.single.fill, prev.single.fill);
    });
  });

  group('组件', () {
    final candles = loadKlines();
    late KLineChartState state;

    setUp(() => state = KLineChartState(timeFrame: TimeFrame.m15)..setData(candles));
    tearDown(() => state.dispose());

    KLineChart chart(Color? fill,
            {ChartMode mode = ChartMode.candle,
            bool log = false,
            bool legend = false,
            double gap = 0,
            DrawingController? drawings,
            ChartReplayController? replay,
            List<Indicator> extra = const []}) =>
        KLineChart(
          state: state,
          mode: mode,
          entranceAnimation: false,
          showVolume: false,
          mainIndicators: [Boll(fillColor: fill), ...extra],
          logScale: log,
          reserveMainLegend: legend,
          mainBottomGap: gap,
          drawingController: drawings,
          replay: replay,
        );

    /// 两根之间（避开蜡烛实体和影线）、中轨和上轨正中的那一点。
    Offset between(KLineChartMapper m, IndicatorSeries s, int i) {
      final x = m.indexToX(i) + m.candleWidth / 2;
      final up = math.max(s.lines[0].values[i]!, s.lines[0].values[i + 1]!);
      final mb = math.min(s.lines[1].values[i]!, s.lines[1].values[i + 1]!);
      return Offset(x, m.priceToY((up + mb) / 2));
    }

    testWidgets('填充在蜡烛、BOLL 线、画线下面：不透明填充时蜡烛实体中心仍是蜡烛色，线也都还在', (tester) async {
      final drawings = DrawingController(style: const DrawingStyle(color: Color(0xFFFFFF00)));
      addTearDown(drawings.dispose);
      await pumpChart(tester, state, chart(_opaque, drawings: drawings), cw: 12);
      final m = state.mapper.value!;
      final s = const Boll().compute(candles);
      // 一根实体较高的蜡烛
      var i = m.lastIndex - 3;
      while ((m.priceToY(candles[i].open) - m.priceToY(candles[i].close)).abs() < 6) {
        i--;
      }
      final c = candles[i];
      final mid = (c.open + c.close) / 2;
      // 中轨价位的一条水平画线
      final hPrice = s.lines[1].values[m.lastIndex - 10]!;
      drawings.add(Drawing(
        id: 'h',
        tool: DrawingTool.horizontalLine,
        anchors: [DrawingAnchor(candles[m.lastIndex - 10].time, hPrice)],
        style: const DrawingStyle(color: Color(0xFFFFFF00), width: 2),
      ));
      await tester.pump();
      final px = await capture(tester);
      final theme = ChartTheme.dark;
      expect(px.at(m.indexToX(i), m.priceToY(mid)), c.isBullish ? theme.candleUp : theme.candleDown,
          reason: '#$i 实体中心');
      // 填充确实画了：两根之间的通道里是填充色
      final p = between(m, s, m.lastIndex - 8);
      expect(px.at(p.dx, p.dy), _opaque);
      // 中轨在通道正中：填充若画在线上面会把它整条盖掉。几根上都看得见（线宽 1.5 个设备像素，按覆盖率）
      var seen = 0;
      for (var k = m.lastIndex - 12; k < m.lastIndex - 2; k++) {
        // 两根中心之间的中点：线是两根中心之间连的直线
        final y = (m.priceToY(s.lines[1].values[k]!) + m.priceToY(s.lines[1].values[k + 1]!)) / 2;
        if (px.coverage(m.indexToX(k) + m.candleWidth / 2, y, theme.indicatorColor(1), _opaque, r: 2) >
            0.4) {
          seen++;
        }
      }
      expect(seen, greaterThan(5), reason: '中轨在填充上面');
      // 画线在填充上面
      final hx = m.indexToX(m.lastIndex - 12) + m.candleWidth / 2;
      expect(px.coverage(hx, m.priceToY(hPrice), const Color(0xFFFFFF00), _opaque, r: 3),
          greaterThan(0.5));
    });

    testWidgets('开头前 N−1 根没有 BOLL 值：填充从第 N 根开始，前面不填', (tester) async {
      await pumpChart(tester, state, chart(_opaque), cw: 12, scroll: 1e9);
      final m = state.mapper.value!;
      expect(m.firstIndex, 0);
      final s = const Boll().compute(candles);
      expect(s.lines[0].values[18], isNull);
      expect(s.lines[0].values[19], isNotNull);
      final px = await capture(tester);
      final yMid = m.priceToY((s.lines[0].values[19]! + s.lines[1].values[19]!) / 2);
      // 第 19 根往右是填充，往左（第 18、19 根之间）不是
      expect(px.at(m.indexToX(19) + m.candleWidth / 2, yMid), isNot(_bg));
      final left = px.at(m.indexToX(18) + m.candleWidth / 2, yMid);
      expect(left, isNot(_opaque));
    });

    testWidgets('中间断开的分段：断开处不填、不跨过去连；只有一个点的段不填', (tester) async {
      final ind = _Band(gap: {984, 985, 986}, lone: 993);
      await pumpChart(
          tester,
          state,
          KLineChart(
              state: state, entranceAnimation: false, showVolume: false, mainIndicators: [ind]),
          cw: 12);
      final m = state.mapper.value!;
      expect(m.firstIndex, lessThan(980));
      final px = await capture(tester);
      double y(int i) => m.priceToY(candles[i].close + 8);
      Color at(int i) => px.at(m.indexToX(i) + m.candleWidth / 2, y(i));
      expect(at(981), _opaque, reason: '断开前的段');
      expect(at(984), isNot(_opaque), reason: '断开处');
      expect(at(985), isNot(_opaque), reason: '断开处');
      expect(at(988), _opaque, reason: '断开后的段');
      // 第 993 根前后都没有值：它两侧的空隙都不填
      expect(at(992), isNot(_opaque));
      expect(at(993), isNot(_opaque));
      expect(at(996), _opaque);
    });

    testWidgets('边缘：可见范围两边各多取一根，左右边缘不缺角；不进右轴', (tester) async {
      Future<Pixels> shot(Color? fill) async {
        // 滚动 204 = 17 根整：最右一根的中心落在图内半格处，它右边那半格要靠多取的一根来填
        await pumpChart(tester, state, chart(fill), cw: 12, scroll: 204);
        return capture(tester);
      }

      final plain = await shot(null);
      final filled = await shot(_opaque);
      final m = state.mapper.value!;
      expect(m.firstIndex, greaterThan(0));
      expect(m.lastIndex, lessThan(candles.length - 1));
      expect(m.indexToX(m.lastIndex), lessThan(m.mainRect.right - 2));
      final s = const Boll().compute(candles);
      // 左边缘 x=1、右边缘 x=chartWidth−1：落在第一根左边、最后一根右边的半格里
      for (final (x, i) in [(1.0, m.firstIndex), (m.mainRect.right - 1, m.lastIndex)]) {
        final y = m.priceToY((s.lines[0].values[i]! + s.lines[1].values[i]!) / 2);
        expect(filled.at(x, y), _opaque, reason: 'x=$x');
      }
      // 右轴区域和不填时逐像素一样
      var diff = 0;
      for (var y = 0.0; y < m.mainRect.bottom; y += 1 / plain.ratio) {
        for (var x = m.mainRect.right + 1; x < m.size.width; x += 1 / plain.ratio) {
          if (plain.at(x, y) != filled.at(x, y)) diff++;
        }
      }
      expect(diff, 0);
    });

    testWidgets('对数坐标：填充的上下沿按对数换算', (tester) async {
      state.setData(_growth(300));
      await pumpChart(tester, state, chart(_opaque, log: true), cw: 2);
      final m = state.mapper.value!;
      expect(m.logScale, isTrue);
      final s = const Boll().compute(state.candles);
      final px = await capture(tester);
      var checked = 0;
      for (var i = m.lastIndex - 120; i < m.lastIndex - 10; i += 9) {
        final x = m.indexToX(i);
        final yUp = m.priceToY(s.lines[0].values[i]!);
        final yDn = m.priceToY(s.lines[2].values[i]!);
        if (yDn - yUp < 12) continue;
        // 上轨以上 4 像素不是填充，上轨以下 4 像素到下轨以上 4 像素是填充（避开蜡烛：取下轨附近）
        expect(px.at(x, yUp - 4), isNot(_opaque), reason: '#$i 上轨外');
        expect(px.at(x, yDn - 3), anyOf(_opaque, isNot(_bg)), reason: '#$i 下轨内');
        expect(px.at(x, yDn + 4), isNot(_opaque), reason: '#$i 下轨外');
        // 线性换算的同一价格在别的位置：确认测的是对数
        final linear = ChartLayout.valueToY(s.lines[0].values[i]!, m.mainRect.top,
            m.mainRect.bottom, m.yToPrice(m.mainRect.bottom), m.yToPrice(m.mainRect.top));
        expect((linear - yUp).abs(), greaterThan(5));
        checked++;
      }
      expect(checked, greaterThan(5));
    });

    group('各模式', () {
      Future<int> diff(WidgetTester tester, KLineChart Function(Color? fill) build,
          {double cw = 6}) async {
        await pumpChart(tester, state, build(null), cw: cw);
        final a = await capture(tester);
        await pumpChart(tester, state, build(_fill), cw: cw);
        final b = await capture(tester);
        return a.diffCount(b);
      }

      testWidgets('分时不画主图指标，也不画填充', (tester) async {
        expect(await diff(tester, (f) => chart(f, mode: ChartMode.timeLine)), 0);
      });

      testWidgets('美国线、折线图、面积图都画填充', (tester) async {
        for (final mode in [ChartMode.ohlc, ChartMode.line, ChartMode.area]) {
          expect(await diff(tester, (f) => chart(f, mode: mode)), greaterThan(1000), reason: '$mode');
        }
      });

      testWidgets('主图下方留空：填充不进空白', (tester) async {
        await pumpChart(tester, state, chart(_opaque, gap: 34), cw: 6);
        final m = state.mapper.value!;
        final gap = m.mainBottomGapRect;
        final px = await capture(tester);
        var other = 0;
        for (var y = gap.top; y < gap.bottom; y += 1 / px.ratio) {
          for (var x = 0.0; x < gap.width; x += 1 / px.ratio) {
            if (px.at(x, y) != _bg) other++;
          }
        }
        expect(other, 0);
      });

      testWidgets('图例留位：填充在价格区里（图例下面）', (tester) async {
        await pumpChart(tester, state, chart(_opaque, legend: true, extra: [Ma()]), cw: 6);
        final m = state.mapper.value!;
        expect(m.mainContentTop, greaterThan(0));
        final s = const Boll().compute(candles);
        for (var i = m.firstIndex + 1; i < m.lastIndex; i++) {
          expect(m.priceToY(s.lines[0].values[i]!), greaterThanOrEqualTo(m.mainContentTop - 1e-6));
        }
      });

      testWidgets('回放：填充按截断后的数据算，只画到游标', (tester) async {
        final replay = ChartReplayController(source: state);
        addTearDown(replay.dispose);
        await pumpChart(
            tester,
            state,
            KLineChart(
              state: state,
              entranceAnimation: false,
              showVolume: false,
              mainIndicators: const [Boll(fillColor: _opaque)],
              blankScrollWidth: 80,
              replay: replay,
            ),
            cw: 8);
        replay
          ..start()
          ..select(900);
        replay.view!.setViewport(scrollOffset: -80);
        await tester.pump();
        await tester.pump();
        final m = state.mapper.value!;
        expect(m.lastIndex, 900);
        final px = await capture(tester);
        // 游标右沿以外（多取的那一根在回放数据里不存在）没有填充色
        final cut = m.indexToX(900) + m.candleWidth / 2;
        var filled = 0;
        for (var y = 0.0; y < m.mainRect.bottom; y += 1) {
          for (var x = cut + 1; x < m.mainRect.right; x += 1) {
            if (px.at(x, y) == _opaque) filled++;
          }
        }
        expect(filled, 0);
        expect(px.at(m.indexToX(895) + m.candleWidth / 2,
            m.priceToY(const Boll().compute(candles.sublist(0, 901)).lines[1].values[895]! + 0.5)),
            anyOf(_opaque, isNot(_bg)));
      });
    });
  });

  group('参考图', () {
    final candles = loadKlines();

    testWidgets('深色：蜡烛、MA、BOLL 底色', (tester) async {
      final state = KLineChartState(timeFrame: TimeFrame.m15)..setData(candles);
      addTearDown(state.dispose);
      await pumpChart(
          tester,
          state,
          KLineChart(
            state: state,
            entranceAnimation: false,
            showVolume: false,
            mainIndicators: [Ma(), Boll(fillColor: ChartTheme.dark.indicatorColor(1).withValues(alpha: 0.12))],
          ),
          cw: 7);
      await matchGolden('16_boll_fill_dark');
    });

    testWidgets('浅色、对数坐标、主图下方留空、MACD 副图', (tester) async {
      final state = KLineChartState(timeFrame: TimeFrame.m15)..setData(candles);
      addTearDown(state.dispose);
      await pumpChart(
          tester,
          state,
          KLineChart(
            state: state,
            theme: ChartTheme.light,
            entranceAnimation: false,
            showVolume: false,
            logScale: true,
            mainBottomGap: 34,
            mainIndicators: [Boll(fillColor: ChartTheme.light.indicatorColor(1).withValues(alpha: 0.12))],
            subIndicators: const [Macd()],
          ),
          cw: 7);
      await matchGolden('17_boll_fill_light_log_gap');
    });
  });
}
