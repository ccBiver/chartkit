# 合成图对照数据的来源

- `xauusd_1h.json`、`ukousd_1h.json`、`xauusd_15m.json`、`xagaud_15m.json`：XAUUSD、UKOUSD、XAGAUD 的真实 K 线样本，2026-11-23 取的。字段是 `time`（开盘时间，UTC 毫秒）和开高低收。
  - 1 小时：XAUUSD 702 根，UKOUSD 333 根（UKOUSD 有的时间 XAUUSD 都有），两边都有的 333 根。用来测一边缺 K 线的情况。
  - 15 分钟：两边都是 919 根，时间完全一样。
- `expected_*.json`：另一份独立实现（TypeScript）对上面两组 K 线算 `A + B`、`A - B`、`A * B`、`A / B` 的结果，每行 `[开盘时间, 开, 高, 低, 收]`。规则和 `combineCandles` 相同：只取两边都有的开盘时间，开高低收各自运算，最高、最低取四个结果里的最大、最小。生成脚本不在本仓库。
