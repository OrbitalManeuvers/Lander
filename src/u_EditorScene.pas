unit u_EditorScene;

interface

uses
  System.Skia,
  u_Models, u_SceneBase, u_FlightRenderer;

type
  // Terrain editor scene — keyboard-driven, grid-aligned cursor,
  // procedural feature placement.
  TEditorScene = class(TGameScene)
  private
    fRenderer: TFlightRenderer;
    fWorld: TWorldProfile;
    fFilePath: string;
    fCursor: TEditorCursor;
    fViewport: TViewport;
    fTime: Single;
    fSelectedFeature: Integer;   // 0 = pad, 1-9 = terrain features
    fLastSeed: Integer;          // seed used for last generation
    fDirty: Boolean;             // unsaved changes flag
    fStatusText: string;         // current status message for overlay
    fStatusTimer: Single;        // countdown timer to clear status text
    function CursorOverlapsPad: Boolean;
    procedure PlaceFeature(aKind: TFeatureKind);
    procedure PlacePad;
    procedure ScaleRelief(aFactor: Single);
    procedure InitFromWorld;
  public
    constructor Create(const aFilePath: string); overload;
    constructor Create(const aFilePath: string; aWorld: TWorldProfile); overload;
    destructor Destroy; override;
    function RequiredLayout: TLayoutMode; override;

    procedure HandleInput(aKeyCode: Word; aKeyState: TKeyState); override;
    procedure Tick; override;
    procedure Render(const aCanvas: ISkCanvas; aWidth, aHeight: Integer); override;
    procedure RenderPanel(const aCanvas: ISkCanvas; aWidth, aHeight: Integer); override;

    // Transfers world ownership to caller (editor no longer frees it)
    function DetachWorld: TWorldProfile;
  end;

implementation

uses
  System.SysUtils, System.Types, System.UITypes, System.Math,
  Winapi.Windows, u_Serialization, u_TerrainFeatureGen;

{ TEditorScene }

constructor TEditorScene.Create(const aFilePath: string);
begin
  inherited Create;
  fFilePath := aFilePath;
  fWorld := LoadWorldFromJSON(aFilePath);
  InitFromWorld;
end;

constructor TEditorScene.Create(const aFilePath: string; aWorld: TWorldProfile);
begin
  inherited Create;
  fFilePath := aFilePath;
  fWorld := aWorld;  // Takes ownership
  InitFromWorld;
end;

procedure TEditorScene.InitFromWorld;
var
  midIndex: Integer;
begin
  fRenderer := TFlightRenderer.Create;
  fRenderer.SetTerrain(fWorld.Terrain, fWorld.Pads);

  // Initialize cursor at grid center with width 3
  fCursor.GridWidth := 3;
  if Length(fWorld.Terrain) > 0 then
  begin
    midIndex := Length(fWorld.Terrain) div 2;
    fCursor.GridX := Round(fWorld.Terrain[midIndex].X) div 10;
    fCursor.Altitude := fWorld.Terrain[midIndex].Y;
  end
  else
  begin
    fCursor.GridX := 0;
    fCursor.Altitude := 800.0;
  end;

  fSelectedFeature := 1;
  fLastSeed := Random(MaxInt);
  fDirty := False;
  fTime := 0;
end;

destructor TEditorScene.Destroy;
begin
  fRenderer.Free;
  fWorld.Free;
  inherited;
end;

function TEditorScene.DetachWorld: TWorldProfile;
begin
  Result := fWorld;
  fWorld := nil;  // Caller takes ownership; destructor won't free it
end;

procedure TEditorScene.ScaleRelief(aFactor: Single);
var
  startX, endX: Single;
  maxY: Single;
  i: Integer;
  terrain: TTerrainArray;
  delta: Single;
