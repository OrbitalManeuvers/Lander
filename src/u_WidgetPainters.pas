unit u_WidgetPainters;

interface

uses
  System.Types, System.UITypes, System.Math, System.SysUtils,
  System.Skia, u_Models, u_PanelComputed;

type
  // Paint procedure type for all instrument widgets.
  TWidgetPaintProc = procedure(const aCanvas: ISkCanvas; const aRect: TRectF;
    const aState: TCraftState; const aProfile: TCraftProfile;
    aAltitude, aTimeToBurn: Single;
    const aFont: ISkFont; const aSmallFont: ISkFont);

// Widget paint procedures
procedure PaintFuelGauge(const aCanvas: ISkCanvas; const aRect: TRectF;
  const aState: TCraftState; const aProfile: TCraftProfile;
  aAltitude, aTimeToBurn: Single;
  const aFont: ISkFont; const aSmallFont: ISkFont);

procedure PaintRCSGauge(const aCanvas: ISkCanvas; const aRect: TRectF;
  const aState: TCraftState; const aProfile: TCraftProfile;
  aAltitude, aTimeToBurn: Single;
  const aFont: ISkFont; const aSmallFont: ISkFont);

procedure PaintVelocity(const aCanvas: ISkCanvas; const aRect: TRectF;
  const aState: TCraftState; const aProfile: TCraftProfile;
  aAltitude, aTimeToBurn: Single;
  const aFont: ISkFont; const aSmallFont: ISkFont);

procedure PaintAltimeter(const aCanvas: ISkCanvas; const aRect: TRectF;
  const aState: TCraftState; const aProfile: TCraftProfile;
  aAltitude, aTimeToBurn: Single;
  const aFont: ISkFont; const aSmallFont: ISkFont);

procedure PaintAttitude(const aCanvas: ISkCanvas; const aRect: TRectF;
  const aState: TCraftState; const aProfile: TCraftProfile;
  aAltitude, aTimeToBurn: Single;
  const aFont: ISkFont; const aSmallFont: ISkFont);

procedure PaintSAS(const aCanvas: ISkCanvas; const aRect: TRectF;
  const aState: TCraftState; const aProfile: TCraftProfile;
  aAltitude, aTimeToBurn: Single;
  const aFont: ISkFont; const aSmallFont: ISkFont);

procedure PaintLandingGuidance(const aCanvas: ISkCanvas; const aRect: TRectF;
  const aState: TCraftState; const aProfile: TCraftProfile;
  aAltitude, aTimeToBurn: Single;
  const aFont: ISkFont; const aSmallFont: ISkFont);

// Registry: returns the paint procedure for a given instrument kind.
function GetWidgetPainter(aKind: TInstrumentKind): TWidgetPaintProc;

implementation

// Helper: draws text centered horizontally within a rect at a given Y.
procedure DrawTextCentered(const aCanvas: ISkCanvas; const aFont: ISkFont;
  const aPaint: ISkPaint; const aText: string; aRect: TRectF; aY: Single);
var
  Bounds: TRectF;
  TextX: Single;
begin
  aFont.MeasureText(aText, Bounds, aPaint);
  TextX := aRect.Left + (aRect.Width - Bounds.Width) / 2;
  aCanvas.DrawSimpleText(aText, TextX, aY, aFont, aPaint);
end;

// Helper: draws a vertical gauge bar (fuel/RCS style).
procedure DrawVerticalBar(const aCanvas: ISkCanvas; const aRect: TRectF;
  aPercent: Single; aColor: TAlphaColor; const aLabel: string;
  aUnits: Single; const aFont: ISkFont; const aSmallFont: ISkFont);
var
  Paint: ISkPaint;
  BarRect, FillRect: TRectF;
  LabelY, BarTop, BarBottom, FillHeight: Single;
  PercentStr, UnitsStr: string;
