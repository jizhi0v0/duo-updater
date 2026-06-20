#!/usr/bin/env python3
"""Duo Updater app icon — a stylized Siamese cat ("Duo", the owner's cat).

Front-facing color-point Siamese head: cream face, dark seal points on the
ears + muzzle mask, vivid blue almond eyes. Pure SVG paths/gradients so
rsvg-convert renders crisply at every size. Symmetric about x=512.

Two appearances share one geometry:
  * light — cream face on a sky-blue squircle (the default Dock icon).
  * dark  — a "moonlit" treatment: the cream face stays bright (so the
    Siamese identity survives at 16px instead of muddying into the
    background), set on a midnight-navy squircle, with the seal points kept
    a legible warm brown, a soft glow behind the eyes, and a cool rim on the
    ear edges so they don't merge into the dark backdrop.
"""
import os

OUT = os.path.join(os.path.dirname(__file__), "out")
os.makedirs(OUT, exist_ok=True)

CX = 512
BODY_INSET = 100
BODY = 1024 - 2 * BODY_INSET
RX = round(BODY * 0.2237)


def mx(x):
    """Mirror an x coord about the center axis."""
    return 2 * CX - x


def n(v):
    return f"{v:.1f}"


# ---- palettes ------------------------------------------------------------
# Geometry is identical across appearances; only colors and a few dark-only
# accents (eye glow, ear rim, vignette) change. Gradient *ids* stay the same
# in both modes so the path strings below never have to branch.
LIGHT = {
    "dark": False,
    "bg_0": "#8FD3F4", "bg_1": "#4F86D6",           # sky squircle
    "cream_0": "#FBEFD9", "cream_1": "#EAD3A8",      # warm cream face
    "point_0": "#5B4636", "point_1": "#3A2A20",      # seal point brown
    "eye_0": "#7FE0FF", "eye_1": "#2E9BE6",          # blue iris
    "nose": "#C77E8A",                               # mauve nose
    "inner_ear": "#D9A7A2",                          # pink inner ear
    "pupil": "#14202b",
    "whisker": "#ffffff", "whisker_op": "0.85",
}

DARK = {
    "dark": True,
    "bg_0": "#243650", "bg_1": "#0B0E16",            # midnight squircle
    "cream_0": "#EFE2C4", "cream_1": "#C2AB7E",      # face stays bright, a hair cooler
    "point_0": "#5E4634", "point_1": "#33241A",      # warm brown (kept off-black)
    "eye_0": "#9BEBFF", "eye_1": "#2E9BE6",          # iris with a brighter core
    "nose": "#C77E8A",
    "inner_ear": "#C7938D",
    "pupil": "#101a24",
    "whisker": "#DCE7F5", "whisker_op": "0.70",
    # dark-only accents
    "glow": "#6FD3FF",                               # eye halo
    "rim": "#7FA8DE",                                # cool ear rim
    "vignette": "#3A5C8C",                           # faint bg lift behind the head
}


def defs(p):
    d = (
        f'<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">'
        f'<stop offset="0" stop-color="{p["bg_0"]}"/>'
        f'<stop offset="1" stop-color="{p["bg_1"]}"/></linearGradient>'
        f'<linearGradient id="cream" x1="0" y1="0" x2="0" y2="1">'
        f'<stop offset="0" stop-color="{p["cream_0"]}"/>'
        f'<stop offset="1" stop-color="{p["cream_1"]}"/></linearGradient>'
        f'<linearGradient id="point" x1="0" y1="0" x2="0" y2="1">'
        f'<stop offset="0" stop-color="{p["point_0"]}"/>'
        f'<stop offset="1" stop-color="{p["point_1"]}"/></linearGradient>'
        f'<radialGradient id="eye" cx="0.5" cy="0.38" r="0.75">'
        f'<stop offset="0" stop-color="{p["eye_0"]}"/>'
        f'<stop offset="1" stop-color="{p["eye_1"]}"/></radialGradient>'
    )
    if p["dark"]:
        # softer top sheen + a deeper bottom vignette for the night look
        d += (
            f'<linearGradient id="gloss" x1="0" y1="0" x2="0" y2="1">'
            f'<stop offset="0" stop-color="#ffffff" stop-opacity="0.10"/>'
            f'<stop offset="0.5" stop-color="#ffffff" stop-opacity="0"/>'
            f'<stop offset="1" stop-color="#000000" stop-opacity="0.22"/></linearGradient>'
            f'<radialGradient id="bgGlow" cx="0.5" cy="0.56" r="0.62">'
            f'<stop offset="0" stop-color="{p["vignette"]}" stop-opacity="0.55"/>'
            f'<stop offset="1" stop-color="{p["vignette"]}" stop-opacity="0"/></radialGradient>'
            f'<radialGradient id="eyeGlow" cx="0.5" cy="0.5" r="0.5">'
            f'<stop offset="0" stop-color="{p["glow"]}" stop-opacity="0.85"/>'
            f'<stop offset="0.55" stop-color="{p["glow"]}" stop-opacity="0.28"/>'
            f'<stop offset="1" stop-color="{p["glow"]}" stop-opacity="0"/></radialGradient>'
        )
    else:
        d += (
            f'<linearGradient id="gloss" x1="0" y1="0" x2="0" y2="1">'
            f'<stop offset="0" stop-color="#ffffff" stop-opacity="0.22"/>'
            f'<stop offset="0.45" stop-color="#ffffff" stop-opacity="0.04"/>'
            f'<stop offset="0.5" stop-color="#ffffff" stop-opacity="0"/>'
            f'<stop offset="1" stop-color="#000000" stop-opacity="0.10"/></linearGradient>'
        )
    return f"<defs>{d}</defs>"


