import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import '../script/script_hit.dart';
import 'chart_layout.dart';
import 'chart_painter.dart';
import 'chart_renderer.dart';
import 'chart_types.dart';
import 'k_line_chart.dart';
import 'k_line_chart_state.dart';
import 'replay_controller.dart';

/// 低于此速度（逻辑像素/秒）的松手不触发惯性滚动。
const double _minFlingVelocity = 50;

/// 惯性滚动的阻力系数（越小停得越快）。
const double _flingDrag = 0.05;

/// 图表手势：单指横向拖动（带惯性）、双指缩放、长按十字光标、点击。
///
/// 纵向拖动不被图表认领，父级（页面）可正常上下滚动。
/// 常驻十字光标显示期间，拖动/缩放只用于关闭光标，本次手势不滚动。
class ChartGestures {
  ChartGestures({
    required TickerProvider vsync,
    required KLineChart Function() widgetOf,
    required ChartLayout? Function() layoutOf,
    ScriptHit? Function(Offset position)? scriptHitAt,
  })  : _widgetOf = widgetOf,
        _layoutOf = layoutOf,
        _scriptHitAt = scriptHitAt,
        _fling = AnimationController.unbounded(vsync: vsync) {
    _fling.addListener(_onFlingTick);
  }

  final KLineChart Function() _widgetOf;
  final ChartLayout? Function() _layoutOf;
  final ScriptHit? Function(Offset position)? _scriptHitAt;
  final AnimationController _fling;

  /// 本次拖动/缩放是否仅用于关闭十字光标（不滚动）。
  bool _dismissOnly = false;
  double _scaleStartWidth = 0;

  KLineChart get _widget => _widgetOf();
  KLineChartState get _state => shownState(_widget);

  /// 宿主是否暂时锁住了视口（如正在拖拽图层上的改价标签）。
  bool get _locked => _widget.isViewportLocked?.call() ?? false;

  void dispose() => _fling.dispose();

  void stopFling() => _fling.stop();

  // ───────────────────────── 拖动 ─────────────────────────

  void onDragStart(DragStartDetails details) => _beginViewportGesture();

  void onDragUpdate(DragUpdateDetails details) {
    final layout = _layoutOf();
    if (_dismissOnly || _locked || layout == null) return;
    _scrollTo(_state.scrollOffset + details.delta.dx, layout);
  }

  void onDragEnd(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond.dx;
    if (_dismissOnly || _locked || !_widget.enableFling) return;
    if (velocity.abs() < _minFlingVelocity) return;
    _fling.animateWith(FrictionSimulation(_flingDrag, _state.scrollOffset, velocity));
  }

  void _onFlingTick() {
    final layout = _layoutOf();
    if (layout == null) return stopFling();
    final target = _fling.value;
    _scrollTo(target, layout);
    if (target < layout.minOffset || target > layout.maxOffset) stopFling(); // 撞到边界
  }

  void _scrollTo(double offset, ChartLayout layout) => _state.setViewport(
        scrollOffset: offset.clamp(layout.minOffset, layout.maxOffset).toDouble(),
      );

  /// 拖动/缩放开始：停掉惯性；若十字光标正显示则关闭它，且本次手势不滚动。
  void _beginViewportGesture() {
    stopFling();
    _dismissOnly = _state.crosshairIndex >= 0;
    if (_dismissOnly) clearCrosshair();
  }

  // ───────────────────────── 缩放 ─────────────────────────

  void onScaleStart(ScaleStartDetails details) {
    _beginViewportGesture();
    _scaleStartWidth = effectiveCandleWidth(_state, _widget.theme.dims);
  }

