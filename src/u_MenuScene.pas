unit u_MenuScene;

interface

uses
  System.Types, System.UITypes, System.SysUtils, System.Skia,
  u_Models, u_SceneBase, u_FlightRenderer;

type
  // Title screen scene with drifting craft demo and starfield background.
  TMenuScene = class(TGameScene)
  private
    fRenderer: TFlightRenderer;
    fCraftState: TCraftState;
    fHullParts: TCraftPartArray;
    fThrustOffset: TPointF;
    fRCSOffsets: TPointFArray;
    fPlumeColor: TAlphaColor;
    fPlumeLength: Single;
    fPlumeWidth: Single;
    fRCSRadius: Single;
    fTime: Single;

    // Craft drift parameters (no physics engine, linear motion only)
    fDriftVX: Single;
    fDriftVY: Single;
    fDriftAngularVel: Single;

    // Random thruster firing state
    fThrustTimer: Single;       // Countdown to next thrust event
    fThrustDuration: Single;    // How long current thrust stays on
    fThrustActive: Boolean;     // Currently firing main engine (visual only)
    fRCSTimer: Single;          // Countdown to next RCS event
    fRCSDuration: Single;       // How long current RCS stays on
    fRCSActive: Boolean;        // Currently firing RCS (visual only)

    // Fade animation
    fFadeAlpha: Single;         // 0 = fully visible, 1 = fully black
    fExiting: Boolean;          // True when fade-out has been triggered

    // Last known canvas dimensions for wrapping calculations
    fCanvasWidth: Integer;
    fCanvasHeight: Integer;

    procedure InitDemoCraft;
    procedure UpdateCraftDrift;
    procedure UpdateThrusters;
    procedure UpdateFade;
  public
    constructor Create;
    destructor Destroy; override;

    procedure HandleInput(AKeyCode: Word; AKeyState: TKeyState); override;
    procedure Tick; override;
    procedure Render(const ACanvas: ISkCanvas; AWidth, AHeight: Integer); override;
  end;

implementation

uses
  System.Math;

const
  CTickDelta = 0.016;          // ~60 FPS assumed tick interval
  CFadeSpeed = 1.0 / 30.0;    // Fully fade in/out over 30 ticks
  CThrustMinInterval = 3.0;
  CThrustMaxInterval = 8.0;
  CThrustMinDuration = 1.0;
  CThrustMaxDuration = 2.0;

{ TMenuScene }

constructor TMenuScene.Create;
begin
  inherited Create;
  fRenderer := TFlightRenderer.Create;
  fTime := 0;
  fFadeAlpha := 1.0;  // Start fully black (entrance fade-in)
  fExiting := False;
  fCanvasWidth := 800;
  fCanvasHeight := 600;

  InitDemoCraft;

  // Set initial random timers for thruster events
  fThrustTimer := CThrustMinInterval + Random * (CThrustMaxInterval - CThrustMinInterval);
  fThrustActive := False;
  fRCSTimer := CThrustMinInterval + Random * (CThrustMaxInterval - CThrustMinInterval);
  fRCSActive := False;
end;

destructor TMenuScene.Destroy;
begin
  fRenderer.Free;
  inherited;
end;

procedure TMenuScene.InitDemoCraft;
const
  // Pivot point: center of rotation in grid space
  Pivot: TPointF = (X: 14; Y: 22.5);
var
  Part: TCraftPart;
