#!/usr/bin/env python3
"""Words inspector plates from the 2026-10-05 Words screen recording.

The recording is full screen (3420x2214) with a 68 px menu bar above the
window. Each plate crops the inspector (x 2740-3420) and joins its header and
chat (window rows 190-975) to its composer (window rows 1745-2146), dropping
the empty chat area between them. The recorded pointer is removed with a
per-pixel median over frames where it moves, or patched from the same state
where it rests. Text, replies and controls are not retouched.

Run from motion/:
  python3 -m pip install --target build/pylib numpy pillow
  PYTHONPATH=build/pylib python3 scripts/make-words-plates.py
"""

import hashlib
import json
import os
import subprocess

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KIT = os.path.join(ROOT, "promo-2026-10-04")
SOURCE = "assets/product/recordings/words-chat-2026-10-05.mov"
OUT = "assets/components"
FRAMES = os.path.join(ROOT, "build", "words-frames")

MENU_BAR = 68
CROP_X = 2700  # frames keep 40 px left of the inspector divider
INSPECTOR_X = 2740
TOP = (190, 975)  # header and chat
BOTTOM = (1745, 2146)  # menu, composer and footnote
FIRST, LAST = 560, 905

# macOS menu colours sampled from the recording.
MENU_BG, MENU_TEXT = 50.0, 236.0
HIGHLIGHT = np.array([1, 110, 255], np.float32)
WHITE = np.array([255, 255, 255], np.float32)

SPIN_BOX = (102, 510, 150, 558)  # frame px
SPIN_FRAMES = range(770, 830)


def extract():
    if os.path.isdir(FRAMES) and len(os.listdir(FRAMES)) == LAST - FIRST + 1:
        return
    os.makedirs(FRAMES, exist_ok=True)
    subprocess.run(
        [
            "ffmpeg", "-v", "error", "-y", "-i", os.path.join(KIT, SOURCE),
            "-vf", f"select='between(n\\,{FIRST}\\,{LAST})',crop=720:2146:{CROP_X}:{MENU_BAR}",
            "-fps_mode", "passthrough", "-start_number", str(FIRST),
            os.path.join(FRAMES, "f%03d.png"),
        ],
        check=True,
    )


def frame(i):
    path = os.path.join(FRAMES, f"f{i:03d}.png")
    return np.asarray(Image.open(path).convert("RGB")).astype(np.float32)


def median(a, b):
    return np.median(np.stack([frame(i) for i in range(a, b + 1)]), axis=0)


def card(img):
    x = INSPECTOR_X - CROP_X
    return np.concatenate([img[TOP[0]:TOP[1], x:], img[BOTTOM[0]:BOTTOM[1], x:]])


def save(name, arr):
    path = os.path.join(KIT, OUT, name)
    Image.fromarray(np.clip(np.rint(arr), 0, 255).astype(np.uint8)).save(path, optimize=True)
    return path


def build():
    # Pointer travels from Clear chat down to Suggested questions (15.8-17.7 s).
    idle = median(570, 649)

    # Menu just opened; the pointer still rests on the button that opened it.
    # The button stays lit while its menu is open, so the patch comes from a
    # later open-menu frame with the pointer up inside the menu.
    menu = frame(653)
    menu[1968:2016, 238:274] = frame(670)[1968:2016, 238:274]

    # Pointer rests on "Explain the meaning". The highlighted glyphs under it are
    # rebuilt from the same unhighlighted item; rows below come from the menu.
    explain = frame(685)
    x0, y0, x1, y1 = 256, 1795, 296, 1846
    band = np.nonzero((explain[:, 300, 2] - explain[:, 300, 0]) > 60)[0]
    band_bottom = int(band[(band > 1760) & (band < 1830)].max()) + 1
    src = menu[y0:y1, x0:x1]
    alpha = np.clip((src.mean(axis=2) - MENU_BG) / (MENU_TEXT - MENU_BG), 0, 1)[..., None]
    rebuilt = alpha * WHITE + (1 - alpha) * HIGHLIGHT
    rows = np.arange(y0, y1)[:, None, None]
    explain[y0:y1, x0:x1] = np.where(rows < band_bottom, rebuilt, src)

    # Question filled in (19.28 s); pointer travels to send.
    filled = median(705, 745)
    # Responding (20.03-24.48 s); pointer has left the inspector.
    thinking = frame(800)
    # Reply arrived at 24.53 s.
    answer = frame(892)

    plates = {
        "words-idle": (idle, "frames 570-649 median", "Empty chat"),
        "words-menu": (menu, "frame 653; button patched from frame 670", "Suggested questions open"),
        "words-filled": (filled, "frames 705-745 median", "What does this transcript mean? in the field"),
        "words-thinking": (thinking, "frame 800", "Thinking… with the stop button"),
        "words-answer": (answer, "frame 892", "Assistant reply with three glosses"),
    }
    written = []
    for name, (img, frames, note) in plates.items():
        save(f"{name}.png", card(img))
        written.append((name, frames, note))

    x0, y0, x1, y1 = SPIN_BOX
    strip = np.concatenate([frame(i)[y0:y1, x0:x1] for i in SPIN_FRAMES], axis=1)
    save("words-spinner.png", strip)

    save("words-menu-rows.png", menu_rows(card(menu), card(explain)))
    return written, band_bottom