def squircle(p):
    s = (
        f'<rect x="{BODY_INSET}" y="{BODY_INSET}" width="{BODY}" height="{BODY}" '
        f'rx="{RX}" ry="{RX}" fill="url(#bg)"/>'
    )
    if p["dark"]:
        # lift the area directly behind the head out of the black
        s += (
            f'<rect x="{BODY_INSET}" y="{BODY_INSET}" width="{BODY}" height="{BODY}" '
            f'rx="{RX}" ry="{RX}" fill="url(#bgGlow)"/>'
        )
    s += (
        f'<rect x="{BODY_INSET}" y="{BODY_INSET}" width="{BODY}" height="{BODY}" '
        f'rx="{RX}" ry="{RX}" fill="url(#gloss)"/>'
    )
    return s


def ears(p):
    # Left ear: big triangle with soft tip, dark seal point. Mirror for right.
    L = (
        f'<path d="M 286 470 '
        f'C 250 360 250 250 300 196 '
        f'C 330 250 410 330 470 392 Z" fill="url(#point)"/>'
    )
    R = (
        f'<path d="M {mx(286)} 470 '
        f'C {mx(250)} 360 {mx(250)} 250 {mx(300)} 196 '
        f'C {mx(330)} 250 {mx(410)} 330 {mx(470)} 392 Z" fill="url(#point)"/>'
    )
    # inner ear (pink)
    LI = f'<path d="M 320 420 C 300 350 302 290 326 256 C 344 300 386 350 424 392 Z" fill="{p["inner_ear"]}"/>'
    RI = f'<path d="M {mx(320)} 420 C {mx(300)} 350 {mx(302)} 290 {mx(326)} 256 C {mx(344)} 300 {mx(386)} 350 {mx(424)} 392 Z" fill="{p["inner_ear"]}"/>'
    out = L + R + LI + RI
    if p["dark"]:
        # cool rim along the outer ear edges so the brown doesn't vanish into
        # the midnight background (only the upper/outer arc shows; the lower
        # edge tucks behind the head).
        rimL = (
            f'<path d="M 286 470 C 250 360 250 250 300 196 C 330 250 410 330 470 392" '
            f'fill="none" stroke="{p["rim"]}" stroke-width="6" stroke-opacity="0.55" '
            f'stroke-linejoin="round" stroke-linecap="round"/>'
        )
        rimR = (
            f'<path d="M {mx(286)} 470 C {mx(250)} 360 {mx(250)} 250 {mx(300)} 196 '
            f'C {mx(330)} 250 {mx(410)} 330 {mx(470)} 392" '
            f'fill="none" stroke="{p["rim"]}" stroke-width="6" stroke-opacity="0.55" '
            f'stroke-linejoin="round" stroke-linecap="round"/>'
        )
        out += rimL + rimR
    return out


def head(p):
    # cream face: wide cheeks, soft chin. Symmetric.
    return (
        f'<path d="M 512 360 '
        f'C 640 330 712 372 742 470 '       # forehead -> right temple
        f'C 772 568 760 660 690 728 '        # right cheek
        f'C 630 786 565 812 512 812 '        # jaw to chin
        f'C 459 812 394 786 334 728 '        # left jaw
        f'C 264 660 252 568 282 470 '        # left cheek
        f'C 312 372 384 330 512 360 Z" fill="url(#cream)"/>'
    )