begin
  // Reject if cursor overlaps a landing pad
  if CursorOverlapsPad then
    Exit;

  startX := fCursor.GridX * 10.0;
  endX := startX + fCursor.GridWidth * 10.0;

  terrain := fWorld.Terrain;

  // Find the floor (maximum Y) within the cursor range — this is the anchor
  maxY := -1e9;
  for i := 0 to High(terrain) do
  begin
    if (terrain[i].X >= startX) and (terrain[i].X <= endX) then
    begin
      if terrain[i].Y > maxY then
        maxY := terrain[i].Y;
    end;
  end;

  if maxY <= -1e9 then
    Exit;  // No points in range

  // Scale each point's distance from the floor
  for i := 0 to High(terrain) do
  begin
    if (terrain[i].X >= startX) and (terrain[i].X <= endX) then
    begin
      delta := maxY - terrain[i].Y;  // Distance above floor (positive)
      terrain[i].Y := maxY - delta * aFactor;
    end;
  end;

  fWorld.Terrain := terrain;
  fRenderer.SetTerrain(fWorld.Terrain, fWorld.Pads);
  fDirty := True;
end;

procedure TEditorScene.HandleInput(aKeyCode: Word; aKeyState: TKeyState);
var
  shiftHeld: Boolean;
begin
  if aKeyState <> ksDown then
    Exit;

  shiftHeld := GetKeyState(VK_SHIFT) < 0;

  case aKeyCode of
    VK_LEFT:
      begin
        if shiftHeld then
        begin
          // Decrease cursor width (minimum 1)
          if fCursor.GridWidth > 1 then
            Dec(fCursor.GridWidth);
        end
        else
        begin
          // Move cursor left (minimum 0)
          if fCursor.GridX > 0 then
            Dec(fCursor.GridX);
        end;
      end;

    VK_RIGHT:
      begin
        if shiftHeld then
        begin
          // Increase cursor width
          Inc(fCursor.GridWidth);
        end
        else
        begin
          // Move cursor right
          Inc(fCursor.GridX);
        end;
      end;

    VK_UP:
      begin
        if shiftHeld then
          ScaleRelief(1.1)  // Shift+Up: make craggier
        else
          // Decrease altitude (lower Y = higher on screen)
          fCursor.Altitude := fCursor.Altitude - 10;
      end;

    VK_DOWN:
      begin
        if shiftHeld then
          ScaleRelief(0.9)  // Shift+Down: make smoother
        else
          // Increase altitude (higher Y = lower on screen)
          fCursor.Altitude := fCursor.Altitude + 10;
      end;

    VK_SPACE:
      begin
        // Re-roll seed
        fLastSeed := Random(MaxInt);
      end;

    VK_ESCAPE:
      begin
        SetFinished(sidMenu);
      end;
  else
    // Number keys 0-9: select feature and place
    if (aKeyCode >= Ord('0')) and (aKeyCode <= Ord('9')) then
    begin
      fSelectedFeature := aKeyCode - Ord('0');
      if fSelectedFeature = 0 then
        PlacePad
      else
        PlaceFeature(TFeatureKind(fSelectedFeature - 1));
    end
    // P key: play the current terrain
    else if aKeyCode = Ord('P') then
    begin
      SetFinished(sidPlay);
    end
    // S key: save world to JSON
    else if aKeyCode = Ord('S') then
    begin
      try
        SaveWorldToJSON(fWorld, fFilePath);
        fDirty := False;
        fStatusText := 'SAVED';
      except
        fStatusText := 'SAVE FAILED';
      end;
      fStatusTimer := 2.0;
    end;
  end;
end;

function TEditorScene.CursorOverlapsPad: Boolean;
var
  startX, endX: Single;
  padStartX, padEndX: Single;
  i: Integer;
begin
  Result := False;
  startX := fCursor.GridX * 10.0;
  endX := startX + fCursor.GridWidth * 10.0;

  for i := 0 to High(fWorld.Pads) do
  begin
    if (fWorld.Pads[i].StartIndex < 0) or
       (fWorld.Pads[i].EndIndex > High(fWorld.Terrain)) then
      Continue;

    padStartX := fWorld.Terrain[fWorld.Pads[i].StartIndex].X;
    padEndX := fWorld.Terrain[fWorld.Pads[i].EndIndex].X;

    // Check for overlap between [startX, endX] and [padStartX, padEndX]
    if (startX < padEndX) and (endX > padStartX) then
    begin
      Result := True;
      Exit;
    end;
  end;
