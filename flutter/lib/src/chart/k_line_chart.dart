import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../drawing/drawing_controller.dart';
import '../drawing/drawing_geometry.dart';
import '../drawing/drawing_gestures.dart';
import '../drawing/drawing_painter.dart';
import '../drawing/drawing_theme.dart';
import '../indicator/indicator.dart';
import '../indicator/indicator_engine.dart';
import '../model/candle.dart';
import '../script/script_controller.dart';
import '../script/script_painter.dart';
import 'chart_formatter.dart';
import 'chart_gestures.dart';
import 'chart_layout.dart';
import 'chart_mapper.dart';
import 'chart_overlays.dart';
import 'chart_painter.dart';
import 'chart_text.dart';
import 'chart_theme.dart';
import 'chart_types.dart';
import 'k_line_chart_state.dart';
import 'replay_controller.dart';

const Duration _exitDuration = Duration(milliseconds: 340);
const Duration _enterDuration = Duration(milliseconds: 620);
const Duration _subPaneDuration = Duration(milliseconds: 300);
const Duration _skeletonDuration = Duration(milliseconds: 1300);
const Curve _curve = Curves.fastOutSlowIn;

/// chartkit 的 K 线图。全部画在一个 `CustomPaint` 上，需要有界的宽高约束。
///
/// 数据通过 [state] 驱动（`setData` / `appendOrUpdate` / `prepend`）。
/// 列表类参数（[mainIndicators]、[subIndicators]、[tradeMarks]）按不可变值对待：
/// 要变更请传入新的 list，而不是原地修改。
class KLineChart extends StatefulWidget {
  const KLineChart({
    super.key,
    required this.state,
    this.theme = ChartTheme.dark,
    this.upDownColor = UpDownColor.greenUpRedDown,
    this.mode = ChartMode.candle,
    this.mainIndicators = const [],
    this.subIndicators = const [],
    this.formatter = const ChartFormatter(),
    this.entranceAnimation = true,
    bool? resetAnimation,
    this.showVolume = true,
    this.tradeMarks = const [],
    this.logo,
    this.logoPosition = LogoPosition.center,
    this.logoOpacity = 0.10,
    this.logoHeight = 32,
    this.showSkeleton = true,
    this.blankScrollRatio = 0,
    this.blankScrollWidth = 0,
    this.initialBlankScroll = false,
    this.showHighLow = false,
    this.lockCrosshairPrice = false,
    this.crosshairPanelMargin = EdgeInsets.zero,
    this.crosshairMode = CrosshairMode.free,
    this.crosshairDismiss = CrosshairDismiss.persistent,
    this.lastPriceMode = LastPriceMode.latest,
    this.labels = const ChartLabels(),
    this.crosshairDetail,
    this.overlayPainter,
    this.enableFling = true,
    this.crosshairTrigger = CrosshairTrigger.longPress,
    this.showCrosshairPriceLabel = true,
    this.crosshairExtraRows,
    this.showCountdown = false,
    this.orderbookProvider,
    this.repaint,
    this.isViewportLocked,
    this.onCrosshairPriceChange,
    this.onToggleFullscreen,
    this.onLoadMore,
    this.onCrosshairChange,
    this.onTradeMarkTap,
    this.drawingController,
    this.drawingTheme = const DrawingTheme(),
    this.drawingLabels = const DrawingLabels(),
    this.scriptOutputs,
    this.logScale = false,
    this.replay,
  })  : resetAnimation = resetAnimation ?? entranceAnimation,
        assert(blankScrollRatio >= 0),
        assert(blankScrollWidth >= 0),
        assert(logoOpacity >= 0 && logoOpacity <= 1);

  final KLineChartState state;
  final ChartTheme theme;
  final UpDownColor upDownColor;
  final ChartMode mode;

  /// 主图叠加指标（MA/EMA/BOLL…），多条线随主题循环取色。
  final List<Indicator> mainIndicators;

  /// 副图指标，每个独立成一个窗格（MACD/KDJ/RSI…）。增删带卷帘动画。
  final List<Indicator> subIndicators;
  final ChartFormatter formatter;

  /// 首屏数据到达时是否播放从左往右的入场动画。
  final bool entranceAnimation;

  /// 后续全量更新（如切周期）是否重播「收起 + 展开」动画；默认跟随 [entranceAnimation]。
  final bool resetAnimation;
  final bool showVolume;
  final List<TradeMark> tradeMarks;

  /// Logo 水印（任意组件，通常是一张图片），位于主图区域内。
  final Widget? logo;
  final LogoPosition logoPosition;
  final double logoOpacity;
  final double logoHeight;

  /// 无数据时是否显示骨架行情。
  final bool showSkeleton;

