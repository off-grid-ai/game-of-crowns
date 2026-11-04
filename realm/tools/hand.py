#!/usr/bin/env python3
"""Playing the running game by hand, from the shell: look at its window, press
its keys, click in it, as a player would. A test aid; nothing here ships.

  hand.py shot out.png          capture the game window
  hand.py key <name>            press a key (Escape, space, h, k, …)
  hand.py click <fx> <fy>       left-click at a fraction of the window (0..1)
  hand.py scroll <fx> <fy> <n>  scroll the wheel there (n > 0 zooms in)
  hand.py drag <fx> <fy> <tx> <ty>
"""
import subprocess
import sys
import time

import Quartz

KEYS = {"escape": 53, "space": 49, "return": 36, "tab": 48, "up": 126, "down": 125, "left": 123, "right": 124}
LETTERS = "asdfhgzxcv bqweryt123465=97-80]ou[ip lj'k;\\,/nm."


def game_window():
    """The game's main window: the largest one Godot has on screen."""
    best = None
    for w in Quartz.CGWindowListCopyWindowInfo(Quartz.kCGWindowListOptionOnScreenOnly, Quartz.kCGNullWindowID):
        owner = str(w.get("kCGWindowOwnerName", ""))
        if owner.lower().startswith("godot") or owner == "Game of Crowns":
            b = w["kCGWindowBounds"]
            if best is None or b["Width"] * b["Height"] > best[1]["Width"] * best[1]["Height"]:
                best = (w["kCGWindowNumber"], b)
    if best is None or best[1]["Height"] < 300:
        sys.exit("the game isn't on screen")
    return best


def front():
    subprocess.run(["osascript", "-e", 'tell application "System Events" to set frontmost of (first process whose name contains "odot") to true'], capture_output=True)
    time.sleep(0.2)


def at(fx, fy):
    _, b = game_window()
    return b["X"] + b["Width"] * float(fx), b["Y"] + b["Height"] * float(fy)


def mouse(kind, x, y, button=Quartz.kCGMouseButtonLeft):
    e = Quartz.CGEventCreateMouseEvent(None, kind, (x, y), button)
    Quartz.CGEventPost(Quartz.kCGHIDEventTap, e)


def main():
    cmd, args = sys.argv[1], sys.argv[2:]
    if cmd == "shot":
        wid, _ = game_window()
        out = args[0]
        raw = out if out.endswith(".png") else out + ".tmp.png"
        subprocess.run(["screencapture", "-x", "-o", "-l", str(wid), raw], check=True)
        if raw != out:  # a .jpg for the play record: 1600 wide, small enough to keep in the repo
            subprocess.run(["magick", raw, "-resize", "1600x", "-quality", "82", out], check=True)
            subprocess.run(["rm", "-f", raw])
    elif cmd == "key":
        front()
        name = args[0].lower()
        code = KEYS.get(name)
        if code is None:
            code = LETTERS.index(name)
        for down in (True, False):
            Quartz.CGEventPost(Quartz.kCGHIDEventTap, Quartz.CGEventCreateKeyboardEvent(None, code, down))
            time.sleep(0.05)
    elif cmd == "click":
        front()
        x, y = at(args[0], args[1])
        mouse(Quartz.kCGEventMouseMoved, x, y)
        time.sleep(0.05)
        mouse(Quartz.kCGEventLeftMouseDown, x, y)
        time.sleep(0.05)
        mouse(Quartz.kCGEventLeftMouseUp, x, y)
    elif cmd == "scroll":
        front()
        x, y = at(args[0], args[1])
        mouse(Quartz.kCGEventMouseMoved, x, y)
        for _ in range(abs(int(args[2]))):
            e = Quartz.CGEventCreateScrollWheelEvent(None, Quartz.kCGScrollEventUnitLine, 1, 1 if int(args[2]) > 0 else -1)
            Quartz.CGEventPost(Quartz.kCGHIDEventTap, e)
            time.sleep(0.03)
    elif cmd == "drag":
        front()
        x, y = at(args[0], args[1])
        tx, ty = at(args[2], args[3])
        mouse(Quartz.kCGEventLeftMouseDown, x, y)
        for i in range(1, 21):
            mouse(Quartz.kCGEventLeftMouseDragged, x + (tx - x) * i / 20, y + (ty - y) * i / 20)
            time.sleep(0.01)
        mouse(Quartz.kCGEventLeftMouseUp, tx, ty)


main()
