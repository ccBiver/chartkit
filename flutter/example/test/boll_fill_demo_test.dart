import 'package:chartkit_example/main.dart';
import 'package:chartkit_flutter/chartkit_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('BOLL 底色开关：打开后传给图表的 Boll 带填充色，关掉后不带', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    await tester.pumpWidget(const MaterialApp(home: ChartDemoPage()));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    Boll? boll() =>
        tester.widget<KLineChart>(find.byType(KLineChart)).mainIndicators.whereType<Boll>().firstOrNull;

    await tester.ensureVisible(find.text('BOLL'));
    await tester.tap(find.text('BOLL'));
    await tester.pump(const Duration(seconds: 1));
    expect(boll(), isNotNull);
    expect(boll()!.fillColor, isNull);

    await tester.ensureVisible(find.text('BOLL 底色'));
    await tester.tap(find.text('BOLL 底色'));
    await tester.pump(const Duration(seconds: 1));
    expect(boll()!.fillColor, isNotNull);

    await tester.tap(find.text('BOLL 底色'));
    await tester.pump(const Duration(seconds: 1));
    expect(boll()!.fillColor, isNull);
    expect(tester.takeException(), isNull);

    // 停掉页面里的定时器
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
  });
}
