#!/usr/bin/env python3
"""Whether the final report says how each failure path of sdsreplace was tested.

Usage: report.py <final message>. The task requires NULL on allocation failure, so the
report must say whether that path was tested; a length overflow path counts once the report
names it. A path counts as covered when one sentence names it together with a test status
(injected, simulated, tested, untested) or a trigger. A path reported as tested must also name its
trigger in such a sentence: the allocator seam or double, or which allocation fails, for
allocation failure; the constructed length for overflow. "Injected" or "simulated" alone
is not a trigger. Soft criteria (HIT/MISS).
"""

from __future__ import annotations

import re
import sys

PATHS = {
    "allocation failure": r"分配失败|内存不足|分配器|OOM|out of memory|allocation fail|allocator",
    "length overflow": r"溢出|overflow",
}
TRIGGERS = {
    "allocation failure": r"sdsalloc\.h|s_(?:malloc|realloc)|#define\s+malloc|\w*_malloc\b|malloc\s*(?:替身|宏|返回)"
                          r"|(?:替身|替换|自定义|计数|测试|可失败)的?\s*(?:分配器|malloc)|分配器\s*(?:替身|替换)"
                          r"|第\s*[一二三四五六七八九十\d]+\s*次\s*(?:分配|调用)|(?:每次|逐次|依次|所有).{0,6}分配"
                          r"|(?:replacement|failing|counting|test) allocator|allocator (?:double|stub)",
    "length overflow": r"SIZE_MAX|\(size_t\)\s*-1|size_t\s*的?最大值|最大的?\s*size_t|\b(?:to|from)len\b\s*(?:传|设为|=|为)",
}
STATUS = r"注入|模拟|触发|测试|测过|覆盖|验证|tested|inject|simulat|covered"
UNTESTED = r"未(?:注入|测试|覆盖|验证|完成)|没有(?:注入|测试|覆盖)|无法|not (?:tested|injected)|untested"


def main() -> int:
    text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
    sentences = re.split(r"[\n。；;]", text)

    def about(name: str) -> list[str]:
        return [s for s in sentences if re.search(PATHS[name], s, re.I)]

    named = [name for name in PATHS if name == "allocation failure" or about(name)]
    # A concrete trigger also says the path was tested.
    silent = [name for name in named
              if not any(re.search(STATUS, s, re.I) or re.search(TRIGGERS[name], s, re.I) for s in about(name))]
    if silent:
        print("MISS report does not say whether these failure paths were tested: " + ", ".join(silent))
    else:
        print("HIT report states whether " + " and ".join(named) + " were tested")

    tested = [name for name in named if name not in silent
              and not any(re.search(UNTESTED, s, re.I) for s in about(name))]
    vague = [name for name in tested if not any(re.search(TRIGGERS[name], s, re.I) for s in about(name))]
    if vague:
        print("MISS report does not say how these failure paths were triggered: " + ", ".join(vague))
    elif tested:
        print("HIT report names the trigger for " + " and ".join(tested))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