begin
  Paint := TSkPaint.Create;

  // Label at top
  LabelY := aRect.Top + 14;
  Paint.Color := $FFD0D0D0;
  DrawTextCentered(aCanvas, aSmallFont, Paint, aLabel, aRect, LabelY);

  // Bar area (below label, above bottom text)
  BarTop := aRect.Top + 20;
  BarBottom := aRect.Bottom - 30;

  // Bar outline
  BarRect := TRectF.Create(
    aRect.Left + 8, BarTop,
    aRect.Right - 8, BarBottom);
  Paint.Color := $FF505050;
  Paint.Style := TSkPaintStyle.Stroke;
  Paint.StrokeWidth := 1;
  aCanvas.DrawRect(BarRect, Paint);

  // Bar fill (bottom up)
  FillHeight := (BarBottom - BarTop) * aPercent;
  FillRect := TRectF.Create(
    BarRect.Left + 1, BarBottom - FillHeight,
    BarRect.Right - 1, BarBottom);
  Paint.Style := TSkPaintStyle.Fill;
  Paint.Color := aColor;
  aCanvas.DrawRect(FillRect, Paint);

  // Percentage text below bar
  PercentStr := IntToStr(Round(aPercent * 100)) + '%';
  Paint.Color := aColor;
  DrawTextCentered(aCanvas, aSmallFont, Paint, PercentStr, aRect, aRect.Bottom - 16);

  // Units text at very bottom
  UnitsStr := IntToStr(Round(aUnits));
  Paint.Color := $FFA0A0A0;
  DrawTextCentered(aCanvas, aSmallFont, Paint, UnitsStr, aRect, aRect.Bottom - 4);
end;

procedure PaintFuelGauge(const aCanvas: ISkCanvas; const aRect: TRectF;
  const aState: TCraftState; const aProfile: TCraftProfile;
  aAltitude, aTimeToBurn: Single;
  const aFont: ISkFont; const aSmallFont: ISkFont);
var
  Pct: Single;
  Color: TAlphaColor;
begin
  Pct := ComputeFuelPercent(aState.Fuel, aProfile.FuelCapacity);
  Color := GetGaugeColor(Pct);
  DrawVerticalBar(aCanvas, aRect, Pct, Color, 'FUEL', aState.Fuel,
    aFont, aSmallFont);
end;

procedure PaintRCSGauge(const aCanvas: ISkCanvas; const aRect: TRectF;
  const aState: TCraftState; const aProfile: TCraftProfile;
  aAltitude, aTimeToBurn: Single;
  const aFont: ISkFont; const aSmallFont: ISkFont);
var
  Pct: Single;
  Color: TAlphaColor;
begin
  Pct := ComputeRCSPercent(aState.RCSFuel, aProfile.RCSFuelCapacity);
  Color := GetGaugeColor(Pct);
  DrawVerticalBar(aCanvas, aRect, Pct, Color, 'RCS', aState.RCSFuel,
    aFont, aSmallFont);
end;

procedure PaintVelocity(const aCanvas: ISkCanvas; const aRect: TRectF;
  const aState: TCraftState; const aProfile: TCraftProfile;
  aAltitude, aTimeToBurn: Single;
  const aFont: ISkFont; const aSmallFont: ISkFont);
var
  Paint: ISkPaint;
  VXStr, VYStr: string;
  SignVX, SignVY: string;
  VYColor: TAlphaColor;
  Y: Single;
begin
  Paint := TSkPaint.Create;

  // Header label
  Paint.Color := $FFD0D0D0;
  DrawTextCentered(aCanvas, aSmallFont, Paint, 'VELOCITY', aRect, aRect.Top + 14);

  // VX sign and value
  if aState.VX >= 0 then SignVX := '+' else SignVX := '-';
  VXStr := Format('%s%.1f', [SignVX, Abs(aState.VX)]);

  // VY sign and value (positive = descent)
  if aState.VY >= 0 then SignVY := '+' else SignVY := '-';
  VYStr := Format('%s%.1f', [SignVY, Abs(aState.VY)]);

  // H-VEL label and value
  Y := aRect.Top + 40;
  Paint.Color := $FF909090;
  aCanvas.DrawSimpleText('H-VEL', aRect.Left + 4, Y, aSmallFont, Paint);
  Y := Y + 18;
  Paint.Color := $FFE0E0E0;
  aCanvas.DrawSimpleText(VXStr, aRect.Left + 4, Y, aFont, Paint);

  // V-VEL label and value (color-coded)
  Y := Y + 24;
  Paint.Color := $FF909090;
  aCanvas.DrawSimpleText('V-VEL', aRect.Left + 4, Y, aSmallFont, Paint);
  Y := Y + 18;
  VYColor := GetVelocityColor(Abs(aState.VY), aProfile.LandingCriteria.MaxSpeed);
  Paint.Color := VYColor;
  aCanvas.DrawSimpleText(VYStr, aRect.Left + 4, Y, aFont, Paint);
end;

