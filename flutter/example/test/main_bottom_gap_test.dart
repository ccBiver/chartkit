import 'package:chartkit_example/main.dart';
import 'package:chartkit_flutter/chartkit_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('主图下留空：指标行摆进图表的空白里，点里面的指标名能开关副图', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    await tester.pumpWidget(const MaterialApp(home: ChartDemoPage()));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    final chartRect = tester.getRect(find.byType(KLineChart));
    expect(chartRect.contains(tester.getCenter(find.text('RSI'))), isFalse);

    await tester.tap(find.text('主图下留空'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    final chart = tester.widget<KLineChart>(find.byType(KLineChart));
    expect(chart.mainBottomGap, 34);
    final gap = chart.state.mapper.value!.mainBottomGapRect.shift(chartRect.topLeft);
    expect(gap.height, 34);
    // 指标行横向可滚动，RSI 可能在屏幕右边外面；只核对竖直方向落在空白里
    final rsi = tester.getCenter(find.text('RSI'));
    expect(rsi.dy, inInclusiveRange(gap.top, gap.bottom), reason: '空白 $gap，RSI 在 $rsi');
    await tester.ensureVisible(find.text('RSI'));
    await tester.pump();

    final before = chart.subIndicators.length;
    await tester.tap(find.text('RSI'));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.widget<KLineChart>(find.byType(KLineChart)).subIndicators.length, before + 1);
    expect(tester.takeException(), isNull);

    // 停掉页面里的定时器
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
  });
}