end;

procedure TEditorScene.PlaceFeature(aKind: TFeatureKind);
var
  worldX, worldEnd: Single;
  newPoints: TTerrainArray;
  terrain: TTerrainArray;
  pads: TPadArray;
  cutStart, cutEnd: Integer;
  removedCount, delta: Integer;
  insertIdx: Integer;
  resultTerrain: TTerrainArray;
  i, j: Integer;
begin
  // Reject if cursor overlaps a landing pad
  if CursorOverlapsPad then
  begin
    fStatusText := 'PAD PROTECTED';
    Exit;
  end;

  worldX := fCursor.GridX * 10.0;
  worldEnd := worldX + fCursor.GridWidth * 10.0;

  // Generate new terrain segment
  newPoints := TTerrainFeatureGen.Generate(aKind, worldX,
    fCursor.GridWidth * 10.0, fCursor.Altitude, fLastSeed);

  terrain := fWorld.Terrain;

  // Find points within the cursor X range to remove
  cutStart := -1;
  cutEnd := -1;
  for i := 0 to High(terrain) do
  begin
    if (terrain[i].X >= worldX) and (terrain[i].X <= worldEnd) then
    begin
      if cutStart = -1 then
        cutStart := i;
      cutEnd := i;
    end;
  end;

  // Calculate how many points will be removed
  if cutStart >= 0 then
    removedCount := cutEnd - cutStart + 1
  else
    removedCount := 0;

  // Determine insertion index
  if cutStart >= 0 then
    insertIdx := cutStart
  else
  begin
    // Find first point with X > worldX
    insertIdx := Length(terrain);
    for i := 0 to High(terrain) do
    begin
      if terrain[i].X > worldX then
      begin
        insertIdx := i;
        Break;
      end;
    end;
  end;

  // Build the new terrain array: before cut + newPoints + after cut
  SetLength(resultTerrain, Length(terrain) - removedCount + Length(newPoints));

  // Copy points before cut/insert position
  j := 0;
  for i := 0 to insertIdx - 1 do
  begin
    resultTerrain[j] := terrain[i];
    Inc(j);
  end;

  // Insert new points
  for i := 0 to High(newPoints) do
  begin
    resultTerrain[j] := newPoints[i];
    Inc(j);
  end;

  // Copy points after the cut region
  if cutStart >= 0 then
  begin
    for i := cutEnd + 1 to High(terrain) do
    begin
      resultTerrain[j] := terrain[i];
      Inc(j);
    end;
  end
  else
  begin
    for i := insertIdx to High(terrain) do
    begin
      resultTerrain[j] := terrain[i];
      Inc(j);
    end;
  end;

  // Calculate index delta for pad adjustment
  delta := Length(newPoints) - removedCount;

  // Adjust pad indices — copy to local, modify, assign back
  // (Delphi won't let you modify fields of a property-returned array element)
  pads := fWorld.Pads;
  for i := 0 to High(pads) do
  begin
    if pads[i].StartIndex >= insertIdx then
    begin
      pads[i].StartIndex := pads[i].StartIndex + delta;
      pads[i].EndIndex := pads[i].EndIndex + delta;
    end;
  end;
  fWorld.Pads := pads;

  // Apply the modified terrain
  fWorld.Terrain := resultTerrain;

  // Rebuild renderer cache
  fRenderer.SetTerrain(fWorld.Terrain, fWorld.Pads);
  fDirty := True;
  fStatusText := TTerrainFeatureGen.FeatureName(aKind);
end;

