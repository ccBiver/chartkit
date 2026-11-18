import 'package:chartkit_flutter/chartkit_flutter.dart';
import 'package:chartkit_flutter/src/chart/countdown.dart';
import 'package:chartkit_flutter/src/chart/number_format.dart';
import 'package:flutter_test/flutter_test.dart';

Candle _c(int time, [double close = 1]) =>
    Candle(time: time, open: close, high: close, low: close, close: close);

List<Candle> _data(int n, {int start = 0}) => [for (var i = 0; i < n; i++) _c(start + i)];

void main() {
  group('number format', () {
    test('fixed keeps digits and never prints negative zero', () {
      expect(fixed(1.006, 2), '1.01');
      expect(fixed(3, 2), '3.00');
      expect(fixed(-1.5, 1), '-1.5');
      expect(fixed(-0.001, 2), '0.00');
      expect(fixed(12.7, 0), '13');
      expect(fixed(double.nan, 2), 'NaN');
    });

    test('trimmed rounds and drops trailing zeros', () {
      expect(trimmed(1.239, 2), '1.24');
      expect(trimmed(2.5, 2), '2.5');
      expect(trimmed(3, 2), '3.0');
      expect(trimmed(double.nan, 2), '--');
    });

    test('abbrevNum', () {
      expect(abbrevNum(999), '999.00');
      expect(abbrevNum(1500), '1.50K');
      expect(abbrevNum(2500000), '2.50M');
      expect(abbrevNum(-3e9), '-3.00B');
    });

    test('candle countdown formats the time left in the current candle', () {
      Candle at(int time) => Candle(time: time, open: 1, high: 1, low: 1, close: 1);
      final candles = [at(0), at(60000)];
      expect(candleCountdown(candles, TimeFrame.m1, 60000 + 15000), '00:45');
      expect(candleCountdown(candles, TimeFrame.m1, 999999), '00:00', reason: 'never negative');
      final twoHourly = [at(0), at(7200000)];
      expect(candleCountdown(twoHourly, TimeFrame.h2, 7200000 + 1000), '01:59:59');
      expect(candleCountdown([at(0)], TimeFrame.m15, 60000), '14:00',
          reason: 'falls back to the time frame');
      expect(candleCountdown(const [], TimeFrame.m1, 0), isNull);
    });

    test('default formatter', () {
      const f = ChartFormatter();
      expect(f.price(1.239), '1.24');
      expect(f.volume(1234567), '1.23M');
      final t = DateTime(2026, 3, 4, 5, 6).millisecondsSinceEpoch;
      expect(f.time(t, TimeFrame.m15), '05:06');
      expect(f.crosshairTime(t, TimeFrame.m15), '03-04 05:06');
    });
  });

  group('KLineChartState', () {
    test('setData replaces data, bumps both versions and snaps to latest', () {
      final s = KLineChartState();
      var notified = 0;
      s.addListener(() => notified++);
      s.setViewport(scrollOffset: 120);
      s.setCrosshair(3, 10, 20);
      s.setData(_data(5));
      expect(s.candles.length, 5);
      expect(s.dataVersion, 1);
      expect(s.resetVersion, 1);
      expect(s.scrollOffset, 0);
      expect(s.crosshairIndex, -1);
      expect(notified, 3);
    });

    test('candles are exposed as an unmodifiable list', () {
      final source = _data(3);
      final s = KLineChartState()..setData(source);
      expect(() => s.candles.add(_c(9)), throwsUnsupportedError);
      source.add(_c(9));
      expect(s.candles.length, 3, reason: 'state must not alias the caller list');
    });

    test('appendOrUpdate replaces the last candle on equal time, else appends', () {
      final s = KLineChartState()..setData(_data(3));
      final before = s.candles;
      s.appendOrUpdate(_c(2, 9));
      expect(s.candles.length, 3);
      expect(s.candles.last.close, 9);
      expect(before.last.close, 1, reason: 'previous list is left untouched');
      s.appendOrUpdate(_c(3, 7));
      expect(s.candles.length, 4);
      expect(s.dataVersion, 3);
      expect(s.resetVersion, 1);
    });

    test('prepend inserts older candles and ignores empty input', () {
      final s = KLineChartState()..setData(_data(3, start: 10));
      s.prepend(const []);
      expect(s.dataVersion, 1);
      s.prepend(_data(2, start: 8));
      expect(s.candles.map((e) => e.time), [8, 9, 10, 11, 12]);
      expect(s.resetVersion, 1);
    });

    test('applyUpdate dispatches by type', () {
      final s = KLineChartState();
      s.applyUpdate(KLineUpdate.reset, _data(3, start: 10));
      expect(s.candles.length, 3);
      s.applyUpdate(KLineUpdate.latest, [..._data(3, start: 10), _c(13)]);
      expect(s.candles.length, 4);
      s.applyUpdate(KLineUpdate.more, [..._data(2, start: 8), ...s.candles]);
      expect(s.candles.first.time, 8);
      expect(s.resetVersion, 1);
      s.applyUpdate(KLineUpdate.more, _data(2));
      expect(s.resetVersion, 2, reason: 'a shorter list falls back to a reset');
    });

    test('changeTimeFrame clears the crosshair only when it changes', () {
      final s = KLineChartState()..setData(_data(3));
      s.setCrosshair(1, 5, 5);
      s.changeTimeFrame(TimeFrame.m15);
      expect(s.crosshairIndex, 1);
      s.changeTimeFrame(TimeFrame.h1);
      expect(s.timeFrame, TimeFrame.h1);
      expect(s.crosshairIndex, -1);
    });

    test('viewport setters do not notify when nothing changes', () {
      final s = KLineChartState();
      var notified = 0;
      s.addListener(() => notified++);
      s.setViewport(scrollOffset: 0);
      s.clearCrosshair();
      expect(notified, 0);
      s.setViewport(candleWidth: 12, scrollOffset: 30);
      expect(s.candleWidth, 12);
      expect(s.scrollOffset, 30);
      expect(notified, 1);
    });
  });

  group('SubIndicatorController', () {
    test('single mode replaces, and toggling the selected one closes it', () {
      final c = SubIndicatorController();
      c.toggle(const Macd());
      c.toggle(const Kdj());
      expect(c.selected.map((e) => e.id), ['KDJ']);
      c.toggle(const Kdj());
      expect(c.selected, isEmpty);
    });

    test('multiple mode stacks panes', () {
      final c = SubIndicatorController(mode: SubIndicatorMode.multiple);
      c.toggle(const Macd());
      c.toggle(const Kdj());
      expect(c.selected.map((e) => e.id), ['MACD', 'KDJ']);
      expect(c.isSelected('MACD'), isTrue);
      c.toggle(const Macd());
      expect(c.selected.map((e) => e.id), ['KDJ']);
    });

    test('switching to single keeps only the last one', () {
      final c = SubIndicatorController(mode: SubIndicatorMode.multiple);
      c.set([const Macd(), const Kdj(), Rsi()]);
      var notified = 0;
      c.addListener(() => notified++);
      c.changeMode(SubIndicatorMode.single);
      expect(c.selected.map((e) => e.id), ['RSI']);
      expect(notified, 1);
      c.set([const Macd(), const Kdj()]);
      expect(c.selected.map((e) => e.id), ['KDJ']);
      c.clear();
      expect(c.selected, isEmpty);
    });

    test('selected is unmodifiable', () {
      final c = SubIndicatorController()..toggle(const Macd());
      expect(() => c.selected.clear(), throwsUnsupportedError);
    });
  });
}
