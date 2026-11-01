#!/usr/bin/env python3
"""Whether the final report says how each failure path of sdsreplace was tested.

Usage: report.py <final message>. The task requires NULL on allocation failure, so the
report must cover that path; a length overflow path counts once the report names it. A
tested path must name its trigger: the allocator seam or double, or which allocation fails,
for allocation failure; the constructed length for overflow. "Injected" or "simulated"
alone is not a trigger. Soft criteria (HIT/MISS); see common/failure_report.py.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "common"))
import failure_report  # noqa: E402

PATHS = {
    "allocation failure": (
        r"分配失败|内存不足|分配器|OOM|out of memory|allocation fail|allocator",
        r"sdsalloc\.h|s_(?:malloc|realloc)|#define\s+`?malloc|\w*_malloc\b"
        r"|`?malloc`?\s*(?:替身|宏|(?:使其|让其)?返回)|(?:替换|替身|包装)\s*`?malloc"
        r"|(?:替身|替换|自定义|计数|测试|临时|可失败)的?\s*(?:分配器|malloc)|分配器\s*(?:替身|替换)"
        r"|第\s*[一二三四五六七八九十\d]+\s*次\s*(?:分配|调用)|(?:每次|逐次|依次|所有).{0,6}分配"
        r"|(?:replacement|failing|counting|test) allocator|allocator (?:double|stub)"),
    "length overflow": (
        r"溢出|overflow",
        r"SIZE_MAX|\(size_t\)\s*-1|size_t\s*的?最大值|最大的?\s*size_t|\b(?:to|from)len\b\s*(?:传|设为|=|为)"),
}


def classify(text: str) -> dict[str, str]:
    return failure_report.classify(text, PATHS, {"allocation failure"})


def main() -> int:
    text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
    print("\n".join(failure_report.grade(classify(text))))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
