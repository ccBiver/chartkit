import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';

import 'drawing.dart';
import 'drawing_controller.dart';
import 'drawing_geometry.dart';

/// 画线手势。和图表原有手势的分工：
///
/// - 新建（选了工具）：单击落点；长按后拖动可以先看预览、松手落点（长按不再唤出十字光标）。
///   单指横拖、双指缩放照常移动图表，方便边看边点。
/// - 没选工具：单击点中画线就选中，点空白取消选中；都没有时交给图表（十字光标等原有行为）。
/// - 拖动只对已选中、未锁定的画线生效：按下点在它的端点或线身上时由 [DrawingDragRecognizer]
///   立即接手，图表不滚动；按在别处照常滚动、缩放。
class DrawingGestures {
  DrawingGestures({
    required DrawingController? Function() controllerOf,
    required DrawingProjection? Function() projectionOf,
    required VoidCallback clearCrosshair,
  })  : _controllerOf = controllerOf,
        _projectionOf = projectionOf,
        _clearCrosshair = clearCrosshair;

  final DrawingController? Function() _controllerOf;
  final DrawingProjection? Function() _projectionOf;
  final VoidCallback _clearCrosshair;

  bool _placing = false;
  Drawing? _dragOrigin;
  DrawingHit? _dragHit;
  Offset _dragStart = Offset.zero;
  bool _dragMoved = false;

  // ───────────────────────── 点击 ─────────────────────────

  /// 返回 true 表示画线用掉了这次点击，图表不再处理。
  bool onTapUp(Offset pos) {
    final c = _controllerOf();
    final p = _projectionOf();
    if (c == null || p == null) return false;
    if (c.tool != null) {
      if (p.rect.contains(pos)) {
        _clearCrosshair();
        c.addDraftPoint(_snap(c, p, pos));
      }
      return true;
    }
    if (!c.visible) return false;
    final hit = hitTopmost(c, p, pos);
    if (hit != null) {
      _clearCrosshair();
      c.select(hit.id);
      return true;
    }
    if (c.selectedId != null) {
      c.select(null);
      return true;
    }
    return false;
  }

  /// [pos] 下最上面的画线；选中的那条优先。
  Drawing? hitTopmost(DrawingController c, DrawingProjection p, Offset pos) {
    if (!p.rect.inflate(drawingHitSlop).contains(pos)) return null;
    final selected = c.selected;
    if (selected != null && hitTestShape(shapeOf(selected, p), pos) != null) return selected;
    for (final d in c.drawings.reversed) {
      if (hitTestShape(shapeOf(d, p), pos) != null) return d;
    }
    return null;
  }

  // ───────────────────────── 长按定位（仅新建时） ─────────────────────────

  bool onLongPressStart(Offset pos) {
    final c = _controllerOf();
    final p = _projectionOf();
    if (c == null || p == null || c.tool == null) return false;
    _placing = true;
    _clearCrosshair();
    c.setDraftPreview(_snap(c, p, _clampTo(p.rect, pos)));
    return true;
  }

  bool onLongPressMove(Offset pos) {
    if (!_placing) return false;
    final c = _controllerOf();
    final p = _projectionOf();
    if (c != null && p != null && c.tool != null) {
      c.setDraftPreview(_snap(c, p, _clampTo(p.rect, pos)));
    }
    return true;
  }

  bool onLongPressEnd() {
    if (!_placing) return false;
    _placing = false;
    final c = _controllerOf();
    final preview = c?.preview;
    if (c != null && preview != null && c.tool != null) c.addDraftPoint(preview);
    return true;
  }

  bool onLongPressCancel() {
    if (!_placing) return false;
    _placing = false;
    _controllerOf()?.setDraftPreview(null);
    return true;
  }

  // ───────────────────────── 拖动选中的画线 ─────────────────────────

  /// 按下时判断：点在选中且未锁定的画线上才接手。
  bool canDrag(Offset pos) {
    final c = _controllerOf();
    final p = _projectionOf();
    if (c == null || p == null || !c.visible || c.tool != null) return false;
    final selected = c.selected;
    if (selected == null || selected.locked) return false;
    if (!p.rect.inflate(drawingHandleSlop).contains(pos)) return false;
    final hit = hitTestShape(shapeOf(selected, p), pos);
    if (hit == null) return false;
    _dragOrigin = selected;
    _dragHit = hit;
    _dragStart = pos;
    _dragMoved = false;
    return true;
  }

  void onDragUpdate(Offset pos) {
    final c = _controllerOf();
    final p = _projectionOf();
    final origin = _dragOrigin;
    final hit = _dragHit;
    if (c == null || p == null || origin == null || hit == null) return;
    final handle = hit.handle;
    final Drawing next;
    if (handle != null) {
      next = moveHandle(origin, handle, p.fromScreen(_clampTo(p.rect, pos)));
    } else {
      final bars = ((pos.dx - _dragStart.dx) / p.candleWidth).round();
      final from = p.yToPrice(_dragStart.dy), to = p.yToPrice(pos.dy);
      // 对数刻度下整体按比例移动，形状在屏幕上不变
      next = p.logScale && from > 0
          ? translateDrawing(origin, p.timeline, bars, 0, priceFactor: to / from)
          : translateDrawing(origin, p.timeline, bars, to - from);
    }
    _dragMoved = _dragMoved || next != origin;
    c.replaceDuringEdit(next);
  }

  void onDragEnd() {
    if (_dragMoved) _controllerOf()?.commitEdit();
    _dragOrigin = null;
    _dragHit = null;
    _dragMoved = false;
  }

  // ───────────────────────── 内部 ─────────────────────────

  static DrawingAnchor _snap(DrawingController c, DrawingProjection p, Offset pos) =>
      p.snap(pos, radius: c.magnet ? c.magnetRadius : 0);

  static Offset _clampTo(Rect r, Offset pos) => Offset(
        pos.dx.clamp(r.left, r.right).toDouble(),
        pos.dy.clamp(r.top, r.bottom).toDouble(),
      );
}

/// 拖动选中画线的手势识别器：[canStart] 在按下时返回 true 就立即胜出（不等滑动阈值），
/// 这样图表的横拖、缩放、长按和外层页面的竖向滚动都不会抢走这次拖动。
class DrawingDragRecognizer extends OneSequenceGestureRecognizer {
  DrawingDragRecognizer({super.debugOwner});

  bool Function(Offset localPosition)? canStart;
  ValueChanged<Offset>? onUpdate;
  VoidCallback? onEnd;

  int? _pointer;
  bool _accepted = false;

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      _pointer == null &&
      super.isPointerAllowed(event) &&
      (canStart?.call(event.localPosition) ?? false);

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    _pointer = event.pointer;
    resolve(GestureDisposition.accepted);
  }

  @override
  void acceptGesture(int pointer) {
    if (pointer == _pointer) _accepted = true;
  }

  @override
  void rejectGesture(int pointer) {
    if (pointer == _pointer) _accepted = false;
    stopTrackingPointer(pointer);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event.pointer != _pointer) return;
    if (event is PointerMoveEvent && _accepted) onUpdate?.call(event.localPosition);
    if (event is PointerUpEvent || event is PointerCancelEvent) stopTrackingPointer(event.pointer);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    final accepted = _accepted;
    _pointer = null;
    _accepted = false;
    if (accepted) onEnd?.call();
  }

  @override
  String get debugDescription => 'drawing drag';
}