procedure TEditorScene.PlacePad;
var
  worldX, worldEnd: Single;
  flatPoints: TTerrainArray;
  terrain: TTerrainArray;
  pads: TPadArray;
  cutStart, cutEnd: Integer;
  removedCount, delta: Integer;
  insertIdx: Integer;
  resultTerrain: TTerrainArray;
  count, i, j: Integer;
  pad: TPad;
begin
  worldX := fCursor.GridX * 10.0;
  worldEnd := worldX + fCursor.GridWidth * 10.0;

  // Generate flat points at cursor altitude across the width
  count := fCursor.GridWidth + 1;
  if count < 2 then
    count := 2;
  SetLength(flatPoints, count);
  for i := 0 to count - 1 do
    flatPoints[i] := PointF(worldX + i * 10.0, fCursor.Altitude);

  terrain := fWorld.Terrain;

  // Find points within the cursor X range to remove
  cutStart := -1;
  cutEnd := -1;
  for i := 0 to High(terrain) do
  begin
    if (terrain[i].X >= worldX) and (terrain[i].X <= worldEnd) then
    begin
      if cutStart = -1 then
        cutStart := i;
      cutEnd := i;
    end;
  end;

  // Calculate how many points will be removed
  if cutStart >= 0 then
    removedCount := cutEnd - cutStart + 1
  else
    removedCount := 0;

  // Determine insertion index
  if cutStart >= 0 then
    insertIdx := cutStart
  else
  begin
    // Find first point with X > worldX
    insertIdx := Length(terrain);
    for i := 0 to High(terrain) do
    begin
      if terrain[i].X > worldX then
      begin
        insertIdx := i;
        Break;
      end;
    end;
  end;

  // Build the new terrain array: before cut + flatPoints + after cut
  SetLength(resultTerrain, Length(terrain) - removedCount + Length(flatPoints));

  // Copy points before cut/insert position
  j := 0;
  for i := 0 to insertIdx - 1 do
  begin
    resultTerrain[j] := terrain[i];
    Inc(j);
  end;

  // Insert flat pad points
  for i := 0 to High(flatPoints) do
  begin
    resultTerrain[j] := flatPoints[i];
    Inc(j);
  end;

  // Copy points after the cut region
  if cutStart >= 0 then
  begin
    for i := cutEnd + 1 to High(terrain) do
    begin
      resultTerrain[j] := terrain[i];
      Inc(j);
    end;
  end
  else
  begin
    for i := insertIdx to High(terrain) do
    begin
      resultTerrain[j] := terrain[i];
      Inc(j);
    end;
  end;

  // Calculate index delta for existing pad adjustment
  delta := Length(flatPoints) - removedCount;

  // Adjust existing pad indices — copy to local, modify, assign back
  pads := fWorld.Pads;
  for i := 0 to High(pads) do
  begin
    if pads[i].StartIndex >= insertIdx then
    begin
      pads[i].StartIndex := pads[i].StartIndex + delta;
      pads[i].EndIndex := pads[i].EndIndex + delta;
    end;
  end;

  // Add new pad entry with indices of the inserted flat segment
  pad.StartIndex := insertIdx;
  pad.EndIndex := insertIdx + Length(flatPoints) - 1;
  pad.PointValue := 50;

  SetLength(pads, Length(pads) + 1);
  pads[High(pads)] := pad;
  fWorld.Pads := pads;

  // Apply the modified terrain
  fWorld.Terrain := resultTerrain;

  // Rebuild renderer cache
  fRenderer.SetTerrain(fWorld.Terrain, fWorld.Pads);
  fDirty := True;
  fStatusText := 'Landing Pad';
end;

procedure TEditorScene.Tick;
begin
  // Advance time for starfield animation (assuming 60fps timer)
  fTime := fTime + 1 / 60;

  // Count down status text timer
  if fStatusTimer > 0 then
  begin
    fStatusTimer := fStatusTimer - 1 / 60;
    if fStatusTimer <= 0 then
    begin
      fStatusTimer := 0;
      fStatusText := '';
    end;
  end;
end;

