unit u_ResultScene;

interface

uses
  System.Types, System.UITypes, System.SysUtils, System.Skia,
  u_Models, u_SceneBase, u_FlightRenderer;

type
  // Displays landing/crash outcome with score breakdown.
  // Uses starfield background, entrance fade-in, exit fade-out to menu.
  TResultScene = class(TGameScene)
  private
    fOutcome: TPlayOutcome;
    fRenderer: TFlightRenderer;
    fTime: Single;
    fFadeAlpha: Single;   // 0 = fully visible, 1 = fully black
    fExiting: Boolean;    // True when fade-out triggered

    procedure UpdateFade;
  public
    constructor Create(const aOutcome: TPlayOutcome);
    destructor Destroy; override;

    procedure HandleInput(aKeyCode: Word; aKeyState: TKeyState); override;
    procedure Tick; override;
    procedure Render(const aCanvas: ISkCanvas; aWidth, aHeight: Integer); override;
  end;

implementation

uses
  System.Math;

const
  CTickDelta = 0.016;        // ~60 FPS assumed tick interval
  CFadeSpeed = 1.0 / 30.0;   // Fade over 30 ticks

{ TResultScene }

constructor TResultScene.Create(const aOutcome: TPlayOutcome);
begin
  inherited Create;
  fOutcome := aOutcome;
  fRenderer := TFlightRenderer.Create;
  fTime := 0;
  fFadeAlpha := 1.0;  // Start fully black (entrance fade-in)
  fExiting := False;
end;

destructor TResultScene.Destroy;
begin
  fRenderer.Free;
  inherited;
end;

procedure TResultScene.UpdateFade;
begin
  if fExiting then
  begin
    // Fade out to black
    fFadeAlpha := fFadeAlpha + CFadeSpeed;
    if fFadeAlpha >= 1.0 then
    begin
      fFadeAlpha := 1.0;
      SetFinished(sidMenu);
    end;
  end
  else
  begin
    // Entrance: fade in from black
    if fFadeAlpha > 0 then
    begin
      fFadeAlpha := fFadeAlpha - CFadeSpeed;
      if fFadeAlpha < 0 then
        fFadeAlpha := 0;
    end;
  end;
end;

procedure TResultScene.HandleInput(aKeyCode: Word; aKeyState: TKeyState);
begin
  if aKeyState <> ksDown then
    Exit;

  // Enter or Space returns to menu
  if (aKeyCode = 13) or (aKeyCode = 32) then
  begin
    if not fExiting then
      fExiting := True;
  end;
end;

procedure TResultScene.Tick;
begin
  fTime := fTime + CTickDelta;
  UpdateFade;
end;

procedure TResultScene.Render(const aCanvas: ISkCanvas; aWidth, aHeight: Integer);
var
  Typeface: ISkTypeface;
  Font: ISkFont;
  Paint: ISkPaint;
  TextBounds: TRectF;
  TextX, TextY: Single;
  Rect: TRectF;
