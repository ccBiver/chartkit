import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'drawing.dart';
import 'drawing_geometry.dart';

/// 画线的状态与控制接口：全部画线、当前工具、显示开关、选中项、新建中的点。
///
/// 交给 `KLineChart.drawingController` 后图表才开启画线；不传则图表与原来完全一样。
/// 工具栏、样式面板等界面由调用方自己做，读写这里的属性即可，变化时会 `notifyListeners`。
///
/// 保存：画线增删、拖动结束、改样式、锁定时调用 [onChanged]，调用方在里面存 [toJson]
/// （按品种分开存）；换品种时用 [loadJson] 恢复。选中、切工具、拖动过程中不调用。
///
/// 用完需 [dispose]。
class DrawingController extends ChangeNotifier {
  DrawingController({
    required DrawingStyle style,
    List<double> fibLevels = defaultFibLevels,
    this.magnet = true,
    this.magnetRadius = 20,
    this.onChanged,
  })  : _style = style,
        _fibLevels = List.unmodifiable(fibLevels);

  /// 新建时是否把落点吸到附近 K 线的开高低收。
  bool magnet;

  /// 吸附半径（逻辑像素）：落点离开高低收在这个距离以内才吸过去。
  double magnetRadius;

  /// 保存用的回调，见类说明。
  VoidCallback? onChanged;

  List<Drawing> _drawings = const [];
  DrawingStyle _style;
  List<double> _fibLevels;
  DrawingTool? _tool;
  List<DrawingAnchor> _draft = const [];
  DrawingAnchor? _preview;
  bool _visible = true;
  String? _selectedId;
  int _seq = 0;
  final ValueNotifier<Rect?> _selectionBounds = ValueNotifier(null);

  /// 全部画线，按绘制顺序（后画的在上）。
  List<Drawing> get drawings => _drawings;

  /// 新建画线用的样式（颜色、线宽）。
  DrawingStyle get style => _style;

  set style(DrawingStyle value) {
    if (value == _style) return;
    _style = value;
    notifyListeners();
  }

  /// 新建斐波那契回撤时显示的档位。
  List<double> get fibLevels => _fibLevels;

  set fibLevels(List<double> value) {
    _fibLevels = List.unmodifiable(value);
    notifyListeners();
  }

  /// 当前工具；null 表示没在新建，图上的点击用于选中画线。
  DrawingTool? get tool => _tool;

  /// 切换工具：放弃没点完的画线、取消选中；选了工具时自动打开显示。
  set tool(DrawingTool? value) {
    _tool = value;
    _draft = const [];
    _preview = null;
    _selectedId = null;
    if (value != null) _visible = true;
    notifyListeners();
  }

  /// 新建中已经点下的点（不含长按拖动中的预览点）。调用方可用 `draft.length` 提示「点第几个点」。
  List<DrawingAnchor> get draft => _draft;

  /// 长按拖动定位时的预览点。
  DrawingAnchor? get preview => _preview;

  /// 是否显示全部画线。关掉时画线不画、点不中，数据保留。
  bool get visible => _visible;

  set visible(bool value) {
    if (value == _visible) return;
    _visible = value;
    if (!value) {
      _selectedId = null;
      _tool = null;
      _draft = const [];
      _preview = null;
    }
    notifyListeners();
  }

  String? get selectedId => _selectedId;

  Drawing? get selected => _byId(_selectedId);

  /// 选中项在图上的范围（相对图表左上角，已裁到主图内），给调用方摆放「样式 / 锁定 / 删除」浮层。
  /// 没有选中、选中项不在可视区或图表还没画出来时为 null。图表每帧更新。
  ValueListenable<Rect?> get selectionBounds => _selectionBounds;

  void select(String? id) {
    final next = _byId(id)?.id;
    if (next == _selectedId) return;
    _selectedId = next;
    notifyListeners();
  }

  /// 加一条画线（如从别处恢复的单条）。id 重复时替换原来那条。
  void add(Drawing drawing) {
    _drawings = [
      for (final d in _drawings)
        if (d.id != drawing.id) d,
      drawing,
    ];
    notifyListeners();
    onChanged?.call();
  }

