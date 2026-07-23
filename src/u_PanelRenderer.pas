unit u_PanelRenderer;

interface

uses
  System.Types, System.UITypes, System.Skia,
  u_Models, u_FontManager, u_PanelLayout, u_PanelComputed, u_WidgetPainters,
  u_Terrain;

type
  // Orchestrates drawing the entire instrument panel surface each frame.
  // Owns layout computation, delegates widget rendering to paint procedures.
  TPanelRenderer = class
  private
    fFont: ISkFont;
    fSmallFont: ISkFont;
    fTypeface: ISkTypeface;
    fPanelState: TPanelState;
    fCraftProfile: TCraftProfile;
    fWorldProfile: TWorldProfile;
    fAltitude: Single;
    fTimeToBurn: Single;
    // Game chrome state
    fFlightTime: Single;
    fLives: Integer;
    fScore: Integer;
  public
    // Resolves typeface, creates font instances, stores profile references.
    procedure Init(aProfile: TCraftProfile; aWorld: TWorldProfile;
      aFontManager: TFontManager);

    // Copies live state into internal fields; computes altitude and derived
    // values. Skipped when frozen.
    procedure UpdateState(const aState: TCraftState);

    // Updates game chrome values (timer, lives, score).
    procedure UpdateChrome(aFlightTime: Single; aLives, aScore: Integer);

    // Freezes panel state from given craft state + altitude. Sets Frozen = True.
    // Ignores subsequent captures.
    procedure CaptureSnapshot(const aState: TCraftState; aAltitude: Single);

    // Unfreezes the panel so it resumes live updates.
    procedure Unfreeze;

    // Draws background, computes layout, iterates slots calling widget painters.
    procedure RenderPanel(const aCanvas: ISkCanvas; aWidth, aHeight: Single);

    property PanelState: TPanelState read fPanelState;
  end;

implementation

uses
  System.SysUtils;

procedure TPanelRenderer.Init(aProfile: TCraftProfile; aWorld: TWorldProfile;
  aFontManager: TFontManager);
begin
  fCraftProfile := aProfile;
  fWorldProfile := aWorld;

  // Resolve typeface
  fTypeface := aFontManager.GetTypeface(aProfile.PanelFontFamily);
  fFont := TSkFont.Create(fTypeface, 16);
  fSmallFont := TSkFont.Create(fTypeface, 11);

  fPanelState.Frozen := False;
  fAltitude := -1;
  fTimeToBurn := -1;
  fFlightTime := 0;
  fLives := 0;
  fScore := 0;
end;

procedure TPanelRenderer.UpdateState(const aState: TCraftState);
begin
  if fPanelState.Frozen then
    Exit;

  // Compute altitude
  fAltitude := CalcAltitude(aState.X, aState.Y, fWorldProfile);

  // Compute time-to-burn
  fTimeToBurn := ComputeTimeToBurn(
    aState.VY, fAltitude,
    fCraftProfile.ThrustPower, fCraftProfile.Mass,
    fWorldProfile.Gravity);

  // Store state for snapshot access
  fPanelState.Fuel := aState.Fuel;
  fPanelState.RCSFuel := aState.RCSFuel;
  fPanelState.VX := aState.VX;
  fPanelState.VY := aState.VY;
  fPanelState.Altitude := fAltitude;
  fPanelState.Angle := aState.Angle;
  fPanelState.SASActive := aState.SASActive;
end;

procedure TPanelRenderer.UpdateChrome(aFlightTime: Single; aLives, aScore: Integer);
begin
  fFlightTime := aFlightTime;
  fLives := aLives;
  fScore := aScore;
end;

procedure TPanelRenderer.CaptureSnapshot(const aState: TCraftState;
  aAltitude: Single);
begin
  // Only capture once
  if fPanelState.Frozen then
    Exit;

  fPanelState.Fuel := aState.Fuel;
  fPanelState.RCSFuel := aState.RCSFuel;
  fPanelState.VX := aState.VX;
  fPanelState.VY := aState.VY;
  fPanelState.Altitude := aAltitude;
  fPanelState.Angle := aState.Angle;
  fPanelState.SASActive := aState.SASActive;
  fPanelState.Frozen := True;

  fAltitude := aAltitude;
  fTimeToBurn := ComputeTimeToBurn(
    aState.VY, aAltitude,
    fCraftProfile.ThrustPower, fCraftProfile.Mass,
    fWorldProfile.Gravity);
end;

procedure TPanelRenderer.Unfreeze;
begin
  fPanelState.Frozen := False;
end;

procedure TPanelRenderer.RenderPanel(const aCanvas: ISkCanvas;
  aWidth, aHeight: Single);
