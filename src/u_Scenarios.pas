unit u_Scenarios;

interface

uses
  System.Types, System.UITypes, System.Skia,
  u_Models;

type
  // Initial conditions for the craft at mission start.
  TStartConditions = record
    X: Single;           // Starting world X position
    Y: Single;           // Starting world Y position
    VX: Single;          // Initial velocity X (0 for stationary start)
    VY: Single;          // Initial velocity Y (0 for stationary start)
    Angle: Single;       // Initial facing angle (0 = up)
  end;

  // A complete scenario definition: everything needed to start a play session.
  TScenario = record
    Name: string;
    Description: string;
    Lives: Integer;
    WorldID: string;         // Identifier for the world (filename or resource key)
    CraftID: string;         // Identifier for the craft (filename or resource key)
    World: TWorldProfile;    // Constructed world profile
    Craft: TCraftProfile;    // Constructed craft profile
    Criteria: TLandingCriteria;  // Landing success/fail thresholds
    Start: TStartConditions;     // Where and how the craft begins
  end;

  // Builds scenario instances. V1 constructs in code; later versions
  // delegate to u_Serialization for JSON-based loading.
  TScenarioBuilder = class
  public
    // Returns the default v1 scenario (Moon + basic lander).
    class function BuildDefault: TScenario;
    class function BuildBubbleCraft: TCraftProfile;
  end;

implementation

uses
  System.Math;

class function TScenarioBuilder.BuildDefault: TScenario;
var
  Terrain: TTerrainArray;
  Pads: TPadArray;
{$ifdef false}
  Part: TCraftPart;
  Pivot: TPointF;
  HullParts: TCraftPartArray;
  RCSOffsets: TPointFArray;
{$endif}
begin
  Result.WorldID := 'moon';
  Result.CraftID := 'basicLander';

  // --- Build World Profile ---
  Result.World := TWorldProfile.Create;
  Result.World.Name := 'The Moon';
  Result.World.Gravity := 0.7;
  Result.World.Wind := 0;
  Result.World.TerrainColor := $FFB0B0B0;  // Light gray lunar surface
  Result.World.PadColor := $FF00E060;       // Bright green pads

  // Terrain polyline: ~1000 units wide, jagged lunar surface with 2 pads.
  // Y increases downward; terrain sits in the 850–950 range.
  SetLength(Terrain, 24);
  Terrain[0]  := PointF(0, 900);
  Terrain[1]  := PointF(60, 880);
  Terrain[2]  := PointF(120, 920);
  Terrain[3]  := PointF(200, 890);
  Terrain[4]  := PointF(280, 910);
  // Pad 1: large easy pad (indices 5–7)
  Terrain[5]  := PointF(350, 940);
  Terrain[6]  := PointF(420, 940);
  Terrain[7]  := PointF(490, 940);
  // Continue terrain
  Terrain[8]  := PointF(540, 910);
  Terrain[9]  := PointF(600, 880);
  Terrain[10] := PointF(650, 920);
  Terrain[11] := PointF(700, 900);
  Terrain[12] := PointF(740, 930);
  // Pad 2: small hard pad (indices 13–14)
  Terrain[13] := PointF(780, 950);
  Terrain[14] := PointF(830, 950);
  // Continue terrain
  Terrain[15] := PointF(870, 910);
  Terrain[16] := PointF(910, 890);
  Terrain[17] := PointF(950, 920);
  Terrain[18] := PointF(980, 900);
  Terrain[19] := PointF(1000, 880);

  Terrain[20] := PointF(1000, 580);
  Terrain[21] := PointF(1150, 610);
  Terrain[22] := PointF(1200, 610);
  Terrain[23] := PointF(1500, 940);


  Result.World.Terrain := Terrain;

  // Landing pads
  SetLength(Pads, 3);
  Pads[0].StartIndex := 5;
  Pads[0].EndIndex := 7;
  Pads[0].PointValue := 50;    // Easy pad, fewer points
  Pads[1].StartIndex := 13;
  Pads[1].EndIndex := 14;
  Pads[1].PointValue := 150;   // Hard pad, more points
  Pads[2].StartIndex := 21;
  Pads[2].EndIndex := 22;
  Pads[2].PointValue := 200;   // Hardest pad, more points

  Result.World.Pads := Pads;

  // --- Build Craft Profile ---
  Result.Craft := BuildBubbleCraft;

