# Implementation Plan: Lunar Lander

## Overview

Implement a 2D physics-based lunar lander game using Delphi CE 12.2 (VCL) with Skia4Delphi for rendering. The architecture follows a scene manager pattern where the main form is a minimal host. Two TSkPaintBox surfaces provide rendering: a fixed-width control panel (left) and a 3:2 aspect-ratio flight view (right). Implementation proceeds from data models and core systems outward to scenes, rendering, and integration.

## Tasks

- [x] 1. Define data models and core interfaces
  - [x] 1.1 Create data model unit with TCraftState, TCraftProfile, TWorldProfile, TPad, and TLandingCriteria
    - Create `src/u_Models.pas` with all record/class definitions from the design
    - TCraftState as a record with fields: X, Y, VX, VY, Angle, AngularVel, Fuel, RCSFuel, Thrust, RotatingLeft, RotatingRight, GearDeployed, SASActive, Alive
    - TCraftProfile as a class with hull path, thrust/fuel params, system booleans, instruments array
    - TWorldProfile as a class with Name, Gravity, Terrain (array of TPointF), Pads (array of TPad)
    - TPad as a record with StartIndex, EndIndex, PointValue
    - TLandingCriteria as a record with MaxSpeed, MaxAngle, RequiresGear, MustBeOnPad
    - TSceneID enumeration (sidMenu, sidPlay, sidResult)
    - _References design: Data Models section_

  - [x] 1.2 Create base scene class and scene manager interface
    - Create `src/u_SceneBase.pas` with TGameScene abstract class
    - TGameScene must expose: Finished (Boolean), NextSceneID (TSceneID), HandleInput, Tick, Render, RenderPanel (virtual; empty default)
    - Create `src/u_SceneManager.pas` with TSceneManager class
    - TSceneManager holds CurrentScene reference, handles Tick/Render/HandleInput forwarding
    - TSceneManager handles layout mode switching (full-window vs panel+flight)
    - _References design: Scene System, Component 1_

- [x] 2. Implement physics engine
  - [x] 2.1 Create physics engine unit
    - Create `src/u_Physics.pas` with a procedure or class that takes TCraftState (var), TCraftProfile, TWorldProfile, and delta
    - Apply gravity: VY += Gravity
    - Apply thrust in facing direction scaled by Thrust level when Fuel > 0
    - Deplete fuel proportional to throttle: Fuel -= BurnRate × Thrust
    - Apply RCS angular acceleration when rotating and RCSFuel > 0
    - Deplete RCS fuel: RCSFuel -= RCSBurnRate per tick while rotating
    - Apply SAS auto-damping if SASActive and RCSFuel > 0 (costs RCS fuel)
    - Integrate angular velocity into angle
    - Integrate velocity into position
    - Clamp Fuel and RCSFuel at zero (Property 1)
    - Zero thrust effect when Fuel = 0 (Property 2)
    - Zero RCS effect when RCSFuel = 0 (Property 3)
    - _References design: Component 5, Correctness Properties 1–5_

  - [ ]* 2.2 Write property tests for fuel non-negativity
    - **Property 1: Fuel non-negativity**
    - Generate random craft states with varying fuel levels (including near-zero) and verify that after any physics tick, Fuel >= 0 and RCSFuel >= 0
    - **Validates: Design Property 1**

  - [ ]* 2.3 Write property tests for thrust/fuel dependency
    - **Property 2: No thrust without fuel**
    - Generate states where Fuel = 0 with Thrust > 0, verify velocity unchanged by thrust
    - **Property 2a: Thrust scales linearly**
    - Verify acceleration = ThrustPower × Thrust and fuel consumed = BurnRate × Thrust
    - **Validates: Design Properties 2, 2a**

  - [ ]* 2.4 Write property tests for RCS and angular velocity
    - **Property 3: No RCS without RCS fuel**
    - Generate states where RCSFuel = 0 with rotation input active, verify angular velocity unchanged
    - **Property 4: Angular velocity persistence**
    - Generate states with no RCS input and SAS inactive, verify angular velocity constant between ticks
    - **Validates: Design Properties 3, 4**

  - [ ]* 2.5 Write property test for ballistic consistency
    - **Property 5: Ballistic consistency**
    - Generate states with Thrust = 0 and no RCS input, verify position change = velocity and velocity change = gravity exactly
    - **Validates: Design Property 5**

