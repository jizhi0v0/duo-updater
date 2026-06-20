#!/usr/bin/env python3
"""Generate a restrained Siamese-cat app icon concept for Duo Updater.

This version intentionally avoids the "AI render" look:
- simple geometry
- limited palette
- subtle gradients only
- no fur, photo lighting, or glossy glass treatment
"""

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


def squircle():
    return (
        f'<rect x="{BODY_INSET}" y="{BODY_INSET}" width="{BODY}" height="{BODY}" '
        f'rx="{RX}" ry="{RX}" fill="url(#bg)"/>'
        f'<rect x="{BODY_INSET}" y="{BODY_INSET}" width="{BODY}" height="{BODY}" '
        f'rx="{RX}" ry="{RX}" fill="url(#noiseGlow)"/>'
        f'<rect x="{BODY_INSET + 2}" y="{BODY_INSET + 2}" width="{BODY - 4}" height="{BODY - 4}" '
        f'rx="{RX - 2}" ry="{RX - 2}" fill="none" stroke="url(#rim)" stroke-width="4"/>'
    )


def defs():
    return """
<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" stop-color="#233047"/>
  <stop offset="1" stop-color="#121927"/>
</linearGradient>
<radialGradient id="noiseGlow" cx="0.28" cy="0.16" r="0.95">
  <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.16"/>
  <stop offset="0.35" stop-color="#8DB3FF" stop-opacity="0.07"/>
  <stop offset="1" stop-color="#000000" stop-opacity="0"/>
</radialGradient>
<linearGradient id="rim" x1="0" y1="0" x2="1" y2="1">
  <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.16"/>
  <stop offset="1" stop-color="#3C5C89" stop-opacity="0.28"/>
</linearGradient>
<linearGradient id="arrowA" x1="0" y1="0" x2="1" y2="1">
  <stop offset="0" stop-color="#68E5F5"/>
  <stop offset="1" stop-color="#2788FF"/>
</linearGradient>
<linearGradient id="arrowB" x1="0" y1="0" x2="1" y2="1">
  <stop offset="0" stop-color="#2A8EFF"/>
  <stop offset="1" stop-color="#1955D6"/>
</linearGradient>
<linearGradient id="face" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" stop-color="#F7E8CC"/>
  <stop offset="1" stop-color="#E6D0A8"/>
</linearGradient>
<linearGradient id="point" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" stop-color="#5B4436"/>
  <stop offset="1" stop-color="#34261F"/>
</linearGradient>
<linearGradient id="innerEar" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" stop-color="#DDB0A9"/>
  <stop offset="1" stop-color="#C8938D"/>
</linearGradient>
<linearGradient id="eye" x1="0" y1="0" x2="1" y2="1">
  <stop offset="0" stop-color="#8BE7FF"/>
  <stop offset="1" stop-color="#318DFF"/>
</linearGradient>
"""


def arrows():
    r = 254
    sw = 86
    head = 68
    arc1 = arc_path(CX, CY, r, 214, 20)
    arc2 = arc_path(CX, CY, r, 32, 198)
    h1 = arrowhead(CX, CY, r, 20, head, tangent_cw=False)
    h2 = arrowhead(CX, CY, r, 198, head, tangent_cw=False)
    return (
        f'<g>'
        f'<path d="{arc1}" stroke="url(#arrowA)" stroke-width="{sw}" fill="none" stroke-linecap="round"/>'
        f'<path d="{arc2}" stroke="url(#arrowB)" stroke-width="{sw}" fill="none" stroke-linecap="round"/>'
        f'<path d="{h1}" fill="url(#arrowA)"/>'
        f'<path d="{h2}" fill="url(#arrowB)"/>'
        f'</g>'
    )


