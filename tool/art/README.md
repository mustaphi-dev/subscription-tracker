# Brand and onboarding art

Everything here is generated from code: no AI image or video tools.

## Logo and app icons

`rib2d.py` draws the mark: a two-sided ribbon (lavender `#C4B5FF` one side, violet
`#6236FF` the other) closed into a loop with one half twist, seen from a fixed angle,
filled flat with a painter's algorithm. `make_flat_icons.py` turns it into every icon:

    pip install numpy pillow scipy
    python3 tool/art/make_flat_icons.py .

It writes `assets/brand/{icon,mark}.webp`, the iOS AppIcon set and the Android
launcher icons (legacy + adaptive layers). The splash draws the same ribbon live in
`lib/ribbon.dart`; keep the shape and view constants in step if the mark changes.
Native launch screens are background colour only, so the splash can tie the ribbon
without a jump.

## Onboarding loops

Rendered headless with Blender's Python module (`pip install bpy==5.2.3`, Python
3.13), Cycles on CPU with a transparent film, 960×1280 at 24 fps. Frames are seamless
loops (frame N+1 equals frame 1).

    python ribbon2.py   -- --w 960 --h 1280 --n 216 --samples 48 --top 1 --out frames/renewals
    python hourglass.py -- --w 960 --h 1280 --n 144 --samples 56 --out frames/trials
    python coin.py      -- --w 960 --h 1280 --n 120 --samples 64 --out frames/shortfalls

    ./encode.sh frames/renewals   renewals   '#0B0A15' '#231A4A'
    ./encode.sh frames/trials     trials     '#1E0A07' '#4A1A0C'
    ./encode.sh frames/shortfalls shortfalls '#160708' '#3F0E10'

`common.py` holds the shared scene helpers (materials, lights, studio world, camera,
render loop). Rendering skips frames that already exist, so an interrupted run can be
restarted with the same command. Expect roughly 15–40 s per frame on 4 CPU cores.