const
  CChromeWidth = 80.0;  // Reserved width for game chrome on left
var
  Paint: ISkPaint;
  I: Integer;
  Painter: TWidgetPaintProc;
  State: TCraftState;
  ChromeRect: TRectF;
  TimeStr, LivesStr, ScoreStr: string;
  Mins, Secs: Integer;
  Y: Single;
  InstrSlots: TArray<TSlot>;
begin
  Paint := TSkPaint.Create;

  // Background: dark flat fill
  Paint.Style := TSkPaintStyle.Fill;
  Paint.Color := $FF1A1A1A;
  aCanvas.DrawRect(TRectF.Create(0, 0, aWidth, aHeight), Paint);

  // Chrome zone background (slightly lighter)
  ChromeRect := TRectF.Create(0, 0, CChromeWidth, aHeight);
  Paint.Color := $FF222222;
  aCanvas.DrawRect(ChromeRect, Paint);

  // Top border line (bright, 2px)
  Paint.Style := TSkPaintStyle.Stroke;
  Paint.StrokeWidth := 2;
  Paint.Color := $FF4488AA;
  aCanvas.DrawLine(PointF(0, 1), PointF(aWidth, 1), Paint);

  // Chrome zone: vertical divider on right edge
  Paint.StrokeWidth := 1;
  Paint.Color := $30FFFFFF;
  aCanvas.DrawLine(PointF(CChromeWidth, 6), PointF(CChromeWidth, aHeight - 4), Paint);

  // Render chrome: TIME, LIVES, SCORE stacked vertically
  Paint.Style := TSkPaintStyle.Fill;
  Y := 18;

  // Flight time (MM:SS format)
  Mins := Trunc(fFlightTime) div 60;
  Secs := Trunc(fFlightTime) mod 60;
  TimeStr := Format('%.2d:%.2d', [Mins, Secs]);
  Paint.Color := $FF808080;
  aCanvas.DrawSimpleText('TIME', 8, Y, fSmallFont, Paint);
  Y := Y + 14;
  Paint.Color := $FFE0E0E0;
  aCanvas.DrawSimpleText(TimeStr, 8, Y, fFont, Paint);

  // Lives
  Y := Y + 24;
  LivesStr := IntToStr(fLives);
  Paint.Color := $FF808080;
  aCanvas.DrawSimpleText('LIVES', 8, Y, fSmallFont, Paint);
  Y := Y + 14;
  if fLives > 1 then
    Paint.Color := $FF33FF66
  else if fLives = 1 then
    Paint.Color := $FFFFAA00
  else
    Paint.Color := $FFFF3333;
  aCanvas.DrawSimpleText(LivesStr, 8, Y, fFont, Paint);

  // Score
  Y := Y + 24;
  ScoreStr := IntToStr(fScore);
  Paint.Color := $FF808080;
  aCanvas.DrawSimpleText('SCORE', 8, Y, fSmallFont, Paint);
  Y := Y + 14;
  Paint.Color := $FFFFDD44;
  aCanvas.DrawSimpleText(ScoreStr, 8, Y, fFont, Paint);

  // Compute instrument layout (offset by chrome zone width)
  // We pass a reduced width and will offset slot rects when rendering
  InstrSlots := ComputeSlots(fCraftProfile.Instruments,
    aWidth - CChromeWidth, aHeight, fCraftProfile.HasSAS);

  // Build a TCraftState from panel state for widget painters
  State := Default(TCraftState);
  State.Fuel := fPanelState.Fuel;
  State.RCSFuel := fPanelState.RCSFuel;
  State.VX := fPanelState.VX;
  State.VY := fPanelState.VY;
  State.Angle := fPanelState.Angle;
  State.SASActive := fPanelState.SASActive;

  // Render each instrument slot (offset by chrome width)
  for I := 0 to High(InstrSlots) do
  begin
    var SlotRect: TRectF;
    SlotRect := InstrSlots[I].Rect;
    SlotRect.Offset(CChromeWidth, 0);

    // Vertical divider between slots (faint)
    if I > 0 then
    begin
      Paint.Style := TSkPaintStyle.Stroke;
      Paint.StrokeWidth := 1;
      Paint.Color := $20FFFFFF;
      aCanvas.DrawLine(
        PointF(SlotRect.Left - 3, 6),
        PointF(SlotRect.Left - 3, aHeight - 4),
        Paint);
    end;

    // Call widget painter
    Painter := GetWidgetPainter(InstrSlots[I].Kind);
    if Assigned(Painter) then
      Painter(aCanvas, SlotRect, State, fCraftProfile,
        fAltitude, fTimeToBurn, fFont, fSmallFont);
  end;
end;

end.