procedure PaintAltimeter(const aCanvas: ISkCanvas; const aRect: TRectF;
  const aState: TCraftState; const aProfile: TCraftProfile;
  aAltitude, aTimeToBurn: Single;
  const aFont: ISkFont; const aSmallFont: ISkFont);
var
  Paint: ISkPaint;
  AltStr: string;
  AltInt: Integer;
  Y: Single;
begin
  Paint := TSkPaint.Create;

  // Label
  Paint.Color := $FFD0D0D0;
  DrawTextCentered(aCanvas, aSmallFont, Paint, 'ALT', aRect, aRect.Top + 14);

  // Value
  Y := aRect.Top + (aRect.Height / 2) + 8;
  if aAltitude < 0 then
    AltStr := '---'
  else
  begin
    AltInt := Min(Trunc(aAltitude), 99999);
    AltStr := IntToStr(AltInt);
  end;

  // Right-aligned
  Paint.Color := $FFE0E0E0;
  var Bounds: TRectF;
  aFont.MeasureText(AltStr, Bounds, Paint);
  var TextX := aRect.Right - Bounds.Width - 6;
  aCanvas.DrawSimpleText(AltStr, TextX, Y, aFont, Paint);
end;

procedure PaintAttitude(const aCanvas: ISkCanvas; const aRect: TRectF;
  const aState: TCraftState; const aProfile: TCraftProfile;
  aAltitude, aTimeToBurn: Single;
  const aFont: ISkFont; const aSmallFont: ISkFont);
var
  Paint: ISkPaint;
  CX, CY, Radius: Single;
  MaxAngleRad, AngleDeg, TickAngle: Single;
  NeedleX, NeedleY: Single;
  TickX1, TickY1, TickX2, TickY2: Single;
  I: Integer;
  Ticks: array[0..8] of Single;
  SafeRect: TRectF;
  PathBuilder: ISkPathBuilder;
  SafePath: ISkPath;
begin
  Paint := TSkPaint.Create;

  // Label
  Paint.Color := $FFD0D0D0;
  DrawTextCentered(aCanvas, aSmallFont, Paint, 'ATT', aRect, aRect.Top + 14);

  // Dial center and radius
  CX := aRect.Left + aRect.Width / 2;
  CY := aRect.Top + 20 + (aRect.Height - 34) / 2;
  Radius := Min(aRect.Width, aRect.Height - 34) / 2 - 4;

  // Outer circle
  Paint.Style := TSkPaintStyle.Stroke;
  Paint.StrokeWidth := 1.5;
  Paint.Color := $FF606060;
  aCanvas.DrawCircle(CX, CY, Radius, Paint);

  // Safe zone arc
  MaxAngleRad := aProfile.LandingCriteria.MaxAngle * (Pi / 180);
  SafeRect := TRectF.Create(CX - Radius + 4, CY - Radius + 4,
    CX + Radius - 4, CY + Radius - 4);
  Paint.Style := TSkPaintStyle.Fill;
  Paint.Color := $1A33FF66;  // Semi-transparent green

  // Draw safe zone as a filled arc from -MaxAngle to +MaxAngle
  // Skia arcs: 0° = right, so -90° = up. Our angle convention: 0 = up.
  // Safe zone: from (-MaxAngle - 90) to (+MaxAngle - 90) in Skia degrees
  AngleDeg := aProfile.LandingCriteria.MaxAngle;
  PathBuilder := TSkPathBuilder.Create;
  PathBuilder.MoveTo(PointF(CX, CY));
  PathBuilder.ArcTo(SafeRect, -90 - AngleDeg, AngleDeg * 2, False);
  PathBuilder.Close;
  SafePath := PathBuilder.Detach;
  aCanvas.DrawPath(SafePath, Paint);

  // Tick marks at 0, ±15, ±30, ±45, ±90
  Ticks[0] := 0;
  Ticks[1] := 15;  Ticks[2] := -15;
  Ticks[3] := 30;  Ticks[4] := -30;
  Ticks[5] := 45;  Ticks[6] := -45;
  Ticks[7] := 90;  Ticks[8] := -90;

  Paint.Style := TSkPaintStyle.Stroke;
  Paint.StrokeWidth := 1;
  Paint.Color := $FF909090;

  for I := 0 to 8 do
  begin
    TickAngle := Ticks[I] * (Pi / 180); // Convert to radians
    // In our coordinate system: 0 = up, positive = CW
    // Screen: up = -Y. Rotate from up (screen -Y direction)
    TickX1 := CX + Sin(TickAngle) * (Radius - 6);
    TickY1 := CY - Cos(TickAngle) * (Radius - 6);
    TickX2 := CX + Sin(TickAngle) * Radius;
    TickY2 := CY - Cos(TickAngle) * Radius;
    aCanvas.DrawLine(PointF(TickX1, TickY1), PointF(TickX2, TickY2), Paint);
  end;

  // Needle at current craft angle
  // aState.Angle is in radians, 0 = up, positive = CW
  NeedleX := CX + Sin(aState.Angle) * (Radius - 10);
  NeedleY := CY - Cos(aState.Angle) * (Radius - 10);

  Paint.StrokeWidth := 2;
  // Warning color if outside safe zone
  if Abs(aState.Angle) > MaxAngleRad then
    Paint.Color := $FFFF3333   // Red warning
  else
    Paint.Color := $FF33FF66;  // Green nominal

  aCanvas.DrawLine(PointF(CX, CY), PointF(NeedleX, NeedleY), Paint);

  // Center dot
  Paint.Style := TSkPaintStyle.Fill;
  Paint.Color := $FFE0E0E0;
  aCanvas.DrawCircle(CX, CY, 3, Paint);
