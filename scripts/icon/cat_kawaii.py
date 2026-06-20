#!/usr/bin/env python3
"""Generate a cuter Siamese-cat icon concept for Duo Updater.

Design goals:
- unmistakably a cat
- more rounded and friendly
- flat/vector feel, no AI-rendered texture
- keep Duo Updater's blue refresh motif in the background
"""

import math
import os

OUT = os.path.join(os.path.dirname(__file__), "out")
os.makedirs(OUT, exist_ok=True)

CANVAS = 1024
CX = CANVAS / 2
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
  <stop offset="0" stop-color="#233047"/>
  <stop offset="1" stop-color="#121927"/>
</linearGradient>
<radialGradient id="glow" cx="0.28" cy="0.16" r="0.95">
  <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.15"/>
  <stop offset="0.35" stop-color="#8DB3FF" stop-opacity="0.06"/>
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
<linearGradient id="cream" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" stop-color="#F9EDD8"/>
  <stop offset="1" stop-color="#E9D3AB"/>
</linearGradient>
<linearGradient id="point" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" stop-color="#63493A"/>
  <stop offset="1" stop-color="#402F25"/>
</linearGradient>
<linearGradient id="innerEar" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" stop-color="#E0B5AF"/>
  <stop offset="1" stop-color="#CC968F"/>
</linearGradient>
<linearGradient id="eye" x1="0" y1="0" x2="1" y2="1">
  <stop offset="0" stop-color="#87E5FF"/>
  <stop offset="1" stop-color="#39A0FF"/>
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
    r = 248
    sw = 82
    head = 64
    arc1 = arc_path(CX, CX, r, 214, 22)
    arc2 = arc_path(CX, CX, r, 34, 198)
    h1 = arrowhead(CX, CX, r, 22, head, tangent_cw=False)
    h2 = arrowhead(CX, CX, r, 198, head, tangent_cw=False)
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
  <path d="M 332 456 C 302 378 306 296 360 238 C 390 206 420 216 432 272 C 444 334 434 396 410 454 Z" fill="url(#point)"/>
  <path d="M 692 456 C 722 378 718 296 664 238 C 634 206 604 216 592 272 C 580 334 590 396 614 454 Z" fill="url(#point)"/>
  <path d="M 362 430 C 352 366 362 314 390 274 C 406 252 420 270 424 318 C 428 358 422 394 410 428 Z" fill="url(#innerEar)"/>
  <path d="M 662 430 C 672 366 662 314 634 274 C 618 252 604 270 600 318 C 596 358 602 394 614 428 Z" fill="url(#innerEar)"/>

  <path d="M 512 366
    C 626 342 714 402 744 506
    C 770 594 752 688 684 752
    C 634 800 566 824 512 824
    C 458 824 390 800 340 752
    C 272 688 254 594 280 506
    C 310 402 398 342 512 366 Z"
    fill="url(#cream)" stroke="#FFF8EA" stroke-opacity="0.16" stroke-width="4"/>

  <path d="M 512 470
    C 556 470 594 498 612 546
    C 628 596 626 666 604 722
    C 582 758 442 758 420 722
    C 398 666 396 596 412 546
    C 430 498 468 470 512 470 Z"
    fill="url(#point)" opacity="0.96"/>

  <path d="M 346 544
    Q 430 488 502 536
    Q 430 590 346 566
    Q 328 556 346 544 Z" fill="url(#eye)"/>
  <path d="M 678 544
    Q 594 488 522 536
    Q 594 590 678 566
    Q 696 556 678 544 Z" fill="url(#eye)"/>

  <ellipse cx="426" cy="548" rx="13" ry="38" fill="#192433"/>
  <ellipse cx="598" cy="548" rx="13" ry="38" fill="#192433"/>
  <circle cx="412" cy="528" r="10" fill="#ffffff" opacity="0.96"/>
  <circle cx="584" cy="528" r="10" fill="#ffffff" opacity="0.96"/>

  <path d="M 512 624
    C 534 624 548 636 544 650
    C 538 664 522 676 512 684
    C 502 676 486 664 480 650
    C 476 636 490 624 512 624 Z" fill="#CC8794"/>

  <path d="M 512 684 L 512 712" stroke="#3A2A20" stroke-width="7" stroke-linecap="round"/>
  <path d="M 512 712 C 496 726 472 726 454 712" stroke="#3A2A20" stroke-width="7" fill="none" stroke-linecap="round"/>
  <path d="M 512 712 C 528 726 552 726 570 712" stroke="#3A2A20" stroke-width="7" fill="none" stroke-linecap="round"/>

  <path d="M 418 652 Q 320 634 210 614" stroke="#ffffff" stroke-opacity="0.76" stroke-width="6" fill="none" stroke-linecap="round"/>
  <path d="M 418 678 Q 316 688 196 686" stroke="#ffffff" stroke-opacity="0.68" stroke-width="6" fill="none" stroke-linecap="round"/>
  <path d="M 606 652 Q 704 634 814 614" stroke="#ffffff" stroke-opacity="0.76" stroke-width="6" fill="none" stroke-linecap="round"/>
  <path d="M 606 678 Q 708 688 828 686" stroke="#ffffff" stroke-opacity="0.68" stroke-width="6" fill="none" stroke-linecap="round"/>
</g>
"""


def build():
    body = squircle() + arrows() + cat()
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" '
        f'width="1024" height="1024"><defs>{defs()}</defs>{body}</svg>'
    )


def main():
    path = os.path.join(OUT, "cat_kawaii.svg")
    with open(path, "w") as fh:
        fh.write(build())
    print("wrote", path)


if __name__ == "__main__":
    main()
