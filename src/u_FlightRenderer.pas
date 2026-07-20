unit u_FlightRenderer;

interface

uses
  System.Types, System.UITypes, System.Math.Vectors, System.Skia, u_Models;

type
  // Viewport definition for world-to-screen coordinate mapping.
  TViewport = record
    ViewLeft: Single;    // World X left edge
    ViewRight: Single;   // World X right edge
    ViewTop: Single;     // World Y top edge
    ViewBottom: Single;  // World Y bottom edge
    ScreenWidth: Single; // Screen pixel width
    ScreenHeight: Single; // Screen pixel height
  end;

  // Renders the flight view: starfield background, terrain, craft, and effects.
  TFlightRenderer = class
  private
    fEffect: ISkRuntimeEffect;
    fTerrainPath: ISkPath;       // Cached full terrain polyline (world coords)
    fPadPaths: array of ISkPath; // Cached pad segment paths (world coords)

    // Builds a Skia matrix that maps world coordinates to screen coordinates.
    function BuildWorldToScreenMatrix(const aViewport: TViewport): TMatrix;
  public
    constructor Create;
    destructor Destroy; override;

    // Pre-builds terrain paths from world data. Call once when the world is loaded.
    procedure SetTerrain(const aTerrain: TTerrainArray; const aPads: TPadArray);

    // Computes a viewport that shows the entire terrain with margin.
    function ViewportFromTerrain(const aTerrain: TTerrainArray;
      aScreenWidth, aScreenHeight: Single): TViewport;

    // Draws fullscreen procedural starfield behind all other elements.
    // aHorizon: screen Y below which stars fade out. Pass 9999 for full-screen stars.
    procedure RenderStarfield(const aCanvas: ISkCanvas; aWidth, aHeight: Integer;
      aTime: Single; aHorizon: Single = 9999);

    // Draws cached terrain polyline and pad segments using canvas matrix transform.
    procedure RenderTerrain(const aCanvas: ISkCanvas; const aViewport: TViewport;
      aTerrainColor, aPadColor: TAlphaColor);

    // Draws the craft hull parts transformed by craft state (position + rotation).
    procedure RenderCraft(const aCanvas: ISkCanvas; const aViewport: TViewport;
      const aState: TCraftState; const aHullParts: TCraftPartArray);

    // Draws thrust plume and RCS puff effects in craft-local space.
    procedure RenderEffects(const aCanvas: ISkCanvas; const aViewport: TViewport;
      const aState: TCraftState; const aThrustOffset: TPointF;
      const aRCSOffsets: TPointFArray; aPlumeColor: TAlphaColor;
      aPlumeLength, aPlumeWidth, aRCSRadius: Single);

    // Main entry point: composes full render pass with 3:2 letterboxing.
    procedure RenderFrame(const aCanvas: ISkCanvas;
      aCanvasWidth, aCanvasHeight: Single; aTime: Single;
      const aViewport: TViewport; const aState: TCraftState;
      const aHullParts: TCraftPartArray; const aThrustOffset: TPointF;
      const aRCSOffsets: TPointFArray; aPlumeColor, aTerrainColor,
      aPadColor: TAlphaColor; aPlumeLength, aPlumeWidth, aRCSRadius: Single);
  end;

implementation

uses
  System.Math;