def cat():
    return """
<g>
  <path d="M 286 470 C 250 360 250 250 300 196 C 330 250 410 330 470 392 Z" fill="url(#point)"/>
  <path d="M 738 470 C 774 360 774 250 724 196 C 694 250 614 330 554 392 Z" fill="url(#point)"/>
  <path d="M 320 420 C 300 350 302 290 326 256 C 344 300 386 350 424 392 Z" fill="url(#innerEar)"/>
  <path d="M 704 420 C 724 350 722 290 698 256 C 680 300 638 350 600 392 Z" fill="url(#innerEar)"/>

  <path d="M 512 360
    C 640 330 712 372 742 470
    C 772 568 760 660 690 728
    C 630 786 565 812 512 812
    C 459 812 394 786 334 728
    C 264 660 252 568 282 470
    C 312 372 384 330 512 360 Z"
    fill="url(#face)" stroke="#FFF7E8" stroke-opacity="0.16" stroke-width="4"/>

  <path d="M 512 470
    C 556 470 588 520 596 580
    C 616 640 624 700 600 742
    C 566 786 458 786 424 742
    C 400 700 408 640 428 580
    C 436 520 468 470 512 470 Z"
    fill="url(#point)" opacity="0.95"/>

  <path d="M 336 454 C 308 514 304 632 332 706 C 348 748 372 780 404 806"
    stroke="#09111D" stroke-opacity="0.22" stroke-width="10" fill="none" stroke-linecap="round"/>
  <path d="M 688 454 C 716 514 720 632 692 706 C 676 748 652 780 620 806"
    stroke="#09111D" stroke-opacity="0.22" stroke-width="10" fill="none" stroke-linecap="round"/>

  <path d="M 336 544
    Q 420 478 504 534
    Q 430 590 336 564
    Q 320 556 336 544 Z" fill="url(#eye)"/>
  <path d="M 688 544
    Q 604 478 520 534
    Q 594 590 688 564
    Q 704 556 688 544 Z" fill="url(#eye)"/>

  <ellipse cx="430" cy="552" rx="13" ry="40" fill="#182331"/>
  <ellipse cx="594" cy="552" rx="13" ry="40" fill="#182331"/>
  <circle cx="418" cy="528" r="10" fill="#ffffff" opacity="0.96"/>
  <circle cx="582" cy="528" r="10" fill="#ffffff" opacity="0.96"/>

  <path d="M 512 612
    C 540 612 552 626 540 644
    C 532 656 520 666 512 672
    C 504 666 492 656 484 644
    C 472 626 484 612 512 612 Z" fill="#C7858E"/>

  <path d="M 512 672 L 512 700" stroke="#3A2A20" stroke-width="7" stroke-linecap="round"/>
  <path d="M 512 700 C 492 724 456 724 442 706" stroke="#3A2A20" stroke-width="7" fill="none" stroke-linecap="round"/>
  <path d="M 512 700 C 532 724 568 724 582 706" stroke="#3A2A20" stroke-width="7" fill="none" stroke-linecap="round"/>

  <path d="M 596 650 Q 710 620 824 612" stroke="#ffffff" stroke-opacity="0.78" stroke-width="6" fill="none" stroke-linecap="round"/>
  <path d="M 596 672 Q 716 686 836 686" stroke="#ffffff" stroke-opacity="0.72" stroke-width="6" fill="none" stroke-linecap="round"/>
  <path d="M 428 650 Q 314 620 200 612" stroke="#ffffff" stroke-opacity="0.78" stroke-width="6" fill="none" stroke-linecap="round"/>
  <path d="M 428 672 Q 308 686 188 686" stroke="#ffffff" stroke-opacity="0.72" stroke-width="6" fill="none" stroke-linecap="round"/>
</g>
"""


def build():
    body = squircle()
    body += arrows()
    body += cat()
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" '
        f'width="1024" height="1024"><defs>{defs()}</defs>{body}</svg>'
    )


def main():
    path = os.path.join(OUT, "cat_mark.svg")
    with open(path, "w") as fh:
        fh.write(build())
    print("wrote", path)


if __name__ == "__main__":
    main()
