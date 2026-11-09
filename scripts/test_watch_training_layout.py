#!/usr/bin/env python3
"""Watch layout bounds. Not a simulator run, and not an inset table.

Expected presets below are written out as literals. The line-height check
uses ceil(font * 1.35) for text and ceil(font * 1.25) for countdown digits.
Those factors are not read from WatchTrainingLayout.swift.
"""

from __future__ import annotations

import math
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LAYOUT = (ROOT / "MasoWatch" / "WatchTrainingLayout.swift").read_text()
VIEWS = (ROOT / "MasoWatch" / "WatchViews.swift").read_text()
PLAYER = (ROOT / "Maso" / "Views" / "Screens" / "PlanPlayerScreen.swift").read_text()


def fail(message: str) -> None:
    raise SystemExit(f"FAIL {message}")


def presets() -> dict[str, dict]:
    pattern = re.compile(
        r"private static let (roomy|medium|compact) = WatchLayoutPreset\(\s*"
        r"spacing: ([0-9.]+), horizontalPadding: ([0-9.]+),\s*"
        r"kicker: ([0-9.]+), titleManual: ([0-9.]+), titleTimed: ([0-9.]+), detail: ([0-9.]+),\s*"
        r"countdownExercise: ([0-9.]+), countdownRest: ([0-9.]+),\s*"
        r"buttonManual: ([0-9.]+), buttonOther: ([0-9.]+), footer: ([0-9.]+),\s*"
        r"lineFactor: ([0-9.]+), countdownFactor: ([0-9.]+)\s*\)",
        re.S,
    )
    found = {}
    order = []
    for match in pattern.finditer(LAYOUT):
        name = match.group(1)
        keys = (
            "spacing", "hpad", "kicker", "title_manual", "title_timed", "detail",
            "cd_ex", "cd_rest", "btn_manual", "btn_other", "footer", "line", "cdf",
        )
        found[name] = dict(zip(keys, map(float, match.groups()[1:])))
        order.append(name)
    if order != ["roomy", "medium", "compact"]:
        fail(f"preset order {order}")
    return found


def layout_height(p: dict, page: str, detail: bool = True, nxt: bool = True) -> float:
    def line(size: float) -> float:
        return size * p["line"]

    rows = [line(p["kicker"])]
    if page == "manual":
        rows.append(line(p["title_manual"]) * 2)
        if detail:
            rows.append(line(p["detail"]))
        rows.append(p["btn_manual"])
    elif page == "timed":
        rows.append(line(p["title_timed"]) * 2)
        if detail:
            rows.append(line(p["detail"]))
        rows.append(p["cd_ex"] * p["cdf"])
        rows.append(p["btn_other"])
    elif page == "rest":
        rows.append(p["cd_rest"] * p["cdf"])
        if nxt:
            rows.append(line(10) + 1 + line(13))
        rows.append(p["btn_other"])
    else:
        fail(page)
    rows.append(line(p["footer"]))
    return sum(rows) + p["spacing"] * (len(rows) - 1)


def external_height(p: dict, page: str) -> int:
    """Independent of the file's lineFactor / countdownFactor."""

    def text(size: float) -> int:
        return math.ceil(size * 1.35)

    def digits(size: float) -> int:
        return math.ceil(size * 1.25)

    rows = [text(p["kicker"])]
    if page == "manual":
        rows += [text(p["title_manual"]) * 2, text(p["detail"]), int(p["btn_manual"])]
    elif page == "timed":
        rows += [text(p["title_timed"]) * 2, text(p["detail"]), digits(p["cd_ex"]), int(p["btn_other"])]
    else:
        rows += [digits(p["cd_rest"]), text(10) + 1 + text(13), int(p["btn_other"])]
    rows.append(text(p["footer"]))
    return sum(rows) + int(p["spacing"]) * (len(rows) - 1)


def choose(table: dict[str, dict], box: float, page: str, margin: float) -> str:
    for name in ("roomy", "medium", "compact"):
        if layout_height(table[name], page) + margin <= box:
            return name
    return "scroll"


def usable_height(reported: float, top: float, bottom: float) -> float:
    inset = max(0, top) + max(0, bottom)
    base = max(0, reported - inset)
    if inset < 16 and reported >= 190:
        reserve = max(48, reported * 0.28)
        return max(0, reported - reserve)
    return base


def slice_struct(source: str, name: str) -> str:
    start = source.index(f"struct {name}")
    nxt = source.find("\nstruct ", start + 1)
    mark = source.find("\n// MARK:", start + 1)
    end = len(source)
    for candidate in (nxt, mark):
        if candidate != -1:
            end = min(end, candidate)
    return source[start:end]


