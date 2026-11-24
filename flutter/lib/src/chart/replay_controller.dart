import 'dart:async';

import 'package:flutter/foundation.dart';

import '../model/candle.dart';
import 'k_line_chart.dart';
import 'k_line_chart_state.dart';

/// K 线回放的阶段。
enum ReplayPhase {
  /// 没有回放，图上是实时数据。
  off,

  /// 等用户在图上点一根 K 线作为起点（图上仍是实时数据）。
  picking,

  /// 回放中：图上只有起点到游标的 K 线。
  active,
}

/// K 线回放：从选定的一根开始，一根一根往后放。只管数据和节奏，控制条界面由宿主做。
///
/// 回放时图表画的是控制器自己的一份截断数据（[view]），宿主照常往 [source] 推实时行情，
/// 图不会被带走；退出后图回到 [source]，自然就是最新的。
/// 本地指标按截断后的数据重算；脚本图元按游标裁掉之后的部分（见 `KLineChart.replay`）。
///
/// [source] 换成新数据（`setData`，如切周期）时自动退出回放；往前加载更早的数据（`prepend`）时
/// 回放里也补上。用完要 [dispose]。
class ChartReplayController extends ChangeNotifier {
  ChartReplayController({
    required this.source,
    this.speeds = const [0.5, 1, 2, 4],
    double speed = 1,
    this.interval = const Duration(seconds: 1),
  })  : assert(speeds.contains(speed)),
        _speed = speed {
    _resetVersion = source.resetVersion;
    source.addListener(_onSource);
  }

  /// 宿主喂实时行情的那份状态，也就是 `KLineChart.state`。
  final KLineChartState source;

  /// 可选的倍速，默认 0.5x、1x、2x、4x。
  final List<double> speeds;

  /// 1x 时每根的间隔。
  final Duration interval;

  ReplayPhase _phase = ReplayPhase.off;
  KLineChartState? _view;
  double _speed;
  Timer? _timer;
  late int _resetVersion;

  ReplayPhase get phase => _phase;

  /// 回放中图表画的数据；不在回放时为 null。
  KLineChartState? get view => _view;

  bool get playing => _timer != null;

  double get speed => _speed;

  /// 游标所在的那根（回放里最新的一根）；不在回放时为 null。
  Candle? get cursor {
    final c = _view?.candles;
    return c == null || c.isEmpty ? null : c.last;
  }

  /// 游标在 [source] 里的下标；不在回放时为 -1。
  int get cursorIndex {
    final c = _view?.candles;
    return c == null ? -1 : c.length - 1;
  }

  /// 已经放到 [source] 的最后一根。
  bool get atEnd => _phase == ReplayPhase.active && cursorIndex >= source.candles.length - 1;

  /// 进入选起点（第一次进入或「重选起点」）：暂停，图上换回实时数据等用户点一根。
  void start() {
    if (source.candles.isEmpty) return;
    pause();
    final old = _view;
    _view = null;
    _phase = ReplayPhase.picking;
    notifyListeners();
    old?.dispose();
  }

  /// 以 [source] 的第 [index] 根为起点开始回放（含这一根，之后的隐藏）。
  /// 一般由图表在选起点时点击触发；也可以直接调用。
  void select(int index) {
    final all = source.candles;
    if (all.isEmpty) return;
    pause();
    final i = index.clamp(0, all.length - 1);
    final old = _view;
    _view = KLineChartState(timeFrame: source.timeFrame)
      ..setViewport(candleWidth: source.candleWidth)
      ..setData(all.sublist(0, i + 1));
    _phase = ReplayPhase.active;
    notifyListeners();
    old?.dispose();
  }

  /// 下一根。返回是否已经放到最后一根。
  bool next() {
    final view = _view;
    if (_phase != ReplayPhase.active || view == null) return true;
    final all = source.candles;
    final i = view.candles.length;
    if (i >= all.length) {
      pause();
      return true;
    }
    view.appendOrUpdate(all[i]);
    final end = i >= all.length - 1;
    if (end) pause();
    notifyListeners();
    return end;
  }

  /// 按当前倍速自动往后放，放到最后一根自动暂停。
  void play() {
    if (_phase != ReplayPhase.active || playing || atEnd) return;
    _timer = Timer.periodic(_period, (_) => next());
    notifyListeners();
  }

  void pause() {
    if (_timer == null) return;
    _timer!.cancel();
    _timer = null;
    notifyListeners();
  }

  /// 换倍速；播放中立即按新倍速继续。
  set speed(double value) {
    assert(speeds.contains(value));
    if (value == _speed) return;
    _speed = value;
    if (_timer != null) {
      _timer!.cancel();
      _timer = Timer.periodic(_period, (_) => next());
    }
    notifyListeners();
  }

  /// 退出回放，图回到实时数据。
  void exit() {
    if (_phase == ReplayPhase.off) return;
    _timer?.cancel();
    _timer = null;
    final old = _view;
    _view = null;
    _phase = ReplayPhase.off;
    notifyListeners();
    old?.dispose();
  }

  Duration get _period =>
      Duration(microseconds: (interval.inMicroseconds / _speed).round());

  void _onSource() {
    if (source.resetVersion != _resetVersion) {
      _resetVersion = source.resetVersion;
      exit();
      return;
    }
    final view = _view;
    if (view == null || view.candles.isEmpty || source.candles.isEmpty) return;
    final first = view.candles.first.time;
    if (source.candles.first.time >= first) return;
    view.prepend([
      for (final c in source.candles)
        if (c.time < first) c,
    ]);
  }

  @override
  void dispose() {
    _timer?.cancel();
    source.removeListener(_onSource);
    _view?.dispose();
    super.dispose();
  }
}

/// 图表实际画的那份状态：回放中是回放的截断数据，否则是 `KLineChart.state`。
KLineChartState shownState(KLineChart chart) => chart.replay?.view ?? chart.state;