  /// 允许向左滑出的空白区域占图宽比例（0=禁用并贴右；~0.5 可把最新根拖离右边缘留白）。
  final double blankScrollRatio;

  /// 同上，但用绝对宽度（逻辑像素）指定；大于 0 时优先于 [blankScrollRatio]。
  final double blankScrollWidth;

  /// 首屏和每次全量更新（`setData`）后，是否让最新一根停在留白区左缘：
  /// 即一打开右侧就先空出 [blankScrollWidth]（或 [blankScrollRatio]）那么宽，而不是贴右。
  /// 适合右侧要放现价、下单标签等宿主组件的场景。未开启留白时无效。
  final bool initialBlankScroll;

  /// 在主图上标注可见区的最高价与最低价（仅蜡烛模式）。
  final bool showHighLow;

  /// 自由模式下把十字光标的水平线锁在价位上：行情刷新或缩放使价格区间变化时，
  /// 线跟着价位走，[onCrosshairPriceChange] 也不会因此变化。适合用十字光标选下单价。
  final bool lockCrosshairPrice;

  /// 详情浮窗的额外外边距，用来避开宿主叠在图上的组件（如右侧的价格标签）。
  final EdgeInsets crosshairPanelMargin;
  final CrosshairMode crosshairMode;
  final CrosshairDismiss crosshairDismiss;
  final LastPriceMode lastPriceMode;
  final ChartLabels labels;

  /// 自定义详情浮窗内容：给定聚焦 K 线返回任意「标签+数据」行；为空则用内置 OHLC 行。
  final List<CrosshairDetailRow> Function(Candle candle)? crosshairDetail;

  /// 在图表画布上追加自定义绘制（挂单线、持仓线等），与 K 线同帧、零滞后。
  final ChartOverlayPainter? overlayPainter;

  /// 松手后是否惯性滚动。
  final bool enableFling;

  /// 十字光标的触发方式：默认仅长按；也可设为单击或长按。
  final CrosshairTrigger crosshairTrigger;

  /// 是否绘制十字光标的右轴价签。宿主用自己的组件（如可下单的价格标签）代替时关掉。
  final bool showCrosshairPriceLabel;

  /// 追加到详情浮窗默认行（或 [crosshairDetail] 的结果）之后的行，如该根的成交均价。
  final List<CrosshairDetailRow> Function(Candle candle)? crosshairExtraRows;

  /// 在现价标签内加一行「当根 K 线剩余时间」，每秒刷新。
  final bool showCountdown;

  /// 盘口买一/卖一贴纸的数据来源，贴在现价标签左侧；返回 null 则不显示。
  /// 每次绘制时调用，**不要在里面访问 `BuildContext`**；盘口变化时用 [repaint] 触发重绘。
  final ChartOrderbook? Function()? orderbookProvider;

  /// 额外的重绘信号：变化时重绘画布（[overlayPainter]、[orderbookProvider] 会被重新调用）。
  /// 图层自身的状态（挂单、持仓、盘口）变化而行情没变时用它。
  final Listenable? repaint;

  /// 返回 true 时暂停图表的平移/缩放/惯性（如宿主图层上正在拖拽改价）。
  final bool Function()? isViewportLocked;

  /// 十字光标水平线所指的主图价格变化时回调；光标消失或不在主图区时为 null。
  /// 自由模式下是手指处的价格，吸附模式下是命中 K 线的收盘价。
  final ValueChanged<double?>? onCrosshairPriceChange;

  /// 非空时在主图左下角显示全屏按钮；全屏由宿主自行实现。
  final VoidCallback? onToggleFullscreen;

  /// 滚动接近最早数据时触发（同一数据版本只触发一次）。
  final VoidCallback? onLoadMore;

  /// 十字光标命中的 K 线变化时回调；消失或落在右侧留白时为 null。
  final ValueChanged<Candle?>? onCrosshairChange;
  final ValueChanged<TradeMark>? onTradeMarkTap;

  /// 画线。为空时不开启画线，图表的界面和手势与原来完全一样。
  /// 画线画在主图里，在 K 线之上、[overlayPainter] 和十字光标之下。手势分工见 `DrawingGestures`。
  final DrawingController? drawingController;

  /// 画线的公共配色（盈亏区、端点填充、色块文字）；为空的项取 [theme]。
  final DrawingTheme drawingTheme;

  /// 画线上的文字（头寸的入场/目标/止损、盈亏比、测量的根数单位）。
  final DrawingLabels drawingLabels;