procedure TEditorScene.Render(const aCanvas: ISkCanvas; aWidth, aHeight: Integer);
var
  worldWidth, worldHeight: Single;
  scaleX, scaleY, scale: Single;
  offsetX, offsetY: Single;
  cursorLeftX, cursorRightX: Single;
  screenLeft, screenRight: Single;
  screenAltY: Single;
  paint: ISkPaint;
  rect: TRectF;
  typeface: ISkTypeface;
  font: ISkFont;
  textBounds: TRectF;
  textX, textY: Single;
begin
  // Draw starfield background
  fRenderer.RenderStarfield(aCanvas, aWidth, aHeight, fTime);

  // Fixed 1500-unit wide viewport, terrain pinned to left edge
  fViewport.ViewLeft := 0;
  fViewport.ViewRight := 1500;
  fViewport.ViewTop := 600;
  fViewport.ViewBottom := 1000;
  fViewport.ScreenWidth := aWidth;
  fViewport.ScreenHeight := aHeight;
  fRenderer.RenderTerrain(aCanvas, fViewport, fWorld.TerrainColor, fWorld.PadColor);

  // Compute world-to-screen transform (matching BuildWorldToScreenMatrix logic)
  worldWidth := fViewport.ViewRight - fViewport.ViewLeft;
  worldHeight := fViewport.ViewBottom - fViewport.ViewTop;
  if (worldWidth <= 0) or (worldHeight <= 0) then
    Exit;

  scaleX := fViewport.ScreenWidth / worldWidth;
  scaleY := fViewport.ScreenHeight / worldHeight;
  scale := Min(scaleX, scaleY);
  offsetX := (fViewport.ScreenWidth - worldWidth * scale) / 2;
  offsetY := fViewport.ScreenHeight - worldHeight * scale;

  // Cursor world X range
  cursorLeftX := fCursor.GridX * 10.0;
  cursorRightX := (fCursor.GridX + fCursor.GridWidth) * 10.0;

  // Convert to screen coordinates
  screenLeft := (cursorLeftX - fViewport.ViewLeft) * scale + offsetX;
  screenRight := (cursorRightX - fViewport.ViewLeft) * scale + offsetX;

  // Draw full-height semi-transparent selection column
  paint := TSkPaint.Create;
  paint.Style := TSkPaintStyle.Fill;
  paint.Color := $3300CCFF;  // Cyan at ~20% alpha
  paint.AntiAlias := True;
  rect := RectF(screenLeft, 0, screenRight, aHeight);
  aCanvas.DrawRect(rect, paint);

  // Draw cursor altitude indicator (horizontal line at cursor Y)
  screenAltY := (fCursor.Altitude - fViewport.ViewTop) * scale + offsetY;
  paint := TSkPaint.Create;
  paint.Style := TSkPaintStyle.Stroke;
  paint.Color := TAlphaColors.Yellow;
  paint.StrokeWidth := 2.0;
  paint.AntiAlias := True;
  aCanvas.DrawLine(PointF(screenLeft, screenAltY), PointF(screenRight, screenAltY), paint);

  // Draw status text overlay (bottom-left area)
  if fStatusText <> '' then
  begin
    typeface := TSkTypeface.MakeFromName('Consolas', TSkFontStyle.Normal);
    font := TSkFont.Create(typeface, 18);
    paint := TSkPaint.Create;
    paint.AntiAlias := True;
    paint.Color := TAlphaColors.White;
    font.MeasureText(fStatusText, textBounds, paint);
    textX := 12;
    textY := aHeight - 12;
    aCanvas.DrawSimpleText(fStatusText, textX, textY, font, paint);
  end;
end;

