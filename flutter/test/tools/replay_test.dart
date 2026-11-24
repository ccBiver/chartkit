// K 线回放：控制器的阶段和节奏、选起点、实时行情不带走图、指标按截断数据算、脚本图元按游标裁剪。
import 'package:chartkit_flutter/chartkit_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../script/fixtures.dart';
import 'harness.dart';

void main() {
  final candles = loadKlines();
  late KLineChartState state;
  late ChartReplayController replay;

  setUp(() {
    state = KLineChartState(timeFrame: TimeFrame.m15)..setData(candles);
    replay = ChartReplayController(source: state);
  });
  tearDown(() {
    replay.dispose();
    state.dispose();
  });

  Candle next(Candle last, {double close = 3600}) => Candle(
      time: last.time + 900000, open: last.close, high: close + 1, low: close - 1, close: close);

  group('控制器', () {
    test('选起点：含起点那一根，之后的隐藏；周期和缩放沿用', () {
      state.setViewport(candleWidth: 9);
      expect(replay.phase, ReplayPhase.off);
      replay.start();
      expect(replay.phase, ReplayPhase.picking);
      expect(replay.view, isNull);
      replay.select(700);
      expect(replay.phase, ReplayPhase.active);
      expect(replay.view!.candles.length, 701);
      expect(replay.cursor, candles[700]);
      expect(replay.cursorIndex, 700);
      expect(replay.view!.timeFrame, TimeFrame.m15);
      expect(replay.view!.candleWidth, 9);
    });

    test('下一根，放到最后一根返回 true 并停在那里', () {
      replay
        ..start()
        ..select(997);
      expect(replay.next(), isFalse);
      expect(replay.cursor, candles[998]);
      expect(replay.next(), isTrue);
      expect(replay.cursor, candles.last);
      expect(replay.atEnd, isTrue);
      expect(replay.next(), isTrue);
      expect(replay.view!.candles.length, candles.length);
    });

    // testWidgets 里的定时器走假时钟，tester.pump 推进
    testWidgets('播放按倍速走，放到最后自动暂停', (tester) async {
      {
        replay
          ..start()
          ..select(900)
          ..play();
        expect(replay.playing, isTrue);
        await tester.pump(const Duration(milliseconds: 3100));
        expect(replay.cursorIndex, 903);
        replay.speed = 4;
        await tester.pump(const Duration(milliseconds: 1010));
        expect(replay.cursorIndex, 907);
        replay.speed = 0.5;
        await tester.pump(const Duration(milliseconds: 4100));
        expect(replay.cursorIndex, 909);
        replay.pause();
        await tester.pump(const Duration(seconds: 10));
        expect(replay.cursorIndex, 909);
        replay
          ..select(996)
          ..speed = 4
          ..play();
        await tester.pump(const Duration(seconds: 5));
        expect(replay.atEnd, isTrue);
        expect(replay.playing, isFalse);
      }
    });

    test('默认倍速是 0.5x、1x、2x、4x，1x 每根 1 秒', () {
      expect(replay.speeds, [0.5, 1, 2, 4]);
      expect(replay.speed, 1);
      expect(replay.interval, const Duration(seconds: 1));
    });

    test('实时行情只进宿主的状态，回放的数据不动；退出后回到最新', () {
      replay
        ..start()
        ..select(500);
      state.appendOrUpdate(next(candles.last));
      expect(replay.view!.candles.length, 501);
      expect(replay.cursor, candles[500]);
      replay.exit();
      expect(replay.phase, ReplayPhase.off);
      expect(replay.view, isNull);
      expect(state.candles.length, candles.length + 1);
    });

    test('回放中能一直放到实时推来的新 K 线', () {
      replay
        ..start()
        ..select(998);
      state.appendOrUpdate(next(candles.last));
      expect(replay.next(), isFalse);
      expect(replay.next(), isTrue);
      expect(replay.cursor!.time, candles.last.time + 900000);
    });

    test('宿主整份换数据（切周期）时自动退出', () {
      replay
        ..start()
        ..select(500);
      state.setData(candles.sublist(0, 800));
      expect(replay.phase, ReplayPhase.off);
    });

    test('宿主往前加载更早的数据时回放里也补上', () {
      final older = state.candles.sublist(0, 100);
      state.setData(state.candles.sublist(100));
      replay
        ..start()
        ..select(400);
      final cursor = replay.cursor;
      state.prepend(older);
      expect(replay.view!.candles.length, 501);
      expect(replay.view!.candles.first, candles.first);
      expect(replay.cursor, cursor);
      expect(replay.cursorIndex, 500);
    });

    testWidgets('重选起点：暂停、回到选起点', (tester) async {
      {
        replay
          ..start()
          ..select(400)
          ..play();
        replay.start();
        expect(replay.playing, isFalse);
        expect(replay.phase, ReplayPhase.picking);
        expect(replay.view, isNull);
        replay.select(100);
        expect(replay.cursor, candles[100]);
      }
    });
  });

  group('组件', () {
    KLineChart chart({
      List<Indicator> main = const [],
      List<Indicator> sub = const [],
      ScriptOutputController? scripts,
      DrawingController? drawings,
      double blank = 0,
      LastPriceMode lastPrice = LastPriceMode.latest,
      ChartReplayController? withReplay,
    }) =>
        KLineChart(
          state: state,
          entranceAnimation: false,
          showVolume: false,
          mainIndicators: main,
          subIndicators: sub,
          scriptOutputs: scripts,
          drawingController: drawings,
          blankScrollWidth: blank,
          lastPriceMode: lastPrice,
          replay: withReplay,
        );

    testWidgets('选起点时点一根 K 线，图上只剩到它为止；实时行情不带走图；退出回到最新', (tester) async {
      final drawings = DrawingController(style: const DrawingStyle(color: Color(0xFF3B82F6)));
      addTearDown(drawings.dispose);
      await pumpChart(tester, state, chart(withReplay: replay, drawings: drawings));
      final m = state.mapper.value!;
      final target = m.lastIndex - 30;
      replay.start();
      await tester.pump();
      // 开着画线也是选起点优先
      await tester.tapAt(tester.getTopLeft(find.byKey(shotKey)) + Offset(m.indexToX(target), 100));
      await tester.pump();
      expect(replay.phase, ReplayPhase.active);
      expect(replay.cursorIndex, target);
      expect(drawings.drawings, isEmpty);
      expect(state.mapper.value!.itemCount, target + 1);
      expect(state.mapper.value!.lastIndex, target);
      state.appendOrUpdate(next(candles.last));
      await tester.pump();
      expect(state.mapper.value!.itemCount, target + 1);
      expect(state.mapper.value!.latestPrice, candles[target].close);
      replay.next();
      await tester.pump();
      expect(state.mapper.value!.itemCount, target + 2);
      replay.exit();
      await tester.pump();
      expect(state.mapper.value!.itemCount, candles.length + 1);
    });

    testWidgets('回放的画面和直接画截断后的数据一样（含本地主图、副图指标）', (tester) async {
      await pumpChart(tester, state, chart(main: [Ma(), const Boll()], sub: const [Macd()], withReplay: replay));
      replay
        ..start()
        ..select(820);
      await tester.pump();
      await tester.pump();
      final a = await capture(tester);
      final truncated = KLineChartState(timeFrame: TimeFrame.m15)..setData(candles.sublist(0, 821));
      addTearDown(truncated.dispose);
      truncated.setViewport(candleWidth: state.candleWidth);
      await tester.pumpWidget(frame(
          KLineChart(
            state: truncated,
            entranceAnimation: false,
            showVolume: false,
            mainIndicators: [Ma(), const Boll()],
            subIndicators: const [Macd()],
          ),
          size: const Size(400, 460)));
      await tester.pump();
      final b = await capture(tester);
      expect(a.diffCount(b), 0);
    });

    testWidgets('脚本图元：游标之后的部分不画，跨过游标的从游标右沿裁掉', (tester) async {
      final scripts = ScriptOutputController(onAlignmentIssue: (i) => fail('$i'));
      addTearDown(scripts.dispose);
      const tex = 'com-trend-exhaustion-continuation-map-bullby';
      // 主图只放对象（不影响价格区间），副图放逐根序列、背景、方框、标记
      Map<String, dynamic> po3(bool on) =>
          onlyFields(sampleJson('opt-po3'), on ? {'lines', 'boxes', 'labels'} : {});
      Map<String, dynamic> sub(bool on) =>
          onlyFields(sampleJson(tex), on ? {'series', 'boxes', 'bg', 'markers'} : {});
      const blank = 80.0;
      const cursor = 950;
      await pumpChart(tester, state, chart(scripts: scripts, blank: blank, withReplay: replay),
          scroll: -blank);

      /// 两次渲染（图元开、关）在游标右沿以右的不同像素数，和以左的不同像素数。
      Future<(int, int)> diff(Future<void> Function() setView) async {
        Future<Pixels> shot(bool on) async {
          scripts
            ..setJson('po3', po3(on))
            ..setJson('tex', sub(on));
          await setView();
          await tester.pump();
          await tester.pump();
          return capture(tester);
        }

        final a = await shot(true), b = await shot(false);
        final m = state.mapper.value!;
        final cut = m.indexToX(cursor) + m.candleWidth / 2;
        var right = 0, left = 0;
        for (var y = 0.0; y < m.size.height - 20; y += 1) {
          for (var x = 2.0; x < m.mainRect.right - 2; x += 1) {
            if (a.at(x, y) == b.at(x, y)) continue;
            if (x > cut + 1) {
              right++;
            } else if (x < cut - 1) {
              left++;
            }
          }
        }
        return (right, left);
      }

      replay
        ..start()
        ..select(cursor);
      final inReplay = await diff(() async {
        replay.view!.setViewport(scrollOffset: -blank);
      });
      expect(state.mapper.value!.lastIndex, cursor);
      expect(inReplay.$1, 0, reason: '游标右边不画');
      expect(inReplay.$2, greaterThan(500), reason: '游标左边照常画');
      // 不回放、视口一样时游标右边有图元：证明上面不是空测
      replay.exit();
      final full = await diff(() async {
        state.setViewport(scrollOffset: (candles.length - 1 - cursor) * state.candleWidth - blank);
      });
      expect(full.$1, greaterThan(200));
    });

    testWidgets('脚本的表格回放时照常画', (tester) async {
      final scripts = ScriptOutputController(onAlignmentIssue: (i) => fail('$i'));
      addTearDown(scripts.dispose);
      await pumpChart(tester, state, chart(scripts: scripts, withReplay: replay));
      replay
        ..start()
        ..select(900);
      Future<Pixels> shot(Map<String, dynamic> json) async {
        scripts.setJson('po3', json);
        await tester.pump();
        await tester.pump();
        return capture(tester);
      }

      final withTable = await shot(onlyFields(sampleJson('opt-po3'), {'tables'}));
      final none = await shot(onlyFields(sampleJson('opt-po3'), {}));
      expect(withTable.diffCount(none), greaterThan(100));
    });

    testWidgets('不传 replay 时和原来一样（没有回放入口）', (tester) async {
      await pumpChart(tester, state, chart());
      final a = await capture(tester);
      await pumpChart(tester, state, chart(withReplay: replay));
      final b = await capture(tester);
      expect(a.diffCount(b), 0);
    });
  });

  group('参考图', () {
    testWidgets('回放中：主图指标、副图脚本、留白', (tester) async {
      final scripts = ScriptOutputController(onAlignmentIssue: (i) => fail('$i'));
      addTearDown(scripts.dispose);
      scripts.setJson('macd', sampleJson('macd'));
      scripts.setJson('tex', sampleJson('com-trend-exhaustion-continuation-map-bullby'));
      await pumpChart(
          tester,
          state,
          KLineChart(
            state: state,
            entranceAnimation: false,
            showVolume: false,
            mainIndicators: [Ma()],
            scriptOutputs: scripts,
            blankScrollWidth: 60,
            initialBlankScroll: true,
            replay: replay,
          ),
          size: const Size(400, 560),
          scroll: -60);
      replay
        ..start()
        ..select(930);
      await tester.pump();
      await tester.pump();
      await matchGolden('07_replay_sub_scripts');
    });
  });
}
