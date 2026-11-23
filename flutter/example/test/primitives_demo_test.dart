import 'package:chartkit_example/primitives_demo.dart';
import 'package:chartkit_flutter/chartkit_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('demo page loads the samples and toggles scripts', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    await tester.pumpWidget(const MaterialApp(home: PrimitivesDemoPage()));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(KLineChart), findsOneWidget);
    expect(find.textContaining('Basis'), findsOneWidget, reason: 'values row shows BOLL');

    await tester.ensureVisible(find.text('MACD'));
    await tester.tap(find.text('MACD'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('Histogram'), findsOneWidget);

    await tester.tap(find.text('浅色'));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('全部移除'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('Basis'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.binding.setSurfaceSize(null);
  });
}