def mask(p):
    # seal-point muzzle/mask: a darker patch over the lower-center face,
    # extending up the nose bridge between the eyes. Soft, semi-transparent.
    return (
        f'<path d="M 512 470 '
        f'C 556 470 588 520 596 580 '
        f'C 616 640 624 700 600 742 '
        f'C 566 786 458 786 424 742 '
        f'C 400 700 408 640 428 580 '
        f'C 436 520 468 470 512 470 Z" fill="url(#point)" opacity="0.92"/>'
    )


def eyes(p):
    # Big, open, friendly almond eyes — the Siamese signature. Slight upward
    # slant at the outer corner (cat-like, not angry), bright blue iris with a
    # vertical pupil and a catch-light.
    CY = 558

    def eye_group(cx_):
        sign = -1 if cx_ < CX else 1          # -1 left eye, +1 right eye
        outer_x = cx_ + sign * 84
        inner_x = cx_ - sign * 70
        oc_y = CY - 14                         # outer corner lifted gently
        ic_y = CY + 14                         # inner corner dips toward nose
        top = CY - 58
        bot = CY + 52
        pre = ""
        if p["dark"]:
            # soft halo so the eyes read as glowing at night
            pre = f'<circle cx="{n(cx_)}" cy="{n(CY)}" r="92" fill="url(#eyeGlow)"/>'
        # dark rim slightly larger than the iris for definition
        rim = (
            f'<path d="M {n(outer_x)} {n(oc_y)} '
            f'Q {n(cx_)} {n(top-12)} {n(inner_x)} {n(ic_y)} '
            f'Q {n(cx_)} {n(bot+12)} {n(outer_x)} {n(oc_y)} Z" '
            f'fill="url(#point)"/>'
        )
        iris = (
            f'<path d="M {n(outer_x)} {n(oc_y)} '
            f'Q {n(cx_)} {n(top)} {n(inner_x)} {n(ic_y)} '
            f'Q {n(cx_)} {n(bot)} {n(outer_x)} {n(oc_y)} Z" '
            f'fill="url(#eye)"/>'
        )
        pupil = f'<ellipse cx="{n(cx_)}" cy="{n(CY)}" rx="14" ry="38" fill="{p["pupil"]}"/>'
        # single soft catch-light near the top of the eye, same side on both
        catch = (
            f'<circle cx="{n(cx_ - 6)}" cy="{n(CY-24)}" r="10" fill="#ffffff" opacity="0.95"/>'
        )
        return pre + rim + iris + pupil + catch

    return eye_group(420) + eye_group(mx(420))


def nose_mouth(p):
    s = (
        # nose: small rounded heart/triangle, sits on the mask
        f'<path d="M 512 612 '
        f'C 540 612 552 626 540 644 '
        f'C 532 656 520 666 512 672 '
        f'C 504 666 492 656 484 644 '
        f'C 472 626 484 612 512 612 Z" fill="{p["nose"]}"/>'
    )
    # mouth: two soft curves under the nose (the cat smile)
    s += (
        f'<path d="M 512 672 L 512 700" stroke="{p["point_1"]}" stroke-width="7" stroke-linecap="round"/>'
        f'<path d="M 512 700 C 492 724 456 724 442 706" stroke="{p["point_1"]}" '
        f'stroke-width="7" fill="none" stroke-linecap="round"/>'
        f'<path d="M 512 700 C 532 724 568 724 582 706" stroke="{p["point_1"]}" '
        f'stroke-width="7" fill="none" stroke-linecap="round"/>'
    )
    return s


def whiskers(p):
    w = ""
    pts = [(596, 650, 824, 612), (596, 672, 836, 686), (428, 650, 200, 612), (428, 672, 188, 686)]
    for x1, y1, x2, y2 in pts:
        cy = (y1 + y2) / 2 + 12
        w += (f'<path d="M {x1} {y1} Q {(x1+x2)/2:.0f} {cy:.0f} {x2} {y2}" '
              f'stroke="{p["whisker"]}" stroke-width="6" fill="none" stroke-linecap="round" opacity="{p["whisker_op"]}"/>')
    return w


def build(p):
    body = (squircle(p) + ears(p) + head(p) + mask(p)
            + whiskers(p) + eyes(p) + nose_mouth(p))
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" '
        f'width="1024" height="1024">{defs(p)}{body}</svg>'
    )


if __name__ == "__main__":
    for name, palette in (("cat.svg", LIGHT), ("cat-dark.svg", DARK)):
        path = os.path.join(OUT, name)
        with open(path, "w") as fh:
            fh.write(build(palette))
        print("wrote", path)