{$ifdef false}
  Result.Craft := TCraftProfile.Create;
  Result.Craft.Name := 'Basic Lander';

  // Pivot: center of rotation in grid space (craft is 28 wide × 45 tall)
  Pivot := PointF(14, 22.5);

  // Hull parts (authored in grid space, pivot-centered automatically)
  SetLength(HullParts, 4);

  // Part 0: Main body outline
  Part.Path := BuildCraftPath([
    PointF(14, 0),     // Nose
    PointF(26, 18),    // Upper right
    PointF(24, 38),    // Lower right
    PointF(4, 38),     // Lower left
    PointF(2, 18)      // Upper left
  ], Pivot, True);
  Part.Color := $FFC0C0C0;  // Silver
  Part.Style := TSkPaintStyle.Stroke;
  Part.StrokeWidth := 1.8;
  HullParts[0] := Part;

  // Part 1: Cockpit window
  Part.Path := BuildCraftPath([
    PointF(14, 5),
    PointF(19, 16),
    PointF(9, 16)
  ], Pivot, True);
  Part.Color := $FF4488CC;  // Blue cockpit
  Part.Style := TSkPaintStyle.Fill;
  Part.StrokeWidth := 0;
  HullParts[1] := Part;

  // Part 2: Left landing leg
  Part.Path := BuildCraftPath([
    PointF(4, 38),
    PointF(0, 45),
    PointF(6, 45)
  ], Pivot, False);
  Part.Color := $FF808080;  // Dark gray
  Part.Style := TSkPaintStyle.Stroke;
  Part.StrokeWidth := 1.5;
  HullParts[2] := Part;

  // Part 3: Right landing leg
  Part.Path := BuildCraftPath([
    PointF(24, 38),
    PointF(28, 45),
    PointF(22, 45)
  ], Pivot, False);
  Part.Color := $FF808080;  // Dark gray
  Part.Style := TSkPaintStyle.Stroke;
  Part.StrokeWidth := 1.5;
  HullParts[3] := Part;

  Result.Craft.HullParts := HullParts;

  // Offsets (grid space, pivot-centered)
  Result.Craft.ThrustOffset := PivotOffset(PointF(14, 40), Pivot);

  SetLength(RCSOffsets, 2);
  RCSOffsets[0] := PivotOffset(PointF(0, 20), Pivot);
  RCSOffsets[1] := PivotOffset(PointF(28, 20), Pivot);
  Result.Craft.RCSOffsets := RCSOffsets;

  // Effect sizes (in craft units)
  Result.Craft.PlumeLength := 16.0;
  Result.Craft.PlumeWidth := 6.0;
  Result.Craft.RCSRadius := 4.0;
  Result.Craft.PlumeColor := $FFFF8800;  // Orange

  // Physics parameters
  Result.Craft.Mass := 1.0;
  Result.Craft.ThrustPower := 2.8;
  Result.Craft.FuelCapacity := 100;
  Result.Craft.BurnRate := 0.3;
  Result.Craft.RCSFuelCapacity := 50;
  Result.Craft.RCSBurnRate := 0.2;
  Result.Craft.RCSThrust := 0.5;
  Result.Craft.HasSAS := True;
  Result.Craft.HasThrottleControl := True;

  // Collision path (simplified outer boundary, grid space)
  Result.Craft.CollisionPath := BuildCraftPath([
    PointF(14, 0),
    PointF(26, 18),
    PointF(24, 38),
    PointF(28, 45),
    PointF(0, 45),
    PointF(4, 38),
    PointF(2, 18)
  ], Pivot, True);

  // Collision points: same vertices as collision path, pivot-centered.
  // Used directly by the play scene for hull collision testing.
  Result.Craft.CollisionPoints := TPointFArray.Create(
    PivotOffset(PointF(14, 0), Pivot),
    PivotOffset(PointF(26, 18), Pivot),
    PivotOffset(PointF(24, 38), Pivot),
    PivotOffset(PointF(28, 45), Pivot),
    PivotOffset(PointF(0, 45), Pivot),
    PivotOffset(PointF(4, 38), Pivot),
    PivotOffset(PointF(2, 18), Pivot));
{$endif}

  // --- Landing Criteria ---
  Result.Criteria.MaxSpeed := 3.0;
  Result.Criteria.MaxAngle := 15.0;   // Degrees

  // --- Start Conditions ---
  Result.Start.X := 0;    // Center of terrain
  Result.Start.Y := 400;    // Just above terrain (terrain starts ~880)
  Result.Start.VX := 20.2;
  Result.Start.VY := 0;
  Result.Start.Angle := -90;
end;


class function TScenarioBuilder.BuildBubbleCraft: TCraftProfile;
var
  Part: TCraftPart;
  Pivot: TPointF;
  HullParts: TCraftPartArray;
  RCSOffsets: TPointFArray;
  BubbleBuilder: ISkPathBuilder;
  BubblePath: ISkPath;
  BodyPath: ISkPath;
