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

## Onboarding loops

These are seamless loops at 960×1280 and 24 fps (frame N+1 equals frame 1).

    python infinity.py  -- --w 960 --h 1280 --n 144 --samples 48 --dist 11.6 --cstr 11 --out frames/renewals
    python hourglass.py -- --w 960 --h 1280 --n 144 --samples 56 --out frames/trials
    python coin.py      -- --w 960 --h 1280 --n 120 --samples 64 --out frames/shortfalls

    ./encode.sh frames/renewals   renewals   '#0B0A15' '#231A4A'
    ./encode.sh frames/trials     trials     '#1E0A07' '#4A1A0C'
    ./encode.sh frames/shortfalls shortfalls '#160708' '#3F0E10'

`common.py` holds the shared scene helpers: materials, lights, studio world, camera and
the render loop. Rendering skips frames that already exist, so you can restart an
interrupted run with the same command. Expect roughly 15–40 s per frame on 4 CPU cores.
