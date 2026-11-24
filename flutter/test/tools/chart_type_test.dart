// 图表类型：美国线、折线图、面积图。
import 'package:chartkit_flutter/chartkit_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../script/fixtures.dart';
import 'harness.dart';

void main() {
  final candles = loadKlines();
  late KLineChartState state;

  setUp(() => state = KLineChartState(timeFrame: TimeFrame.m15)..setData(candles));
  tearDown(() => state.dispose());

  KLineChart chart(ChartMode mode, {ChartTheme theme = ChartTheme.dark, bool highLow = false}) =>
      KLineChart(
        state: state,
        mode: mode,
        theme: theme,
        entranceAnimation: false,
        showVolume: false,
        showHighLow: highLow,
        mainIndicators: [Ma()],
      );

  ({double lo, double hi}) visible(List<Candle> c, KLineChartMapper m, double Function(Candle) f,
      double Function(Candle) g) {
    var lo = double.infinity, hi = double.negativeInfinity;
    for (var i = m.firstIndex; i <= m.lastIndex; i++) {
      if (f(c[i]) < lo) lo = f(c[i]);
      if (g(c[i]) > hi) hi = g(c[i]);
    }
    return (lo: lo, hi: hi);
  }

  group('价格区间', () {
    testWidgets('折线图和面积图只按收盘价算，美国线按最高最低价算', (tester) async {
      for (final mode in [ChartMode.line, ChartMode.area, ChartMode.ohlc]) {
        await pumpChart(tester, state,
            KLineChart(state: state, mode: mode, entranceAnimation: false, showVolume: false));
        final m = state.mapper.value!;
        final r = mode.closeOnly
            ? visible(candles, m, (c) => c.close, (c) => c.close)
            : visible(candles, m, (c) => c.low, (c) => c.high);
        // 区间上下各留 6%：反推出数据区间
        final span = (m.yToPrice(m.mainRect.top) - m.yToPrice(m.mainRect.bottom)) / 1.12;
        final lo = m.yToPrice(m.mainRect.bottom) + span * 0.06;
        expect(lo, closeTo(r.lo, 1e-6), reason: '$mode');
        expect(lo + span, closeTo(r.hi, 1e-6), reason: '$mode');
      }
    });
  });

  group('像素', () {
    testWidgets('美国线：左边短横在开盘价，右边短横在收盘价，颜色按涨跌', (tester) async {
      await pumpChart(tester, state,
          KLineChart(state: state, mode: ChartMode.ohlc, entranceAnimation: false, showVolume: false),
          cw: 12);
      final m = state.mapper.value!;
      final px = await capture(tester);
      final theme = ChartTheme.dark;
      var checked = 0;
      for (var i = m.lastIndex - 20; i < m.lastIndex - 2; i++) {
        final c = candles[i];
        final x = m.indexToX(i);
        final yo = m.priceToY(c.open), yc = m.priceToY(c.close);
        // 线宽 1.2 个设备像素，落在像素边界上时颜色不会盖满，按覆盖率判断
        // 开收盘离高低点太近时短横和竖线分不开，跳过
        if ((yo - yc).abs() < 3) continue;
        final color = c.isBullish ? theme.candleUp : theme.candleDown;
        expect(px.coverage(x - 3, yo, color, theme.background), greaterThan(0.45), reason: '#$i 开盘短横');
        expect(px.coverage(x + 3, yc, color, theme.background), greaterThan(0.45), reason: '#$i 收盘短横');
        expect(near(px.at(x + 3, yo), theme.background, 0.02), isTrue, reason: '#$i 开盘右侧空');
        expect(near(px.at(x - 3, yc), theme.background, 0.02), isTrue, reason: '#$i 收盘左侧空');
        checked++;
      }
      expect(checked, greaterThan(5));
    });

    testWidgets('折线图不画填充，面积图画填充', (tester) async {
      Future<Color> below(ChartMode mode) async {
        await pumpChart(tester, state,
            KLineChart(state: state, mode: mode, entranceAnimation: false, showVolume: false));
        final m = state.mapper.value!;
        final i = m.lastIndex - 10;
        final y = m.priceToY(candles[i].close);
        final px = await capture(tester);
        // 收盘价下方 6 像素
        return px.at(m.indexToX(i), y + 6);
      }

      final bg = ChartTheme.dark.background;
      expect(await below(ChartMode.line), bg);
      expect(await below(ChartMode.area), isNot(bg));
    });

    testWidgets('最高最低价标注：美国线画，折线图和面积图不画', (tester) async {
      Future<int> diff(ChartMode mode) async {
        await pumpChart(tester, state, chart(mode));
        final a = await capture(tester);
        await pumpChart(tester, state, chart(mode, highLow: true));
        final b = await capture(tester);
        return a.diffCount(b);
      }

      expect(await diff(ChartMode.ohlc), greaterThan(0));
      expect(await diff(ChartMode.line), 0);
      expect(await diff(ChartMode.area), 0);
    });

    testWidgets('脚本的 K 线改色对美国线生效', (tester) async {
      final scripts = ScriptOutputController(onAlignmentIssue: (i) => fail('$i'));
      addTearDown(scripts.dispose);
      Future<Pixels> shot() async {
        await pumpChart(
            tester,
            state,
            KLineChart(
                state: state,
                mode: ChartMode.ohlc,
                entranceAnimation: false,
                showVolume: false,
                scriptOutputs: scripts),
            cw: 12);
        return capture(tester);
      }

      final plain = await shot();
      final j = onlyFields(sampleJson('com-decycler-high-low-breakout-schizoquant'), {'barColors'});
      expect(scripts.setJson('d', j).ok, isTrue);
      final colored = await shot();
      expect(plain.diffCount(colored), greaterThan(0));
    });
  });

  group('参考图', () {
    testWidgets('美国线', (tester) async {
      await pumpChart(tester, state, chart(ChartMode.ohlc, highLow: true), cw: 8);
      await matchGolden('01_ohlc');
    });
    testWidgets('折线图', (tester) async {
      await pumpChart(tester, state, chart(ChartMode.line));
      await matchGolden('02_line');
    });
    testWidgets('面积图', (tester) async {
      await pumpChart(tester, state, chart(ChartMode.area));
      await matchGolden('03_area');
    });
    testWidgets('浅色美国线', (tester) async {
      await pumpChart(tester, state, chart(ChartMode.ohlc, theme: ChartTheme.light), cw: 8);
      await matchGolden('04_ohlc_light');
    });
  });
}
