# Brand and onboarding art

Everything here is generated from code: no AI image or video tools. Scenes are
rendered headless with Blender's Python module (`pip install bpy==5.2.3`, Python 3.13)
using Cycles on the CPU with a transparent film. The post steps need
`pip install numpy pillow scipy` and `ffmpeg`.

## App icon and splash mark

`s_mark.py` builds the mark: a chrome S for Subtracker, made of the same grooved band as
the renewals infinity sign, with one half twist through its spine. A violet light runs in
the groove. Render it twice, with and without the light, and export the groove's path:

    python s_mark.py -- --size 1024 --samples 96 --twist 180 --span 0.6 --head 0.93 --lens 112 \
        --bw 0.46 --bt 0.13 --face 0.95 --ev -0.1 --glow 1 --name s_glow  --out out/
    python s_mark.py -- (same flags) --glow 0 --name s_plain --path out/s_path.json --out out/
    python3 make_s_icons.py out/s_glow.png out/s_plain.png out/s_path.json ../..

`make_s_icons.py` writes `assets/brand/icon.webp`, the iOS AppIcon set and the Android
launcher icons (legacy, plus adaptive foreground and background). It also writes
`assets/brand/mark.webp` (the S without its light) and `lib/brand_mark_path.dart` (the
groove path), which the splash uses to draw the light live. Native launch screens are
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