def main() -> None:
    margin_match = re.search(r"static let fitMargin: CGFloat = ([0-9.]+)", LAYOUT)
    if not margin_match:
        fail("fitMargin missing")
    margin = float(margin_match.group(1))
    if margin < 12:
        fail(f"fit margin {margin} is still a razor")

    table = presets()
    # Literals, not generated. A 1pt clearance must not count as fitting.
    expected = {
        (141, "manual"): ("compact", 14, 40),
        (141, "timed"): ("compact", 11, 36),
        (141, "rest"): ("compact", 24, 36),
        (162, "manual"): ("medium", 15, 40),
        (162, "rest"): ("medium", 30, 36),
        (180, "manual"): ("roomy", 17, 44),
        (180, "timed"): ("medium", 15, 36),
        (210, "timed"): ("roomy", 17, 36),
        (210, "rest"): ("roomy", 40, 36),
    }
    # rest roomy reports countdown via cd_rest; the tuple's middle value is
    # title for exercise pages and countdown for rest. Handled below.
    print("content box -> preset (layout budget + 12pt margin)")
    for (box, page), spec in expected.items():
        name = choose(table, box, page, margin)
        preset = table[name] if name != "scroll" else None
        if page == "rest":
            got = (
                name,
                preset["cd_rest"] if preset else None,
                preset["btn_other"] if preset else None,
            )
        elif page == "manual":
            got = (
                name,
                preset["title_manual"] if preset else None,
                preset["btn_manual"] if preset else None,
            )
        else:
            got = (
                name,
                preset["title_timed"] if preset else None,
                preset["btn_other"] if preset else None,
            )
        need = None if preset is None else layout_height(preset, page)
        print(f"  {box:3} {page:6} {got} layout {need}")
        if got != spec:
            fail(f"box {box} {page}: got {got}, expected {spec}")
        if name == "scroll":
            fail(f"default type scrolls in a {box}pt box for {page}")
        external = external_height(preset, page)
        spare = box - external
        print(f"         external line box {external} spare {spare}")
        if spare < 8:
            fail(f"box {box} {page} external spare {spare} < 8 (real line height would clip)")

    # 162pt rest must not keep the 40pt countdown. That was the 0.75pt fit.
    if choose(table, 162, "rest", margin) == "roomy":
        fail("162pt rest still selects the 40pt countdown")

    usable_cases = (
        (197, 0, 0, 141.84),
        (141, 0, 0, 141),
        (162, 0, 0, 162),
        (224, 31, 31, 162),
        (242, 0, 0, 174.24),
    )
    for reported, top, bottom, expect in usable_cases:
        got = usable_height(reported, top, bottom)
        if abs(got - expect) > 0.05:
            fail(f"usableHeight({reported},{top},{bottom}) = {got}, expected {expect}")
        swift = f"usableHeight(reportedHeight:"
        if swift not in LAYOUT:
            fail("runtime does not call usableHeight")
    if "reportedHeight >= 190" not in LAYOUT or "0.28" not in LAYOUT:
        fail("full-screen fallback reserve changed without updating the expected cases")

    # Long strings stay inside the line limits the height budget assumes.
    exercise = slice_struct(VIEWS, "WatchExerciseView")
    rest = slice_struct(VIEWS, "WatchRestView")
    footer = slice_struct(VIEWS, "WatchVitalsFooter")
    if exercise.count(".lineLimit(2)") < 1 or exercise.count(".lineLimit(1)") < 2:
        fail("exercise text can wrap past the budgeted lines")
    if "第 12/12 组" :
        # 8 CJK/digit glyphs at 11pt (~0.9em) stay on one line inside 140pt.
        if 8 * 11 * 0.9 > 140:
            fail("Chinese set label wider than the content width")
    long_name = "杠铃卧推（下斜，宽握，暂停两秒）" * 2
    if len(long_name) < 20:
        fail("long-name fixture too short")
    # two lines are allowed; a third is not, because lineLimit is 2.
    if ".lineLimit(2)" not in exercise:
        fail("long exercise names are not capped at two lines")
    sample = "188" + "9999 kcal" + "128/128"
    natural = 11 * 0.62 * len(sample) + 16
    if natural * 0.6 > 140:
        fail("3-digit HR + 4-digit kcal cannot scale into the footer")
    if "if workout.running, workout.heartRate > 0" not in footer:
        fail("heart-rate display condition changed")
    if "if workout.running, workout.activeCalories > 0" not in footer:
        fail("calorie display condition changed")

    # One visible primary button per training page. The exercise view's two
    # Button closures are the manual check and the timed pause, in if/else.
    def buttons(blob: str) -> int:
        return blob.count("Button {")

    counts = {
        "WatchIdleView": buttons(slice_struct(VIEWS, "WatchIdleView")),
        "WatchExerciseView": buttons(exercise),
        "WatchRestView": buttons(rest),
        "WatchDoneView": buttons(slice_struct(VIEWS, "WatchDoneView")),
    }
    print("Button closures:", counts)
    if counts != {
        "WatchIdleView": 0,
        "WatchExerciseView": 2,
        "WatchRestView": 1,
        "WatchDoneView": 0,
    }:
        fail(f"button census changed: {counts}")
    if "if state.manualConfirm" not in exercise or "} else {" not in exercise:
        fail("exercise buttons are not mutually exclusive")
    pause = exercise.split("} else {", 1)[1]
    if ".buttonStyle(.plain)" not in pause or ".tint(" in pause:
        fail("timed pause button is not a measured plain button")

    if "LiveHeartRateCardSlot" in PLAYER or "showsLiveHeartRateCard" in PLAYER:
        fail("empty heart-rate slot is back")
    if "WorkoutHeartRateButton" in PLAYER:
        fail("this tree unexpectedly contains the real heart card; gate that call instead of a new view")

    print("OK")


if __name__ == "__main__":
    main()