  /// 服务端脚本引擎输出的图元。为空时不画，图表和原来完全一样。
  /// 主图脚本叠在 K 线上，副图脚本各占一个窗格（排在 [subIndicators] 之后）。见 `PRIMITIVES.md`。
  final ScriptOutputController? scriptOutputs;

  /// 主图价格轴按对数刻度。价格换算、刻度、现价标签、十字光标读数、自动价格区间、
  /// 画线和脚本图元都跟着换算；成交量和副图不受影响。非正数在对数刻度下画不出来，不计入价格区间。
  final bool logScale;

  /// K 线回放。为空时没有回放。`replay.source` 必须就是 [state]。
  /// 选起点时点图上任意位置即选中那一根；回放中图上只有起点到游标的 K 线，主图和副图指标按这些 K 线重算，
  /// 脚本图元只画到游标为止（表格、水平线这类不带时间的照常画）。宿主推到 [state] 的实时行情不影响回放。
  final ChartReplayController? replay;

  @override
  State<KLineChart> createState() => _KLineChartView();
}

/// 一个副图窗格及其进出场动画（0→1 长出，1→0 收缩后移除）。
class _SubPane {
  const _SubPane(this.indicator, this.controller);

  final Indicator indicator;
  final AnimationController controller;

  double get weight => _curve.transform(controller.value);
}

class _Ticker extends ChangeNotifier {
  void tick() => notifyListeners();
}

