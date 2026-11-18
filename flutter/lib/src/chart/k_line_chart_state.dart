import 'package:flutter/foundation.dart';

import '../model/candle.dart';
import '../model/time_frame.dart';
import 'chart_mapper.dart';

/// K 线数据更新类型——宿主用它驱动图，无需关心内部 setData/appendOrUpdate/prepend：
///  - [reset]  全量替换（首次加载、切周期）
///  - [latest] 更新最新一根（实时 tick：同周期替换末根，跨周期追加）
///  - [more]   加载更多更早数据（头部插入，保持当前可视位置不跳）
enum KLineUpdate { reset, latest, more }

/// 图表状态宿主（状态上提）。持有数据、可见视口、十字光标。
/// 业务方通过 [setData]/[appendOrUpdate]/[prepend] 驱动；`KLineChart` 监听并渲染。
///
/// 视口用「每根宽 [candleWidth]」+「相对最新一根的横向偏移 [scrollOffset]」表达。
/// 用完需 [dispose]。
class KLineChartState extends ChangeNotifier {
  KLineChartState({TimeFrame timeFrame = TimeFrame.m15}) : _timeFrame = timeFrame;

  TimeFrame _timeFrame;
  List<Candle> _candles = const [];
  double _candleWidth = 0;
  double _scrollOffset = 0;
  int _crosshairIndex = -1;
  double _crosshairX = -1;
  double _crosshairY = -1;
  double? _crosshairPrice;
  int _dataVersion = 0;
  int _resetVersion = 0;
  final ValueNotifier<KLineChartMapper?> _mapper = ValueNotifier(null);

  TimeFrame get timeFrame => _timeFrame;

  /// 当前全部 K 线（不可修改；每次数据变化都会换成新的 list）。
  List<Candle> get candles => _candles;

  /// 单根宽度（逻辑像素，含间隙），由缩放手势改变。0 表示用主题默认值。
  double get candleWidth => _candleWidth;

  /// 横向滚动偏移（逻辑像素；0=贴最新，>0 表示向历史方向拖动）。
  double get scrollOffset => _scrollOffset;

  /// 十字光标命中的数据索引；-1 表示无。可大于末根索引（落在右侧留白）。
  int get crosshairIndex => _crosshairIndex;

  /// 十字光标手指位置；-1 表示无。
  double get crosshairX => _crosshairX;
  double get crosshairY => _crosshairY;

  /// 十字光标锁定的价位；未锁价或无光标时为 null。
  double? get crosshairPrice => _crosshairPrice;

  /// 数据版本号：每次数据变化自增，用于指标缓存失效判断。
  int get dataVersion => _dataVersion;

  /// 全量替换版本号：仅 [setData] 自增，用于触发「换周期重播入场动画」。
  int get resetVersion => _resetVersion;

  /// 最近一帧的坐标映射；首帧绘制前、或无数据时为 null。
  ValueListenable<KLineChartMapper?> get mapper => _mapper;

  void changeTimeFrame(TimeFrame timeFrame) {
    if (timeFrame == _timeFrame) return;
    _timeFrame = timeFrame;
    _resetCrosshair();
    notifyListeners();
  }

  /// 全量替换数据（首屏 / 切周期），总是回到最新一屏。
  ///
  /// [data] 需按 [Candle.time] 升序、且价格/成交量为有限数值（debug 模式下断言校验）。
  void setData(List<Candle> data) {
    assert(_debugCheck(data));
    _candles = List.unmodifiable(data);
    _dataVersion++;
    _resetVersion++;
    _scrollOffset = 0;
    _resetCrosshair();
    notifyListeners();
  }

  /// 实时更新：若末根时间相同则替换末根，否则追加新根。
  void appendOrUpdate(Candle candle) {
    assert(_debugCheck([candle]));
    final cur = _candles;
    assert(cur.isEmpty || candle.time >= cur.last.time, 'tick is older than the last candle');
    final replace = cur.isNotEmpty && cur.last.time == candle.time;
    final kept = replace ? cur.take(cur.length - 1) : cur;
    _candles = List.unmodifiable(kept.followedBy([candle]));
    _dataVersion++;
    notifyListeners();
  }

  /// 头部插入更早的数据。保持当前可视位置不“跳”。
  void prepend(List<Candle> older) {
    if (older.isEmpty) return;
    assert(_debugCheck(older));
    assert(
        _candles.isEmpty || older.last.time < _candles.first.time, 'prepend needs older candles');
    _candles = List.unmodifiable(older.followedBy(_candles));
    _dataVersion++;
    notifyListeners();
  }

  /// 统一更新入口：[data] 始终传当前完整列表；
  /// [KLineUpdate.more] 时自动取「比现有多出来的头部增量」做 prepend。
  void applyUpdate(KLineUpdate type, List<Candle> data) {
    switch (type) {
      case KLineUpdate.reset:
        setData(data);
      case KLineUpdate.latest:
        if (data.isNotEmpty) appendOrUpdate(data.last);
      case KLineUpdate.more:
        final delta = data.length - _candles.length;
        if (delta > 0) {
          prepend(data.sublist(0, delta));
        } else {
          setData(data);
        }
    }
  }

  /// 修改视口（缩放 / 滚动）。值未变化时不通知。
  void setViewport({double? candleWidth, double? scrollOffset}) {
    final cw = candleWidth ?? _candleWidth;
    final so = scrollOffset ?? _scrollOffset;
    if (cw == _candleWidth && so == _scrollOffset) return;
    _candleWidth = cw;
    _scrollOffset = so;
    notifyListeners();
  }

  /// 设置十字光标（命中索引 + 手指位置）。
  ///
  /// [price] 非空表示把水平线锁在该价位：行情刷新、缩放使价格区间变化时，
  /// 线跟着价位走，而不是停在屏幕上的固定位置。
  void setCrosshair(int index, double x, double y, {double? price}) {
    final same = index == _crosshairIndex && x == _crosshairX && y == _crosshairY;
    if (same && price == _crosshairPrice) return;
    _crosshairIndex = index;
    _crosshairX = x;
    _crosshairY = y;
    _crosshairPrice = price;
    notifyListeners();
  }

  /// 清除十字光标。
  void clearCrosshair() {
    if (_crosshairIndex < 0 && _crosshairX < 0 && _crosshairY < 0) return;
    _resetCrosshair();
    notifyListeners();
  }

  /// 由 `KLineChart` 在帧末调用，宿主不应调用。
  void updateMapper(KLineChartMapper? mapper) => _mapper.value = mapper;

  /// 边界校验（仅 debug）：数值有限、时间升序。非法数据会让坐标换算产生 NaN。
  static bool _debugCheck(List<Candle> data) {
    for (var i = 0; i < data.length; i++) {
      final c = data[i];
      final finite = c.open.isFinite && c.high.isFinite && c.low.isFinite && c.close.isFinite;
      assert(finite && c.volume.isFinite, 'candle #$i has a non-finite value: $c');
      assert(i == 0 || c.time > data[i - 1].time, 'candles must be sorted by time (index $i)');
    }
    return true;
  }

  void _resetCrosshair() {
    _crosshairIndex = -1;
    _crosshairX = -1;
    _crosshairY = -1;
    _crosshairPrice = null;
  }

  @override
  void dispose() {
    _mapper.dispose();
    super.dispose();
  }
}