  void onScaleUpdate(ScaleUpdateDetails details) {
    final layout = _layoutOf();
    if (_dismissOnly || _locked || layout == null || details.pointerCount < 2) return;
    final dims = _widget.theme.dims;
    // 取状态里的当前宽度而非上一帧的：一帧内可能连续收到多个缩放事件
    final old = effectiveCandleWidth(_state, dims);
    final width = (_scaleStartWidth * details.scale)
        .clamp(dims.candleMinWidth, dims.candleMaxWidth)
        .toDouble();
    // 围绕捏合焦点缩放：保持焦点下那根的屏幕位置不动
    final k = layout.chartWidth - details.localFocalPoint.dx;
    final zoomed = (_state.scrollOffset + k) * (width / old) - k;
    final maxOffset = math.max(0.0, layout.itemCount * width - layout.chartWidth);
    _state.setViewport(
      candleWidth: width,
      scrollOffset:
          (zoomed + details.focalPointDelta.dx).clamp(layout.minOffset, maxOffset).toDouble(),
    );
  }

  // ───────────────────────── 十字光标 ─────────────────────────

  void onLongPressStart(LongPressStartDetails details) {
    stopFling();
    _moveCrosshair(details.localPosition);
  }

  void onLongPressMove(LongPressMoveUpdateDetails details) => _moveCrosshair(details.localPosition);

  /// 松手：onRelease 立即消失；persistent 保留（由点击/拖动再消失）。
  void onLongPressEnd() {
    if (_widget.crosshairDismiss == CrosshairDismiss.onRelease) clearCrosshair();
  }

  void _moveCrosshair(Offset position) {
    final layout = _layoutOf();
    if (layout == null) return;
    // 锁价：手指落在主图内时，记下它所指的价位
    final inMain = position.dy >= layout.mainTop && position.dy <= layout.mainBottom;
    final lock =
        _widget.lockCrosshairPrice && _widget.crosshairMode == CrosshairMode.free && inMain;
    _state.setCrosshair(
      layout.indexAtX(position.dx),
      position.dx,
      position.dy,
      price: lock ? layout.yToPrice(position.dy) : null,
    );
  }

  void clearCrosshair() => _state.clearCrosshair();

  // ───────────────────────── 点击 ─────────────────────────

  void onTapUp(TapUpDetails details) {
    if (pickReplayStart(details.localPosition)) return;
    if (_state.crosshairIndex >= 0) return clearCrosshair(); // 常驻浮窗：点击空白处消失
    // 点到脚本图元：交给宿主，不再看买卖标记、不唤出十字光标
    final onScriptTap = _widget.onScriptTap;
    final hit = onScriptTap == null ? null : _scriptHitAt?.call(details.localPosition);
    if (hit != null) return onScriptTap!(hit);
    // 松手即消失模式：点击蜡烛上的买卖标记 → 回调
    final mark = _widget.crosshairDismiss == CrosshairDismiss.onRelease
        ? _tradeMarkAt(details.localPosition.dx)
        : null;
    if (mark != null) return _widget.onTradeMarkTap?.call(mark);
    if (_widget.crosshairTrigger == CrosshairTrigger.tapOrLongPress) {
      _moveCrosshair(details.localPosition);
    }
  }

  /// 回放选起点时，点击处的那根作为起点。返回是否处理了这次点击。
  bool pickReplayStart(Offset position) {
    final replay = _widget.replay;
    final layout = _layoutOf();
    if (replay == null || replay.phase != ReplayPhase.picking || layout == null) return false;
    clearCrosshair();
    replay.select(layout.indexAtX(position.dx));
    return true;
  }

  /// 离 [x] 最近、且在一根蜡烛宽度内的可见买卖标记。
  TradeMark? _tradeMarkAt(double x) {
    final layout = _layoutOf();
    if (layout == null) return null;
    TradeMark? best;
    var bestDx = layout.candleWidth;
    for (final mark in _widget.tradeMarks) {
      final index = indexForTime(_state.candles, mark.time);
      if (index < layout.firstIndex || index > layout.lastIndex) continue;
      final dx = (x - layout.centerX(index)).abs();
      if (dx < bestDx) {
        bestDx = dx;
        best = mark;
      }
    }
    return best;
  }
}
