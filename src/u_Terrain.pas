unit u_Terrain;

interface

uses
  System.Types, u_Models;

type
  // Result of a collision test between craft hull and terrain.
  TContactResult = record
    Hit: Boolean;           // Whether any hull segment intersects terrain
    SegmentIndex: Integer;  // Index of the terrain segment that was hit (-1 if no hit)
    IsPad: Boolean;         // Whether the hit segment belongs to a landing pad
    PadIndex: Integer;      // Index into the pads array (-1 if not a pad)
  end;

// Tests craft hull segments against terrain segments using line-line intersection.
// aHullPoints: hull vertices in world space (already transformed by craft position/angle).
// aWorld: the world profile containing terrain and pad definitions.
// Returns a TContactResult indicating if/where contact occurred.
function TestHullCollision(const aHullPoints: array of TPointF;
  aWorld: TWorldProfile): TContactResult;

// Calculates the altitude (vertical distance) from the craft center to the
// nearest terrain segment directly below.
// aCraftX, aCraftY: craft center position in world coordinates.
// aWorld: the world profile containing terrain.
// Returns the vertical distance to terrain below, or -1 if no terrain is below.
function CalcAltitude(aCraftX, aCraftY: Single; aWorld: TWorldProfile): Single;

// Tests whether two line segments intersect.
// Segment 1: (aP1, aP2), Segment 2: (aP3, aP4).
// Returns True if the segments cross each other.
function SegmentsIntersect(const aP1, aP2, aP3, aP4: TPointF): Boolean;

implementation

uses
  System.Math;

// Returns the cross product of vectors (B-A) and (C-A).
function CrossProduct(const aA, aB, aC: TPointF): Single;
begin
  Result := (aB.X - aA.X) * (aC.Y - aA.Y) - (aB.Y - aA.Y) * (aC.X - aA.X);
end;

// Checks if point aP lies on the axis-aligned bounding box of segment (aA, aB).
// Used for collinear overlap detection.
function PointOnSegment(const aP, aA, aB: TPointF): Boolean;
begin
  Result := (Min(aA.X, aB.X) <= aP.X) and (aP.X <= Max(aA.X, aB.X)) and
            (Min(aA.Y, aB.Y) <= aP.Y) and (aP.Y <= Max(aA.Y, aB.Y));
end;

function SegmentsIntersect(const aP1, aP2, aP3, aP4: TPointF): Boolean;
var
  D1, D2, D3, D4: Single;
begin
  // Compute cross products to determine which side of each segment
  // the endpoints of the other segment lie on.
  D1 := CrossProduct(aP3, aP4, aP1);
  D2 := CrossProduct(aP3, aP4, aP2);
  D3 := CrossProduct(aP1, aP2, aP3);
  D4 := CrossProduct(aP1, aP2, aP4);

  // Segments intersect if endpoints of each segment straddle the other.
  if ((D1 > 0) and (D2 < 0)) or ((D1 < 0) and (D2 > 0)) then
    if ((D3 > 0) and (D4 < 0)) or ((D3 < 0) and (D4 > 0)) then
    begin
      Result := True;
      Exit;
    end;

  // Check collinear cases — endpoint on segment.
  if (D1 = 0) and PointOnSegment(aP1, aP3, aP4) then
  begin
    Result := True;
    Exit;
  end;
  if (D2 = 0) and PointOnSegment(aP2, aP3, aP4) then
  begin
    Result := True;
    Exit;
  end;
  if (D3 = 0) and PointOnSegment(aP3, aP1, aP2) then
  begin
    Result := True;
    Exit;
  end;
  if (D4 = 0) and PointOnSegment(aP4, aP1, aP2) then
  begin
    Result := True;
    Exit;
  end;

  Result := False;
end;

// Determines whether a terrain segment index falls within any landing pad.
function IsSegmentOnPad(aSegIndex: Integer; aWorld: TWorldProfile;
  out aPadIndex: Integer): Boolean;
var
  I: Integer;
begin
  Result := False;
  aPadIndex := -1;
  for I := 0 to Length(aWorld.Pads) - 1 do
  begin
    if (aSegIndex >= aWorld.Pads[I].StartIndex) and
       (aSegIndex < aWorld.Pads[I].EndIndex) then
    begin
      Result := True;
      aPadIndex := I;
      Exit;
    end;
  end;
end;

function TestHullCollision(const aHullPoints: array of TPointF;
  aWorld: TWorldProfile): TContactResult;
var
  HullCount, TerrainCount: Integer;
  I, J: Integer;
  HP1, HP2: TPointF;
  TP1, TP2: TPointF;
  PadIdx: Integer;
begin
  Result.Hit := False;
  Result.SegmentIndex := -1;
  Result.IsPad := False;
  Result.PadIndex := -1;

  HullCount := Length(aHullPoints);
  TerrainCount := Length(aWorld.Terrain);

  if (HullCount < 2) or (TerrainCount < 2) then
    Exit;

  // Test each hull edge against each terrain segment.
  for I := 0 to HullCount - 1 do
  begin
    HP1 := aHullPoints[I];
    HP2 := aHullPoints[(I + 1) mod HullCount]; // Closed polygon

    for J := 0 to TerrainCount - 2 do
    begin
      TP1 := aWorld.Terrain[J];
      TP2 := aWorld.Terrain[J + 1];

      if SegmentsIntersect(HP1, HP2, TP1, TP2) then
      begin
        Result.Hit := True;
        Result.SegmentIndex := J;
        Result.IsPad := IsSegmentOnPad(J, aWorld, PadIdx);
        Result.PadIndex := PadIdx;
        Exit; // Return first hit
      end;
    end;
  end;
end;

function CalcAltitude(aCraftX, aCraftY: Single; aWorld: TWorldProfile): Single;
var
  TerrainCount: Integer;
  I: Integer;
  TP1, TP2: TPointF;
  MinX, MaxX: Single;
  T, TerrainY, Dist: Single;
  Found: Boolean;
begin
  Result := -1;
  TerrainCount := Length(aWorld.Terrain);
  if TerrainCount < 2 then
    Exit;

  Found := False;

  // Cast a vertical ray downward from (aCraftX, aCraftY).
  // Find the nearest terrain segment directly below.
  for I := 0 to TerrainCount - 2 do
  begin
    TP1 := aWorld.Terrain[I];
    TP2 := aWorld.Terrain[I + 1];

    // Check if craft X is within the horizontal span of this segment.
    MinX := Min(TP1.X, TP2.X);
    MaxX := Max(TP1.X, TP2.X);

    if (aCraftX < MinX) or (aCraftX > MaxX) then
      Continue;

    // Interpolate terrain Y at craft X position.
    if Abs(TP2.X - TP1.X) < 0.0001 then
      TerrainY := Min(TP1.Y, TP2.Y) // Vertical segment — use top
    else
    begin
      T := (aCraftX - TP1.X) / (TP2.X - TP1.X);
      TerrainY := TP1.Y + T * (TP2.Y - TP1.Y);
    end;

    // Terrain must be below craft (Y increases downward).
    if TerrainY < aCraftY then
      Continue;

    Dist := TerrainY - aCraftY;

    if (not Found) or (Dist < Result) then
    begin
      Result := Dist;
      Found := True;
    end;
  end;

  if not Found then
    Result := -1;
end;

end.