const
  // SkSL fragment shader: procedural starfield with twinkle.
  // Grid-based star placement using hash function. uTime drives brightness oscillation.
  CStarfieldShader =
    'uniform float2 uResolution;'#10 +
    'uniform float uTime;'#10 +
    'uniform float uHorizon;'#10 +
    #10 +
    '// Simple hash for deterministic pseudo-random per grid cell'#10 +
    'float hash(float2 p) {'#10 +
    '  p = fract(p * float2(123.34, 456.21));'#10 +
    '  p += dot(p, p + 45.32);'#10 +
    '  return fract(p.x * p.y);'#10 +
    '}'#10 +
    #10 +
    'half4 main(float2 fragCoord) {'#10 +
    '  float cellSize = 40.0;'#10 +
    '  float2 cell = floor(fragCoord / cellSize);'#10 +
    '  float2 localPos = fract(fragCoord / cellSize);'#10 +
    #10 +
    '  // Determine if this cell has a star (roughly 25% of cells)'#10 +
    '  float starPresence = hash(cell);'#10 +
    '  if (starPresence > 0.25) {'#10 +
    '    return half4(0.0, 0.0, 0.0, 1.0);'#10 +
    '  }'#10 +
    #10 +
    '  // Star position within cell from hash'#10 +
    '  float2 starPos = float2(hash(cell + float2(1.0, 0.0)),'#10 +
    '                          hash(cell + float2(0.0, 1.0)));'#10 +
    #10 +
    '  // Distance from fragment to star center'#10 +
    '  float dist = length(localPos - starPos);'#10 +
    #10 +
    '  // Star radius with size tiers for variety'#10 +
    '  float radius = 0.04 + 0.05 * hash(cell + float2(7.0, 3.0));'#10 +
    '  float sizeTier = hash(cell + float2(41.0, 43.0));'#10 +
    '  if (sizeTier > 0.92) {'#10 +
    '    radius *= 3.0;  // ~8% of stars are large'#10 +
    '  } else if (sizeTier > 0.75) {'#10 +
    '    radius *= 1.8;  // ~17% of stars are medium'#10 +
    '  }'#10 +
    #10 +
    '  if (dist > radius) {'#10 +
    '    return half4(0.0, 0.0, 0.0, 1.0);'#10 +
    '  }'#10 +
    #10 +
    '  // Twinkle: sin-based brightness oscillation driven by uTime'#10 +
    '  float phase = hash(cell + float2(13.0, 17.0)) * 6.2832;'#10 +
    '  float speed = 0.8 + hash(cell + float2(19.0, 23.0)) * 1.5;'#10 +
    '  float brightness = 0.5 + 0.5 * sin(uTime * speed + phase);'#10 +
    #10 +
    '  // Base brightness varies per star'#10 +
    '  float baseBright = 0.5 + 0.5 * hash(cell + float2(31.0, 37.0));'#10 +
    '  float finalBright = baseBright * brightness;'#10 +
    #10 +
    '  // Soft falloff from center'#10 +
    '  float falloff = 1.0 - (dist / radius);'#10 +
    '  falloff *= falloff;  // Quadratic falloff for brighter cores'#10 +
    '  finalBright *= falloff;'#10 +
    #10 +
    '  // Fade out stars approaching the horizon (terrain zone)'#10 +
    '  float horizonFade = 1.0 - smoothstep(uHorizon - 80.0, uHorizon, fragCoord.y);'#10 +
    '  finalBright *= horizonFade;'#10 +
    #10 +
    '  return half4(half3(finalBright), 1.0);'#10 +
    '}';

{ TFlightRenderer }

constructor TFlightRenderer.Create;
begin
  inherited Create;
  // Compile the SkSL shader once at creation — reused every frame.
  fEffect := TSkRuntimeEffect.MakeForShader(CStarfieldShader);
end;

destructor TFlightRenderer.Destroy;
begin
  fEffect := nil;
  fTerrainPath := nil;
  SetLength(fPadPaths, 0);
  inherited;
end;

procedure TFlightRenderer.SetTerrain(const aTerrain: TTerrainArray;
  const aPads: TPadArray);
var
  Builder: ISkPathBuilder;
  I, J: Integer;
begin
  fTerrainPath := nil;
  SetLength(fPadPaths, 0);

  if Length(aTerrain) < 2 then
    Exit;

  // Build full terrain polyline path in world coordinates.
  Builder := TSkPathBuilder.Create;
  Builder.MoveTo(PointF(aTerrain[0].X, aTerrain[0].Y));
  for I := 1 to High(aTerrain) do
    Builder.LineTo(PointF(aTerrain[I].X, aTerrain[I].Y));
  fTerrainPath := Builder.Detach;

  // Build a path for each landing pad segment.
  SetLength(fPadPaths, Length(aPads));
  for I := 0 to High(aPads) do
  begin
    if (aPads[I].StartIndex < 0) or (aPads[I].EndIndex > High(aTerrain)) then
      Continue;
    if aPads[I].StartIndex >= aPads[I].EndIndex then
      Continue;

    Builder := TSkPathBuilder.Create;
    Builder.MoveTo(PointF(aTerrain[aPads[I].StartIndex].X,
                           aTerrain[aPads[I].StartIndex].Y));
    for J := aPads[I].StartIndex + 1 to aPads[I].EndIndex do
      Builder.LineTo(PointF(aTerrain[J].X, aTerrain[J].Y));
    fPadPaths[I] := Builder.Detach;
  end;
end;

function TFlightRenderer.ViewportFromTerrain(const aTerrain: TTerrainArray;
  aScreenWidth, aScreenHeight: Single): TViewport;
var
  I: Integer;
  MinX, MaxX, MinY, MaxY: Single;
  MarginX, MarginY: Single;
