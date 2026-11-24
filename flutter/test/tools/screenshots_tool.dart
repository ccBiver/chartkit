// 给人看效果的截图，不是测试（文件名不以 _test 结尾，`flutter test` 默认不跑）。
// 用法：SHOTS_DIR=<输出目录> flutter test test/tools/screenshots_tool.dart
// K 线是 XAUUSD 样本（testdata/chart_tools/klines/）；带脚本图元的几张用图元样本对应的那份 K 线。
// 用 Flutter SDK 自带的 Roboto 代替测试默认的方块字体。
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chartkit_flutter/chartkit_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../script/fixtures.dart';

final _key = GlobalKey();

Future<void> _loadFont() async {
  final sdk = Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.parent.path;
  final dir = '$sdk/bin/cache/artifacts/material_fonts';
  final loader = FontLoader('Roboto')
    ..addFont(
        Future.value(ByteData.sublistView(File('$dir/Roboto-Regular.ttf').readAsBytesSync())));
  await loader.load();
}

List<Candle> _klines(String path) => [
      for (final e in jsonDecode(File(path).readAsStringSync()) as List)
        Candle(
          time: e['time'] as int,
          open: (e['open'] as num).toDouble(),
          high: (e['high'] as num).toDouble(),
          low: (e['low'] as num).toDouble(),
          close: (e['close'] as num).toDouble(),
        ),
    ];

List<Candle> _api(String period) => _klines('testdata/chart_tools/klines/xauusd_$period.json');
List<Candle> _combine(String name) => _klines('testdata/chart_tools/combine/$name');

final _theme = ChartTheme.dark.copyWith(fontFamily: 'Roboto');

