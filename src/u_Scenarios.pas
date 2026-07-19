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
    WorldID: String;         // Identifier for the world (filename or resource key)
    CraftID: String;         // Identifier for the craft (filename or resource key)
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
  end;

implementation

uses
  System.Math;

class function TScenarioBuilder.BuildDefault: TScenario;
var
  Part: TCraftPart;
  Pivot: TPointF;
  Terrain: TTerrainArray;
  Pads: TPadArray;
  HullParts: TCraftPartArray;
  RCSOffsets: TPointFArray;
begin
  Result.WorldID := 'moon';
  Result.CraftID := 'basicLander';

  // --- Build World Profile ---
  Result.World := TWorldProfile.Create;
  Result.World.Name := 'The Moon';
  Result.World.Gravity := 0.4;
  Result.World.Wind := 0;
  Result.World.TerrainColor := $FFB0B0B0;  // Light gray lunar surface
  Result.World.PadColor := $FF00E060;       // Bright green pads

  // Terrain polyline: ~1000 units wide, jagged lunar surface with 2 pads.
  // Y increases downward; terrain sits in the 600–800 range.
  SetLength(Terrain, 20);
  Terrain[0]  := PointF(0, 700);
  Terrain[1]  := PointF(60, 680);
  Terrain[2]  := PointF(120, 720);
  Terrain[3]  := PointF(200, 690);
  Terrain[4]  := PointF(280, 710);
  // Pad 1: large easy pad (indices 5–7)
  Terrain[5]  := PointF(350, 750);
  Terrain[6]  := PointF(420, 750);
  Terrain[7]  := PointF(490, 750);
  // Continue terrain
  Terrain[8]  := PointF(540, 720);
  Terrain[9]  := PointF(600, 690);
  Terrain[10] := PointF(650, 730);
  Terrain[11] := PointF(700, 710);
  Terrain[12] := PointF(740, 740);
  // Pad 2: small hard pad (indices 13–14)
  Terrain[13] := PointF(780, 760);
  Terrain[14] := PointF(830, 760);
  // Continue terrain
  Terrain[15] := PointF(870, 720);
  Terrain[16] := PointF(910, 700);
  Terrain[17] := PointF(950, 730);
  Terrain[18] := PointF(980, 710);
  Terrain[19] := PointF(1000, 690);

  Result.World.Terrain := Terrain;

  // Landing pads
  SetLength(Pads, 2);
  Pads[0].StartIndex := 5;
  Pads[0].EndIndex := 7;
  Pads[0].PointValue := 50;    // Easy pad, fewer points
  Pads[1].StartIndex := 13;
  Pads[1].EndIndex := 14;
  Pads[1].PointValue := 150;   // Hard pad, more points
  Result.World.Pads := Pads;

  // --- Build Craft Profile ---
  Result.Craft := TCraftProfile.Create;
  Result.Craft.Name := 'Basic Lander';

  // Pivot: center of rotation in grid space (craft is 28 wide × 45 tall)
  Pivot := PointF(14, 22.5);

  // Hull parts (authored in grid space, pivot-centered automatically)
  SetLength(HullParts, 3);

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

  // Part 2: Landing legs
  Part.Path := BuildCraftPath([
    PointF(4, 38),
    PointF(0, 45),
    PointF(6, 45)
  ], Pivot, False);
  Part.Color := $FF808080;  // Dark gray
  Part.Style := TSkPaintStyle.Stroke;
  Part.StrokeWidth := 1.5;
  HullParts[2] := Part;

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
  Result.Craft.ThrustPower := 0.15;
  Result.Craft.FuelCapacity := 100;
  Result.Craft.BurnRate := 0.3;
  Result.Craft.RCSFuelCapacity := 50;
  Result.Craft.RCSBurnRate := 0.2;
  Result.Craft.RCSThrust := 0.03;
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

  // --- Landing Criteria ---
  Result.Criteria.MaxSpeed := 3.0;
  Result.Criteria.MaxAngle := 15.0;   // Degrees
  Result.Criteria.MustBeOnPad := True;

  // --- Start Conditions ---
  Result.Start.X := 500;    // Center of terrain
  Result.Start.Y := 100;    // Well above terrain
  Result.Start.VX := 0;
  Result.Start.VY := 0;
  Result.Start.Angle := 0;  // Pointing up
end;

end.
