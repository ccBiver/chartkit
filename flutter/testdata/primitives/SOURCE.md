# 图元样本的来源

- `15m/*.json`：服务端脚本引擎的真实输出，图元格式是 SCHEMA v1。每个文件是一个脚本输出的 `output` 字段，没改过。
  - 脚本都用默认参数，2026-11-23 取的。
- `klines_15m.json`：上面这些输出用的 K 线，XAUUSD 15m 1000 根，含每天的休市空档和周末空档。
- `15m-protojson/*.json`：`to_protojson.py` 从 `15m/` 转出来的，模拟经过 `google.protobuf.Value` + protojson 后的样子：所有数都是 double（`1795211100000.0` 或 `1.7952111e+12`），键的顺序打乱。数值和原文件完全一样。

| 脚本 | 窗格 | 覆盖的图元 |
|---|---|---|
| boll | 主图 | 曲线、填充 |
| smc | 主图 | 线段、方框、标签 |
| com-supertrend-strategy | 主图 | 曲线（断开）、点、逐根变色的填充、标记、策略成交点、K 线改色 |
| com-ict-silver-bullet-backtest | 主图 | 背景色、成交点、方框、曲线 |
| com-decycler-high-low-breakout-schizoquant | 主图 | 自绘 K 线、K 线改色、标记 |
| opt-po3 | 主图 | 表格、越过最后一根的线段和方框 |
| fvg | 主图 | 231 个方框 |
| com-candlestick-patterns-identified-updated- | 主图 | 9 组共 417 个标记 |
| com-machine-learning-adaptive-supertrend-alg | 主图 | 500 个标签、表格 |
| sar | 主图 | 点 |
| macd | 副图 | 柱（逐根变色）、曲线、水平线 |
| rsi | 副图 | 水平线之间的填充 |
| wt | 副图 | 面积、点、阶梯线、线段、标签 |
| com-trend-exhaustion-continuation-map-bullby | 副图 | 背景色、227 个方框、标记、表格、面积、柱 |
| com-signed-realized-variance-trend-backquant | 副图 | 自绘 K 线 |
| st-macd | 副图 | 157 个成交点 |