begin
  // Author craft in grid space: 0,0 = top-left, 28×45 bounding box.
  // Pivot at (14, 22.5) centers the craft for rotation.
  SetLength(fHullParts, 2);

  // Main body: diamond shape (stroke)
  Part.Path := BuildCraftPath([
    PointF(14, 0),    // Nose (top)
    PointF(28, 28),   // Right
    PointF(14, 45),   // Bottom
    PointF(0, 28)     // Left
  ], Pivot, True);
  Part.Color := TAlphaColors.Silver;
  Part.Style := TSkPaintStyle.Stroke;
  Part.StrokeWidth := 1.8;
  fHullParts[0] := Part;

  // Cockpit window: small triangle (filled)
  Part.Path := BuildCraftPath([
    PointF(14, 8),
    PointF(20, 22),
    PointF(8, 22)
  ], Pivot, True);
  Part.Color := $FF4488CC;
  Part.Style := TSkPaintStyle.Fill;
  Part.StrokeWidth := 0;
  fHullParts[1] := Part;

  // Thrust offset: below the craft body (grid: bottom center)
  fThrustOffset := PivotOffset(PointF(14, 45), Pivot);

  // RCS offsets: left and right sides (grid: widest points, slightly outward)
  SetLength(fRCSOffsets, 2);
  fRCSOffsets[0] := PivotOffset(PointF(-0.7, 28), Pivot);
  fRCSOffsets[1] := PivotOffset(PointF(28.7, 28), Pivot);

  fPlumeColor := TAlphaColors.Orange;
  fPlumeLength := 18.0;
  fPlumeWidth := 7.0;
  fRCSRadius := 5.0;

  // Initial craft state: start from left side, drifting right with slow spin
  fCraftState := Default(TCraftState);
  fCraftState.X := 100;
  fCraftState.Y := 200;
  fCraftState.Alive := True;
  fCraftState.Fuel := 100;      // Always have fuel for visual effects
  fCraftState.RCSFuel := 100;

  // Linear drift: move right and slightly down with slow clockwise spin
  fDriftVX := 1.2;
  fDriftVY := 0.3;
  fDriftAngularVel := 0.02;  // Slow spin (radians per tick)
end;

procedure TMenuScene.UpdateCraftDrift;
begin
  // Simple linear motion — no physics engine involved
  fCraftState.X := fCraftState.X + fDriftVX;
  fCraftState.Y := fCraftState.Y + fDriftVY;
  fCraftState.Angle := fCraftState.Angle + fDriftAngularVel;

  // Wrap around when craft exits view bounds (with some margin)
  if fCraftState.X > fCanvasWidth + 20 then
    fCraftState.X := -20
  else if fCraftState.X < -20 then
    fCraftState.X := fCanvasWidth + 20;

  if fCraftState.Y > fCanvasHeight + 20 then
    fCraftState.Y := -20
  else if fCraftState.Y < -20 then
    fCraftState.Y := fCanvasHeight + 20;
end;

procedure TMenuScene.UpdateThrusters;
begin
  // Main engine random firing
  if fThrustActive then
  begin
    fThrustDuration := fThrustDuration - CTickDelta;
    if fThrustDuration <= 0 then
    begin
      fThrustActive := False;
      fCraftState.Thrust := 0;
      fThrustTimer := CThrustMinInterval + Random * (CThrustMaxInterval - CThrustMinInterval);
    end;
  end
  else
  begin
    fThrustTimer := fThrustTimer - CTickDelta;
    if fThrustTimer <= 0 then
    begin
      fThrustActive := True;
      fThrustDuration := CThrustMinDuration + Random * (CThrustMaxDuration - CThrustMinDuration);
      fCraftState.Thrust := 0.6 + Random * 0.4;  // Visual throttle level
    end;
  end;

  // RCS random firing
  if fRCSActive then
  begin
    fRCSDuration := fRCSDuration - CTickDelta;
    if fRCSDuration <= 0 then
    begin
      fRCSActive := False;
      fCraftState.RotatingLeft := False;
      fCraftState.RotatingRight := False;
      fRCSTimer := CThrustMinInterval + Random * (CThrustMaxInterval - CThrustMinInterval);
    end;
  end
  else
  begin
    fRCSTimer := fRCSTimer - CTickDelta;
    if fRCSTimer <= 0 then
    begin
      fRCSActive := True;
      fRCSDuration := CThrustMinDuration + Random * (CThrustMaxDuration - CThrustMinDuration);
      // Randomly pick left or right
      if Random < 0.5 then
        fCraftState.RotatingLeft := True
      else
        fCraftState.RotatingRight := True;
    end;
  end;
end;