- [x] 3. Implement terrain and collision detection
  - [x] 3.1 Create terrain and collision unit
    - Create `src/u_Terrain.pas`
    - Store terrain as array of TPointF segments from TWorldProfile
    - Implement line-segment intersection test (craft hull segments vs terrain segments)
    - Return contact result: hit boolean, segment index, whether segment is a pad
    - Implement altitude calculation (distance from craft to nearest terrain below)
    - _References design: Component 6_

  - [x] 3.2 Implement landing evaluation logic
    - Create `src/u_Landing.pas` or add to terrain unit
    - Evaluate landing criteria: speed magnitude <= MaxSpeed, angle deviation <= MaxAngle, on pad (if MustBeOnPad), gear deployed (if RequiresGear)
    - Return success/crash result deterministically (Property 6)
    - Enforce gear requirement: retracted gear on pad = crash regardless of speed/angle (Property 7)
    - _References design: Component 6, Landing Evaluation sequence, Properties 6, 7_

  - [ ]* 3.3 Write property tests for landing determinism and gear enforcement
    - **Property 6: Landing determinism**
    - Generate identical craft state + criteria pairs, verify same success/failure result every time
    - **Property 7: Gear requirement enforcement**
    - Generate states with HasRetractableGear=True and GearDeployed=False on a pad with valid speed/angle, verify result is always crash
    - **Validates: Design Properties 6, 7**

- [x] 4. Implement scoring and lives system
  - [x] 4.1 Create scoring and lives unit
    - Create `src/u_Scoring.pas`
    - Award points based on pad PointValue
    - Calculate fuel bonus (remaining fuel as percentage × multiplier)
    - Track lives (start at 3, decrement on crash, never go below 0)
    - Determine game-over state (lives = 0)
    - Successful landing does not change lives (Property 8)
    - _References design: Component 9, Property 8_

  - [ ]* 4.2 Write property test for lives bounded
    - **Property 8: Lives bounded**
    - Generate sequences of crash/land events, verify lives always in [0, 3], crash decrements by exactly 1, landing never changes lives
    - **Validates: Design Property 8**

- [x] 5. Checkpoint
  - Ensure all core system units compile and tests pass. Ask the user if questions arise.

- [x] 6. Configure main form as dumb host
  - [x] 6.1 Refactor main form to host scene manager
    - Modify `src/f_Main.pas` and `src/f_Main.dfm`
    - Add second TSkPaintBox (rename: `PBFlight` for flight view, `PBPanel` for control panel)
    - Add TTimer (16ms interval for ~60 FPS)
    - Wire Timer.OnTimer to call SceneManager.Tick then invalidate both paint boxes
    - Wire PBFlight.OnDraw to call SceneManager.Render
    - Wire PBPanel.OnDraw to call SceneManager.RenderPanel
    - Wire Form.OnKeyDown/OnKeyUp to call SceneManager.HandleInput
    - Form owns TSceneManager instance (create on FormCreate, free on FormDestroy)
    - _References design: Architecture, Main Game Loop sequence_

  - [x] 6.2 Implement layout mode switching in scene manager
    - TSceneManager exposes SetLayoutMode(Full | PanelFlight)
    - Full mode: hide PBPanel, PBFlight fills client area
    - PanelFlight mode: show PBPanel (fixed ~220px left), PBFlight right side with 3:2 aspect and letterboxing
    - Layout changes only occur during scene swap (screen guaranteed black — Property 10)
    - _References design: Layout Modes table, Property 10_