void main() {
  final out = Platform.environment['SHOTS_DIR'] ?? 'build/shots_chart_tools';
  setUpAll(() async {
    await _loadFont();
    Directory(out).createSync(recursive: true);
  });

  Future<void> save(WidgetTester tester, String name) async {
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() async {
      final boundary = _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$out/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
  }

  Future<void> host(WidgetTester tester, Size size, Widget child) async {
    await tester.binding.setSurfaceSize(size);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: RepaintBoundary(key: _key, child: ColoredBox(color: _theme.background, child: child)),
    ));
  }

  /// 一张单图。[setup] 在第一帧之后调用（进回放、长按之类）。
  Future<void> single(
    WidgetTester tester,
    String name,
    KLineChartState state,
    KLineChart Function(KLineChartState s) build, {
    Size size = const Size(430, 760),
    double cw = 7,
    double scroll = 0,
    Future<void> Function()? setup,
  }) async {
    await host(tester, size, build(state));
    state.setViewport(candleWidth: cw, scrollOffset: scroll);
    await tester.pump(const Duration(seconds: 1));
    await setup?.call();
    await save(tester, name);
  }

  KLineChart chart(KLineChartState s,
          {ChartMode mode = ChartMode.candle,
          bool log = false,
          List<Indicator> sub = const [],
          ScriptOutputController? scripts,
          DrawingController? drawings,
          ChartReplayController? replay,
          double blank = 0,
          ChartFormatter formatter = const ChartFormatter()}) =>
      KLineChart(
        state: s,
        theme: _theme,
        mode: mode,
        entranceAnimation: false,
        showVolume: false,
        logScale: log,
        mainIndicators: [Ma()],
        subIndicators: sub,
        scriptOutputs: scripts,
        drawingController: drawings,
        replay: replay,
        blankScrollWidth: blank,
        initialBlankScroll: blank > 0,
        formatter: formatter,
      );

  testWidgets('shots', (tester) async {
    // 图表类型
    for (final (name, mode) in [
      ('01_美国线', ChartMode.ohlc),
      ('02_折线图', ChartMode.line),
      ('03_面积图', ChartMode.area),
    ]) {
      final s = KLineChartState(timeFrame: TimeFrame.m15)..setData(_api('15m'));
      await single(tester, name, s, (s) => chart(s, mode: mode), cw: mode == ChartMode.ohlc ? 8 : 5);
      s.dispose();
    }

    // 对数坐标：1 小时 702 根全放进一屏
    for (final (name, log) in [('04_线性坐标_1小时全部', false), ('05_对数坐标_1小时全部', true)]) {
      final s = KLineChartState(timeFrame: TimeFrame.h1)..setData(_api('1h'));
      await single(tester, name, s, (s) => chart(s, log: log), size: const Size(900, 420), cw: 1.2);
      s.dispose();
    }

    // 对数坐标 + 画线 + 主图脚本 + 副图脚本（图元样本对应的 K 线）
    {
      final candles = loadKlines();
      final s = KLineChartState(timeFrame: TimeFrame.m15)..setData(candles);
      final scripts = ScriptOutputController()
        ..setJson('smc', sampleJson('smc'))
        ..setJson('boll', sampleJson('boll'))
        ..setJson('macd', sampleJson('macd'));
      final d = DrawingController(style: const DrawingStyle(color: Color(0xFF3B82F6)))
        ..add(Drawing(
          id: 't',
          tool: DrawingTool.trendLine,
          anchors: [
            DrawingAnchor(candles[930].time, candles[930].low),
            DrawingAnchor(candles[985].time, candles[985].high)
          ],
          style: const DrawingStyle(color: Color(0xFF3B82F6), width: 2),
        ))
        ..add(Drawing(
          id: 'f',
          tool: DrawingTool.fibRetracement,
          anchors: [DrawingAnchor(candles[945].time, 3520), DrawingAnchor(candles[975].time, 3580)],
          style: const DrawingStyle(color: Color(0xFF8B5CF6)),
        ));
      await single(tester, '06_对数坐标_画线_主图和副图脚本', s,
          (s) => chart(s, log: true, scripts: scripts, drawings: d));
      d.dispose();
      scripts.dispose();
      s.dispose();
    }

    // 回放：本地指标（XAUUSD 15 分钟）
    {
      final s = KLineChartState(timeFrame: TimeFrame.m15)..setData(_api('15m'));
      final r = ChartReplayController(source: s);
      await single(tester, '07_回放中_本地指标按截断数据算', s,
          (s) => chart(s, sub: const [Macd()], replay: r, blank: 80),
          scroll: -80, setup: () async {
        r
          ..start()
          ..select(700);
        await tester.pump();
        for (var i = 0; i < 12; i++) {
          r.next();
        }
      });
      r.dispose();
      s.dispose();
    }

    // 回放：副图脚本按游标裁剪
    {
      final s = KLineChartState(timeFrame: TimeFrame.m15)..setData(loadKlines());
      final scripts = ScriptOutputController()
        ..setJson('macd', sampleJson('macd'))
        ..setJson('tex', sampleJson('com-trend-exhaustion-continuation-map-bullby'));
      final r = ChartReplayController(source: s);
      await single(tester, '08_回放中_脚本图元只画到游标', s,
          (s) => chart(s, scripts: scripts, replay: r, blank: 80),
          scroll: -80, setup: () async {
        r
          ..start()
          ..select(930);
      });
      r.dispose();
      scripts.dispose();
      s.dispose();
    }

    // 多图：竖屏 430 宽、横屏 900×420，各 4 格，周期 15m、1H、4H、1D
    for (final (name, size) in [
      ('09_多图_竖屏430_4格', const Size(430, 760)),
      ('10_多图_横屏900x420_4格', const Size(900, 420)),
    ]) {
      final frames = [
        (TimeFrame.m15, '15m'),
        (TimeFrame.h1, '1h'),
        (TimeFrame.h4, '4h'),
        (TimeFrame.d1, '1d'),
      ];
      final states = [for (final (tf, p) in frames) KLineChartState(timeFrame: tf)..setData(_api(p))];
      final keys = [for (var i = 0; i < 4; i++) GlobalKey()];
      await host(
          tester,
          size,
          GridView.count(
            crossAxisCount: 2,
            childAspectRatio: (size.width / 2) / (size.height / 2),
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (var i = 0; i < 4; i++)
                DecoratedBox(
                  decoration: BoxDecoration(border: Border.all(color: _theme.grid, width: 0.5)),
                  child: KLineChart(
                    key: keys[i],
                    state: states[i],
                    theme: _theme,
                    entranceAnimation: false,
                    showVolume: false,
                    mainIndicators: [Ma()],
                    subIndicators: i == 0 ? const [Macd()] : const [],
                  ),
                ),
            ],
          ));
      for (final s in states) {
        s.setViewport(candleWidth: 5);
      }
      await tester.pump(const Duration(seconds: 1));
      await tester.longPressAt(tester.getCenter(find.byKey(keys[1])));
      await save(tester, name);
      for (final s in states) {
        s.dispose();
      }
    }

    // 合成图
    for (final (name, a, b, tf, digits) in [
      ('11_合成图_金油比_XAUUSD÷UKOUSD_1小时', 'xauusd_1h.json', 'ukousd_1h.json', TimeFrame.h1, 3),
      ('12_合成图_XAUUSD÷XAGAUD_15分钟', 'xauusd_15m.json', 'xagaud_15m.json', TimeFrame.m15, 4),
    ]) {
      final s = KLineChartState(timeFrame: tf)
        ..setData(combineCandles(_combine(a), _combine(b), CombineOp.divide));
      await single(
          tester,
          name,
          s,
          (s) => chart(s,
              sub: const [Macd()],
              formatter: ChartFormatter(price: (v) => v.toStringAsFixed(digits))),
          cw: 6);
      s.dispose();
    }
  });
}
