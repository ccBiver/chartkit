"""把 15m/ 下的样本转成「经过 google.protobuf.Value + protojson」后的样子，写到 15m-protojson/。

- 所有数都变成 double：整数写成 `1795290000000.0`，或者科学计数法 `1.79529e+12`（两种交替出现）。
- 每个对象的键随机重排（固定种子，结果可复现）。
用法：python3 testdata/primitives/to_protojson.py（在 flutter/ 目录下）
"""
import json
import os
import random

SRC = 'testdata/primitives/15m'
DST = 'testdata/primitives/15m-protojson'
rng = random.Random(20261123)
counter = [0]


def num(v):
    f = float(v)
    counter[0] += 1
    if f == int(f) and abs(f) >= 1e5 and counter[0] % 2 == 0:
        s = '%.15e' % f
        mant, exp = s.split('e')
        mant = mant.rstrip('0').rstrip('.')
        return '%se+%d' % (mant, int(exp)) if int(exp) >= 0 else '%se%d' % (mant, int(exp))
    return repr(f)


def dump(v):
    if v is None:
        return 'null'
    if isinstance(v, bool):
        return 'true' if v else 'false'
    if isinstance(v, (int, float)):
        return num(v)
    if isinstance(v, str):
        return json.dumps(v, ensure_ascii=False)
    if isinstance(v, list):
        return '[' + ','.join(dump(x) for x in v) + ']'
    keys = list(v.keys())
    rng.shuffle(keys)
    return '{' + ','.join(json.dumps(k) + ':' + dump(v[k]) for k in keys) + '}'


os.makedirs(DST, exist_ok=True)
for name in sorted(os.listdir(SRC)):
    data = json.load(open(os.path.join(SRC, name)))
    out = dump(data)
    assert json.loads(out) == json.loads(json.dumps(data)), name  # 数值不变
    open(os.path.join(DST, name), 'w').write(out)
    print(name)
