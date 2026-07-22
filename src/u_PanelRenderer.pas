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
    fSlots: TArray<TSlot>;
    fPanelState: TPanelState;
    fCraftProfile: TCraftProfile;
    fWorldProfile: TWorldProfile;
    fAltitude: Single;
    fTimeToBurn: Single;
  public
    // Resolves typeface, creates font instances, stores profile references.
    procedure Init(aProfile: TCraftProfile; aWorld: TWorldProfile;
      aFontManager: TFontManager);

    // Copies live state into internal fields; computes altitude and derived
    // values. Skipped when frozen.
    procedure UpdateState(const aState: TCraftState);

    // Freezes panel state from given craft state + altitude. Sets Frozen = True.
    // Ignores subsequent captures.
    procedure CaptureSnapshot(const aState: TCraftState; aAltitude: Single);

    // Draws background, computes layout, iterates slots calling widget painters.
    procedure RenderPanel(const aCanvas: ISkCanvas; aWidth, aHeight: Single);

    property PanelState: TPanelState read fPanelState;
  end;

implementation

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

procedure TPanelRenderer.RenderPanel(const aCanvas: ISkCanvas;
  aWidth, aHeight: Single);
var
  Paint: ISkPaint;
  I: Integer;
  Painter: TWidgetPaintProc;
  State: TCraftState;
begin
  Paint := TSkPaint.Create;

  // Background: dark flat fill
  Paint.Style := TSkPaintStyle.Fill;
  Paint.Color := $FF1A1A1A;
  aCanvas.DrawRect(TRectF.Create(0, 0, aWidth, aHeight), Paint);

  // Top border line (bright, 2px)
  Paint.Style := TSkPaintStyle.Stroke;
  Paint.StrokeWidth := 2;
  Paint.Color := $FF4488AA;
  aCanvas.DrawLine(PointF(0, 1), PointF(aWidth, 1), Paint);

  // Compute layout
  fSlots := ComputeSlots(fCraftProfile.Instruments, aWidth, aHeight,
    fCraftProfile.HasSAS);

  // Build a TCraftState from panel state for widget painters
  State := Default(TCraftState);
  State.Fuel := fPanelState.Fuel;
  State.RCSFuel := fPanelState.RCSFuel;
  State.VX := fPanelState.VX;
  State.VY := fPanelState.VY;
  State.Angle := fPanelState.Angle;
  State.SASActive := fPanelState.SASActive;

  // Render each slot
  for I := 0 to High(fSlots) do
  begin
    // Vertical divider between slots (faint)
    if I > 0 then
    begin
      Paint.Style := TSkPaintStyle.Stroke;
      Paint.StrokeWidth := 1;
      Paint.Color := $20FFFFFF;
      aCanvas.DrawLine(
        PointF(fSlots[I].Rect.Left - 3, 6),
        PointF(fSlots[I].Rect.Left - 3, aHeight - 4),
        Paint);
    end;

    // Call widget painter
    Painter := GetWidgetPainter(fSlots[I].Kind);
    if Assigned(Painter) then
      Painter(aCanvas, fSlots[I].Rect, State, fCraftProfile,
        fAltitude, fTimeToBurn, fFont, fSmallFont);
  end;
end;

end.
