#!/usr/bin/env python3
"""Generate a cute cat-head silhouette icon concept for Duo Updater."""

import math
import os

OUT = os.path.join(os.path.dirname(__file__), "out")
os.makedirs(OUT, exist_ok=True)

CANVAS = 1024
CX = CANVAS / 2
CY = CANVAS / 2
BODY_INSET = 100
BODY = CANVAS - 2 * BODY_INSET
RX = round(BODY * 0.2237)


def f(v):
    return f"{v:.2f}"


def pt(cx, cy, r, ang_deg):
    a = math.radians(ang_deg - 90)
    return (cx + r * math.cos(a), cy + r * math.sin(a))


def arc_path(cx, cy, r, a0, a1):
    x0, y0 = pt(cx, cy, r, a0)
    x1, y1 = pt(cx, cy, r, a1)
    large = 1 if abs(a1 - a0) > 180 else 0
    sweep = 1 if a1 > a0 else 0
    return f"M {f(x0)} {f(y0)} A {r} {r} 0 {large} {sweep} {f(x1)} {f(y1)}"


def arrowhead(cx, cy, r, ang, size, tangent_cw=True):
    tip_ang = ang + (size / r) * (180 / math.pi) * (1 if tangent_cw else -1)
    tip = pt(cx, cy, r, tip_ang)
    outer = pt(cx, cy, r + size * 0.95, ang)
    inner = pt(cx, cy, r - size * 0.95, ang)
    return (
        f"M {f(tip[0])} {f(tip[1])} "
        f"L {f(outer[0])} {f(outer[1])} "
        f"L {f(inner[0])} {f(inner[1])} Z"
    )


def defs():
    return """
<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" stop-color="#243149"/>
  <stop offset="1" stop-color="#101722"/>
</linearGradient>
<radialGradient id="glow" cx="0.28" cy="0.14" r="0.95">
  <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.15"/>
  <stop offset="0.35" stop-color="#A7C3FF" stop-opacity="0.06"/>
  <stop offset="1" stop-color="#000000" stop-opacity="0"/>
</radialGradient>
<linearGradient id="rim" x1="0" y1="0" x2="1" y2="1">
  <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.14"/>
  <stop offset="1" stop-color="#3C5C89" stop-opacity="0.26"/>
</linearGradient>
<linearGradient id="arrowA" x1="0" y1="0" x2="1" y2="1">
  <stop offset="0" stop-color="#6DECF7"/>
  <stop offset="1" stop-color="#2D93FF"/>
</linearGradient>
<linearGradient id="arrowB" x1="0" y1="0" x2="1" y2="1">
  <stop offset="0" stop-color="#2F95FF"/>
  <stop offset="1" stop-color="#1A5BE0"/>
</linearGradient>
<linearGradient id="cream" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" stop-color="#FAEED9"/>
  <stop offset="1" stop-color="#E9D2AA"/>
</linearGradient>
<linearGradient id="point" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" stop-color="#684C3C"/>
  <stop offset="1" stop-color="#402F25"/>
</linearGradient>
<linearGradient id="eye" x1="0" y1="0" x2="1" y2="1">
  <stop offset="0" stop-color="#9BEAFF"/>
  <stop offset="1" stop-color="#40A4FF"/>
</linearGradient>
"""


def squircle():
    return (
        f'<rect x="{BODY_INSET}" y="{BODY_INSET}" width="{BODY}" height="{BODY}" '
        f'rx="{RX}" ry="{RX}" fill="url(#bg)"/>'
        f'<rect x="{BODY_INSET}" y="{BODY_INSET}" width="{BODY}" height="{BODY}" '
        f'rx="{RX}" ry="{RX}" fill="url(#glow)"/>'
        f'<rect x="{BODY_INSET + 2}" y="{BODY_INSET + 2}" width="{BODY - 4}" height="{BODY - 4}" '
        f'rx="{RX - 2}" ry="{RX - 2}" fill="none" stroke="url(#rim)" stroke-width="4"/>'
    )


