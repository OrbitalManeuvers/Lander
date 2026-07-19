# Lunar Lander — Project Context

## Tech Stack

- **Language**: Object Pascal (Delphi CE 12.2 Athens)
- **UI Framework**: VCL (Windows)
- **Rendering**: Skia4Delphi (TSkPaintBox, ISkCanvas, ISkPath, ISkPaint, SkSL shaders)
- **No additional third-party packages**

## Project Structure

```
src/           — All source files (.pas, .dfm, .dpr, .dproj)
bin/           — Compiled output
dcu/           — Compiled units
docs/          — Project documentation
.kiro/specs/   — Feature specs
.kiro/steering/ — Steering documents (this folder)
```

## Architecture

- Scene manager pattern: main form is a dumb host (timer + two paint boxes + key forwarding)
- Two rendering surfaces: `PBFlight` (flight view, 3:2 aspect) and `PBPanel` (control panel, fixed 220px)
- Physics engine is pure calculation — no rendering, no input awareness
- Scenes own their own exit/entrance animations

## Key Conventions

- All new units added to `Lander.dpr` uses clause
- Compile target: Win32 (Debug and Release configurations)
- Coordinate system: angle 0 = up, positive angular velocity = clockwise, gravity = +Y (screen down)
- Game state uses `Single` precision throughout

## References

- Design doc: #[[file:.kiro/specs/lunar-lander/design.md]]
- Task list: #[[file:.kiro/specs/lunar-lander/tasks.md]]
