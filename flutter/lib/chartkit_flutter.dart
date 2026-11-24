/// chartkit 的 Flutter 版：纯 Dart、全部画在一个 `CustomPaint` 上的 K 线图。
library;

export 'src/indicator/builtins.dart';
export 'src/indicator/chart_registry.dart';
export 'src/indicator/indicator.dart';
export 'src/model/candle.dart';
export 'src/model/time_frame.dart';
export 'src/chart/chart_formatter.dart';
export 'src/chart/chart_mapper.dart';
export 'src/chart/chart_theme.dart';
export 'src/chart/chart_types.dart';
export 'src/chart/k_line_chart_state.dart';
export 'src/chart/sub_indicator_controller.dart';
export 'src/chart/chart_painter.dart' show ChartOverlayPainter;
export 'src/chart/k_line_chart.dart';
export 'src/chart/replay_controller.dart' show ChartReplayController, ReplayPhase;
export 'src/drawing/drawing.dart';
export 'src/drawing/drawing_controller.dart';
export 'src/drawing/drawing_geometry.dart'
    show DrawingTimeline, PositionStats, RangeStats, positionStats, gannFanRatios;
export 'src/drawing/drawing_theme.dart';
export 'src/script/script_align.dart'
    show ScriptAlignment, ScriptAlignmentIssue, ScriptAlignmentProblem, alignScriptOutput;
export 'src/script/script_controller.dart';
export 'src/script/script_output.dart';