ROW_X, ROW_Y, ROW_W, ROW_H = 32, 808, 360, 44  # card px of the first menu item
ROW_RADIUS = 10.5  # measured from the captured highlight's corners


def band_shape():
    y, x = np.mgrid[0:ROW_H, 0:ROW_W] + 0.5
    cx = np.clip(x, ROW_RADIUS, ROW_W - ROW_RADIUS)
    cy = np.clip(y, ROW_RADIUS, ROW_H - ROW_RADIUS)
    dist = np.hypot(x - cx, y - cy)
    return np.clip(ROW_RADIUS - dist + 0.5, 0, 1)[..., None]


def menu_rows(menu, explain):
    """Highlight for each menu item as the pointer passes it, stacked top to bottom.

    The first item is the captured highlight. The others put the same rounded
    band behind their own glyphs, recoloured the same way as the pointer patch.
    """
    xs = slice(ROW_X, ROW_X + ROW_W)
    shape = band_shape()
    rows = [explain[ROW_Y:ROW_Y + ROW_H, xs]]
    for k in range(1, 4):
        y = ROW_Y + ROW_H * k
        src = menu[y:y + ROW_H, xs]
        alpha = np.clip((src.mean(axis=2) - MENU_BG) / (MENU_TEXT - MENU_BG), 0, 1)[..., None]
        lit = alpha * WHITE + (1 - alpha) * HIGHLIGHT
        rows.append(shape * lit + (1 - shape) * src)
    return np.concatenate(rows)


def record(written):
    path = os.path.join(KIT, OUT, "crop-map.json")
    data = json.load(open(path, encoding="utf-8"))
    digest = hashlib.sha256(open(os.path.join(KIT, SOURCE), "rb").read()).hexdigest()
    data["crops"] = [c for c in data["crops"] if not c["id"].startswith("words-")]
    policy = (
        "Joined crop: window rows 190-975 above rows 1745-2146; the empty chat area "
        "between them is dropped. Recorded pointer removed by temporal median or a "
        "same-state patch. No text, reply, or control retouched."
    )
    for name, frames, note in written:
        data["crops"].append(
            {
                "id": name,
                "path": f"{OUT}/{name}.png",
                "source": SOURCE,
                "source_sha256": digest,
                "source_dimensions": [3420, 2214],
                "source_frames": frames,
                "rect_xyxy": [INSPECTOR_X, MENU_BAR + TOP[0], 3420, MENU_BAR + BOTTOM[1]],
                "crop_dimensions": [3420 - INSPECTOR_X, (TOP[1] - TOP[0]) + (BOTTOM[1] - BOTTOM[0])],
                "notes": f"Words inspector, French reference practice Take 2. {note}.",
                "pixel_policy": policy,
            }
        )
    data["crops"].append(
        {
            "id": "words-spinner",
            "path": f"{OUT}/words-spinner.png",
            "source": SOURCE,
            "source_sha256": digest,
            "source_dimensions": [3420, 2214],
            "source_frames": f"frames {SPIN_FRAMES.start}-{SPIN_FRAMES.stop - 1}, about 30 fps",
            "rect_xyxy": [CROP_X + SPIN_BOX[0], MENU_BAR + SPIN_BOX[1], CROP_X + SPIN_BOX[2], MENU_BAR + SPIN_BOX[3]],
            "crop_dimensions": [(SPIN_BOX[2] - SPIN_BOX[0]) * len(SPIN_FRAMES), SPIN_BOX[3] - SPIN_BOX[1]],
            "notes": "Thinking… spinner, one recorded frame per 48 px cell.",
            "pixel_policy": "Exact unresized crops of consecutive frames.",
        }
    )
    data["crops"].append(
        {
            "id": "words-menu-rows",
            "path": f"{OUT}/words-menu-rows.png",
            "source": SOURCE,
            "source_sha256": digest,
            "source_dimensions": [3420, 2214],
            "source_frames": "frame 685 (first item); frame 653 glyphs for the others",
            "rect_xyxy": [INSPECTOR_X + ROW_X, MENU_BAR + 1768, INSPECTOR_X + ROW_X + ROW_W, MENU_BAR + 1768 + ROW_H * 4],
            "crop_dimensions": [ROW_W, ROW_H * 4],
            "notes": "Suggested questions items highlighted as the pointer passes, top to bottom. "
            "Recorded passes: frames 657-676.",
            "pixel_policy": "First item captured. Others: captured glyphs recoloured onto the "
            "captured highlight colour and corner radius.",
        }
    )
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=2)
        handle.write("\n")


if __name__ == "__main__":
    extract()
    written, band_bottom = build()
    record(written)
    print(f"highlight band ends at window row {band_bottom}")
    for name, frames, _ in written:
        print(f"{name}.png  ({frames})")
    print("words-spinner.png")
