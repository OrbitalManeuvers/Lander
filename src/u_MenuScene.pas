unit u_MenuScene;

interface

uses
  System.Types, System.UITypes, System.SysUtils, System.Skia,
  u_Models, u_SceneBase, u_FlightRenderer;

type
  // Sub-state for the menu scene: title screen vs world file selection.
  TMenuSubState = (msTitle, msWorldSelect);

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
    fExitTarget: TSceneID;      // Which scene to transition to on fade complete

    // Last known canvas dimensions for wrapping calculations
    fCanvasWidth: Integer;
    fCanvasHeight: Integer;

    // World selection sub-state
    fSubState: TMenuSubState;
    fWorldFiles: TArray<string>;      // Full paths of discovered .json files
    fWorldFileNames: TArray<string>;  // Just filenames for display
    fSelectedIndex: Integer;          // Currently highlighted file index
    fEditorFilePath: string;          // Selected file path for editor

    procedure InitDemoCraft;
    procedure UpdateCraftDrift;
    procedure UpdateThrusters;
    procedure UpdateFade;
    procedure ScanWorldFiles;
    procedure HandleTitleInput(aKeyCode: Word);
    procedure HandleWorldSelectInput(aKeyCode: Word);
    procedure RenderTitle(const aCanvas: ISkCanvas; aWidth, aHeight: Integer);
    procedure RenderWorldSelect(const aCanvas: ISkCanvas; aWidth, aHeight: Integer);
  public
    constructor Create;
    destructor Destroy; override;

    procedure HandleInput(AKeyCode: Word; AKeyState: TKeyState); override;
    procedure Tick; override;
    procedure Render(const ACanvas: ISkCanvas; AWidth, AHeight: Integer); override;

    property EditorFilePath: string read fEditorFilePath;
  end;

implementation

uses
  System.Math, System.IOUtils;

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
  fExitTarget := sidPlay;
  fCanvasWidth := 800;
  fCanvasHeight := 600;

  // World selection state
  fSubState := msTitle;
  fSelectedIndex := 0;
  fEditorFilePath := '';

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
      SetFinished(fExitTarget);
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

  case fSubState of
    msTitle:
      HandleTitleInput(AKeyCode);
    msWorldSelect:
      HandleWorldSelectInput(AKeyCode);
  end;
end;

procedure TMenuScene.HandleTitleInput(aKeyCode: Word);
begin
  // Enter or Space: start game
  if (aKeyCode = 13) or (aKeyCode = 32) then
  begin
    if not fExiting then
    begin
      fExitTarget := sidPlay;
      fExiting := True;
    end;
  end
  // E key: open world selection for editor
  else if aKeyCode = Ord('E') then
  begin
    if not fExiting then
    begin
      ScanWorldFiles;
      fSelectedIndex := 0;
      fSubState := msWorldSelect;
    end;
  end;
end;

procedure TMenuScene.HandleWorldSelectInput(aKeyCode: Word);
begin
  case aKeyCode of
    // Up arrow
    38:
      begin
        if (Length(fWorldFiles) > 0) and (fSelectedIndex > 0) then
          Dec(fSelectedIndex);
      end;
    // Down arrow
    40:
      begin
        if fSelectedIndex < High(fWorldFiles) then
          Inc(fSelectedIndex);
      end;
    // Enter: select file and transition to editor
    13:
      begin
        if Length(fWorldFiles) > 0 then
        begin
          fEditorFilePath := fWorldFiles[fSelectedIndex];
          fExitTarget := sidEditor;
          fExiting := True;
        end;
      end;
    // Escape: return to title
    27:
      fSubState := msTitle;
  end;
end;

procedure TMenuScene.ScanWorldFiles;
var
  WorldsDir: string;
  I: Integer;
begin
  WorldsDir := TPath.Combine(ExtractFilePath(ParamStr(0)), 'worlds');
  if TDirectory.Exists(WorldsDir) then
    fWorldFiles := TDirectory.GetFiles(WorldsDir, '*.json')
  else
    SetLength(fWorldFiles, 0);

  // Extract just filenames for display
  SetLength(fWorldFileNames, Length(fWorldFiles));
  for I := 0 to High(fWorldFiles) do
    fWorldFileNames[I] := TPath.GetFileName(fWorldFiles[I]);
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
  Rect: TRectF;
  Paint: ISkPaint;
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

  // 1. Render starfield background (shared across sub-states)
  fRenderer.RenderStarfield(ACanvas, AWidth, AHeight, fTime);

  // 2. Render the demo craft and its effects (shared across sub-states)
  fRenderer.RenderCraft(ACanvas, Viewport, fCraftState, fHullParts);
  fRenderer.RenderEffects(ACanvas, Viewport, fCraftState, fThrustOffset,
    fRCSOffsets, fPlumeColor, fPlumeLength, fPlumeWidth, fRCSRadius);

  // 3. Sub-state specific rendering
  case fSubState of
    msTitle:
      RenderTitle(ACanvas, AWidth, AHeight);
    msWorldSelect:
      RenderWorldSelect(ACanvas, AWidth, AHeight);
  end;

  // 4. Draw fade overlay (black rect with alpha for entrance/exit animation)
  if fFadeAlpha > 0 then
  begin
    Paint := TSkPaint.Create;
    Paint.Style := TSkPaintStyle.Fill;
    Paint.Color := TAlphaColor(Cardinal(Round(fFadeAlpha * 255)) shl 24);
    Rect := RectF(0, 0, AWidth, AHeight);
    ACanvas.DrawRect(Rect, Paint);
  end;