begin
  Result := TCraftProfile.Create;
  Result.Name := 'Bubble Lander';

  // Grid: 32 wide × 42 tall
  Pivot := PointF(16, 21);

  SetLength(HullParts, 5);

  // Build the body path once (used for both fill and stroke)
  // Top edge: X 5..27 (22 wide), Bottom edge: X 3..29 (26 wide)
  BodyPath := BuildCraftPath([
    PointF(5, 18),    // Top-left
    PointF(27, 18),   // Top-right
    PointF(29, 36),   // Bottom-right
    PointF(3, 36)     // Bottom-left
  ], Pivot, True);

  // Part 0: Bubble cockpit dome (drawn first, behind body)
  // Slightly narrower than body top edge: X 7..25 (18 wide)
  BubbleBuilder := TSkPathBuilder.Create;
  BubbleBuilder.MoveTo(PointF(7 - Pivot.X, 18 - Pivot.Y));
  BubbleBuilder.ArcTo(
    RectF(7 - Pivot.X, 1 - Pivot.Y, 25 - Pivot.X, 35 - Pivot.Y),  // Oval rect
    180,   // Start angle (left side)
    180,   // Sweep angle (half circle going over the top)
    False
  );
  BubbleBuilder.Close;
  BubblePath := BubbleBuilder.Detach;

  Part.Path := BubblePath;
  Part.Color := $FF4488CC;  // Blue cockpit
  Part.Style := TSkPaintStyle.Fill;
  Part.StrokeWidth := 0;
  HullParts[0] := Part;

  // Part 1: Body fill (black, covers bubble bottom half so stars don't show)
  Part.Path := BodyPath;
  Part.Color := $FF000000;  // Black fill
  Part.Style := TSkPaintStyle.Fill;
  Part.StrokeWidth := 0;
  HullParts[1] := Part;

  // Part 2: Body stroke (silver outline on top)
  Part.Path := BodyPath;
  Part.Color := $FFC0C0C0;  // Silver
  Part.Style := TSkPaintStyle.Stroke;
  Part.StrokeWidth := 1.8;
  HullParts[2] := Part;

  // Part 3: Left landing leg
  Part.Path := BuildCraftPath([
    PointF(3, 36),
    PointF(0, 42),
    PointF(7, 42)
  ], Pivot, False);
  Part.Color := $FF808080;  // Dark gray
  Part.Style := TSkPaintStyle.Stroke;
  Part.StrokeWidth := 1.5;
  HullParts[3] := Part;

  // Part 4: Right landing leg
  Part.Path := BuildCraftPath([
    PointF(29, 36),
    PointF(32, 42),
    PointF(25, 42)
  ], Pivot, False);
  Part.Color := $FF808080;  // Dark gray
  Part.Style := TSkPaintStyle.Stroke;
  Part.StrokeWidth := 1.5;
  HullParts[4] := Part;

  Result.HullParts := HullParts;

  // Thrust offset (center bottom of body)
  Result.ThrustOffset := PivotOffset(PointF(16, 38), Pivot);

  // RCS offsets (left and right sides, mid-body height)
  SetLength(RCSOffsets, 2);
  RCSOffsets[0] := PivotOffset(PointF(3, 19), Pivot);
  RCSOffsets[1] := PivotOffset(PointF(29, 19), Pivot);
  Result.RCSOffsets := RCSOffsets;

  // Effect sizes
  Result.PlumeLength := 14.0;
  Result.PlumeWidth := 7.0;
  Result.RCSRadius := 4.0;
  Result.PlumeColor := $FFFF8800;  // Orange

  // Physics (same as basic lander for now — tweak as desired)
  Result.Mass := 1.0;
  Result.ThrustPower := 2.8;
  Result.FuelCapacity := 100;
  Result.BurnRate := 0.3;
  Result.RCSFuelCapacity := 50;
  Result.RCSBurnRate := 0.2;
  Result.RCSThrust := 0.5;
  Result.HasSAS := True;
  Result.HasThrottleControl := True;

  // Collision path (outer boundary)
  Result.CollisionPath := BuildCraftPath([
    PointF(16, 0),     // Top of dome
    PointF(27, 18),    // Dome meets body top-right
    PointF(29, 36),    // Body bottom-right
    PointF(32, 42),    // Right leg tip
    PointF(0, 42),     // Left leg tip
    PointF(3, 36),     // Body bottom-left
    PointF(5, 18)      // Dome meets body top-left
  ], Pivot, True);

  // Collision points
  Result.CollisionPoints := TPointFArray.Create(
    PivotOffset(PointF(16, 0), Pivot),
    PivotOffset(PointF(27, 18), Pivot),
    PivotOffset(PointF(29, 36), Pivot),
    PivotOffset(PointF(32, 42), Pivot),
    PivotOffset(PointF(0, 42), Pivot),
    PivotOffset(PointF(3, 36), Pivot),
    PivotOffset(PointF(5, 18), Pivot));
end;


end.