begin
  // 1. Starfield background
  fRenderer.RenderStarfield(aCanvas, aWidth, aHeight, fTime);

  // 2. Outcome title
  Typeface := TSkTypeface.MakeFromName('Consolas', TSkFontStyle.Bold);
  Font := TSkFont.Create(Typeface, 48);
  Paint := TSkPaint.Create;
  Paint.AntiAlias := True;

  if fOutcome.Success then
  begin
    Paint.Color := TAlphaColors.Lime;
    Font.MeasureText('LANDED!', TextBounds, Paint);
    TextX := (aWidth - TextBounds.Width) / 2;
    TextY := aHeight * 0.25;
    aCanvas.DrawSimpleText('LANDED!', TextX, TextY, Font, Paint);

    // Score breakdown
    Typeface := TSkTypeface.MakeFromName('Consolas', TSkFontStyle.Normal);
    Font := TSkFont.Create(Typeface, 28);
    Paint := TSkPaint.Create;
    Paint.AntiAlias := True;
    Paint.Color := TAlphaColors.White;

    TextY := aHeight * 0.40;
    Font.MeasureText('Pad Points: ' + IntToStr(fOutcome.PadPoints), TextBounds, Paint);
    TextX := (aWidth - TextBounds.Width) / 2;
    aCanvas.DrawSimpleText('Pad Points: ' + IntToStr(fOutcome.PadPoints), TextX, TextY, Font, Paint);

    TextY := aHeight * 0.48;
    Font.MeasureText('Fuel Bonus: ' + IntToStr(fOutcome.FuelBonus), TextBounds, Paint);
    TextX := (aWidth - TextBounds.Width) / 2;
    aCanvas.DrawSimpleText('Fuel Bonus: ' + IntToStr(fOutcome.FuelBonus), TextX, TextY, Font, Paint);

    TextY := aHeight * 0.56;
    Paint.Color := TAlphaColors.Yellow;
    Font.MeasureText('Total: ' + IntToStr(fOutcome.TotalScore), TextBounds, Paint);
    TextX := (aWidth - TextBounds.Width) / 2;
    aCanvas.DrawSimpleText('Total: ' + IntToStr(fOutcome.TotalScore), TextX, TextY, Font, Paint);
  end
  else
  begin
    Paint.Color := TAlphaColors.Red;
    Font.MeasureText('CRASH!', TextBounds, Paint);
    TextX := (aWidth - TextBounds.Width) / 2;
    TextY := aHeight * 0.25;
    aCanvas.DrawSimpleText('CRASH!', TextX, TextY, Font, Paint);

    // Failure message with reasons
    Typeface := TSkTypeface.MakeFromName('Consolas', TSkFontStyle.Normal);
    Font := TSkFont.Create(Typeface, 28);
    Paint := TSkPaint.Create;
    Paint.AntiAlias := True;
    Paint.Color := TAlphaColors.White;

    TextY := aHeight * 0.40;

    if fOutcome.FailSpeed then
    begin
      Font.MeasureText('Too fast!', TextBounds, Paint);
      TextX := (aWidth - TextBounds.Width) / 2;
      aCanvas.DrawSimpleText('Too fast!', TextX, TextY, Font, Paint);
      TextY := TextY + aHeight * 0.08;
    end;

    if fOutcome.FailAngle then
    begin
      Font.MeasureText('Bad angle!', TextBounds, Paint);
      TextX := (aWidth - TextBounds.Width) / 2;
      aCanvas.DrawSimpleText('Bad angle!', TextX, TextY, Font, Paint);
      TextY := TextY + aHeight * 0.08;
    end;

    if fOutcome.FailPad then
    begin
      Font.MeasureText('Missed the pad!', TextBounds, Paint);
      TextX := (aWidth - TextBounds.Width) / 2;
      aCanvas.DrawSimpleText('Missed the pad!', TextX, TextY, Font, Paint);
      TextY := TextY + aHeight * 0.08;
    end;

    if (not fOutcome.FailSpeed) and (not fOutcome.FailAngle) and (not fOutcome.FailPad) then
    begin
      Font.MeasureText('Mission Failed', TextBounds, Paint);
      TextX := (aWidth - TextBounds.Width) / 2;
      aCanvas.DrawSimpleText('Mission Failed', TextX, TextY, Font, Paint);
    end;
  end;

  // 3. Navigation prompt
  Typeface := TSkTypeface.MakeFromName('Consolas', TSkFontStyle.Normal);
  Font := TSkFont.Create(Typeface, 20);
  Paint := TSkPaint.Create;
  Paint.AntiAlias := True;
  // Subtle pulse on prompt text
  Paint.Color := TAlphaColor(Cardinal(Round(180 + 75 * Abs(Sin(fTime * 2.0)))) shl 24
    or $00FFFFFF);

  Font.MeasureText('Press ENTER for Menu', TextBounds, Paint);
  TextX := (aWidth - TextBounds.Width) / 2;
  TextY := aHeight * 0.75;
  aCanvas.DrawSimpleText('Press ENTER for Menu', TextX, TextY, Font, Paint);

  // 4. Fade overlay
  if fFadeAlpha > 0 then
  begin
    Paint := TSkPaint.Create;
    Paint.Style := TSkPaintStyle.Fill;
    Paint.Color := TAlphaColor(Cardinal(Round(fFadeAlpha * 255)) shl 24);
    Rect := RectF(0, 0, aWidth, aHeight);
    aCanvas.DrawRect(Rect, Paint);
  end;
end;

end.