procedure TMenuScene.UpdateFade;
begin
  if fExiting then
  begin
    // Fade out: increase alpha toward fully black
    fFadeAlpha := fFadeAlpha + CFadeSpeed;
    if fFadeAlpha >= 1.0 then
    begin
      fFadeAlpha := 1.0;
      SetFinished(sidPlay);
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

procedure TMenuScene.HandleInput(AKeyCode: Word; AKeyState: TKeyState);
begin
  if AKeyState <> ksDown then
    Exit;

  // Detect start action: Enter or Space
  if (AKeyCode = 13) or (AKeyCode = 32) then
  begin
    if not fExiting then
      fExiting := True;
  end;
end;

procedure TMenuScene.Tick;
begin
  fTime := fTime + CTickDelta;
  UpdateCraftDrift;
  UpdateThrusters;
  UpdateFade;
end;

procedure TMenuScene.Render(const ACanvas: ISkCanvas; AWidth, AHeight: Integer);
var
  Viewport: TViewport;
  Font: ISkFont;
  Typeface: ISkTypeface;
  Paint: ISkPaint;
  TextBounds: TRectF;
  TextX: Single;
  Rect: TRectF;
begin
  // Build a 1:1 viewport (world coords = screen pixels, no letterboxing for menu)
  Viewport.ViewLeft := 0;
  Viewport.ViewRight := AWidth;
  Viewport.ViewTop := 0;
  Viewport.ViewBottom := AHeight;
  Viewport.ScreenWidth := AWidth;
  Viewport.ScreenHeight := AHeight;

  // Update stored canvas dimensions for wrapping in Tick
  fCanvasWidth := AWidth;
  fCanvasHeight := AHeight;

  // 1. Render starfield background (full canvas, no letterboxing)
  fRenderer.RenderStarfield(ACanvas, AWidth, AHeight, fTime);

  // 2. Render the demo craft and its effects
  fRenderer.RenderCraft(ACanvas, Viewport, fCraftState, fHullParts);
  fRenderer.RenderEffects(ACanvas, Viewport, fCraftState, fThrustOffset,
    fRCSOffsets, fPlumeColor, fPlumeLength, fPlumeWidth, fRCSRadius);

  // 3. Draw title text
  Typeface := TSkTypeface.MakeFromName('Consolas', TSkFontStyle.Bold);
  Font := TSkFont.Create(Typeface, 52);
  Paint := TSkPaint.Create;
  Paint.Color := TAlphaColors.White;
  Paint.AntiAlias := True;

  // Measure text for centering
  Font.MeasureText('LUNAR LANDER', TextBounds, Paint);
  TextX := (AWidth - TextBounds.Width) / 2;
  ACanvas.DrawSimpleText('LUNAR LANDER', TextX, AHeight * 0.28, Font, Paint);

  // 4. Draw start prompt (smaller, slightly pulsing alpha)
  Typeface := TSkTypeface.MakeFromName('Consolas', TSkFontStyle.Normal);
  Font := TSkFont.Create(Typeface, 24);

  // Subtle pulse effect on the prompt text
  Paint := TSkPaint.Create;
  Paint.AntiAlias := True;
  Paint.Color := TAlphaColor(Cardinal(Round(180 + 75 * Abs(Sin(fTime * 2.0)))) shl 24
    or $00FFFFFF);

  Font.MeasureText('Press ENTER to start', TextBounds, Paint);
  TextX := (AWidth - TextBounds.Width) / 2;
  ACanvas.DrawSimpleText('Press ENTER to start', TextX, AHeight * 0.45, Font, Paint);

  // 5. Draw fade overlay (black rect with alpha for entrance/exit animation)
  if fFadeAlpha > 0 then
  begin
    Paint := TSkPaint.Create;
    Paint.Style := TSkPaintStyle.Fill;
    Paint.Color := TAlphaColor(Cardinal(Round(fFadeAlpha * 255)) shl 24);
    Rect := RectF(0, 0, AWidth, AHeight);
    ACanvas.DrawRect(Rect, Paint);
  end;
end;

end.