- [x] 7. Implement flight renderer
  - [x] 7.1 Create flight renderer unit with starfield shader
    - Create `src/u_FlightRenderer.pas` with the unit skeleton (class or set of procedures)
    - Define SkSL starfield shader source as a const string in the unit
    - Procedural star positions from grid hash (no bitmap, resolution-independent)
    - uTime uniform drives per-star twinkle via sin-based brightness oscillation
    - Uniform inputs: uResolution (vec2), uTime (float)
    - Compile shader once at creation into ISkRuntimeEffect, reuse every frame
    - Implement RenderStarfield method: draw fullscreen quad behind all other elements
    - _References design: Component 8 starfield shader description_

  - [x] 7.2 Add terrain rendering
    - Implement world-to-screen coordinate transform (camera/viewport mapping)
    - Draw terrain polyline (white/gray) with highlighted pad segments (different color)
    - _References design: Component 8, terrain polyline rendering_

  - [x] 7.3 Add craft rendering
    - Draw craft hull (ISkPath rotated/translated via Skia matrix from CraftState)
    - Use world-to-screen transform from 7.2 for positioning
    - _References design: Component 8, path caching and transform_

  - [x] 7.4 Add thrust plume and RCS effects
    - Draw thrust plume (semi-transparent triangles/circles below nozzle, random size per frame for flicker) when Thrust > 0 and Fuel > 0
    - Draw RCS puffs (small translucent dots at hull edges) when rotating and RCSFuel > 0
    - _References design: Component 8, plume and RCS descriptions_

  - [x] 7.5 Compose full render pass with letterboxing
    - Maintain 3:2 aspect ratio with letterboxing (black bars)
    - Compose full render pass: starfield → terrain → craft → effects
    - _References design: Component 8, Performance Considerations_

- [ ] 8. Implement panel renderer
  - [ ] 8.1 Create panel renderer with instrument widgets
    - Create `src/u_PanelRenderer.pas`
    - Draw static panel background (dark composite fill or bitmap)
    - Define TInstrument abstract base class with Bounds and Render method
    - Implement fuel gauge widget (vertical bar showing Fuel/FuelCapacity ratio)
    - Implement RCS gauge widget (vertical bar showing RCSFuel/RCSFuelCapacity ratio)
    - Implement velocity indicator widget (numeric display of speed magnitude)
    - Implement altimeter widget (height above nearest terrain)
    - Implement attitude indicator widget (current angle visualization)
    - Implement SAS indicator (on/off light)
    - Implement gear indicator (deployed/retracted state)
    - Panel reads from TCraftState; iterate craft profile's instrument list to render
    - _References design: Component 7_

- [ ] 9. Checkpoint
  - Ensure rendering units compile. Ask the user if questions arise.

- [ ] 10. Implement play scene
  - [ ] 10.1 Create play scene with physics integration
    - Create `src/u_PlayScene.pas` implementing TGameScene
    - Initialize TCraftState from TCraftProfile and TWorldProfile on creation (starting position, full fuel)
    - On Tick: call physics engine, then test collision
    - On collision: evaluate landing criteria → success (award score, signal result) or crash (decrement lives, retry or signal result)
    - HandleInput: map arrow keys to Thrust/Rotation, G to gear toggle, T to SAS toggle
    - Render: delegate to flight renderer passing craft state + world profile
    - RenderPanel: delegate to panel renderer passing craft state + craft profile
    - Signal Finished instantly on landing/crash (no exit animation) with NextSceneID = sidResult
    - On retry (lives > 0 and crash): reset craft state, continue play
    - _References design: Component 3, Play Scene responsibilities_

  - [ ]* 10.2 Write unit tests for play scene input handling
    - Test that key inputs correctly modify CraftState flags (Thrust, RotatingLeft/Right, GearDeployed, SASActive)
    - Test that gear toggle and SAS toggle only work for craft that have those systems
    - _References design: Component 3_

- [x] 11. Implement menu scene
  - [x] 11.1 Create menu scene with drifting craft demo
    - Create `src/u_MenuScene.pas` implementing TGameScene
    - Render title text and "Start" prompt over starfield background
    - Background demo craft: no physics engine, just simple linear drift + constant angular velocity
    - Craft enters from one side with a set trajectory and slow spin
    - Wraps around to the opposite side when it exits the view bounds
    - Randomly fires main engine (Thrust flag on) for 1–2 seconds at random intervals (visual only, no acceleration)
    - Randomly fires RCS (RotatingLeft/Right flag on) for 1–2 seconds at random intervals (visual only, no angular change)
    - Uses TFlightRenderer.RenderCraft + RenderEffects over starfield (no terrain)
    - HandleInput: detect start action (Enter or Space)
    - Own exit animation: fade to black (draw black rect with increasing alpha each tick)
    - Signal Finished only when fully black, NextSceneID = sidPlay
    - Own entrance animation: fade in from black when created
    - _References design: Component 2, Scene Transition sequence_