begin
  if Length(aTerrain) = 0 then
  begin
    Result.ViewLeft := 0;
    Result.ViewRight := aScreenWidth;
    Result.ViewTop := 0;
    Result.ViewBottom := aScreenHeight;
    Result.ScreenWidth := aScreenWidth;
    Result.ScreenHeight := aScreenHeight;
    Exit;
  end;

  MinX := aTerrain[0].X;
  MaxX := aTerrain[0].X;
  MinY := aTerrain[0].Y;
  MaxY := aTerrain[0].Y;

  for I := 1 to High(aTerrain) do
  begin
    if aTerrain[I].X < MinX then MinX := aTerrain[I].X;
    if aTerrain[I].X > MaxX then MaxX := aTerrain[I].X;
    if aTerrain[I].Y < MinY then MinY := aTerrain[I].Y;
    if aTerrain[I].Y > MaxY then MaxY := aTerrain[I].Y;
  end;

  // Add a small margin (5% of range) so terrain doesn't clip against edges.
  MarginX := (MaxX - MinX) * 0.05;
  MarginY := (MaxY - MinY) * 0.05;

  Result.ViewLeft := MinX - MarginX;
  Result.ViewRight := MaxX + MarginX;
  Result.ViewTop := MinY - MarginY;
  Result.ViewBottom := MaxY + MarginY;
  Result.ScreenWidth := aScreenWidth;
  Result.ScreenHeight := aScreenHeight;
end;

function TFlightRenderer.BuildWorldToScreenMatrix(
  const aViewport: TViewport): TMatrix;
var
  ScaleX, ScaleY, Scale: Single;
  WorldWidth, WorldHeight: Single;
  TransX, TransY: Single;
  OffsetX, OffsetY: Single;
begin
  WorldWidth := aViewport.ViewRight - aViewport.ViewLeft;
  WorldHeight := aViewport.ViewBottom - aViewport.ViewTop;

  // Compute independent scales.
  ScaleX := aViewport.ScreenWidth / WorldWidth;
  ScaleY := aViewport.ScreenHeight / WorldHeight;

  // Use uniform scaling (smaller of the two) to preserve aspect ratio.
  Scale := Min(ScaleX, ScaleY);

  // Center horizontally, anchor to bottom vertically.
  OffsetX := (aViewport.ScreenWidth - WorldWidth * Scale) / 2;
  OffsetY := aViewport.ScreenHeight - WorldHeight * Scale;

  // Translation: world origin to screen, plus centering offset.
  TransX := -aViewport.ViewLeft * Scale + OffsetX;
  TransY := -aViewport.ViewTop * Scale + OffsetY;

  Result := TMatrix.Identity;
  Result.m11 := Scale;
  Result.m22 := Scale;
  Result.m31 := TransX;
  Result.m32 := TransY;
end;

procedure TFlightRenderer.RenderStarfield(const aCanvas: ISkCanvas;
  aWidth, aHeight: Integer; aTime: Single; aHorizon: Single);
var
  Builder: ISkRuntimeShaderBuilder;
  Paint: ISkPaint;
begin
  if fEffect = nil then
    Exit;

  Builder := TSkRuntimeShaderBuilder.Create(fEffect);
  Builder.SetUniform('uResolution', [Single(aWidth), Single(aHeight)]);
  Builder.SetUniform('uTime', aTime);
  Builder.SetUniform('uHorizon', aHorizon);

  Paint := TSkPaint.Create;
  Paint.Shader := Builder.MakeShader;

  // Draw fullscreen quad — DrawPaint fills the entire canvas surface.
  aCanvas.DrawPaint(Paint);
end;

procedure TFlightRenderer.RenderTerrain(const aCanvas: ISkCanvas;
  const aViewport: TViewport; aTerrainColor, aPadColor: TAlphaColor);
var
  Paint: ISkPaint;
  Matrix: TMatrix;
  I: Integer;
begin
  if fTerrainPath = nil then
    Exit;

  // Build the world-to-screen affine transform matrix.
  Matrix := BuildWorldToScreenMatrix(aViewport);

  // Save canvas state, apply the world-to-screen transform.
  aCanvas.Save;
  try
    aCanvas.Concat(Matrix);

    // Draw main terrain polyline in light gray.
    Paint := TSkPaint.Create;
    Paint.Style := TSkPaintStyle.Stroke;
    Paint.StrokeWidth := 1.5;
    Paint.AntiAlias := True;
    Paint.Color := aTerrainColor;
    aCanvas.DrawPath(fTerrainPath, Paint);

    // Draw pad segments in bright green.
    if Length(fPadPaths) > 0 then
    begin
      Paint := TSkPaint.Create;
      Paint.Style := TSkPaintStyle.Stroke;
      Paint.StrokeWidth := 2.5;
      Paint.AntiAlias := True;
      Paint.Color := aPadColor;

      for I := 0 to High(fPadPaths) do
        if fPadPaths[I] <> nil then
          aCanvas.DrawPath(fPadPaths[I], Paint);
    end;
  finally
    aCanvas.Restore;
  end;
