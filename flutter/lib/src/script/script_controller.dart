import 'dart:collection';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../model/candle.dart';
import 'script_align.dart';
import 'script_output.dart';

/// 某个序列在某根 K 线上的值，给 App 画图例、十字光标数值用。
@immutable
class ScriptValue {
  const ScriptValue({
    required this.scriptId,
    required this.scriptName,
    required this.pane,
    required this.seriesId,
    required this.title,
    required this.value,
    required this.color,
    required this.precision,
  });

  /// 设置输出时用的 id（[ScriptOutputController.setOutput] 的第一个参数）。
  final String scriptId;
  final String scriptName;

  /// 这条序列画在哪个窗格（副图脚本里标了 `pane: "main"` 的序列是 main）。
  final ScriptPane pane;
  final String seriesId;
  final String title;

  /// 这一根没有值时为 null。
  final double? value;

  /// 这一根的颜色；调色板下标 0（不画）时为 null。
  final Color? color;

  /// 脚本声明的小数位，null 表示跟随品种。
  final int? precision;

  @override
  String toString() => 'ScriptValue($scriptId/$seriesId $title=$value)';
}

class _Entry {
  _Entry(this.output, this.version);

  final ScriptOutput output;
  final int version;
  Object? alignedKey;
  ScriptAlignResult? aligned;
  ResolvedScript? resolved;
  ScriptAlignmentProblem? reported;
}

/// 脚本输出的容器：按脚本 id 设置、替换、移除，交给 `KLineChart.scriptOutputs` 画出来。
///
/// - 主图（`pane: main`）的输出按设置顺序叠在 K 线上；副图的每个占一个窗格，窗格顺序也按设置顺序。
/// - 替换同一个 id 的输出时窗格位置不变，只重画这个脚本所在的窗格。
/// - 输出和本地 K 线对不上时这份输出不画，并在帧末调用一次 [onAlignmentIssue]（同一份输出只报一次）。
class ScriptOutputController extends ChangeNotifier {
  ScriptOutputController({this.onAlignmentIssue});

  /// 输出对不上本地 K 线时调用（例如本地没有 `bars.to` 那一根），调用方应重新拉输出或 K 线。
  final ValueChanged<ScriptAlignmentIssue>? onAlignmentIssue;

  final LinkedHashMap<String, _Entry> _entries = LinkedHashMap();
  final List<ScriptAlignmentIssue> _pending = [];
  int _version = 0;
  bool _visible = true;
  List<Candle> _candles = const [];
  Object? _candlesKey;
  int? _intervalMs;

  /// 每个脚本的图层被重新录制的次数（测试用：替换一个脚本后只有它所在窗格的计数会变）。
  @visibleForTesting
  final Map<String, int> debugPaintCounts = {};

  /// 已设置的脚本 id，按设置顺序。
  List<String> get scriptIds => List.unmodifiable(_entries.keys);

  /// 副图脚本的 id，按设置顺序（也是窗格从上到下的顺序）。
  List<String> get subPaneIds => [
        for (final e in _entries.entries)
          if (e.value.output.pane == ScriptPane.sub) e.key,
      ];

  ScriptOutput? outputOf(String scriptId) => _entries[scriptId]?.output;

  /// 是否显示全部脚本输出。隐藏时副图窗格也收起来，数据保留。
  bool get visible => _visible;
  set visible(bool value) {
    if (value == _visible) return;
    _visible = value;
    notifyListeners();
  }

  /// 解析 [json]（字符串或 `jsonDecode` 的结果）并设置为 [scriptId] 的输出。
  ///
  /// 解析失败（如 `v` 不是 1）时移除这个脚本原有的输出，返回的结果里带错误原因。
  /// 输出很大时可以先在后台 isolate 里调 [parseScriptOutput]，再用 [setOutput]。
  ScriptParseResult setJson(String scriptId, Object? json) {
    final result = parseScriptOutput(json);
    final output = result.output;
    if (output == null) {
      remove(scriptId);
    } else {
      setOutput(scriptId, output);
    }
    return result;
  }