- [ ] 12. Implement result scene
  - [ ] 12.1 Create result scene with outcome display
    - Create `src/u_ResultScene.pas` implementing TGameScene
    - Display landing/crash outcome with final stats (speed, angle, fuel remaining)
    - Display scoring breakdown (pad points + fuel bonus)
    - Show navigation options: Retry (if lives > 0), Return to Menu
    - Panel remains visible with frozen craft state from moment of outcome (Property 11)
    - HandleInput: detect retry or menu selection
    - Own exit animation (fade to black) when returning to menu
    - Signal Finished only when fully black, NextSceneID = sidMenu
    - For retry: signal a retry flag back to scene manager (NextSceneID = sidPlay with lives preserved)
    - _References design: Component 4, Property 11_

- [ ] 13. Wire scene transitions in scene manager
  - [ ] 13.1 Complete scene manager transition logic
    - On Tick: check CurrentScene.Finished flag
    - When finished: destroy current scene, reconfigure layout based on NextSceneID, create new scene
    - Menu → Play: switch to PanelFlight layout, create TPlayScene with craft/world profiles
    - Play → Result: keep PanelFlight layout, create TResultScene with final state + score
    - Result → Menu: switch to Full layout, create TMenuScene
    - Result → Play (retry): keep PanelFlight layout, create TPlayScene with decremented lives
    - Ensure exactly one scene active at all times (Property 9)
    - _References design: Scene System state diagram, Properties 9, 10_

  - [ ]* 13.2 Write unit tests for scene manager transitions
    - **Property 9: Scene exclusivity**
    - Verify that after any transition, exactly one scene reference is non-nil
    - Verify old scene is freed before new scene is created
    - **Validates: Design Property 9**

- [ ] 14. Create default craft and world profiles
  - [ ] 14.1 Create default Moon world and starter craft profile
    - Create `src/u_Profiles.pas` with factory functions
    - Define Moon world: low gravity (~0.5), hand-crafted terrain polyline with 2 landing pads (one large/easy, one small/hard)
    - Define starter craft: moderate thrust, adequate fuel, has SAS, has retractable gear, balanced RCS
    - Build ISkPath for craft hull (simple lander shape — legs, body, nozzle)
    - Define instrument layout for starter craft (all V1 instruments)
    - Define TLandingCriteria for the Moon level
    - _References design: TCraftProfile, TWorldProfile, MVP Scope_

- [ ] 15. Final integration and polish
  - [ ] 15.1 Wire everything together in main form creation
    - On FormCreate: load profiles, create SceneManager, set initial scene to MenuScene
    - Ensure proper destruction order on FormDestroy
    - Set form properties: caption, default size, keyboard handling (KeyPreview := True)
    - Verify full game loop: menu → start → play → land/crash → result → retry/menu
    - _References design: Architecture, Main Game Loop sequence_

  - [ ]* 15.2 Write integration tests for full game loop
    - Test complete cycle: create scene manager, start menu scene, simulate start → play scene active
    - Test play to result transition on crash
    - Test play to result transition on successful landing
    - Test lives system across multiple retries
    - _References design: Gameplay Loop_

- [ ] 16. Final checkpoint
  - Ensure all units compile, all tests pass, and the game runs from menu through play to result. Ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific design components and correctness properties for traceability
- Checkpoints ensure incremental validation
- Property tests validate universal correctness properties from the design document
- The project uses Delphi CE 12.2 with Skia4Delphi — all code is Object Pascal
- Coordinate convention: angle 0 = up, positive angular velocity = clockwise, gravity = +Y (screen down)
- The existing `f_Main.pas` and `Lander.dpr` form the starting point; task 6 refactors them

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1"] },
    { "id": 1, "tasks": ["1.2", "2.1"] },
    { "id": 2, "tasks": ["2.2", "2.3", "2.4", "2.5", "3.1", "4.1"] },
    { "id": 3, "tasks": ["3.2", "3.3", "4.2"] },
    { "id": 4, "tasks": ["6.1", "7.1", "8.1"] },
    { "id": 5, "tasks": ["6.2", "7.2", "10.1", "14.1"] },
    { "id": 6, "tasks": ["7.3"] },
    { "id": 7, "tasks": ["7.4"] },
    { "id": 8, "tasks": ["7.5", "10.2", "11.1", "12.1"] },
    { "id": 9, "tasks": ["13.1"] },
    { "id": 10, "tasks": ["13.2", "15.1"] },
    { "id": 11, "tasks": ["15.2"] }
  ]
}
```
