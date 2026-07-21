unit u_TerrainFeatureGen;

interface

uses
  System.Types, System.Math, u_Models;

type
  // Static class providing procedural terrain generators.
  // Each feature produces a deterministic polyline segment given a seed.
  TTerrainFeatureGen = class
  public
    class function Generate(aKind: TFeatureKind; aWorldX, aWidth, aAltitude: Single;
      aSeed: Integer): TTerrainArray;
    class function FeatureName(aKind: TFeatureKind): string;
  end;

implementation

{ TTerrainFeatureGen }

class function TTerrainFeatureGen.FeatureName(aKind: TFeatureKind): string;
begin
  case aKind of
    fkJagged:       Result := 'Jagged';
    fkRollingHills: Result := 'Rolling Hills';
    fkCanyon:       Result := 'Canyon';
    fkMountain:     Result := 'Mountain';
    fkCrater:       Result := 'Crater';
    fkCliff:        Result := 'Cliff';
    fkFlat:         Result := 'Flat';
    fkRidgeLine:    Result := 'Ridge Line';
    fkChaos:        Result := 'Chaos';
  else
    Result := 'Unknown';
  end;
end;

class function TTerrainFeatureGen.Generate(aKind: TFeatureKind;
  aWorldX, aWidth, aAltitude: Single; aSeed: Integer): TTerrainArray;
var
  count: Integer;
  i: Integer;
  t: Single;       // normalized position 0..1
  x: Single;
  y: Single;
  amplitude: Single;
  oldSeed: Integer;
begin
  // Number of points: endpoints included
  count := Round(aWidth / 10) + 1;
  if count < 2 then
    count := 2;

  SetLength(Result, count);

  // Save and set random seed for determinism
  oldSeed := RandSeed;
  RandSeed := aSeed;

  try
    for i := 0 to count - 1 do
    begin
      // X position evenly spaced across the width
      if count > 1 then
        t := i / (count - 1)
      else
        t := 0;

      x := aWorldX + t * aWidth;

      case aKind of
        fkJagged:
          begin
            // Sharp random peaks with large amplitude
            amplitude := 80;
            y := aAltitude + (Random - 0.5) * 2 * amplitude;
          end;

        fkRollingHills:
          begin
            // Smooth sine wave undulations
            amplitude := 40;
            y := aAltitude + Sin(t * 2 * Pi * 2) * amplitude;
          end;

        fkCanyon:
          begin
            // V-shaped cut: drops to low point at center, returns at edges
            amplitude := 100;
            y := aAltitude + amplitude * (1 - Abs(2 * t - 1));
          end;

        fkMountain:
          begin
            // Single tall peak at center, slopes down at edges
            amplitude := 120;
            y := aAltitude - amplitude * (1 - Sqr(2 * t - 1));
          end;

        fkCrater:
          begin
            // Circular depression: raised rim at edges, dip in center
            amplitude := 60;
            y := aAltitude + amplitude * (Sqr(2 * t - 1) - 0.5);
          end;

        fkCliff:
          begin
            // Steep drop: starts at altitude, drops sharply to lower level
            amplitude := 100;
            if t < 0.4 then
              y := aAltitude
            else if t < 0.6 then
              y := aAltitude + amplitude * ((t - 0.4) / 0.2)
            else
              y := aAltitude + amplitude;
          end;

        fkFlat:
          begin
            // Level surface at the given altitude
            y := aAltitude;
          end;

        fkRidgeLine:
          begin
            // Series of small peaks (smaller amplitude than Jagged)
            amplitude := 25;
            y := aAltitude + (Random - 0.5) * 2 * amplitude;
          end;

        fkChaos:
          begin
            // High-frequency random terrain with extreme variation
            amplitude := 150;
            y := aAltitude + (Random - 0.5) * 2 * amplitude;
          end;
      else
        y := aAltitude;
      end;

      Result[i] := PointF(x, y);
    end;
  finally
    // Restore previous random seed
    RandSeed := oldSeed;
  end;
end;

end.
