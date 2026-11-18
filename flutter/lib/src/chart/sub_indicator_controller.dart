import 'package:flutter/foundation.dart';

import '../indicator/indicator.dart';

/// 副图选择模式：
/// - [single]   单选：点新指标替换旧的；点已选中的则关闭。
/// - [multiple] 叠加：点一个往下加一个窗格。
enum SubIndicatorMode { single, multiple }

/// 副图控制器：管理「选了哪些副图」与「单选/叠加」模式，
/// [selected] 直接喂给 `KLineChart.subIndicators`。
class SubIndicatorController extends ChangeNotifier {
  SubIndicatorController({SubIndicatorMode mode = SubIndicatorMode.single}) : _mode = mode;

  SubIndicatorMode _mode;
  List<Indicator> _selected = const [];

  SubIndicatorMode get mode => _mode;

  /// 当前选中的副图（有序，不可修改；每次变化都会换成新的 list）。
  List<Indicator> get selected => _selected;

  bool isSelected(String id) => _selected.any((e) => e.id == id);

  /// 切换某指标的选中态，遵循当前 [mode]。
  void toggle(Indicator indicator) {
    final exists = isSelected(indicator.id);
    final others = _selected.where((e) => e.id != indicator.id);
    _update(switch (_mode) {
      SubIndicatorMode.single => exists ? const [] : [indicator],
      SubIndicatorMode.multiple => exists ? others.toList() : [..._selected, indicator],
    });
  }

  /// 直接设定选中列表（如恢复用户偏好）。单选模式下只保留最后一个。
  void set(List<Indicator> indicators) {
    final keepLast = _mode == SubIndicatorMode.single && indicators.length > 1;
    _update(keepLast ? [indicators.last] : indicators);
  }

  void clear() => _update(const []);

  /// 切换模式；切到单选时仅保留最后一个，避免残留多个窗格。
  void changeMode(SubIndicatorMode mode) {
    if (mode == _mode) return;
    _mode = mode;
    if (mode == SubIndicatorMode.single && _selected.length > 1) {
      _selected = List.unmodifiable([_selected.last]);
    }
    notifyListeners();
  }

  void _update(List<Indicator> next) {
    _selected = List.unmodifiable(next);
    notifyListeners();
  }
}