end;

procedure TFlightRenderer.RenderCraft(const aCanvas: ISkCanvas;
  const aViewport: TViewport; const aState: TCraftState;
  const aHullParts: TCraftPartArray);
var
  Matrix: TMatrix;
  Paint: ISkPaint;
  AngleDeg: Single;
  I: Integer;
begin
  if Length(aHullParts) = 0 then
    Exit;

  // Convert radians to degrees for Skia's Rotate call.
  AngleDeg := aState.Angle * (180 / Pi);

  // Build the world-to-screen affine transform matrix.
  Matrix := BuildWorldToScreenMatrix(aViewport);

  // Save canvas state, apply transforms in reverse composition order:
  // 1. World-to-screen (outermost)
  // 2. Translate to craft world position
  // 3. Rotate hull by craft angle around origin (innermost)
  aCanvas.Save;
  try
    aCanvas.Concat(Matrix);
    aCanvas.Translate(aState.X, aState.Y);
    aCanvas.Rotate(AngleDeg, 0, 0);

    // Draw each hull part in order (back to front).
    for I := 0 to High(aHullParts) do
    begin
      if aHullParts[I].Path = nil then
        Continue;

      Paint := TSkPaint.Create;
      Paint.Style := aHullParts[I].Style;
      Paint.Color := aHullParts[I].Color;
      Paint.AntiAlias := True;

      if aHullParts[I].Style in [TSkPaintStyle.Stroke, TSkPaintStyle.StrokeAndFill] then
        Paint.StrokeWidth := aHullParts[I].StrokeWidth;

      aCanvas.DrawPath(aHullParts[I].Path, Paint);
    end;
  finally
    aCanvas.Restore;
  end;
end;

procedure TFlightRenderer.RenderFrame(const aCanvas: ISkCanvas;
  aCanvasWidth, aCanvasHeight: Single; aTime: Single;
  const aViewport: TViewport; const aState: TCraftState;
  const aHullParts: TCraftPartArray; const aThrustOffset: TPointF;
  const aRCSOffsets: TPointFArray; aPlumeColor, aTerrainColor,
  aPadColor: TAlphaColor; aPlumeLength, aPlumeWidth, aRCSRadius: Single);
var
  TargetAspect, CanvasAspect: Single;
  ViewWidth, ViewHeight: Single;
  OffsetX, OffsetY: Single;
  HorizonY: Single;
  Paint: ISkPaint;
  FrameViewport: TViewport;
begin
  // Compute 3:2 letterbox rectangle within the canvas.
  TargetAspect := 3.0 / 2.0;
  CanvasAspect := aCanvasWidth / aCanvasHeight;

  if CanvasAspect > TargetAspect then
  begin
    // Too wide — pillarbox (black bars left and right).
    ViewHeight := aCanvasHeight;
    ViewWidth := ViewHeight * TargetAspect;
  end
  else
  begin
    // Too tall — letterbox (black bars top and bottom).
    ViewWidth := aCanvasWidth;
    ViewHeight := ViewWidth / TargetAspect;
  end;

  OffsetX := (aCanvasWidth - ViewWidth) / 2;
  OffsetY := (aCanvasHeight - ViewHeight) / 2;

  // Fill entire canvas with black (provides the letterbox/pillarbox bars).
  Paint := TSkPaint.Create;
  Paint.Color := TAlphaColors.Black;
  Paint.Style := TSkPaintStyle.Fill;
  aCanvas.DrawRect(RectF(0, 0, aCanvasWidth, aCanvasHeight), Paint);

  // Set viewport dimensions to the 3:2 rect size.
  FrameViewport := aViewport;
  FrameViewport.ScreenWidth := ViewWidth;
  FrameViewport.ScreenHeight := ViewHeight;

  // Clip and translate canvas to the computed 3:2 rect.
  aCanvas.Save;
  try
    aCanvas.ClipRect(RectF(OffsetX, OffsetY, OffsetX + ViewWidth, OffsetY + ViewHeight));
    aCanvas.Translate(OffsetX, OffsetY);

    // Horizon: fade stars in the lower portion of the view.
    // Use the viewport's world-to-screen mapping to find where terrain starts.
    // With uniform scaling, terrain top maps to a screen Y we can compute.
    HorizonY := ViewHeight * 0.7;

    // Compose render pass: starfield → terrain → craft → effects.
    RenderStarfield(aCanvas, Round(ViewWidth), Round(ViewHeight), aTime, HorizonY);
    RenderTerrain(aCanvas, FrameViewport, aTerrainColor, aPadColor);
    RenderCraft(aCanvas, FrameViewport, aState, aHullParts);
    RenderEffects(aCanvas, FrameViewport, aState, aThrustOffset, aRCSOffsets,
      aPlumeColor, aPlumeLength, aPlumeWidth, aRCSRadius);
  finally
    aCanvas.Restore;
  end;
