# Brand and onboarding art

Everything here is generated from code: no AI image or video tools. The 3D scenes are
rendered headless with Blender's Python module (`pip install bpy==5.2.3`, Python 3.13)
using Cycles on the CPU with a transparent film. The post steps need
`pip install numpy pillow scipy` and `ffmpeg`.

## App icon and splash mark

The Wince W is pure vector geometry, in `wince/`. `wince_logo.py` builds it with shapely:
four slanted strokes, with both outer legs cut away from the middle on a curved arc
that starts at the elbow, so each leg ends in a knife edge. The bevel is a chamfer
whose facets are shaded by a light at the top left. `render.js` rasterises the SVGs with
the preinstalled Playwright Chromium.

    pip install shapely pillow
    python3 wince/make_w_icons.py ../..

`make_w_icons.py` writes `assets/brand/icon.webp` (light) and `icon_dark.webp`, the iOS
AppIcon set (single size, with light, dark and tinted appearances), and the Android
launcher icons (legacy, plus adaptive foreground, background and monochrome). It also
writes `assets/brand/w_left.webp`, `w_middle.webp` and `w_right.webp`, the white W in
three layers on one square canvas, which the splash animates. Native launch screens are
background colour only, so the splash starts from a dark screen.

## The stage

Every onboarding page and the sign-in screens share one backdrop, built by `stage.py`:
violet light falling from the top left into `#07080C` (the app's `kBg`), a soft pool of
light behind the object, and a few large, faint isometric blocks. It is measured in
frame widths, so every 960-wide frame lines up when the app shows it full width and top
aligned (`lib/stage.dart`). The bare plate is the app's backdrop:

    python3 stage.py --plate ../../assets/onboarding/stage.jpg

The scenes render on a transparent film; `encode.sh` puts each frame on the stage,
adds bloom, and writes the loop and its first frame to `assets/onboarding/`.

## Onboarding and sign-in loops

These are seamless loops at 960×1280 and 24 fps (frame N+1 equals frame 1). All the
light in them is the stage's violet; the only other colour is the red cut in the coin.

    python hourglass.py  -- --w 960 --h 1280 --n 144 --samples 56 --out frames/trials
    python infinity.py   -- --w 960 --h 1280 --n 144 --samples 48 --dist 11.6 --cstr 11 --out frames/renewals
    python coin.py       -- --w 960 --h 1280 --n 120 --samples 64 --out frames/shortfalls
    python wince/w3d.py  -- --w 960 --h 1200 --n 120 --samples 48 --out frames/signin

    PY=python3 ./encode.sh frames/trials     trials --sat 2.0 --dy 0.06
    PY=python3 ./encode.sh frames/renewals   renewals
    PY=python3 ./encode.sh frames/shortfalls shortfalls
    PY=python3 ./encode.sh frames/signin     signin

The hourglass sand glows violet. AgX mutes saturated violets toward pastel, so its
frames get `--sat 2.0`, a chroma boost on the object before it goes on the stage.
`--dy 0.06` sits the hourglass 6% of the frame lower. Only the object moves, so the
stage behind it still lines up with every other page.

The sign-in W is extruded from the same `wince_logo.glyph()` geometry as the icon, in
black lacquer with violet rim light. It sways slowly, and once per loop the cut legs
ease out along their slant and settle back. Its frames are 1200 tall; the stage fills
the rest of the 1280.

`common.py` holds the shared scene helpers: materials, lights, studio world, camera and
the render loop. Rendering skips frames that already exist, so you can restart an
interrupted run with the same command. Expect roughly 15–40 s per frame on 4 CPU cores.
For look tests, `BORDER=x0,y0,x1,y1` (fractions, y from the bottom) renders just that
window.
