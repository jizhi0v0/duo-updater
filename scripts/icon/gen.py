#!/usr/bin/env python3
"""Generate macOS app-icon candidate SVGs for Duo Updater.

Pure geometry -> SVG (gradients + paths only, so ImageMagick's built-in SVG
renderer handles it cleanly). Render with:  magick -background none X.svg out.png
"""
import math
import os

OUT = os.path.join(os.path.dirname(__file__), "out")
os.makedirs(OUT, exist_ok=True)

C = 512          # canvas center (1024 canvas)
BODY_INSET = 100  # macOS-style transparent margin
BODY = 1024 - 2 * BODY_INSET   # 824
RX = round(BODY * 0.2237)      # continuous-corner radius approximation


def pt(cx, cy, r, ang_deg):
    """Point on circle. 0deg = up (12 o'clock), clockwise positive (screen)."""
    a = math.radians(ang_deg - 90)
    return (cx + r * math.cos(a), cy + r * math.sin(a))


def f(x):
    return f"{x:.2f}"


def squircle(grad_id, gloss=True):
    s = f'<rect x="{BODY_INSET}" y="{BODY_INSET}" width="{BODY}" height="{BODY}" rx="{RX}" ry="{RX}" fill="url(#{grad_id})"/>'
    if gloss:
        # subtle top highlight, clipped to the body
        s += (f'<rect x="{BODY_INSET}" y="{BODY_INSET}" width="{BODY}" height="{BODY}" '
              f'rx="{RX}" ry="{RX}" fill="url(#gloss)"/>')
    return s


def linear(id_, c0, c1, x1=0, y1=0, x2=0, y2=1):
    return (f'<linearGradient id="{id_}" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}">'
            f'<stop offset="0" stop-color="{c0}"/>'
            f'<stop offset="1" stop-color="{c1}"/></linearGradient>')


GLOSS = ('<linearGradient id="gloss" x1="0" y1="0" x2="0" y2="1">'
         '<stop offset="0" stop-color="#ffffff" stop-opacity="0.22"/>'
         '<stop offset="0.45" stop-color="#ffffff" stop-opacity="0.05"/>'
         '<stop offset="0.5" stop-color="#ffffff" stop-opacity="0"/>'
         '<stop offset="1" stop-color="#000000" stop-opacity="0.10"/></linearGradient>')


def wrap(defs, body):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">'
            f'<defs>{defs}{GLOSS}</defs>{body}</svg>')


def arc_path(cx, cy, r, a0, a1):
    """Arc path string from a0 to a1 (deg, clockwise positive)."""
    x0, y0 = pt(cx, cy, r, a0)
    x1, y1 = pt(cx, cy, r, a1)
    large = 1 if abs(a1 - a0) > 180 else 0
    sweep = 1 if a1 > a0 else 0
    return f'M {f(x0)} {f(y0)} A {r} {r} 0 {large} {sweep} {f(x1)} {f(y1)}'


def arrowhead(cx, cy, r, ang, size, tangent_cw=True):
    """Triangle arrowhead at the arc end pointing along the tangent."""
    tip_ang = ang + (size / r) * (180 / math.pi) * (1 if tangent_cw else -1)
    tip = pt(cx, cy, r, tip_ang)
    # base corners offset radially in/out from the arc at `ang`
    outer = pt(cx, cy, r + size * 0.95, ang)
    inner = pt(cx, cy, r - size * 0.95, ang)
    return f'M {f(tip[0])} {f(tip[1])} L {f(outer[0])} {f(outer[1])} L {f(inner[0])} {f(inner[1])} Z'


# ---------------------------------------------------------------------------
# Concept A: two chasing circular arrows (the universal sync/update glyph)
# ---------------------------------------------------------------------------
def concept_a():
    defs = linear("bgA", "#3B82F6", "#4338CA")  # blue -> indigo
    r = 188
    sw = 74
    gap = 26          # half-gap (deg) at each break
    head = 86
    white = "#ffffff"
    # top-right arc: from ~ -10deg sweeping clockwise to ~170deg (right side & top)
    a_top = arc_path(C, C, r, 178, 372)   # left-top around to right-bottom
    a_bot = arc_path(C, C, r, 358, 552)   # mirror
    # Simpler: two 180-ish arcs with gaps, arrowheads at the gap ends.
    arc1 = arc_path(C, C, r, -8, 168)     # over the top, ends near 9 o'clock-ish
    arc2 = arc_path(C, C, r, 172, 348)    # under the bottom
    h1 = arrowhead(C, C, r, 168, head, tangent_cw=True)
    h2 = arrowhead(C, C, r, 348, head, tangent_cw=True)
    body = squircle("bgA")
    body += f'<path d="{arc1}" stroke="{white}" stroke-width="{sw}" fill="none" stroke-linecap="butt"/>'
    body += f'<path d="{arc2}" stroke="{white}" stroke-width="{sw}" fill="none" stroke-linecap="butt"/>'
    body += f'<path d="{h1}" fill="{white}"/>'
    body += f'<path d="{h2}" fill="{white}"/>'
    return wrap(defs, body)


# ---------------------------------------------------------------------------
# Concept B: stacked double up-chevron ("up to date" / upgrade), duo = two
# ---------------------------------------------------------------------------
def concept_b():
    defs = linear("bgB", "#10B981", "#0EA5A4")  # emerald -> teal
    white = "#ffffff"
    sw = 92
    # chevron: V shape pointing up. Two of them stacked.
    def chevron(cy, half_w, h):
        lx, ty = C - half_w, cy + h
        mx, my = C, cy
        rx, ry = C + half_w, cy + h
        return f'M {f(lx)} {f(ty)} L {f(mx)} {f(my)} L {f(rx)} {f(ry)}'
    half_w = 196
    h = 150
    top = chevron(430, half_w, h)
    bot = chevron(600, half_w, h)
    body = squircle("bgB")
    for d in (top, bot):
        body += (f'<path d="{d}" stroke="{white}" stroke-width="{sw}" fill="none" '
                 f'stroke-linecap="round" stroke-linejoin="round"/>')
    return wrap(defs, body)


# ---------------------------------------------------------------------------
# Concept C: two rounded app-tiles with an upward update arrow rising
# ---------------------------------------------------------------------------
def concept_c():
    defs = linear("bgC", "#8B5CF6", "#6366F1")  # violet -> indigo
    white = "#ffffff"
    # two overlapping rounded tiles (the "duo" of apps) at the base, arrow up
    tile_r = 44
    # back tile
    body = squircle("bgC")
    body += (f'<rect x="318" y="372" width="300" height="300" rx="{tile_r}" '
             f'ry="{tile_r}" fill="#ffffff" fill-opacity="0.30"/>')
    body += (f'<rect x="406" y="460" width="300" height="300" rx="{tile_r}" '
             f'ry="{tile_r}" fill="#ffffff" fill-opacity="0.95"/>')
    # upward arrow centered, in the gradient color, sitting on the front tile
    ax = 556
    shaft_w = 70
    body += (f'<path d="M {ax} 250 L {ax+150} 430 L {ax+shaft_w/2+10} 430 '
             f'L {ax+shaft_w/2+10} 600 L {ax-shaft_w/2-10} 600 '
             f'L {ax-shaft_w/2-10} 430 L {ax-150} 430 Z" fill="url(#bgC)"/>')
    return wrap(defs, body)


def main():
    for name, fn in (("A", concept_a), ("B", concept_b), ("C", concept_c)):
        path = os.path.join(OUT, f"concept_{name}.svg")
        with open(path, "w") as fh:
            fh.write(fn())
        print("wrote", path)


if __name__ == "__main__":
    main()