  /// 设置或替换 [scriptId] 的输出。已有的 id 保持原来的顺序。
  void setOutput(String scriptId, ScriptOutput output) {
    _entries[scriptId] = _Entry(output, ++_version);
    notifyListeners();
  }

  /// 移除一个脚本的输出；不存在时返回 false。
  bool remove(String scriptId) {
    if (_entries.remove(scriptId) == null) return false;
    debugPaintCounts.remove(scriptId);
    notifyListeners();
    return true;
  }

  void clear() {
    if (_entries.isEmpty) return;
    _entries.clear();
    debugPaintCounts.clear();
    notifyListeners();
  }

  /// 指定本地 K 线，供对齐用。`KLineChart` 每次数据变化都会调用；不用图表、只用 [valuesAt] 时自己调。
  /// [intervalMs] 是图表当前周期，给了就核对输出的周期。不会触发通知。
  void attachCandles(List<Candle> candles, {int? intervalMs}) {
    _candles = candles;
    _intervalMs = intervalMs;
    // 对齐只看时间：末根原地更新（同一开盘时间）不需要重新对齐
    _candlesKey = candles.isEmpty
        ? null
        : (candles.length, candles.first.time, candles.last.time, intervalMs);
  }

  /// [scriptId] 当前的对齐结果；没有输出或还没指定 K 线时为 null。
  ScriptAlignResult? alignmentOf(String scriptId) {
    final e = _entries[scriptId];
    if (e == null || _candlesKey == null) return null;
    return _align(scriptId, e);
  }

  ScriptAlignResult _align(String id, _Entry e) {
    if (e.aligned != null && e.alignedKey == _candlesKey) return e.aligned!;
    final r = alignScriptOutput(e.output, _candles, intervalMs: _intervalMs);
    e
      ..aligned = r
      ..alignedKey = _candlesKey
      ..resolved = null;
    final issue = r.issue;
    if (issue == null) {
      e.reported = null;
    } else if (e.reported != issue.problem) {
      e.reported = issue.problem;
      _pending.add(issue);
    }
    return r;
  }

  /// 对齐成功的脚本（含各对象的本地下标），按设置顺序。图表内部用。

  List<(String, ResolvedScript, int)> resolved() {
    if (!_visible || _candlesKey == null) return const [];
    final out = <(String, ResolvedScript, int)>[];
    for (final MapEntry(key: id, value: e) in _entries.entries) {
      final a = _align(id, e).alignment;
      if (a == null) continue;
      out.add((id, e.resolved ??= ResolvedScript(e.output, a), e.version));
    }
    return out;
  }

  /// 把攒下的对齐问题交给 [onAlignmentIssue]。`KLineChart` 在帧末调用（绘制期间不能回调宿主）。
  void deliverIssues() {
    if (_pending.isEmpty) return;
    final issues = List.of(_pending);
    _pending.clear();
    final cb = onAlignmentIssue;
    if (cb == null) return;
    for (final i in issues) {
      cb(i);
    }
  }

  /// 本地第 [index] 根 K 线上，各脚本可见序列的名称、数值和颜色（不进图例的、只当填充边界的不返回）。
  /// 顺序：脚本按设置顺序，序列按输出里的顺序。对不上 K 线的脚本不返回。
  List<ScriptValue> valuesAt(int index) {
    final out = <ScriptValue>[];
    for (final (id, r, _) in resolved()) {
      final o = r.output;
      final i = r.alignment.valueIndex(index);
      for (final s in o.series) {
        if (!s.visible || !s.legend) continue;
        final v = i < 0 ? double.nan : s.values[i];
        out.add(ScriptValue(
          scriptId: id,
          scriptName: o.scriptName,
          pane: s.mainPane ? ScriptPane.main : o.pane,
          seriesId: s.id,
          title: s.title,
          value: v.isNaN ? null : v,
          color: i < 0 ? o.colorOf(s.color) : o.colorOf(s.colorAt(i)),
          precision: o.precision,
        ));
      }
    }
    return out;
  }

  /// 测试和图表内部用：记一次图层录制。

  void countPaint(String scriptId) =>
      debugPaintCounts[scriptId] = (debugPaintCounts[scriptId] ?? 0) + 1;
}
