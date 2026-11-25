import 'dart:async';
import 'dart:math' as math;

import 'package:chartkit_flutter/chartkit_flutter.dart';
import 'package:flutter/material.dart';

import 'primitives_demo.dart';

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
  // 画线：颜色由调用方给；onChanged 里按品种存 toJson()，这里只存在内存里演示
  late final DrawingController _drawings = DrawingController(
    style: const DrawingStyle(color: Color(0xFF3B82F6)),
    onChanged: () => _savedDrawings = _drawings.toJson(),
  );
  Map<String, Object?>? _savedDrawings;
  final _subs = SubIndicatorController(mode: SubIndicatorMode.multiple);
  final _random = math.Random();
  Timer? _ticker;
  Timer? _loader;
  String _period = '15m';
  bool _dark = true;

  /// 主图下方留一行给宿主自己的控件（这里放指标开关）。
  bool _gapRow = false;

  /// BOLL 上下轨之间填半透明底色（颜色由宿主定，这里取主题第二个指标色）。
  bool _bollFill = false;
  static const double _gapHeight = 34;
  List<Indicator> _main = [_mainOptions['MA']!];
  List<TradeMark> _marks = const [];

  @override
  void initState() {
    super.initState();
    _subs.addListener(() => setState(() {}));
    _drawings.addListener(() => setState(() {}));
    _subs.toggle(_subOptions['MACD']!);
    _load();
    _ticker = Timer.periodic(const Duration(milliseconds: 800), (_) => _tick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _loader?.cancel();
    _subs.dispose();
    _drawings.dispose();
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
              _chip('主图下留空', _gapRow, text, () => setState(() => _gapRow = !_gapRow)),
              _chip('BOLL 底色', _bollFill, text, () => setState(() => _bollFill = !_bollFill)),
              _chip(
                '脚本图元',
                false,
                text,
                () => Navigator.of(
                  context,
                ).push(MaterialPageRoute<void>(builder: (_) => const PrimitivesDemoPage())),
              ),
            ]),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(
                    child: KLineChart(
                      state: _state,
                      theme: theme,
                      mode: _period == 'Time' ? ChartMode.timeLine : ChartMode.candle,
                      mainIndicators: [
                        for (final i in _main)
                          i is Boll && _bollFill
                              ? Boll(
                                  period: i.period,
                                  k: i.k,
                                  fillColor: theme.indicatorColor(1).withValues(alpha: 0.12),
                                )
                              : i,
                      ],
                      subIndicators: _subs.selected,
                      tradeMarks: _marks,
                      blankScrollRatio: 0.3,
                      logo: const FlutterLogo(style: FlutterLogoStyle.horizontal),
                      mainBottomGap: _gapRow ? _gapHeight : 0,
                      onLoadMore: _loadMore,
                      onToggleFullscreen: () {},
                      drawingController: _drawings,
                      drawingLabels: const DrawingLabels(
                        entry: '入场',
                        target: '目标',
                        stop: '止损',
                        riskReward: '盈亏比',
                        bars: '根',
                      ),
                      onTradeMarkTap:
                          (m) => ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('${m.isBuy ? 'Buy' : 'Sell'} @ ${m.price}')),
                          ),
                    ),
                  ),
                  // 宿主控件按 mapper 给的空白位置摆放
                  if (_gapRow)
                    ValueListenableBuilder<KLineChartMapper?>(
                      valueListenable: _state.mapper,
                      builder: (context, m, _) => m == null || m.mainBottomGapRect.isEmpty
                          ? const SizedBox.shrink()
                          : Positioned.fromRect(
                              rect: m.mainBottomGapRect,
                              child: _indicatorRow(text),
                            ),
                    ),
                ],
              ),
            ),
            _drawingRow(text),
            if (!_gapRow) _indicatorRow(text),
          ],
        ),
      ),
    );
  }

  static const _toolNames = {
    DrawingTool.trendLine: '趋势线',
    DrawingTool.ray: '射线',
    DrawingTool.horizontalLine: '水平线',
    DrawingTool.verticalLine: '垂直线',
    DrawingTool.rectangle: '矩形',
    DrawingTool.fibRetracement: '斐波那契',
    DrawingTool.priceRange: '测量',
    DrawingTool.longPosition: '多头头寸',
    DrawingTool.shortPosition: '空头头寸',
    DrawingTool.pitchfork: '安德鲁分叉',
    DrawingTool.elliottWave: '艾略特波浪',
    DrawingTool.gannFan: '江恩扇形',
  };

  /// 画线工具栏：工具、显示开关、清除；选中时多出锁定、删除。
  Widget _drawingRow(Color text) {
    final d = _drawings;
    final selected = d.selected;
    final tool = d.tool;
    return _chipRow(text, [
      if (tool != null) ...[
        _chip(
          '${_toolNames[tool]}：点第 ${d.draft.length + 1}/${tool.pointCount} 个点',
          true,
          text,
          () {},
        ),
        _chip('取消', false, text, () => d.tool = null),
      ] else if (selected != null) ...[
        _chip(
          selected.locked ? '解锁' : '锁定',
          false,
          text,
          () => d.setLocked(selected.id, !selected.locked),
        ),
        _chip('删除', false, text, d.removeSelected),
        _chip('换色', false, text, () {
          const colors = [Color(0xFF3B82F6), Color(0xFFF0A020), Color(0xFFB44BE0)];
          final next = colors[(colors.indexOf(selected.style.color) + 1) % colors.length];
          d.setStyle(selected.id, selected.style.copyWith(color: next));
        }),
        _chip('线宽 ${selected.style.width.toInt()}', false, text, () {
          d.setStyle(selected.id, selected.style.copyWith(width: selected.style.width % 3 + 1));
        }),
        if (selected.tool == DrawingTool.fibRetracement)
          _chip(
            '只看 0.382/0.5/0.618',
            false,
            text,
            () => d.setFibLevels(selected.id, const [0.382, 0.5, 0.618]),
          ),
      ] else
        for (final e in _toolNames.entries) _chip(e.value, false, text, () => d.tool = e.key),
      const SizedBox(width: 12),
      _chip('显示画线', d.visible, text, () => d.visible = !d.visible),
      _chip('清除全部', false, text, d.clear),
      _chip('恢复', false, text, () => d.loadJson(_savedDrawings)),
    ]);
  }

  Widget _indicatorRow(Color text) => _chipRow(text, [
        for (final e in _mainOptions.entries)
          _chip(e.key, _main.contains(e.value), text, () => _toggleMain(e.value)),
        const SizedBox(width: 12),
        for (final e in _subOptions.entries)
          _chip(e.key, _subs.isSelected(e.value.id), text, () => _subs.toggle(e.value)),
      ]);

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
