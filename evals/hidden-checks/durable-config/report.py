#!/usr/bin/env python3
"""Whether the final report says how each failure path of SaveConfig was tested.

Usage: report.py <final message>. Every atomic replacement writes, syncs and renames a
temporary file and syncs the directory, so the report must cover those four failure paths;
open and close failures count once the report names them. The project injects failures
through FileSystem fakes, so a trigger is a sentence that names the failing step with the
error the fake returns ("Write 返回 ENOSPC", "让 Rename 失败"), in a report that names the
fake. "Fault injection tests pass" is not a trigger, and "on write failure the temporary
file is removed" only describes behavior.
Soft criteria (HIT/MISS); see common/failure_report.py.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "common"))
import failure_report  # noqa: E402

# The error a fake returns. "Fails" or "returns an error" after the step describes what
# SaveConfig does, not a test; a step that itself returns something is the fake's answer.
ERRNO = r"\bE[A-Z]{2,}\b|errc::\w+|no_space\w*|io_error"
# "替身逐项触发打开、部分写入、同步、关闭、重命名失败" lists several steps; 使 alone would also
# match 使用.
MAKE_FAIL = r"(?:让|令|使其|使得|模拟|注入|触发|覆盖|逐项|逐步|分别)"
FAILS = r"失败|出错|报错|错误|\bE[A-Z]{2,}\b"
STEPS = {
    "write failure": r"\bWrite\b|写入|写失败|半写|写一半|ENOSPC|空间不足|磁盘(?:已)?满|no_space",
    "file sync failure": r"(?<!目录)(?<!目录 )(?:\bSync\b|fsync|同步)|刷盘|文件\S{0,4}同步",
    "rename failure": r"\bRename\b|rename|重命名|改名",
    # A bare 目录 also names opening the directory.
    "directory sync failure": r"目录\S{0,6}(?:Sync|同步|fsync)|(?:同步|Sync|fsync)\S{0,3}(?:父)?目录|directory\s+f?sync",
    "open failure": r"\bOpen\b|打开",
    "close failure": r"\bClose\b|关闭",
}
PATHS = {name: (step, rf"(?:{step}).{{0,20}}?(?:{ERRNO})|(?:{step})`?\s*(?:返回|returns?)"
                      rf"|{MAKE_FAIL}.{{0,60}}?(?:{step}).{{0,60}}?(?:{FAILS})")
         for name, step in STEPS.items()}
REQUIRED = {"write failure", "file sync failure", "rename failure", "directory sync failure"}
FAKE = (r"替身|\bfake|Fake\w*|Failing\w*|Fault\w*|\bstub|Stub\w*|\bmock|Mock\w*|Recording\w*|Inject\w*FileSystem"
        r"|(?:测试|注入故障|故障注入)\s*(?:用)?的?\s*`?FileSystem|FileSystem`?\s*(?:替身|子类)")


def classify(text: str) -> dict[str, str]:
    return failure_report.classify(text, PATHS, REQUIRED, FAKE)


def main() -> int:
    text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
    print("\n".join(failure_report.grade(classify(text))))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
