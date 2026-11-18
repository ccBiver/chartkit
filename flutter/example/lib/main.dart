import 'dart:async';
import 'dart:math' as math;

import 'package:chartkit_flutter/chartkit_flutter.dart';
import 'package:flutter/material.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
    title: 'chartkit_flutter',
    debugShowCheckedModeBanner: false,
    home: ChartDemoPage(),
  );
}

/// 随机游走的模拟行情：[count] 根，末根对齐到当前周期。
List<Candle> mockCandles(TimeFrame timeFrame, {int count = 300, int? endTime, int seed = 7}) {
  final random = math.Random(seed + timeFrame.index);
  final end = timeFrame.openTimeOf(endTime ?? DateTime.now().millisecondsSinceEpoch);
  var price = 64000.0;
  return [
    for (var i = 0; i < count; i++)
      () {
        final open = price;
        final close = open * (1 + (random.nextDouble() - 0.49) * 0.012);
        final high = math.max(open, close) * (1 + random.nextDouble() * 0.004);
        final low = math.min(open, close) * (1 - random.nextDouble() * 0.004);
        final volume = 20 + random.nextDouble() * 180;
        price = close;
        return Candle(
          time: end - (count - 1 - i) * timeFrame.millis,
          open: open,
          high: high,
          low: low,
          close: close,
          volume: volume,
          turnover: volume * close,
        );
      }(),
  ];
}

class ChartDemoPage extends StatefulWidget {
  const ChartDemoPage({super.key});

  @override
  State<ChartDemoPage> createState() => _ChartDemoPageState();
}

class _ChartDemoPageState extends State<ChartDemoPage> {
  static const _timeFrames = {
    'Time': TimeFrame.m1,
    '15m': TimeFrame.m15,
    '1H': TimeFrame.h1,
    '4H': TimeFrame.h4,
    '1D': TimeFrame.d1,
  };
  static final Map<String, Indicator> _mainOptions = {
    'MA': Ma(), 'EMA': Ema(), 'BOLL': const Boll(), 'SAR': const Sar(), //
  };
  static final Map<String, Indicator> _subOptions = {
    'MACD': const Macd(), 'KDJ': const Kdj(), 'RSI': Rsi(), //
    'WR': Wr(), 'OBV': const Obv(),
  };

  final _state = KLineChartState();
  final _subs = SubIndicatorController(mode: SubIndicatorMode.multiple);
  final _random = math.Random();
  Timer? _ticker;
  Timer? _loader;
  String _period = '15m';
  bool _dark = true;
  List<Indicator> _main = [_mainOptions['MA']!];
  List<TradeMark> _marks = const [];

  @override
  void initState() {
    super.initState();
    _subs.addListener(() => setState(() {}));
    _subs.toggle(_subOptions['MACD']!);
    _load();
    _ticker = Timer.periodic(const Duration(milliseconds: 800), (_) => _tick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _loader?.cancel();
    _subs.dispose();
    _state.dispose();
    super.dispose();
  }

  /// 模拟网络加载：先清空（显示骨架屏），稍后数据到达。
  void _load() {
    final timeFrame = _timeFrames[_period]!;
    _state.changeTimeFrame(timeFrame);
    _loader?.cancel();
    _loader = Timer(const Duration(milliseconds: 600), () {
      final data = mockCandles(timeFrame);
      _state.setData(data);
      setState(() {
        _marks = [
          TradeMark(
            time: data[data.length - 12].time,
            isBuy: true,
            price: data[data.length - 12].low,
            count: 2,
          ),
          TradeMark(
            time: data[data.length - 5].time,
            isBuy: false,
            price: data[data.length - 5].high,
            count: 1,
          ),
        ];
      });
    });
  }

  /// 模拟实时 tick：末根在当前周期内更新，跨周期则追加新根。
  void _tick() {
    final candles = _state.candles;
    if (candles.isEmpty) return;
    final last = candles.last;
    final close = last.close * (1 + (_random.nextDouble() - 0.5) * 0.002);
    final openTime = _state.timeFrame.openTimeOf(DateTime.now().millisecondsSinceEpoch);
    _state.appendOrUpdate(
      openTime > last.time
          ? Candle(
            time: openTime,
            open: last.close,
            high: math.max(last.close, close),
            low: math.min(last.close, close),
            close: close,
            volume: 1,
          )
          : last.copyWith(
            close: close,
            high: math.max(last.high, close),
            low: math.min(last.low, close),
            volume: last.volume + _random.nextDouble() * 3,
          ),
    );
  }

  void _loadMore() {
    final candles = _state.candles;
    if (candles.isEmpty || candles.length > 1500) return;
    final older = mockCandles(
      _state.timeFrame,
      count: 200,
      endTime: candles.first.time - _state.timeFrame.millis,
      seed: candles.length,
    );
    // 把更早一段的收盘价接到现有首根的开盘价上，保证曲线连续
    final shift = candles.first.open - older.last.close;
    _state.prepend([
      for (final c in older)
        c.copyWith(
          open: c.open + shift,
          high: c.high + shift,
          low: c.low + shift,
          close: c.close + shift,
        ),
    ]);
  }

  void _toggleMain(Indicator indicator) => setState(() {
    _main =
        _main.contains(indicator)
            ? [
              for (final e in _main)
                if (e != indicator) e,
            ]
            : [..._main, indicator];
  });

  @override
  Widget build(BuildContext context) {
    final theme = _dark ? ChartTheme.dark : ChartTheme.light;
    final text = _dark ? Colors.white70 : Colors.black87;
    return Scaffold(
      backgroundColor: theme.background,
      body: SafeArea(
        child: Column(
          children: [
            _chipRow(text, [
              for (final label in _timeFrames.keys)
                _chip(label, _period == label, text, () {
                  setState(() => _period = label);
                  _load();
                }),
              _chip(_dark ? 'Light' : 'Dark', false, text, () => setState(() => _dark = !_dark)),
            ]),
            Expanded(
              child: KLineChart(
                state: _state,
                theme: theme,
                mode: _period == 'Time' ? ChartMode.timeLine : ChartMode.candle,
                mainIndicators: _main,
                subIndicators: _subs.selected,
                tradeMarks: _marks,
                blankScrollRatio: 0.3,
                logo: const FlutterLogo(style: FlutterLogoStyle.horizontal),
                onLoadMore: _loadMore,
                onToggleFullscreen: () {},
                onTradeMarkTap:
                    (m) => ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('${m.isBuy ? 'Buy' : 'Sell'} @ ${m.price}')),
                    ),
              ),
            ),
            _chipRow(text, [
              for (final e in _mainOptions.entries)
                _chip(e.key, _main.contains(e.value), text, () => _toggleMain(e.value)),
              const SizedBox(width: 12),
              for (final e in _subOptions.entries)
                _chip(e.key, _subs.isSelected(e.value.id), text, () => _subs.toggle(e.value)),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _chipRow(Color color, List<Widget> children) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    child: Row(children: children),
  );

  Widget _chip(String label, bool selected, Color color, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFF3B82F6) : color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: TextStyle(color: selected ? Colors.white : color, fontSize: 12)),
    ),
  );
}