end;

procedure TFlightRenderer.RenderEffects(const aCanvas: ISkCanvas;
  const aViewport: TViewport; const aState: TCraftState;
  const aThrustOffset: TPointF; const aRCSOffsets: TPointFArray;
  aPlumeColor: TAlphaColor; aPlumeLength, aPlumeWidth, aRCSRadius: Single);
var
  Matrix: TMatrix;
  AngleDeg: Single;
  Paint: ISkPaint;
  Scale: Single;
  BaseLen, BaseWidth: Single;
  Len, Width: Single;
  Rect: TRectF;
  I: Integer;
  Radius: Single;
begin
  // Build the same transform as RenderCraft: world-to-screen + translate + rotate.
  AngleDeg := aState.Angle * (180 / Pi);
  Matrix := BuildWorldToScreenMatrix(aViewport);

  aCanvas.Save;
  try
    aCanvas.Concat(Matrix);
    aCanvas.Translate(aState.X, aState.Y);
    aCanvas.Rotate(AngleDeg, 0, 0);

    // Main engine plume: draw when thrusting with fuel available.
    if (aState.Thrust > 0) and (aState.Fuel > 0) then
    begin
      Paint := TSkPaint.Create;
      Paint.Style := TSkPaintStyle.Fill;
      Paint.AntiAlias := True;

      // Scale plume size proportional to throttle level.
      Scale := 0.4 + 0.6 * aState.Thrust;

      // Use profile-defined plume dimensions.
      BaseLen := aPlumeLength * Scale;
      BaseWidth := aPlumeWidth * Scale;

      // First oval: main bright core.
      Len := BaseLen * (0.8 + Random * 0.4);
      Width := BaseWidth * (0.7 + Random * 0.6);
      Paint.Color := (aPlumeColor and $00FFFFFF) or $B0000000; // Alpha ~$B0
      Rect := RectF(
        aThrustOffset.X - Width / 2,
        aThrustOffset.Y,
        aThrustOffset.X + Width / 2,
        aThrustOffset.Y + Len
      );
      aCanvas.DrawOval(Rect, Paint);

      // Second oval: slightly larger, more transparent outer glow.
      Len := BaseLen * (0.9 + Random * 0.5);
      Width := BaseWidth * (0.9 + Random * 0.7);
      Paint.Color := (aPlumeColor and $00FFFFFF) or $80000000; // Alpha ~$80
      Rect := RectF(
        aThrustOffset.X - Width / 2,
        aThrustOffset.Y - Len * 0.05,
        aThrustOffset.X + Width / 2,
        aThrustOffset.Y + Len
      );
      aCanvas.DrawOval(Rect, Paint);

      // Third oval: narrow hot core with random variation.
      Len := BaseLen * (0.5 + Random * 0.5);
      Width := BaseWidth * (0.3 + Random * 0.4);
      Paint.Color := (aPlumeColor and $00FFFFFF) or $C0000000; // Alpha ~$C0
      Rect := RectF(
        aThrustOffset.X - Width / 2,
        aThrustOffset.Y + Len * 0.1,
        aThrustOffset.X + Width / 2,
        aThrustOffset.Y + Len
      );
      aCanvas.DrawOval(Rect, Paint);

    end;

    // RCS puffs: draw when rotating with RCS fuel available.
    if (aState.RotatingLeft or aState.RotatingRight) and (aState.RCSFuel > 0) then
    begin
      Paint := TSkPaint.Create;
      Paint.Style := TSkPaintStyle.Fill;
      Paint.AntiAlias := True;
      // White/light blue with low alpha for translucent puffs.
      Paint.Color := $50D0E8FF;

      for I := 0 to High(aRCSOffsets) do
      begin
        // Vary radius slightly per puff for subtle flicker.
        Radius := aRCSRadius * (0.7 + Random * 0.6);
        aCanvas.DrawCircle(aRCSOffsets[I].X, aRCSOffsets[I].Y, Radius, Paint);
      end;
    end;
  finally
    aCanvas.Restore;
  end;
end;

end.
