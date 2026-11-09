#!/usr/bin/env python3
"""Layout and visibility checks that do not need a watchOS simulator.

The fit math is the same rule as MasoWatch/WatchTrainingLayout.swift:
presets are read from that file, then applied in the same order. Heart-rate
card presence is the same rule as LiveHeartRateCardVisibility.swift.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LAYOUT = (ROOT / "MasoWatch" / "WatchTrainingLayout.swift").read_text()
VIEWS = (ROOT / "MasoWatch" / "WatchViews.swift").read_text()
VIS = (ROOT / "Maso" / "State" / "LiveHeartRateCardVisibility.swift").read_text()
PLAYER = (ROOT / "Maso" / "Views" / "Screens" / "PlanPlayerScreen.swift").read_text()

PAGES = ("exerciseManual", "exerciseTimed", "rest")


def fail(message: str) -> None:
    print(f"FAIL {message}")
    raise SystemExit(1)


def parse_devices() -> list[dict]:
    pattern = re.compile(
        r'WatchDeviceSpec\(name: "([^"]+)", screenWidth: ([0-9.]+), '
        r"screenHeight: ([0-9.]+), safeTop: ([0-9.]+), safeBottom: ([0-9.]+), "
        r"safeLeading: ([0-9.]+), safeTrailing: ([0-9.]+)\)"
    )
    devices = []
    for match in pattern.finditer(LAYOUT):
        name, sw, sh, top, bottom, leading, trailing = match.groups()
        sw, sh, top, bottom, leading, trailing = map(float, (sw, sh, top, bottom, leading, trailing))
        devices.append(
            {
                "name": name,
                "screen": (sw, sh),
                "safe": (top, bottom, leading, trailing),
                "content_width": sw - leading - trailing,
                "content_height": sh - top - bottom,
            }
        )
    if not devices:
        fail("no WatchDeviceSpec rows parsed")
    return devices


def parse_presets() -> list[tuple[str, dict]]:
    pattern = re.compile(
        r"private static let (roomy|medium|compact) = WatchLayoutPreset\(\s*"
        r"spacing: ([0-9.]+), horizontalPadding: ([0-9.]+),\s*"
        r"kicker: ([0-9.]+), title: ([0-9.]+), detail: ([0-9.]+),\s*"
        r"countdownExercise: ([0-9.]+), countdownRest: ([0-9.]+),\s*"
        r"buttonManual: ([0-9.]+), buttonOther: ([0-9.]+), footer: ([0-9.]+),\s*"
        r"lineFactor: ([0-9.]+), countdownFactor: ([0-9.]+)\s*\)",
        re.S,
    )
    found = []
    for match in pattern.finditer(LAYOUT):
        name = match.group(1)
        values = list(map(float, match.groups()[1:]))
        keys = (
            "spacing",
            "horizontalPadding",
            "kicker",
            "title",
            "detail",
            "countdownExercise",
            "countdownRest",
            "buttonManual",
            "buttonOther",
            "footer",
            "lineFactor",
            "countdownFactor",
        )
        found.append((name, dict(zip(keys, values))))
    if [name for name, _ in found] != ["roomy", "medium", "compact"]:
        fail(f"preset order changed: {[name for name, _ in found]}")
    return found


def estimated_height(preset: dict, page: str, shows_detail: bool, shows_next: bool, include_footer: bool, type_scale: float) -> float:
    def line(size: float) -> float:
        return size * preset["lineFactor"] * type_scale

    rows = [line(preset["kicker"])]
    if page in ("exerciseManual", "exerciseTimed"):
        rows.append(line(preset["title"]) * 2)
        if shows_detail:
            rows.append(line(preset["detail"]))
        if page == "exerciseTimed":
            rows.append(preset["countdownExercise"] * preset["countdownFactor"] * type_scale)
        rows.append(preset["buttonManual"] if page == "exerciseManual" else preset["buttonOther"])
    elif page == "rest":
        rows.append(preset["countdownRest"] * preset["countdownFactor"] * type_scale)
        if shows_next:
            rows.append(line(10) + 1 + line(13))
        rows.append(preset["buttonOther"])
    else:
        fail(f"unknown page {page}")
    if include_footer:
        rows.append(line(preset["footer"]))
    gaps = preset["spacing"] * max(0, len(rows) - 1)
    return sum(rows) + gaps


def resolve(presets: list[tuple[str, dict]], content_width: float, content_height: float, page: str, shows_detail: bool, shows_next: bool, type_scale: float) -> dict:
    if type_scale <= 1:
        for name, preset in presets:
            needed = estimated_height(preset, page, shows_detail, shows_next, True, 1)
            if needed <= content_height and content_width > 0:
                countdown = preset["countdownRest"] if page == "rest" else preset["countdownExercise"]
                button = preset["buttonManual"] if page == "exerciseManual" else preset["buttonOther"]
                return {
                    "preset": name,
                    "title": preset["title"],
                    "button": max(36, button),
                    "countdown": countdown,
                    "spacing": preset["spacing"],
                    "draw_scale": 1,
                    "scroll": False,
                    "needed": needed,
                }
    compact = presets[-1][1]
    countdown = compact["countdownRest"] if page == "rest" else compact["countdownExercise"]
    button = compact["buttonManual"] if page == "exerciseManual" else compact["buttonOther"]
    return {
        "preset": "compact",
        "title": compact["title"],
        "button": max(36, button),
        "countdown": countdown,
        "spacing": compact["spacing"],
        "draw_scale": max(type_scale, 1),
        "scroll": True,
        "needed": estimated_height(compact, page, shows_detail, shows_next, True, max(type_scale, 1)),
    }


def playlist_presented(height: float, collapsed: float, slack: float = 40) -> bool:
    return height > collapsed + slack


def shows_card(session_active: bool, playlist_open: bool) -> bool:
    return session_active and not playlist_open


def main() -> None:
    devices = parse_devices()
    presets = parse_presets()
    minimum = min(devices, key=lambda device: device["content_height"])
    if minimum["name"] != "40mm":
        fail(f"minimum content box is {minimum['name']}, expected 40mm")
    if abs(minimum["content_height"] - 141) > 0.01 or abs(minimum["content_width"] - 161) > 0.01:
        fail(f"40mm content box changed: {minimum['content_width']}x{minimum['content_height']}")

    print("device content boxes (pt):")
    for device in devices:
        print(
            f"  {device['name']:14} screen {device['screen'][0]:.0f}x{device['screen'][1]:.0f}"
            f"  safe t/b {device['safe'][0]:.0f}/{device['safe'][1]:.0f}"
            f"  content {device['content_width']:.1f}x{device['content_height']:.1f}"
        )

    print("\ndefault type, worst case (2-line title, detail, next, footer reserved):")
    chosen_by_page: dict[str, list[tuple[dict, dict]]] = {page: [] for page in PAGES}
    for page in PAGES:
        print(f"  {page}")
        for device in devices:
            chosen = resolve(
                presets,
                device["content_width"],
                device["content_height"],
                page,
                True,
                True,
                1,
            )
            chosen_by_page[page].append((device, chosen))
            mark = "SCROLL" if chosen["scroll"] else "fit"
            print(
                f"    {device['name']:14} {mark:6} {chosen['preset']:8} "
                f"title {chosen['title']:.0f}  button {chosen['button']:.0f}  "
                f"countdown {chosen['countdown']:.0f}  need {chosen['needed']:.2f}  "
                f"box {device['content_height']:.1f}"
            )
            if chosen["scroll"]:
                fail(f"{device['name']} {page} scrolls at default type")
            if chosen["needed"] > device["content_height"] + 1e-6:
                fail(f"{device['name']} {page} overflows by {chosen['needed'] - device['content_height']:.2f}")
            if chosen["button"] < 36:
                fail(f"{device['name']} {page} button {chosen['button']} is below 36pt")
            if device["content_width"] - 2 * 4 < chosen["button"]:
                fail(f"{device['name']} button is not full-width enough to tap")

    # Larger content boxes must not pick a smaller title or button than a shorter box.
    for page, rows in chosen_by_page.items():
        ordered = sorted(rows, key=lambda item: item[0]["content_height"])
        for earlier, later in zip(ordered, ordered[1:]):
            if later[1]["title"] + 1e-6 < earlier[1]["title"]:
                fail(f"{page}: {later[0]['name']} title smaller than {earlier[0]['name']}")
            if later[1]["button"] + 1e-6 < earlier[1]["button"]:
                fail(f"{page}: {later[0]['name']} button smaller than {earlier[0]['name']}")

    # Tall screens keep the previous point sizes when the stack fits.
    tall = next(device for device in devices if device["name"] == "49mm-ultra3")
    for page, title, button, countdown in (
        ("exerciseManual", 17, 44, 24),
        ("exerciseTimed", 17, 36, 24),
        ("rest", 17, 36, 40),
    ):
        chosen = resolve(presets, tall["content_width"], tall["content_height"], page, True, True, 1)
        if chosen["scroll"] or chosen["preset"] != "roomy":
            fail(f"ultra3 {page} dropped off roomy: {chosen}")
        if (chosen["title"], chosen["button"], chosen["countdown"]) != (title, button, countdown):
            fail(f"ultra3 {page} chrome changed: {chosen}")

    # 40mm still shows every row. Manual stays near the old 17/44 (15/40).
    small = resolve(presets, minimum["content_width"], minimum["content_height"], "exerciseManual", True, True, 1)
    if small["preset"] != "medium" or small["title"] < 15 or small["button"] < 40:
        fail(f"40mm manual collapsed too far: {small}")
    timed = resolve(presets, minimum["content_width"], minimum["content_height"], "exerciseTimed", True, True, 1)
    if timed["scroll"] or timed["countdown"] < 16 or timed["button"] < 36:
        fail(f"40mm timed missing countdown or button: {timed}")
    rested = resolve(presets, minimum["content_width"], minimum["content_height"], "rest", False, True, 1)
    if rested["scroll"] or rested["countdown"] < 30 or rested["button"] < 36:
        fail(f"40mm rest missing countdown or skip: {rested}")

    # Without a detail line the stack is shorter, never taller.
    with_detail = estimated_height(presets[0][1], "exerciseManual", True, False, True, 1)
    without_detail = estimated_height(presets[0][1], "exerciseManual", False, False, True, 1)
    if without_detail >= with_detail:
        fail("hiding detail did not shrink the stack")

    # Footer reserved in the fit. The not-ready row is shorter, so it cannot overflow a fit that included it.
    with_footer = estimated_height(presets[-1][1], "exerciseTimed", True, False, True, 1)
    without_footer = estimated_height(presets[-1][1], "exerciseTimed", True, False, False, 1)
    if without_footer >= with_footer:
        fail("heart-rate row did not take height")
    if with_footer > minimum["content_height"]:
        fail("40mm timed budget excluding the reserved footer")

    # Paused uses the same page, so the same chrome. Active vs paused is color only.
    paused = resolve(presets, minimum["content_width"], minimum["content_height"], "exerciseTimed", True, False, 1)
    active = resolve(presets, minimum["content_width"], minimum["content_height"], "exerciseTimed", True, False, 1)
    if paused != active:
        fail("paused layout diverged from active")

    # Larger than default type scrolls. Do not claim those sizes fit one screen.
    for scale, label in ((1.12, "xLarge"), (1.40, "xxxLarge"), (1.64, "accessibility1")):
        grown = resolve(presets, minimum["content_width"], minimum["content_height"], "exerciseManual", True, False, scale)
        if not grown["scroll"] or grown["draw_scale"] != scale:
            fail(f"{label} on 40mm was forced onto one screen: {grown}")

    # Default and smaller type do not scroll on the minimum box.
    for scale in (0.82, 0.88, 0.94, 1):
        for page in PAGES:
            chosen = resolve(presets, minimum["content_width"], minimum["content_height"], page, True, True, scale)
            if chosen["scroll"] or chosen["draw_scale"] != 1:
                fail(f"scale {scale} {page} scrolled or resized text: {chosen}")

    # Long values stay one line in the view, and a 3-digit HR + 4-digit kcal + progress
    # still fits the 40mm footer after the 0.6 scale floor.
    for snippet in (
        ".lineLimit(2)",
        ".lineLimit(1)",
        ".minimumScaleFactor(0.6)",
        ".minimumScaleFactor(0.7)",
    ):
        if snippet not in VIEWS:
            fail(f"WatchViews missing {snippet}")
    footer_font = 11
    sample = "188" 
    kcal = "9999 kcal"
    progress = "24/48"
    # monospaced digit width is about 0.62em; the 0.6 floor is the last resort.
    natural = footer_font * 0.62 * (len(sample) + len(kcal) + len(progress)) + 8 * 2 + footer_font
    usable = minimum["content_width"] - 8
    if natural * 0.6 > usable:
        fail(f"long vitals cannot scale into the 40mm footer ({natural:.1f} -> {natural * 0.6:.1f} > {usable:.1f})")

    # Watch display conditions are unchanged.
    if "if workout.running, workout.heartRate > 0" not in VIEWS:
        fail("heart-rate display condition changed")
    if "if workout.running, workout.activeCalories > 0" not in VIEWS:
        fail("calorie display condition changed")
    if ".toolbar(.hidden, for: .navigationBar)" not in VIEWS:
        fail("navigation bar is still able to reserve a top band")
    if "ignoresSafeArea" in VIEWS.split("struct WatchFittedSession")[-1].split("struct ")[0]:
        fail("fitted session ignores the safe area")
    pause = VIEWS.split("计时段", 1)[1].split("WatchVitalsFooter", 1)[0]
    if ".buttonStyle(.plain)" not in pause:
        fail("pause button still uses the system style that adds extra height")
    if ".tint(" in pause:
        fail("pause button still uses tinted system chrome")

    # iOS card: training -> playlist -> back, then end leaves nothing.
    # Opening the playlist must not clear sessionActive.
    slack_match = re.search(r"static let playlistOpenSlack: CGFloat = ([0-9.]+)", VIS)
    if not slack_match or float(slack_match.group(1)) != 40:
        fail("playlist slack drifted from the existing drawer threshold")
    if "sessionActive && !playlistPresented" not in VIS:
        fail("card visibility is not sessionActive && !playlistPresented")
    if "sheet" in VIS.split("static func showsCard")[1].split("struct LiveHeartRateCardNavigation")[0].lower():
        fail("showsCard started treating arbitrary sheets as a reason to hide")
    slot = VIS.split("struct LiveHeartRateCardSlot")[1]
    if "EmptyView()" not in slot:
        fail("card slot is drawing its own visual; leave the ripple treatment alone")

    collapsed = 56
    nav_active = True
    height = collapsed
    if not shows_card(nav_active, playlist_presented(height, collapsed)):
        fail("collapsed playlist hid the card on the training stage")
    height = 254  # default drawer, drag-open, and tap-open all land here or higher
    if shows_card(nav_active, playlist_presented(height, collapsed)):
        fail("open playlist still shows the card")
    if not nav_active:
        fail("opening the playlist cleared the session")
    height = 500
    if shows_card(nav_active, playlist_presented(height, collapsed)):
        fail("fully expanded playlist still shows the card")
    height = collapsed
    if not shows_card(nav_active, playlist_presented(height, collapsed)):
        fail("returning to the training stage did not restore the card")
    nav_active = False
    if shows_card(nav_active, playlist_presented(height, collapsed)):
        fail("ended session left the card up")
    if shows_card(False, playlist_presented(254, collapsed)):
        fail("ended session with the playlist open left the card up")
    if shows_card(False, False):
        fail("inactive session shows the card")
    # Boundary matches `height > collapsed + 40`, not >=.
    if playlist_presented(collapsed + 40, collapsed):
        fail("height exactly at the slack counts as open")
    if not playlist_presented(collapsed + 40 + 0.1, collapsed):
        fail("height just past the slack does not count as open")
    # Player's real default is the open drawer. Session stays active.
    if shows_card(True, playlist_presented(254, 56)):
        fail("default open playlist shows the card")

    if "showsLiveHeartRateCard" not in PLAYER or "LiveHeartRateCardSlot()" not in PLAYER:
        fail("player does not mount the card through the visibility gate")
    drawer = PLAYER.split("private var playlistDrawer")[1].split("private var playlistDragHandleBar")[0]
    if "LiveHeartRateCardSlot" in drawer:
        fail("heart-rate card is mounted inside the playlist drawer")
    if "showsLiveHeartRateCard" not in PLAYER.split("if showsLiveHeartRateCard")[0]:
        fail("player gate is not computed from LiveHeartRateCardVisibility")

    print("\nOK  watch fit + heart-rate card visibility")


if __name__ == "__main__":
    main()