end;

procedure TMenuScene.RenderTitle(const aCanvas: ISkCanvas; aWidth, aHeight: Integer);
var
  Font: ISkFont;
  Typeface: ISkTypeface;
  Paint: ISkPaint;
  TextBounds: TRectF;
  TextX: Single;
begin
  // Draw title text
  Typeface := TSkTypeface.MakeFromName('Consolas', TSkFontStyle.Bold);
  Font := TSkFont.Create(Typeface, 52);
  Paint := TSkPaint.Create;
  Paint.Color := TAlphaColors.White;
  Paint.AntiAlias := True;

  // Measure text for centering
  Font.MeasureText('LUNAR LANDER', TextBounds, Paint);
  TextX := (aWidth - TextBounds.Width) / 2;
  aCanvas.DrawSimpleText('LUNAR LANDER', TextX, aHeight * 0.28, Font, Paint);

  // Draw start prompt (smaller, slightly pulsing alpha)
  Typeface := TSkTypeface.MakeFromName('Consolas', TSkFontStyle.Normal);
  Font := TSkFont.Create(Typeface, 24);

  // Subtle pulse effect on the prompt text
  Paint := TSkPaint.Create;
  Paint.AntiAlias := True;
  Paint.Color := TAlphaColor(Cardinal(Round(180 + 75 * Abs(Sin(fTime * 2.0)))) shl 24
    or $00FFFFFF);

  Font.MeasureText('Press ENTER to start', TextBounds, Paint);
  TextX := (aWidth - TextBounds.Width) / 2;
  aCanvas.DrawSimpleText('Press ENTER to start', TextX, aHeight * 0.45, Font, Paint);

  // Draw editor hint
  Paint := TSkPaint.Create;
  Paint.AntiAlias := True;
  Paint.Color := $99FFFFFF;  // Semi-transparent white
  Font := TSkFont.Create(Typeface, 18);

  Font.MeasureText('E = Editor', TextBounds, Paint);
  TextX := (aWidth - TextBounds.Width) / 2;
  aCanvas.DrawSimpleText('E = Editor', TextX, aHeight * 0.55, Font, Paint);
end;

procedure TMenuScene.RenderWorldSelect(const aCanvas: ISkCanvas; aWidth, aHeight: Integer);
var
  Font: ISkFont;
  Typeface: ISkTypeface;
  Paint: ISkPaint;
  TextBounds: TRectF;
  TextX, TextY: Single;
  I: Integer;
  DisplayText: string;
begin
  // Title: SELECT WORLD
  Typeface := TSkTypeface.MakeFromName('Consolas', TSkFontStyle.Bold);
  Font := TSkFont.Create(Typeface, 36);
  Paint := TSkPaint.Create;
  Paint.Color := TAlphaColors.White;
  Paint.AntiAlias := True;

  Font.MeasureText('SELECT WORLD', TextBounds, Paint);
  TextX := (aWidth - TextBounds.Width) / 2;
  aCanvas.DrawSimpleText('SELECT WORLD', TextX, aHeight * 0.18, Font, Paint);

  // File list
  Typeface := TSkTypeface.MakeFromName('Consolas', TSkFontStyle.Normal);
  Font := TSkFont.Create(Typeface, 22);
  TextY := aHeight * 0.30;

  if Length(fWorldFiles) = 0 then
  begin
    // No files found message
    Paint := TSkPaint.Create;
    Paint.AntiAlias := True;
    Paint.Color := $FFFF6666;  // Red-ish
    Font.MeasureText('No worlds found', TextBounds, Paint);
    TextX := (aWidth - TextBounds.Width) / 2;
    aCanvas.DrawSimpleText('No worlds found', TextX, TextY, Font, Paint);

    Paint := TSkPaint.Create;
    Paint.AntiAlias := True;
    Paint.Color := $99FFFFFF;
    Font := TSkFont.Create(Typeface, 16);
    Font.MeasureText('(place .json files in worlds/ folder)', TextBounds, Paint);
    TextX := (aWidth - TextBounds.Width) / 2;
    aCanvas.DrawSimpleText('(place .json files in worlds/ folder)', TextX, TextY + 30, Font, Paint);
  end
  else
  begin
    for I := 0 to High(fWorldFileNames) do
    begin
      Paint := TSkPaint.Create;
      Paint.AntiAlias := True;

      if I = fSelectedIndex then
      begin
        // Highlighted item: yellow with arrow prefix
        Paint.Color := TAlphaColors.Yellow;
        DisplayText := '> ' + fWorldFileNames[I];
      end
      else
      begin
        Paint.Color := $CCFFFFFF;
        DisplayText := '  ' + fWorldFileNames[I];
      end;

      Font.MeasureText(DisplayText, TextBounds, Paint);
      TextX := (aWidth - TextBounds.Width) / 2;
      aCanvas.DrawSimpleText(DisplayText, TextX, TextY + I * 30, Font, Paint);
    end;
  end;

  // Navigation hints at bottom
  Font := TSkFont.Create(Typeface, 16);
  Paint := TSkPaint.Create;
  Paint.AntiAlias := True;
  Paint.Color := $99FFFFFF;

  DisplayText := 'Up/Down Select   Enter Open   Esc Back';
  Font.MeasureText(DisplayText, TextBounds, Paint);
  TextX := (aWidth - TextBounds.Width) / 2;
  aCanvas.DrawSimpleText(DisplayText, TextX, aHeight * 0.85, Font, Paint);
end;

end.