end;

procedure PaintSAS(const aCanvas: ISkCanvas; const aRect: TRectF;
  const aState: TCraftState; const aProfile: TCraftProfile;
  aAltitude, aTimeToBurn: Single;
  const aFont: ISkFont; const aSmallFont: ISkFont);
var
  Paint: ISkPaint;
  CX, CY, LampRadius: Single;
begin
  Paint := TSkPaint.Create;

  // Label
  Paint.Color := $FFD0D0D0;
  DrawTextCentered(aCanvas, aSmallFont, Paint, 'SAS', aRect, aRect.Top + 14);

  // Lamp position
  CX := aRect.Left + aRect.Width / 2;
  CY := aRect.Top + (aRect.Height / 2);
  LampRadius := 10;

  // Filled circle: green = active, dim gray = inactive
  Paint.Style := TSkPaintStyle.Fill;
  if aState.SASActive then
    Paint.Color := $FF33FF66
  else
    Paint.Color := $FF404040;
  aCanvas.DrawCircle(CX, CY, LampRadius, Paint);

  // Outline
  Paint.Style := TSkPaintStyle.Stroke;
  Paint.StrokeWidth := 1;
  Paint.Color := $FF707070;
  aCanvas.DrawCircle(CX, CY, LampRadius, Paint);
end;

procedure PaintLandingGuidance(const aCanvas: ISkCanvas; const aRect: TRectF;
  const aState: TCraftState; const aProfile: TCraftProfile;
  aAltitude, aTimeToBurn: Single;
  const aFont: ISkFont; const aSmallFont: ISkFont);
var
  Paint: ISkPaint;
  ValueStr: string;
  Color: TAlphaColor;
  Y: Single;
begin
  Paint := TSkPaint.Create;

  // Label
  Paint.Color := $FFD0D0D0;
  DrawTextCentered(aCanvas, aSmallFont, Paint, 'T-BURN', aRect, aRect.Top + 14);

  // Determine display value and color
  if aTimeToBurn < 0 then
  begin
    // Unavailable (ascending, no terrain, insufficient thrust)
    ValueStr := '---';
    Color := $FF909090;
  end
  else
  begin
    ValueStr := Format('%.1f', [aTimeToBurn]);
    if aTimeToBurn > 10.0 then
      Color := $FF33FF66   // Green: plenty of time
    else if aTimeToBurn >= 0 then
      Color := $FFFFAA00   // Amber: burn soon
    else
      Color := $FFFF3333;  // Red: overdue
  end;

  // Draw centered value
  Y := aRect.Top + (aRect.Height / 2) + 8;
  Paint.Color := Color;
  DrawTextCentered(aCanvas, aFont, Paint, ValueStr, aRect, Y);
end;

function GetWidgetPainter(aKind: TInstrumentKind): TWidgetPaintProc;
begin
  case aKind of
    ikFuelGauge:       Result := PaintFuelGauge;
    ikRCSGauge:        Result := PaintRCSGauge;
    ikVelocity:        Result := PaintVelocity;
    ikAltimeter:       Result := PaintAltimeter;
    ikAttitude:        Result := PaintAttitude;
    ikSASIndicator:    Result := PaintSAS;
    ikLandingGuidance: Result := PaintLandingGuidance;
  else
    Result := nil;
  end;
end;

end.