procedure TEditorScene.RenderPanel(const aCanvas: ISkCanvas; aWidth, aHeight: Integer);
var
  typeface: ISkTypeface;
  fontBold: ISkFont;
  fontNormal: ISkFont;
  paint: ISkPaint;
  textBounds: TRectF;
  y: Single;
  i: Integer;
  lineText: string;
  lineColor: TAlphaColor;

  procedure DrawSeparator;
  begin
    paint := TSkPaint.Create;
    paint.Style := TSkPaintStyle.Stroke;
    paint.Color := $FF555555;
    paint.StrokeWidth := 1.0;
    y := y + 8;
    aCanvas.DrawLine(PointF(10, y), PointF(aWidth - 10, y), paint);
    y := y + 12;
  end;

  procedure DrawLine(const aText: string; aColor: TAlphaColor; aFont: ISkFont);
  begin
    paint := TSkPaint.Create;
    paint.AntiAlias := True;
    paint.Color := aColor;
    aCanvas.DrawSimpleText(aText, 12, y, aFont, paint);
    y := y + 20;
  end;

begin
  // Background fill for panel
  paint := TSkPaint.Create;
  paint.Style := TSkPaintStyle.Fill;
  paint.Color := $FF1A1A1A;
  aCanvas.DrawRect(RectF(0, 0, aWidth, aHeight), paint);

  // Fonts
  typeface := TSkTypeface.MakeFromName('Consolas', TSkFontStyle.Bold);
  fontBold := TSkFont.Create(typeface, 18);
  typeface := TSkTypeface.MakeFromName('Consolas', TSkFontStyle.Normal);
  fontNormal := TSkFont.Create(typeface, 14);

  y := 28;

  // Title
  paint := TSkPaint.Create;
  paint.AntiAlias := True;
  paint.Color := TAlphaColors.White;
  fontBold.MeasureText('TERRAIN EDITOR', textBounds, paint);
  aCanvas.DrawSimpleText('TERRAIN EDITOR', (aWidth - textBounds.Width) / 2, y, fontBold, paint);
  y := y + 12;

  DrawSeparator;

  // Cursor info
  DrawLine('Width: ' + IntToStr(fCursor.GridWidth) + '  Alt: ' + IntToStr(Round(fCursor.Altitude)),
    TAlphaColors.White, fontNormal);
  y := y + 4;

  DrawSeparator;

  // Feature key legend
  for i := 1 to 10 do
  begin
    case i of
      1: lineText := '1 Jagged';
      2: lineText := '2 Rolling Hills';
      3: lineText := '3 Canyon';
      4: lineText := '4 Mountain';
      5: lineText := '5 Crater';
      6: lineText := '6 Cliff';
      7: lineText := '7 Flat';
      8: lineText := '8 Ridge Line';
      9: lineText := '9 Chaos';
      10: lineText := '0 Landing Pad';
    end;

    // Highlight the currently selected feature
    if ((i < 10) and (fSelectedFeature = i)) or
       ((i = 10) and (fSelectedFeature = 0)) then
      lineColor := TAlphaColors.Lime
    else
      lineColor := TAlphaColors.White;

    DrawLine(lineText, lineColor, fontNormal);
  end;

  y := y + 4;
  DrawSeparator;

  // Controls reference
  DrawLine(#$2190#$2192' Move', TAlphaColors.Darkgray, fontNormal);
  DrawLine(#$2191#$2193' Altitude', TAlphaColors.Darkgray, fontNormal);
  DrawLine('Shift+'#$2190#$2192' Width', TAlphaColors.Darkgray, fontNormal);
  DrawLine('Shift+'#$2191#$2193' Relief', TAlphaColors.Darkgray, fontNormal);
  DrawLine('Space Re-roll', TAlphaColors.Darkgray, fontNormal);
  DrawLine('S Save  P Play', TAlphaColors.Darkgray, fontNormal);
  DrawLine('Esc Exit', TAlphaColors.Darkgray, fontNormal);

  y := y + 4;
  DrawSeparator;

  // Dirty indicator
  if fDirty then
    DrawLine('* UNSAVED', TAlphaColors.Red, fontNormal);
end;

function TEditorScene.RequiredLayout: TLayoutMode;
begin
  Result := lmLeftPanel;
end;

end.