  void remove(String id) {
    if (_byId(id) == null) return;
    _drawings = [
      for (final d in _drawings)
        if (d.id != id) d,
    ];
    if (_selectedId == id) _selectedId = null;
    notifyListeners();
    onChanged?.call();
  }

  /// 删除选中的画线；没有选中时返回 false。
  bool removeSelected() {
    final id = _selectedId;
    if (id == null) return false;
    remove(id);
    return true;
  }

  /// 清除全部画线。
  void clear() {
    if (_drawings.isEmpty) return;
    _drawings = const [];
    _selectedId = null;
    notifyListeners();
    onChanged?.call();
  }

  void setLocked(String id, bool locked) => _update(id, (d) => d.copyWith(locked: locked));

  /// 改一条画线的颜色、线宽。
  void setStyle(String id, DrawingStyle style) => _update(id, (d) => d.copyWith(style: style));

  /// 改斐波那契回撤显示的档位。
  void setFibLevels(String id, List<double> levels) =>
      _update(id, (d) => d.copyWith(fibLevels: levels));

  /// 放弃没点完的画线，工具保持不变。
  void cancelDraft() {
    if (_draft.isEmpty && _preview == null) return;
    _draft = const [];
    _preview = null;
    notifyListeners();
  }

  /// 序列化全部画线：`{"version": 1, "drawings": [...]}`。
  Map<String, Object?> toJson() => {
        'version': 1,
        'drawings': [for (final d in _drawings) d.toJson()],
      };

  /// 用 [toJson] 的结果替换全部画线（null 表示清空）。认不出的条目跳过。不触发 [onChanged]。
  void loadJson(Object? json) {
    final list = json is Map ? json['drawings'] : null;
    _drawings = [
      if (list is List)
        for (final item in list) Drawing.fromJson(item),
    ].nonNulls.toList(growable: false);
    _selectedId = null;
    _draft = const [];
    _preview = null;
    notifyListeners();
  }

  // ───────────────────────── 由 KLineChart 调用 ─────────────────────────

  /// 新建：落下一个点；点数够了就生成画线、选中它、退出工具。
  void addDraftPoint(DrawingAnchor anchor) {
    final tool = _tool;
    if (tool == null) return;
    _preview = null;
    final placed = [..._draft, anchor];
    if (placed.length < tool.pointCount) {
      _draft = List.unmodifiable(placed);
      notifyListeners();
      return;
    }
    final drawing = Drawing(
      id: _nextId(),
      tool: tool,
      anchors: completeAnchors(tool, placed),
      style: _style,
      fibLevels: tool == DrawingTool.fibRetracement ? _fibLevels : null,
    );
    _draft = const [];
    _tool = null;
    _drawings = [..._drawings, drawing];
    _selectedId = drawing.id;
    notifyListeners();
    onChanged?.call();
  }

  void setDraftPreview(DrawingAnchor? anchor) {
    if (anchor == _preview) return;
    _preview = anchor;
    notifyListeners();
  }

  /// 拖动中替换一条画线（不触发 [onChanged]，松手时调 [commitEdit]）。
  void replaceDuringEdit(Drawing drawing) {
    _drawings = [
      for (final d in _drawings) d.id == drawing.id ? drawing : d,
    ];
    notifyListeners();
  }

  void commitEdit() => onChanged?.call();

  void updateSelectionBounds(Rect? bounds) => _selectionBounds.value = bounds;

  // ───────────────────────── 内部 ─────────────────────────

  Drawing? _byId(String? id) {
    if (id == null) return null;
    for (final d in _drawings) {
      if (d.id == id) return d;
    }
    return null;
  }

  void _update(String id, Drawing Function(Drawing) change) {
    final d = _byId(id);
    if (d == null) return;
    final next = change(d);
    if (next == d) return;
    replaceDuringEdit(next);
    onChanged?.call();
  }

  String _nextId() => '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${_seq++}';

  @override
  void dispose() {
    _selectionBounds.dispose();
    super.dispose();
  }
}
