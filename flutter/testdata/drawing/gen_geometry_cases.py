"""F1-01 画线几何的期望值。

照 DRAWING.md 和 TradingView 的通行定义独立写成，不参考 Dart 代码。
固定的换算：主图 0..400 × 0..200，第 i 根 K 线中心 x = 20*i + 10（每根 20 像素，最新一根 19 贴右），
价格 100..200 映射到 y = 2*(200 - p)。第 i 根的开盘时间 = i*60000 毫秒。

运行：python3 gen_geometry_cases.py > geometry_cases.json
"""
import json

W, H = 400.0, 200.0
FIB = [0, 0.236, 0.382, 0.5, 0.618, 0.786, 1]
GANN = [1 / 8, 1 / 4, 1 / 3, 1 / 2, 1, 2, 3, 4, 8]


def xy(a):
    i, p = a
    return (20.0 * i + 10.0, 2.0 * (200.0 - p))


def exit_point(o, d):
    """从 o 沿 d 射出，离开 0..W × 0..H 时的点。"""
    ts = []
    if d[0] > 0: ts.append((W - o[0]) / d[0])
    if d[0] < 0: ts.append((0 - o[0]) / d[0])
    if d[1] > 0: ts.append((H - o[1]) / d[1])
    if d[1] < 0: ts.append((0 - o[1]) / d[1])
    ts = [t for t in ts if t > 0]
    if not ts: return o
    t = min(ts)
    return (o[0] + d[0] * t, o[1] + d[1] * t)


def seg(a, b): return [a[0], a[1], b[0], b[1]]
def area(a, b): return [min(a[0], b[0]), min(a[1], b[1]), max(a[0], b[0]), max(a[1], b[1])]


def expect(tool, anchors):
    pts = [xy(a) for a in anchors]
    out = {"handles": [list(p) for p in pts], "segments": [], "areas": []}
    if tool == "horizontalLine":
        y = pts[0][1]
        out["handles"] = [[W / 2, y]]
        out["segments"] = [[0, y, W, y]]
    elif tool == "verticalLine":
        x = pts[0][0]
        out["handles"] = [[x, H / 2]]
        out["segments"] = [[x, 0, x, H]]
    elif tool == "trendLine":
        out["segments"] = [seg(pts[0], pts[1])]
    elif tool == "ray":
        d = (pts[1][0] - pts[0][0], pts[1][1] - pts[0][1])
        out["segments"] = [seg(pts[0], exit_point(pts[0], d))]
    elif tool in ("rectangle", "priceRange"):
        out["areas"] = [area(pts[0], pts[1])]
    elif tool == "fibRetracement":
        p1, p2 = anchors[0][1], anchors[1][1]
        left, right = min(pts[0][0], pts[1][0]), max(pts[0][0], pts[1][0])
        if right - left < 1: right = W
        out["segments"] = [seg(pts[0], pts[1])]
        for l in FIB:
            y = 2.0 * (200.0 - (p2 + (p1 - p2) * l))
            out["segments"].append([left, y, right, y])
    elif tool in ("longPosition", "shortPosition"):
        e, t, s = pts
        left, right = min(e[0], t[0]), max(e[0], t[0])
        right = max(right, left + 24)
        out["areas"] = [[left, min(e[1], t[1]), right, max(e[1], t[1])],
                        [left, min(e[1], s[1]), right, max(e[1], s[1])]]
        long = tool == "longPosition"
        ep, tp, sp = anchors[0][1], anchors[1][1], anchors[2][1]
        reward = tp - ep if long else ep - tp
        risk = ep - sp if long else sp - ep
        out["stats"] = {"reward": reward, "risk": risk, "ratio": reward / risk}
    elif tool == "gannFan":
        o, b = pts
        d = (b[0] - o[0], b[1] - o[1])
        out["segments"] = [seg(o, exit_point(o, (d[0], d[1] * r))) for r in GANN]
    elif tool == "pitchfork":
        p0, p1, p2 = pts
        m = ((p1[0] + p2[0]) / 2, (p1[1] + p2[1]) / 2)
        d = (m[0] - p0[0], m[1] - p0[1])
        out["segments"] = [seg(p0, exit_point(p0, d)), seg(p1, exit_point(p1, d)),
                           seg(p2, exit_point(p2, d)), seg(p1, p2)]
    elif tool == "elliottWave":
        out["segments"] = [seg(pts[i - 1], pts[i]) for i in range(1, len(pts))]
    return out


CASES = {
    "horizontalLine": [[(5, 150)], [(0, 199)], [(19, 100.5)]],
    "verticalLine": [[(5, 150)], [(0, 120)], [(19, 180)]],
    "trendLine": [[(2, 120), (10, 180)], [(15, 190), (3, 110)], [(4, 150), (4, 160)]],
    "ray": [[(2, 120), (6, 140)], [(10, 150), (5, 150)], [(3, 180), (3, 110)]],
    "rectangle": [[(2, 180), (8, 130)], [(12, 110), (6, 170)], [(0, 200), (19, 100)]],
    "fibRetracement": [[(2, 100), (12, 200)], [(15, 180), (5, 130)], [(7, 150), (7, 170)]],
    "priceRange": [[(3, 120), (9, 160)], [(14, 175), (11, 125)], [(6, 140), (6, 140)]],
    "longPosition": [[(4, 150), (10, 170), (4, 140)], [(10, 120), (11, 130), (10, 115)],
                     [(8, 150), (2, 165), (8, 140)]],
    "shortPosition": [[(4, 150), (12, 130), (4, 160)], [(15, 180), (18, 150), (15, 190)],
                      [(9, 125), (3, 105), (9, 135)]],
    "gannFan": [[(0, 100), (5, 150)], [(10, 150), (15, 170)], [(18, 120), (12, 180)]],
    "pitchfork": [[(2, 150), (8, 180), (8, 120)], [(1, 120), (6, 170), (9, 150)],
                  [(5, 180), (10, 130), (12, 110)]],
    "elliottWave": [[(0, 110), (3, 140), (5, 125), (9, 180), (11, 160), (15, 195)],
                    [(2, 190), (4, 160), (6, 175), (10, 120), (12, 140), (16, 105)],
                    [(1, 150), (2, 155), (3, 152), (5, 170), (6, 165), (8, 185)]],
}

cases = []
for tool, sets in CASES.items():
    for k, anchors in enumerate(sets):
        cases.append({"name": f"{tool} #{k + 1}", "tool": tool,
                      "anchors": [[i, p] for i, p in anchors], "expect": expect(tool, anchors)})
print(json.dumps({"projection": {"width": W, "height": H, "candleWidth": 20, "rightFloat": 19,
                                 "priceMin": 100, "priceMax": 200, "candles": 20,
                                 "intervalMillis": 60000},
                  "cases": cases}, indent=1))