def arrows():
    r = 250
    sw = 84
    head = 66
    arc1 = arc_path(CX, CY, r, 216, 24)
    arc2 = arc_path(CX, CY, r, 36, 198)
    h1 = arrowhead(CX, CY, r, 24, head, tangent_cw=False)
    h2 = arrowhead(CX, CY, r, 198, head, tangent_cw=False)
    return (
        f'<g opacity="0.98">'
        f'<path d="{arc1}" stroke="url(#arrowA)" stroke-width="{sw}" fill="none" stroke-linecap="round"/>'
        f'<path d="{arc2}" stroke="url(#arrowB)" stroke-width="{sw}" fill="none" stroke-linecap="round"/>'
        f'<path d="{h1}" fill="url(#arrowA)"/>'
        f'<path d="{h2}" fill="url(#arrowB)"/>'
        f'</g>'
    )


def cat():
    return """
<g>
  <path d="
    M 512 316
    C 548 278 586 236 622 220
    C 668 238 694 304 692 382
    C 744 418 776 486 776 572
    C 776 714 672 816 512 824
    C 352 816 248 714 248 572
    C 248 486 280 418 332 382
    C 330 304 356 238 402 220
    C 438 236 476 278 512 316 Z"
    fill="url(#cream)" stroke="#FFF7E8" stroke-opacity="0.16" stroke-width="4"/>

  <path d="M 360 378
    C 358 320 376 274 408 248
    C 430 264 458 298 486 340
    C 452 350 408 364 360 378 Z"
    fill="url(#point)"/>
  <path d="M 664 378
    C 666 320 648 274 616 248
    C 594 264 566 298 538 340
    C 572 350 616 364 664 378 Z"
    fill="url(#point)"/>

  <path d="
    M 512 452
    C 560 452 602 474 624 514
    C 644 554 646 618 632 676
    C 612 730 568 768 512 788
    C 456 768 412 730 392 676
    C 378 618 380 554 400 514
    C 422 474 464 452 512 452 Z"
    fill="url(#point)" opacity="0.95"/>

  <circle cx="420" cy="536" r="58" fill="url(#cream)" opacity="0.98"/>
  <circle cx="604" cy="536" r="58" fill="url(#cream)" opacity="0.98"/>
  <ellipse cx="420" cy="538" rx="34" ry="24" fill="url(#eye)"/>
  <ellipse cx="604" cy="538" rx="34" ry="24" fill="url(#eye)"/>
  <ellipse cx="420" cy="538" rx="9" ry="20" fill="#192433"/>
  <ellipse cx="604" cy="538" rx="9" ry="20" fill="#192433"/>
  <circle cx="410" cy="526" r="8" fill="#ffffff" opacity="0.96"/>
  <circle cx="594" cy="526" r="8" fill="#ffffff" opacity="0.96"/>

  <path d="
    M 512 618
    C 532 618 546 628 544 642
    C 536 654 522 666 512 674
    C 502 666 488 654 480 642
    C 478 628 492 618 512 618 Z"
    fill="#D28B98"/>

  <path d="M 512 674 L 512 698" stroke="#3A2A20" stroke-width="7" stroke-linecap="round"/>
  <path d="M 512 698 C 498 710 480 712 462 702" stroke="#3A2A20" stroke-width="7" fill="none" stroke-linecap="round"/>
  <path d="M 512 698 C 526 710 544 712 562 702" stroke="#3A2A20" stroke-width="7" fill="none" stroke-linecap="round"/>

  <path d="M 430 654 Q 332 634 236 620" stroke="#ffffff" stroke-opacity="0.74" stroke-width="6" fill="none" stroke-linecap="round"/>
  <path d="M 430 680 Q 326 690 220 690" stroke="#ffffff" stroke-opacity="0.66" stroke-width="6" fill="none" stroke-linecap="round"/>
  <path d="M 594 654 Q 692 634 788 620" stroke="#ffffff" stroke-opacity="0.74" stroke-width="6" fill="none" stroke-linecap="round"/>
  <path d="M 594 680 Q 698 690 804 690" stroke="#ffffff" stroke-opacity="0.66" stroke-width="6" fill="none" stroke-linecap="round"/>
</g>
"""


def build():
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">'
        f'<defs>{defs()}</defs>{squircle()}{arrows()}{cat()}</svg>'
    )


def main():
    path = os.path.join(OUT, "cat_silhouette.svg")
    with open(path, "w") as fh:
        fh.write(build())
    print("wrote", path)


if __name__ == "__main__":
    main()
