// 给人看效果的截图，不是测试（文件名不以 _test 结尾，`flutter test` 默认不跑）。
// 用法：SHOTS_DIR=<输出目录> flutter test test/script/screenshots_tool.dart
// 用 Flutter SDK 自带的 Roboto 代替测试默认的方块字体。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chartkit_flutter/chartkit_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

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

void main() {
  final out = Platform.environment['SHOTS_DIR'] ?? 'build/shots';
  setUpAll(() async {
    await _loadFont();
    Directory(out).createSync(recursive: true);
  });

  Future<void> shot(WidgetTester tester, String name, List<Object> ids,
      {ChartTheme theme = ChartTheme.dark,
      Size size = const Size(430, 760),
      double candleWidth = 7,
      double scroll = 0,
      double blank = 0}) async {
    final state = KLineChartState(timeFrame: TimeFrame.m15)..setData(loadKlines());
    final c = ScriptOutputController();
    for (final (i, id) in ids.indexed) {
      c.setJson('$i', id is String ? sampleJson(id) : id);
    }
    final t = theme.copyWith(fontFamily: 'Roboto');
    await tester.binding.setSurfaceSize(size);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: RepaintBoundary(
        key: _key,
        child: ColoredBox(
          color: t.background,
          child: KLineChart(
            state: state,
            theme: t,
            entranceAnimation: false,
            showVolume: false,
            blankScrollWidth: blank,
            initialBlankScroll: blank > 0,
            scriptOutputs: c,
          ),
        ),
      ),
    ));
    state.setViewport(candleWidth: candleWidth, scrollOffset: blank > 0 ? -blank : scroll);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(() async {
      final boundary = _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$out/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
    state.dispose();
    c.dispose();
  }

  testWidgets('shots', (tester) async {
    await shot(tester, '01_主图_布林带和超级趋势策略', ['boll', 'com-supertrend-strategy']);
    await shot(tester, '02_主图_聪明钱_线段方框标签', ['smc'], candleWidth: 6);
    await shot(tester, '03_主图_大周期投影_表格和越过最后一根', ['opt-po3'], blank: 170, candleWidth: 6);
    await shot(tester, '04_主图_FVG方框和ICT背景色', ['fvg', 'com-ict-silver-bullet-backtest'],
        candleWidth: 5);
    await shot(tester, '05_主图_自绘K线和K线改色', ['com-decycler-high-low-breakout-schizoquant'],
        candleWidth: 8);
    await shot(tester, '06_主图_K线形态标记', ['com-candlestick-patterns-identified-updated-'],
        candleWidth: 9);
    await shot(tester, '07_主图_500个标签和表格', ['com-machine-learning-adaptive-supertrend-alg'],
        candleWidth: 5);
    await shot(tester, '08_副图_MACD_RSI_WT', ['macd', 'rsi', 'wt'], theme: ChartTheme.light);
    await shot(tester, '09_副图_背景色方框标记表格_自绘K线_策略', [
      'com-trend-exhaustion-continuation-map-bullby',
      'com-signed-realized-variance-trend-backquant',
      'st-macd',
    ]);
    await shot(tester, '10_组合_3个主图加2个副图_深色',
        ['boll', 'smc', 'fvg', 'rsi', 'com-trend-exhaustion-continuation-map-bullby'],
        candleWidth: 6);
    await shot(tester, '11_组合_3个主图加2个副图_浅色',
        ['boll', 'smc', 'fvg', 'rsi', 'com-trend-exhaustion-continuation-map-bullby'],
        theme: ChartTheme.light, candleWidth: 6);
    await shot(tester, '12_横屏_主图加副图', ['com-supertrend-strategy', 'sar', 'macd'],
        size: const Size(900, 420), candleWidth: 7);
    final candles = loadKlines();
    await shot(tester, '13_合成_全部标签样式和标记形状', [labelMarkerStyles(candles)], candleWidth: 13);
    await shot(
        tester,
        '14_合成_线型延伸方框文字表格位置',
        [
          lineBoxTableStyles([for (final c in candles) c.time])
        ],
        candleWidth: 13);
  });
}
