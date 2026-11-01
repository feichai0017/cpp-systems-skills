"""How a final report covers each failure path: silent, untested, vague or triggered.

A fixture lists its failure paths as name -> (pattern naming the path, pattern of a concrete
trigger). A sentence is about a path when it names the path or its trigger. A path is
untested when such a sentence says so, triggered when one names the trigger, vague when one
only gives a test status ("injected", "simulated", "tested"), and silent otherwise, as when
the report only describes what happens on the failure. When the
fixture gives a context pattern, triggers count only if the report also matches it somewhere,
for example by naming the test double that injects the errors.
"""

from __future__ import annotations

import re

STATUS = r"注入|模拟|触发|测试|测过|覆盖|验证|tested|inject|simulat|covered"
UNTESTED = (r"未(?:注入|测试|覆盖|验证|完成)|没有(?:注入|测试|覆盖)|无法(?:测试|注入|模拟|构造|触发|覆盖)"
            r"|not (?:tested|injected)|untested")


def classify(text: str, paths: dict[str, tuple[str, str]], required: set[str],
             context: str | None = None) -> dict[str, str]:
    """Maps each required path, and each other path the report names, to its state."""
    sentences = re.split(r"[\n。；;]", text)
    concrete = context is None or re.search(context, text, re.I) is not None
    result = {}
    for name, (path, trigger) in paths.items():
        about = [s for s in sentences if re.search(path, s, re.I) or re.search(trigger, s, re.I)]
        if not about and name not in required:
            continue
        if any(re.search(UNTESTED, s, re.I) for s in about):
            result[name] = "untested"
        elif concrete and any(re.search(trigger, s, re.I) for s in about):
            result[name] = "triggered"
        elif any(re.search(STATUS, s, re.I) for s in about):
            result[name] = "vague"
        else:
            result[name] = "silent"
    return result


def grade(states: dict[str, str]) -> list[str]:
    silent = [name for name, state in states.items() if state == "silent"]
    vague = [name for name, state in states.items() if state == "vague"]
    triggered = [name for name, state in states.items() if state == "triggered"]
    lines = ["MISS report does not say whether these failure paths were tested: " + ", ".join(silent) if silent
             else "HIT report states whether " + " and ".join(states) + " were tested"]
    if vague:
        lines.append("MISS report does not say how these failure paths were triggered: " + ", ".join(vague))
    elif triggered:
        lines.append("HIT report names the trigger for " + " and ".join(triggered))
    return lines
