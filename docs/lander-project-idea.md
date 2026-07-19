# Lunar Lander Project — Notes

## Concept

A 2D lunar lander game rendered with Skia4Delphi. Physics-based flight with gravity, thrust, rotation, and fuel management. Multiple craft profiles and worlds for variety.

## Platform

- Delphi CE (12.2), Windows, VCL
- Skia4Delphi for all rendering (two TSkPaintBox surfaces, same pattern as AntSim)
- Vector paths for craft and terrain (resolution-independent, rotatable)

## Core Physics

Simple Newtonian:
- Position (x, y) as floats
- Velocity (vx, vy) as floats
- Gravity: constant downward force per tick (varies by world)
- Thrust: applied in lander's facing direction when engine fires
- Fuel: depletes while thrusting, no fuel = no thrust

Each tick:
```
vy := vy + gravity
if thrusting and (fuel > 0) then begin
  vx := vx + cos(angle) * thrustPower
  vy := vy + sin(angle) * thrustPower  // sin is negative when pointing up
  fuel := fuel - burnRate
end
x := x + vx
y := y + vy
```

## Rotation (RCS Model)

Angular velocity based, with RCS fuel as a separate consumable:
- `angularVel`: persists between ticks, no damping (space — no friction)
- Left/right input applies a fixed angular acceleration and costs RCS fuel
- RCS fuel is limited and independent from main thruster fuel
- Run out of RCS = stuck with whatever spin you have (can't correct)

```
if rotatingLeft and (rcsFuel > 0) then begin
  angularVel := angularVel - rcsThrust;
  rcsFuel := rcsFuel - rcsBurnRate;
end;
if rotatingRight and (rcsFuel > 0) then begin
  angularVel := angularVel + rcsThrust;
  rcsFuel := rcsFuel - rcsBurnRate;
end;
angle := angle + angularVel;
```

No real torque-from-offset physics — the consumable resource is the gameplay hook,
not mechanical fidelity. Player feels the inertia (must counter-rotate to stop)
and pays for every correction.

**Visual:** tiny translucent puffs at hull edges when RCS fires. Doesn't need to
be geometrically accurate — just enough feedback to feel like jets are puffing.

**Two-resource tension:**
- Main fuel = vertical/lateral survival
- RCS fuel = rotational control
- Different consequences when each runs out, different panic moments

## Landing / Crashing

- Terrain is a polyline (array of TPointF segments)
- Flat pads are designated segments (drawn differently)
- Landing success: speed below threshold AND angle within tolerance AND on a pad
- Crash: any terrain contact that doesn't meet landing criteria
- Smaller pads = more points

## Controls

- Left/Right arrows: RCS rotation (angular velocity + fuel cost)
- Up arrow (or Space): main thrust (binary on/off — no throttle for simplicity)
- G: toggle landing gear (craft with retractable gear)
- T: toggle SAS (craft with stability assist)

## Window Layout

Two layout states, switched when scenes change:

**Full-window mode** (menu scene):
- Panel hidden, flight surface fills the entire window
- Used for title screen / menu — maximum canvas for eye candy

**Panel + flight mode** (play and result scenes):
- Left: control panel (fixed width, ~200-250px)
- Right: flight view (maintains 3:2 aspect ratio, letterboxed if needed)
- Panel appears after menu fades out; stays visible through result scene

Layout changes always happen through a black frame (fade out → reconfigure → new
scene appears). No cross-fading between different geometries.

## Visual Design — Flight View

- Black background (space)
- Starfield via SkSL fragment shader (procedural stars with twinkling, resolution-independent)
- White/gray terrain polyline
- Lander as a vector path (ISkPath) — rotated/translated each frame
- Thrust plume: simple Skia draws — semi-transparent triangles/circles below nozzle, flickering size
- RCS puffs: small translucent dots/lines at hull edges when rotating
- No HUD in the flight view — all gauges live on the control panel
- V2: replace plumes with SkSL shaders for procedural turbulent flame

## Control Panel

A second TSkPaintBox on the left side of the window. Displays craft instruments
and systems. Reads craft state each frame and renders gauges/indicators — no
physics knowledge, just visualization.

**Background:** a static bitmap (brushed metal, dark composite, etc.) drawn first,
instruments render on top. Could vary per craft in V2 for different cockpit feels.

**Instrument widget pattern:**

```
TInstrument = class
  Bounds: TRectF;
  procedure Render(ACanvas: ISkCanvas; AState: TLanderState); virtual; abstract;
end;
```

Each craft profile defines which instruments appear and their layout. The panel
renderer iterates the list and draws each one.

**V1 instruments:**
- Fuel gauge (vertical bar)
- RCS gauge (vertical bar)
- Velocity indicator (numeric or needle)
- Altimeter (height above nearest terrain)
- Attitude indicator (current angle / horizon line)

**Craft-specific systems (displayed as panel switches/indicators):**
- **SAS (stability assist):** auto-damps angular velocity toward zero when active.
  Still costs RCS fuel, just does it automatically. Toggle hotkey. Some craft have
  it, some don't. Panel shows on/off light.
- **Retractable gear:** boolean state, must be deployed before landing. Landing
  with gear retracted = crash even if speed/angle are fine. Toggle hotkey. Panel
  shows deployed/retracted indicator.
- More systems can be added per craft without changing the core physics.

**Panel visibility:**
- Hidden during menu scene (full-window mode)
- Visible during play and result scenes
- During result: gauges freeze at moment of landing/crash — satisfying to see
  "I had *that* much fuel left"

## Craft Profiles

```
TCraftProfile = record
  Name: string;
  HullPath: ISkPath;
  ThrustOffset: TPointF;
  Mass: Single;
  ThrustPower: Single;
  FuelCapacity: Single;
  BurnRate: Single;
  RCSFuelCapacity: Single;
  RCSBurnRate: Single;
  RCSThrust: Single;
  HullColor: TAlphaColor;
  PlumeColor: TAlphaColor;
  HasSAS: Boolean;
  HasRetractableGear: Boolean;
  Instruments: array of TInstrument;  // what shows on the panel for this craft
end;
```

Different craft = different handling feel. Heavy + powerful vs light + nimble.
RCS parameters per craft too — some spin easily, some are sluggish to rotate.
Craft-specific systems (SAS, gear) add variety without changing core physics.

## World Profiles

```
TWorldProfile = record
  Name: string;
  Gravity: Single;
  Terrain: array of TPointF;
  Pads: array of TPad;  // start/end index into terrain + point value
  Wind: Single;         // optional horizontal force
end;
```

Moon = low gravity, Mars = medium + wind, asteroid = very low gravity but tight caves.

## Gameplay Loop

1. Show world name + craft
2. Lander starts at top of screen with initial velocity (maybe slight drift)
3. Player navigates to a pad
4. Land successfully = score + next level
5. Crash = explosion effect, retry (3 lives per level)
6. Fuel or RCS runs out = helpless drift/spin, dramatic tension

## MVP Scope (V1)

1. Scene system (manager + fade transitions + layout switching)
2. Title/menu screen with craft/mission selection and autopilot demo background
3. Control panel (second surface, instrument widgets, craft-specific systems)
4. One craft, one world (the moon) — UI supports more, content is V2
5. Physics tick loop (gravity + thrust + RCS rotation)
6. Terrain rendered as polyline (hand-crafted, fixed camera, 3:2 flight view)
7. One or two landing pads
8. Collision detection (line segment intersection)
9. Landing success/failure check (including gear-deployed check)
10. Panel instruments: fuel, RCS, velocity, altimeter, attitude
11. At least one craft system (SAS or retractable gear) to prove the pattern
12. Basic scoring
13. 3 lives per level

## V2 Ideas

- Multiple worlds with different gravity/terrain
- Multiple craft to choose from
- Scrolling terrain (world larger than screen)
- SkSL shader plumes (procedural turbulent flame for main engine and RCS)
- Particle explosion on crash
- Parallax starfield (shader-based depth layers with scroll offset)
- Cave levels (ceiling collision)
- Fuel pickups / RCS pickups
- Wind gusts (random or constant per world)
- Ghost replay of best run
- Sound effects
- Procedurally generated terrain
- Real torque-from-offset RCS (thruster placement matters per craft)

## Scene System

The game uses a scene manager pattern. The form hosts the two paint boxes and a
timer — it's a dumb shell. All logic and rendering is owned by scene classes.
The scene manager controls layout mode (full-window vs panel+flight).

**Base scene class:**

```
TSceneID = (sidMenu, sidPlay, sidResult);

TGameScene = class
  Finished: Boolean;
  NextSceneID: TSceneID;
  procedure HandleInput(var Key: Word; Shift: TShiftState); virtual; abstract;
  procedure Tick; virtual; abstract;
  procedure Render(ACanvas: ISkCanvas; AWidth, AHeight: Single); virtual; abstract;
end;
```

**Scene manager:**

```
TSceneManager = class
  CurrentScene: TGameScene;
  procedure Tick;
  procedure Render(ACanvas: ISkCanvas; AWidth, AHeight: Single);
  procedure HandleInput(var Key: Word; Shift: TShiftState);
end;
```

**Scenes own their exits (and entrances):**
- Each scene handles its own exit animation internally (fade to black, instant cut, etc.)
- Scene only sets `Finished := True` once it's fully done (rendering black/nothing)
- Scene manager just checks the flag, destroys old scene, reconfigures layout, creates new scene
- No transition state machine or alpha tracking in the manager
- Incoming scenes own their entrance too (fade in, or just appear immediately)

**Specific transitions:**
- Menu → Play: menu fades itself to black → signals Finished → manager shows panel,
  resizes flight view → play scene starts immediately (no fade-in)
- Play → Result: play signals Finished instantly (no exit anim) → result takes over,
  panel stays with frozen gauges
- Result → Menu: result fades itself to black → signals Finished → manager hides
  panel, resizes flight view → menu fades itself in

**V1 scenes:**
- `TMenuScene` — title screen, mission/craft selection, background eye candy
- `TPlayScene` — the gameplay (physics, terrain, landing/crash)
- `TResultScene` — outcome summary, retry / next / back to menu

**Menu screen eye candy:**

The title screen runs a little autopilot demo — picks a random craft profile, gives
it a random starting state, lets physics run. If it drifts off-screen or crashes,
spawn a new one. Same physics code as gameplay, zero extra logic. Cycles through
available craft so the player sees what's on offer.

## Architecture (from AntSim learnings)

- Scene manager owns the lifecycle; form is just a host
- Sim tick separate from render (same Timer + Redraw pattern)
- Physics engine doesn't know about drawing
- Craft state is a record (position, velocity, angle, angularVel, fuel, rcsFuel, alive)
- Renderer reads craft state + terrain and draws
- Input handled at frame level, forwarded to active scene
- No defensive code in physics core (same style as AntSim)

## Decisions Made

- **Terrain:** Fixed/hand-crafted per level (procgen is V2)
- **Camera:** Fixed view of whole terrain (scrolling is V2)
- **Rotation:** Angular velocity with RCS fuel cost (not instant, not free)
- **Lives:** 3 attempts per level
- **Coordinate system:** Angle 0 = pointing up, Skia Y-axis points down — be deliberate about sign conventions from the start
- **Screen management:** Scene manager handles layout switching; scenes own their own exit/entrance animations
- **Scene lifecycle:** Scene runs its exit animation internally, sets Finished flag only when fully black. Manager detects flag on tick and safely tears down/swaps. No self-destruction problem, no transition state machine in manager.
- **Display surfaces:** Two TSkPaintBox — panel (left, fixed width) + flight view (right, 3:2 aspect)
- **Layout modes:** Full-window (menu) vs panel+flight (play/result); transitions go through black when layout changes
- **HUD location:** All gauges/instruments on the control panel, not overlaid on flight view
- **Flight view aspect ratio:** 3:2 (good vertical space for descent gameplay)
- **Panel during result:** stays visible with frozen gauges (no layout thrash)