class _KLineChartView extends State<KLineChart>
    with TickerProviderStateMixin
    implements ChartFrameSource {
  late final AnimationController _entrance =
      AnimationController(vsync: this, value: widget.entranceAnimation ? 0 : 1);
  late final AnimationController _skeleton =
      AnimationController(vsync: this, duration: _skeletonDuration);
  late final ChartGestures _gestures =
      ChartGestures(vsync: this, widgetOf: () => widget, layoutOf: () => _layout);
  late final DrawingGestures _drawingGestures = DrawingGestures(
    controllerOf: () => widget.drawingController,
    projectionOf: _drawingProjection,
    clearCrosshair: _gestures.clearCrosshair,
  );

  /// 触发画布重绘（数据、视口、任一动画变化）。
  final _Ticker _repaint = _Ticker();

  /// 副图动画推进：依赖主图底边位置的浮层（水印、全屏按钮）需重建。
  final _Ticker _paneTick = _Ticker();

  List<_SubPane> _subs = const [];
  List<(String, AnimationController)> _scriptPanes = const [];
  final ScriptLayerCache _scriptCache = ScriptLayerCache();
  ScriptTextCache? _scriptText;
  List<IndicatorSeries> _mainSeries = const [];
  List<IndicatorSeries> _subSeries = const [];
  List<Candle> _mainInput = const [];
  List<Candle> _subInput = const [];
  ChartText? _text;
  ChartText? _markText;
  ChartText? _drawingText;
  ChartLayout? _layout;
  double _unit = 1;
  int _dataVersion = -1;
  int _resetVersion = -1;
  int _loadMoreVersion = -1;
  bool _firstReveal = true;
  int _reportedCrosshair = -1;
  double? _reportedPrice;
  Timer? _countdownTimer;
  bool _afterFrameScheduled = false;

  /// 全量更新后待应用初始留白（需要布局宽度，或当前处于构建阶段不能通知）。
  bool _pendingInitialBlank = false;

  /// 图表实际画的状态：回放中是回放的截断数据，否则是 `widget.state`。
  KLineChartState get _state => shownState(widget);

  /// 当前监听着的状态（[_state] 变了要换监听）。
  KLineChartState? _bound;

  // ───────────────────────── ChartFrameSource ─────────────────────────

  @override
  List<IndicatorSeries> get mainSeries => _mainSeries;
  @override
  List<IndicatorSeries> get subSeries => _subSeries;
  @override
  List<String> get subPaneIds => [for (final s in _subs) s.indicator.id];
  @override
  List<double> get subPaneWeights => [for (final s in _subs) s.weight];
  @override
  List<String> get scriptPaneIds => [for (final p in _scriptPanes) p.$1];
  @override
  List<double> get scriptPaneWeights =>
      [for (final p in _scriptPanes) _curve.transform(p.$2.value)];
  @override
  double get entrance => _entrance.value;
  @override
  double get skeletonPhase => -0.2 + 1.4 * _skeleton.value;

  @override
  void onFrameLayout(ChartLayout? layout) {
    _layout = layout;
    _scheduleAfterFrame();
  }

  void _scheduleAfterFrame() {
    if (_afterFrameScheduled) return;
    _afterFrameScheduled = true;
    // 绘制期间不能触发通知/回调，推迟到帧末
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _afterFrameScheduled = false;
      if (mounted) _afterFrame();
    });
  }

  void _afterFrame() {
    final layout = _layout;
    final candles = _state.candles;
    final valid = layout != null && candles.isNotEmpty;
    final mapper = valid ? KLineChartMapper(layout, candles) : null;
    _state.updateMapper(mapper);
    // 回放中宿主的状态也拿到这一帧的映射，宿主图层照常定位
    if (!identical(_state, widget.state)) widget.state.updateMapper(mapper);
    _updateSelectionBounds();
    final scripts = widget.scriptOutputs;
    if (scripts != null) {
      _scriptCache.retain(scripts.scriptIds.toSet());
      scripts.deliverIssues();
    }
    if (!valid) return;
    if (_pendingInitialBlank) {
      _pendingInitialBlank = false;
      _state.setViewport(scrollOffset: layout.minOffset);
    }
    // 分页：接近最早数据时触发，同一数据版本只触发一次
    final nearStart =
        layout.firstIndex <= 3 && layout.offset >= layout.maxOffset - layout.candleWidth * 3;
    if (nearStart && _loadMoreVersion != _state.dataVersion) {
      _loadMoreVersion = _state.dataVersion;
      widget.onLoadMore?.call();
    }
  }

  // ───────────────────────── 生命周期 ─────────────────────────

  @override
  void initState() {
    super.initState();
    _entrance.addListener(_repaint.tick);
    widget.repaint?.addListener(_repaint.tick);
    widget.drawingController?.addListener(_repaint.tick);
    widget.scriptOutputs?.addListener(_onScriptsChanged);
    _syncCountdownTimer();
    _skeleton.addListener(_repaint.tick);
    assert(widget.replay == null || identical(widget.replay!.source, widget.state),
        'replay.source must be the chart state');
    widget.replay?.addListener(_onReplayChanged);
    _bindState();
    _syncSubPanes();
    _syncScriptPanes();
    _onStateChanged();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _unit = 1 / (MediaQuery.maybeDevicePixelRatioOf(context) ?? 1);
    _rebuildText();
  }

  @override
  void didUpdateWidget(KLineChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    assert(widget.replay == null || identical(widget.replay!.source, widget.state),
        'replay.source must be the chart state');
    if (!identical(oldWidget.replay, widget.replay)) {
      oldWidget.replay?.removeListener(_onReplayChanged);
      widget.replay?.addListener(_onReplayChanged);
    }
    _bindState();
    if (!identical(oldWidget.repaint, widget.repaint)) {
      oldWidget.repaint?.removeListener(_repaint.tick);
      widget.repaint?.addListener(_repaint.tick);
    }
    if (!identical(oldWidget.drawingController, widget.drawingController)) {
      oldWidget.drawingController?.removeListener(_repaint.tick);
      widget.drawingController?.addListener(_repaint.tick);
    }
    if (!identical(oldWidget.scriptOutputs, widget.scriptOutputs)) {
      oldWidget.scriptOutputs?.removeListener(_onScriptsChanged);
      widget.scriptOutputs?.addListener(_onScriptsChanged);
      _scriptCache.retain(const {});
      _syncScriptPanes();
    }
    _syncCountdownTimer();
    // 指标实例变了（如改了周期参数）：丢弃增量缓存，全量重算
    final mainChanged = !listEquals(oldWidget.mainIndicators, widget.mainIndicators);
    final subChanged = !listEquals(oldWidget.subIndicators, widget.subIndicators);
    if (mainChanged) _mainInput = const [];
    if (subChanged) _syncSubPanes();
    if (mainChanged || subChanged) _dataVersion = -1;
    if (oldWidget.theme.dims.axisTextSize != widget.theme.dims.axisTextSize ||
        oldWidget.theme.fontFamily != widget.theme.fontFamily) {
      _rebuildText();
    }
    _onStateChanged();
  }

  @override
  void dispose() {
    _bound?.removeListener(_onStateChanged);
    widget.replay?.removeListener(_onReplayChanged);
    widget.repaint?.removeListener(_repaint.tick);
    widget.drawingController?.removeListener(_repaint.tick);
    widget.scriptOutputs?.removeListener(_onScriptsChanged);
    for (final p in _scriptPanes) {
      p.$2.dispose();
    }
    _scriptCache.dispose();
    _scriptText?.dispose();
    _countdownTimer?.cancel();
    _gestures.dispose();
    _entrance.dispose();
    _skeleton.dispose();
    for (final sub in _subs) {
      sub.controller.dispose();
    }
    _text?.dispose();
    _markText?.dispose();
    _drawingText?.dispose();
    _repaint.dispose();
    _paneTick.dispose();
    super.dispose();
  }

  /// 让监听跟上 [_state]：宿主换了状态对象，或进出回放（[replay]）。返回是否换了。
  bool _bindState({bool replay = false}) {
    final s = _state;
    final old = _bound;
    if (identical(s, old)) return false;
    old?.removeListener(_onStateChanged);
    s.addListener(_onStateChanged);
    _bound = s;
    if (old == null) return true;
    // 换了状态对象：版本号不可比，丢弃一切按旧状态缓存的东西
    _resetVersion = -1;
    _dataVersion = -1;
    _loadMoreVersion = -1;
    _mainInput = const [];
    _subInput = const [];
    _reportedCrosshair = s.crosshairIndex;
    _reportedPrice = null;
    if (replay) {
      // 进出回放不播入场动画；刚进回放时按需留出右侧空白
      _resetVersion = s.resetVersion;
      if (!identical(s, widget.state)) _applyInitialBlank();
    }
    return true;
  }

  /// 回放进出、换起点时换成要画的那份状态；回放中的每一根由那份状态自己通知重绘。
  void _onReplayChanged() {
    if (!mounted || !_bindState(replay: true)) return;
    _onStateChanged();
    setState(() {});
  }

  void _rebuildText() {
    final scaler = MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;
    final family = widget.theme.fontFamily;
    _text?.dispose();
    _markText?.dispose();
    _drawingText?.dispose();
    _drawingText = null;
    _scriptText?.dispose();
    _scriptText = null;
    _scriptCache.retain(const {});
    _text = ChartText(
      fontSize: widget.theme.dims.axisTextSize,
      textScaler: scaler,
      fontFamily: family,
    );
    _markText = ChartText(fontSize: 10, textScaler: scaler, fontFamily: family, cacheSize: 4);
  }

  // ───────────────────────── 数据与动画 ─────────────────────────

  void _onStateChanged() {
    _attachScriptCandles();
    if (_dataVersion != _state.dataVersion) {
      _dataVersion = _state.dataVersion;
      _recomputeSeries();
    }
    if (_resetVersion != _state.resetVersion) {
      _resetVersion = _state.resetVersion;
      _gestures.stopFling();
      _applyInitialBlank();
      _playEntrance();
    }
    _syncSkeleton();
    _reportCrosshair();
    _reportCrosshairPrice();
    _repaint.tick();
  }

  /// 全量更新后把视口移到留白区左缘（见 [KLineChart.initialBlankScroll]）。
  /// 构建阶段（initState / didUpdateWidget）不能通知监听者，且留白按比例给时要知道蜡烛区宽度：
  /// 这两种情况推迟到帧末，用本帧布局算出的 `minOffset`。
  void _applyInitialBlank() {
    _pendingInitialBlank = false;
    final w = widget;
    if (!w.initialBlankScroll || _state.candles.isEmpty) return;
    if (w.blankScrollWidth <= 0 && w.blankScrollRatio <= 0) return;
    final layout = _layout;
    final phase = SchedulerBinding.instance.schedulerPhase;
    final building = phase != SchedulerPhase.idle && phase != SchedulerPhase.postFrameCallbacks;
    if (layout == null || building) {
      _pendingInitialBlank = true;
      _scheduleAfterFrame();
      return;
    }
    final maxBlank = layout.chartWidth * 0.9;
    final blank = w.blankScrollWidth > 0
        ? math.min(w.blankScrollWidth, maxBlank)
        : layout.chartWidth * math.min(w.blankScrollRatio, 0.9);
    _state.setViewport(scrollOffset: -blank);
  }

  /// 倒计时每秒变一次，而行情不一定每秒都有 tick：开启时用定时器驱动重绘。
  void _syncCountdownTimer() {
    if (widget.showCountdown == (_countdownTimer != null)) return;
    _countdownTimer?.cancel();
    _countdownTimer = widget.showCountdown
        ? Timer.periodic(const Duration(seconds: 1), (_) => _repaint.tick())
        : null;
  }

  /// 十字光标水平线所指价格变化时通知宿主（几何取自最近一帧）。
  void _reportCrosshairPrice() {
    final onChange = widget.onCrosshairPriceChange;
    if (onChange == null) return;
    final price = _crosshairPrice();
    if (price == _reportedPrice) return;
    _reportedPrice = price;
    onChange(price);
  }

  double? _crosshairPrice() {
    final layout = _layout;
    final index = _state.crosshairIndex;
    if (layout == null || index < 0) return null;
    final candles = _state.candles;
    final candle = index < candles.length ? candles[index] : null;
    final locked = _state.crosshairPrice;
    if (locked != null) return locked;
    final y = _state.crosshairY;
    final followsFinger = (candle == null || widget.crosshairMode == CrosshairMode.free) && y >= 0;
    if (!followsFinger) return candle?.close;
    return y <= layout.mainBottom ? layout.yToPrice(y < layout.mainTop ? layout.mainTop : y) : null;
  }

  /// 十字光标命中索引变化时通知宿主。以状态为唯一来源：手势移动、点击关闭、
  /// 以及 `setData` / `changeTimeFrame` 自行清除光标，都会走到这里。
  void _reportCrosshair() {
    final index = _state.crosshairIndex;
    if (index == _reportedCrosshair) return;
    _reportedCrosshair = index;
    final candles = _state.candles;
    widget.onCrosshairChange?.call(index >= 0 && index < candles.length ? candles[index] : null);
  }

  /// 指标计算：末根更新/追加只增量重算末值，其余全量。
  void _recomputeSeries() {
    final data = _state.candles;
    _mainSeries = _compute(widget.mainIndicators, data, _mainInput, _mainSeries);
    _mainInput = data;
    _subSeries = _compute([for (final s in _subs) s.indicator], data, _subInput, _subSeries);
    _subInput = data;
  }

  /// 自定义指标抛错时不拖垮整张图：上报错误，该组指标本次不显示。
  List<IndicatorSeries> _compute(
    List<Indicator> indicators,
    List<Candle> data,
    List<Candle> prevData,
    List<IndicatorSeries> prevSeries,
  ) {
    try {
      return incrementalCompute(indicators, data, prevData, prevSeries);
    } catch (error, stack) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'chartkit_flutter',
        context: ErrorDescription('while computing chart indicators'),
      ));
      return const [];
    }
  }

  /// 入场/换周期动画：首屏从左往右展开；之后的全量更新先往左收再展开。
  Future<void> _playEntrance() async {
    if (_state.candles.isEmpty) return; // 无数据时不消耗「首屏」机会，等数据到来再播
    final isFirst = _firstReveal;
    _firstReveal = false;
    if (!(isFirst ? widget.entranceAnimation : widget.resetAnimation)) {
      _entrance.value = 1;
      return;
    }
    try {
      if (_entrance.value >= 1) {
        await _entrance.animateTo(0, duration: _exitDuration, curve: _curve).orCancel;
      } else {
        _entrance.value = 0;
      }
      await _entrance.animateTo(1, duration: _enterDuration, curve: _curve).orCancel;
    } on TickerCanceled {
      // 被新的一轮动画或 dispose 打断：正常情况，无需处理
    }
  }

  /// 骨架屏扫光只在「无数据且开启骨架」时运行，有数据后不再触发重绘。
  void _syncSkeleton() {
    final shouldRun = _state.candles.isEmpty && widget.showSkeleton;
    if (shouldRun && !_skeleton.isAnimating) _skeleton.repeat();
    if (!shouldRun && _skeleton.isAnimating) _skeleton.stop();
  }

  /// 让显示中的副图跟上 `widget.subIndicators`：新增的长出，移除的收缩完再删。
  void _syncSubPanes() {
    final wanted = widget.subIndicators;
    final kept = [
      for (final sub in _subs)
        _SubPane(
          wanted.where((e) => e.id == sub.indicator.id).firstOrNull ?? sub.indicator,
          sub.controller,
        ),
    ];
    final added = [
      for (final ind in wanted)
        if (_subs.every((s) => s.indicator.id != ind.id)) _SubPane(ind, _newSubController()),
    ];
    _subs = [...kept, ...added];
    _subInput = const [];
    for (final sub in _subs) {
      if (wanted.any((e) => e.id == sub.indicator.id)) {
        sub.controller.forward();
      } else {
        sub.controller.reverse().then((_) => _removeSubPane(sub.controller));
      }
    }
  }

  AnimationController _newSubController() =>
      AnimationController(vsync: this, duration: _subPaneDuration)..addListener(_onSubPaneTick);

  void _onSubPaneTick() {
    _repaint.tick();
    _paneTick.tick();
  }

  void _removeSubPane(AnimationController controller) {
    if (!mounted || !controller.isDismissed) return;
    _subs = [
      for (final s in _subs)
        if (!identical(s.controller, controller)) s,
    ];
    controller.dispose();
    _onSubPaneTick();
  }

  // ───────────────────────── 脚本图元 ─────────────────────────

  void _onScriptsChanged() {
    _syncScriptPanes();
    _attachScriptCandles();
    _repaint.tick();
    _scheduleAfterFrame();
  }

  /// 脚本图元总是对齐到宿主的完整数据；回放时按游标裁剪（见 [_scriptConfig]）。
  /// 回放的数据是完整数据的前一段，两边同一根 K 线的下标相同。
  void _attachScriptCandles() => widget.scriptOutputs
      ?.attachCandles(widget.state.candles, intervalMs: widget.state.timeFrame.millis);

  /// 副图脚本的窗格跟着输出走：新设置的长出，移除的收缩完再删。替换同一个 id 时窗格不动。
  void _syncScriptPanes() {
    final c = widget.scriptOutputs;
    final wanted = c == null || !c.visible ? const <String>[] : c.subPaneIds;
    final kept = [
      for (final p in _scriptPanes)
        if (wanted.contains(p.$1) || !p.$2.isDismissed) p,
    ];
    final added = [
      for (final id in wanted)
        if (kept.every((p) => p.$1 != id)) (id, _newSubController()),
    ];
    for (final p in _scriptPanes) {
      if (!kept.contains(p)) p.$2.dispose();
    }
    _scriptPanes = [...kept, ...added];
    for (final p in _scriptPanes) {
      if (wanted.contains(p.$1)) {
        p.$2.forward();
      } else {
        p.$2.reverse().then((_) => _removeScriptPane(p.$2));
      }
    }
  }

  void _removeScriptPane(AnimationController controller) {
    if (!mounted || !controller.isDismissed) return;
    final before = _scriptPanes.length;
    _scriptPanes = [
      for (final p in _scriptPanes)
        if (!identical(p.$2, controller)) p,
    ];
    if (_scriptPanes.length == before) return;
    controller.dispose();
    _onSubPaneTick();
  }

  ScriptPaintConfig? _scriptConfig() {
    final controller = widget.scriptOutputs;
    if (controller == null) return null;
    final theme = widget.theme;
    final scaler = MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;
    final text = _scriptText ??= ScriptTextCache(fontFamily: theme.fontFamily, textScaler: scaler);
    return ScriptPaintConfig(
      controller: controller,
      cache: _scriptCache,
      text: text,
      colors: ScriptColors(
        buy: theme.upColor(widget.upDownColor),
        sell: theme.downColor(widget.upDownColor),
        axisText: theme.axisText,
        grid: theme.grid,
        labelText: theme.lastPriceText,
      ),
      fontSize: theme.dims.axisTextSize,
      themeKey: (theme, widget.upDownColor, scaler),
      cutAtLast: !identical(_state, widget.state),
    );
  }

  // ───────────────────────── 构建 ─────────────────────────

  @override
  Widget build(BuildContext context) {
    final painter = KLineChartPainter(
      state: _state,
      source: this,
      repaint: _repaint,
      config: ChartPaintConfig(
        theme: widget.theme,
        upDownColor: widget.upDownColor,
        mode: widget.mode,
        formatter: widget.formatter,
        showVolume: widget.showVolume,
        tradeMarks: widget.tradeMarks,
        showSkeleton: widget.showSkeleton,
        blankScrollRatio: widget.blankScrollRatio,
        blankScrollWidth: widget.blankScrollWidth,
        showHighLow: widget.showHighLow,
        crosshairMode: widget.crosshairMode,
        lastPriceMode: widget.lastPriceMode,
        skeletonSubCount: widget.subIndicators.length,
        overlayPainter: widget.overlayPainter,
        orderbookProvider: widget.orderbookProvider,
        showCountdown: widget.showCountdown,
        showCrosshairPriceLabel: widget.showCrosshairPriceLabel,
        unit: _unit,
        text: _text!,
        markText: _markText!,
        drawing: _drawingConfig(),
        scripts: _scriptConfig(),
        logScale: widget.logScale,
      ),
    );
    // 撑满可用空间：父级约束宽松（如放在 Column 里）时也不会塌缩
    return SizedBox.expand(
      child: LayoutBuilder(
        builder: (context, constraints) => ListenableBuilder(
          listenable: _paneTick,
          builder: (context, _) => _buildLayers(painter, constraints.biggest),
        ),
      ),
    );
  }

  Widget _buildLayers(KLineChartPainter painter, Size size) => Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: _buildCanvas(painter)),
          ChartLegend(chart: widget, seriesOf: () => _mainSeries),
          ChartCrosshairPanel(chart: widget, chartWidth: size.width),
          ...buildMainPaneOverlays(chart: widget, mainBottom: _mainBottom(size.height)),
        ],
      );

  Widget _buildCanvas(KLineChartPainter painter) {
    // 切周期/首屏：整图随入场值淡入淡出。无数据时强制不透明，否则骨架屏会被一起淡没
    final child = ListenableBuilder(
      listenable: Listenable.merge([_entrance, _state]),
      builder: (context, child) => Opacity(
        opacity: _state.candles.isEmpty ? 1 : _entrance.value.clamp(0.0, 1.0),
        child: child,
      ),
      child: RepaintBoundary(child: CustomPaint(painter: painter, size: Size.infinite)),
    );
    if (widget.drawingController == null) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: _gestures.onDragStart,
        onHorizontalDragUpdate: _gestures.onDragUpdate,
        onHorizontalDragEnd: _gestures.onDragEnd,
        onScaleStart: _gestures.onScaleStart,
        onScaleUpdate: _gestures.onScaleUpdate,
        onLongPressStart: _gestures.onLongPressStart,
        onLongPressMoveUpdate: _gestures.onLongPressMove,
        onLongPressEnd: (_) => _gestures.onLongPressEnd(),
        onLongPressCancel: _gestures.onLongPressEnd,
        onTapUp: _gestures.onTapUp,
        child: child,
      );
    }
    // 开启画线：点击、长按先问画线要不要；拖动选中画线由外层识别器在按下时直接接手
    final d = _drawingGestures;
    return RawGestureDetector(
      gestures: {
        DrawingDragRecognizer: GestureRecognizerFactoryWithHandlers<DrawingDragRecognizer>(
          () => DrawingDragRecognizer(debugOwner: this),
          (r) => r
            ..canStart = d.canDrag
            ..onUpdate = d.onDragUpdate
            ..onEnd = d.onDragEnd,
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: _gestures.onDragStart,
        onHorizontalDragUpdate: _gestures.onDragUpdate,
        onHorizontalDragEnd: _gestures.onDragEnd,
        onScaleStart: _gestures.onScaleStart,
        onScaleUpdate: _gestures.onScaleUpdate,
        onLongPressStart: (e) {
          if (!d.onLongPressStart(e.localPosition)) _gestures.onLongPressStart(e);
        },
        onLongPressMoveUpdate: (e) {
          if (!d.onLongPressMove(e.localPosition)) _gestures.onLongPressMove(e);
        },
        onLongPressEnd: (_) {
          if (!d.onLongPressEnd()) _gestures.onLongPressEnd();
        },
        onLongPressCancel: () {
          if (!d.onLongPressCancel()) _gestures.onLongPressEnd();
        },
        onTapUp: (e) {
          if (_gestures.pickReplayStart(e.localPosition)) return;
          if (!d.onTapUp(e.localPosition)) _gestures.onTapUp(e);
        },
        child: child,
      ),
    );
  }

  // ───────────────────────── 画线 ─────────────────────────

  DrawingPaintConfig? _drawingConfig() {
    final controller = widget.drawingController;
    if (controller == null) return null;
    final theme = widget.theme;
    final dt = widget.drawingTheme;
    final text = _drawingText ??= ChartText(
      fontSize: theme.dims.axisTextSize,
      textScaler: MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling,
      fontFamily: theme.fontFamily,
      cacheSize: 64,
    );
    return DrawingPaintConfig(
      controller: controller,
      colors: DrawingColors(
        profit: dt.profit ?? theme.upColor(widget.upDownColor),
        loss: dt.loss ?? theme.downColor(widget.upDownColor),
        handleFill: dt.handleFill ?? theme.background,
        labelText: dt.labelText ?? theme.lastPriceText,
      ),
      labels: widget.drawingLabels,
      text: text,
    );
  }

  /// 按最近一帧的布局做画线坐标换算；布局和数据对不上（刚换了数据、还没重绘）时为 null。
  DrawingProjection? _drawingProjection() {
    final layout = _layout;
    final candles = _state.candles;
    if (layout == null || candles.isEmpty || layout.itemCount != candles.length) return null;
    return DrawingProjection.of(layout, DrawingTimeline(candles, _state.timeFrame.millis));
  }

  void _updateSelectionBounds() {
    final controller = widget.drawingController;
    if (controller == null) return;
    final selected = controller.visible ? controller.selected : null;
    final p = selected == null ? null : _drawingProjection();
    if (selected == null || p == null) return controller.updateSelectionBounds(null);
    final bounds = shapeOf(selected, p).bounds;
    final visible = bounds.inflate(drawingHandleRadius).intersect(p.rect);
    controller.updateSelectionBounds(visible.isEmpty ? null : visible);
  }

  /// 主图底边 y：与渲染层同一套公式（含副图动画权重），浮层随主图平滑移动。
  double _mainBottom(double totalHeight) => PaneSplit.compute(
        chartHeight: totalHeight - widget.theme.dims.bottomAxisHeight,
        dims: widget.theme.dims,
        showVolume: widget.showVolume,
        subWeights: widget.scriptOutputs == null
            ? subPaneWeights
            : [...subPaneWeights, ...scriptPaneWeights],
      ).mainBottom;
}
