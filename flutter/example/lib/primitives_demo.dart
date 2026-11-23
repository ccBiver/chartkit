import 'dart:async';
import 'dart:convert';

import 'package:chartkit_flutter/chartkit_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 脚本图元演示：样本是脚本引擎在测试环境 XAUUSD 15m K 线上的真输出（assets/primitives）。
/// 可以同时开多个脚本：主图的叠在 K 线上，副图的各占一个窗格。
class PrimitivesDemoPage extends StatefulWidget {
  const PrimitivesDemoPage({super.key});

  @override
  State<PrimitivesDemoPage> createState() => _PrimitivesDemoPageState();
}

class _PrimitivesDemoPageState extends State<PrimitivesDemoPage> {
  static const _samples = {
    'boll': 'BOLL',
    'com-supertrend-strategy': '超级趋势策略',
    'sar': 'SAR',
    'smc': 'SMC',
    'fvg': 'FVG',
    'opt-po3': '大周期投影',
    'com-machine-learning-adaptive-supertrend-alg': 'ML 超级趋势',
    'macd': 'MACD',
    'rsi': 'RSI',
    'wt': 'WaveTrend',
    'com-trend-exhaustion-continuation-map-bullby': '趋势衰竭',
  };

  final _state = KLineChartState(timeFrame: TimeFrame.m15);
  late final _scripts = ScriptOutputController(
    onAlignmentIssue: (issue) => _show('${issue.scriptId} 对不上 K 线：${issue.problem.name}'),
  );
  final Map<String, String> _json = {};
  Timer? _refresher;
  bool _dark = true;
  bool _refresh = false;

  @override
  void initState() {
    super.initState();
    _scripts.addListener(() => setState(() {}));
    _state.addListener(() => setState(() {}));
    _loadKlines();
  }

  @override
  void dispose() {
    _refresher?.cancel();
    _scripts.dispose();
    _state.dispose();
    super.dispose();
  }

  Future<void> _loadKlines() async {
    final raw = jsonDecode(await rootBundle.loadString('assets/primitives/klines_15m.json')) as Map;
    _state.setData([
      for (final b in raw['bars'] as List)
        Candle(
          time: (b['time'] as num).toInt(),
          open: (b['open'] as num).toDouble(),
          high: (b['high'] as num).toDouble(),
          low: (b['low'] as num).toDouble(),
          close: (b['close'] as num).toDouble(),
        ),
    ]);
    await _toggle('boll');
    await _toggle('smc');
    await _toggle('rsi');
  }

  Future<void> _toggle(String id) async {
    if (_scripts.remove(id)) return;
    final text = _json[id] ??= await rootBundle.loadString('assets/primitives/$id.json');
    final r = _scripts.setJson(id, text);
    if (!r.ok) _show('$id 解析失败：${r.error}');
  }

  /// 模拟引擎每 5 秒发来一份新的整份输出：按 id 原样替换，窗格不动、不闪。
  void _setRefresh(bool on) {
    _refresher?.cancel();
    _refresher =
        on
            ? Timer.periodic(const Duration(seconds: 5), (_) {
              for (final id in _scripts.scriptIds) {
                _scripts.setJson(id, _json[id]);
              }
            })
            : null;
    setState(() => _refresh = on);
  }

  void _show(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = _dark ? ChartTheme.dark : ChartTheme.light;
    final text = _dark ? Colors.white70 : Colors.black87;
    // 取值接口：十字光标那根（没有光标时是最新一根）
    final focus = _state.crosshairIndex >= 0 ? _state.crosshairIndex : _state.candles.length - 1;
    final values = focus < 0 ? const <ScriptValue>[] : _scripts.valuesAt(focus);
    return Scaffold(
      backgroundColor: theme.background,
      body: SafeArea(
        child: Column(
          children: [
            _row([
              _chip('返回', false, text, () => Navigator.of(context).pop()),
              _chip(_dark ? '浅色' : '深色', false, text, () => setState(() => _dark = !_dark)),
              _chip('每 5 秒替换', _refresh, text, () => _setRefresh(!_refresh)),
              _chip('显示', _scripts.visible, text, () => _scripts.visible = !_scripts.visible),
              _chip('全部移除', false, text, _scripts.clear),
            ]),
            Expanded(
              child: KLineChart(
                state: _state,
                theme: theme,
                entranceAnimation: false,
                showVolume: false,
                blankScrollWidth: 120,
                scriptOutputs: _scripts,
              ),
            ),
            SizedBox(
              height: 34,
              child: _row([
                for (final v in values)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Text(
                      '${v.title.isEmpty ? v.seriesId : v.title} '
                      '${v.value == null ? '--' : v.value!.toStringAsFixed(v.precision ?? 2)}',
                      style: TextStyle(color: v.color ?? text, fontSize: 11),
                    ),
                  ),
              ]),
            ),
            _row([
              for (final e in _samples.entries)
                _chip(e.value, _scripts.scriptIds.contains(e.key), text, () => _toggle(e.key)),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _row(List<Widget> children) => SingleChildScrollView(
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
