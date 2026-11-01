#!/usr/bin/env python3
"""Whether the final report says how each failure path of sdsreplace was tested.

Usage: report.py <final message>. The task requires NULL on allocation failure, so the
report must say whether that path was tested; a length overflow path counts once the report
names it. A path counts as covered when one sentence names it together with a test status
(injected, simulated, tested, untested). Soft criterion (HIT/MISS).
"""

from __future__ import annotations

import re
import sys

PATHS = {
    "allocation failure": r"分配失败|内存不足|分配器|OOM|out of memory|allocation fail|allocator",
    "length overflow": r"溢出|overflow",
}
STATUS = r"注入|模拟|触发|测试|测过|覆盖|验证|tested|inject|simulat|covered"


def main() -> int:
    text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
    sentences = re.split(r"[\n。；;]", text)
    named = [name for name, path in PATHS.items()
             if name == "allocation failure" or any(re.search(path, s, re.I) for s in sentences)]
    silent = [name for name in named
              if not any(re.search(PATHS[name], s, re.I) and re.search(STATUS, s, re.I) for s in sentences)]
    if silent:
        print("MISS report does not say whether these failure paths were tested: " + ", ".join(silent))
    else:
        print("HIT report states whether " + " and ".join(named) + " were tested")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
