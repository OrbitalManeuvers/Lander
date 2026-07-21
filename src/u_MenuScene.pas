unit u_MenuScene;

interface

uses
  System.Types, System.UITypes, System.SysUtils, System.Skia,
  u_Models, u_SceneBase, u_FlightRenderer, u_Scenarios;

type
  // Title screen scene with scenario selection, drifting craft demo,
  // and starfield background.
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
    fThrustTimer: Single;
    fThrustDuration: Single;
    fThrustActive: Boolean;
    fRCSTimer: Single;
    fRCSDuration: Single;
    fRCSActive: Boolean;

    // Fade animation
    fFadeAlpha: Single;
    fExiting: Boolean;
    fExitTarget: TSceneID;

    // Last known canvas dimensions for wrapping calculations
    fCanvasWidth: Integer;
    fCanvasHeight: Integer;

    // Scenario slots
    fScenarios: TArray<TScenario>;
    fSelectedIndex: Integer;
    fEditorFilePath: string;

    procedure InitDemoCraft;
    procedure UpdateCraftDrift;
    procedure UpdateThrusters;
    procedure UpdateFade;
    procedure MoveSelection(aDelta: Integer);
    procedure SelectByNumber(aSlot: Integer);
  public
    constructor Create;
    destructor Destroy; override;

    procedure HandleInput(AKeyCode: Word; AKeyState: TKeyState); override;
    procedure Tick; override;
    procedure Render(const ACanvas: ISkCanvas; AWidth, AHeight: Integer); override;

    // The selected scenario (lightweight — World/Craft are nil until resolved)
    function SelectedScenario: TScenario;
    property EditorFilePath: string read fEditorFilePath;
  end;

implementation

uses
  System.Math, System.IOUtils, u_Serialization;

const
  CTickDelta = 0.016;
  CFadeSpeed = 1.0 / 30.0;
  CThrustMinInterval = 3.0;
  CThrustMaxInterval = 8.0;
  CThrustMinDuration = 1.0;
  CThrustMaxDuration = 2.0;
  CMaxSlots = 8;

{ TMenuScene }

constructor TMenuScene.Create;
var
  ScenariosPath: string;
begin
  inherited Create;
  fRenderer := TFlightRenderer.Create;
  fTime := 0;
  fFadeAlpha := 1.0;  // Start fully black (entrance fade-in)
  fExiting := False;
  fExitTarget := sidPlay;
  fCanvasWidth := 800;
  fCanvasHeight := 600;

  // Load scenario manifest
  ScenariosPath := TPath.Combine(ExtractFilePath(ParamStr(0)), 'scenarios.json');
  fScenarios := LoadScenariosFromJSON(ScenariosPath);

  // Ensure array is always 8 slots
  if Length(fScenarios) < CMaxSlots then
    SetLength(fScenarios, CMaxSlots);

  // Default selection to first filled slot
  fSelectedIndex := -1;
  MoveSelection(1); // finds the first non-empty slot
  if fSelectedIndex < 0 then
    fSelectedIndex := 0; // fallback if all empty

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

function TMenuScene.SelectedScenario: TScenario;
begin
  if (fSelectedIndex >= 0) and (fSelectedIndex <= High(fScenarios)) then
    Result := fScenarios[fSelectedIndex]
  else
    Result := Default(TScenario);
end;

procedure TMenuScene.MoveSelection(aDelta: Integer);
var
  i, Next: Integer;
begin
  // Move selection by aDelta, skipping empty slots
  Next := fSelectedIndex;
  for i := 1 to CMaxSlots do
  begin
    Next := Next + aDelta;
    if (Next < 0) or (Next >= CMaxSlots) then
      Exit; // Don't wrap, just stop at boundaries
    if fScenarios[Next].Name <> '' then
    begin
      fSelectedIndex := Next;
      Exit;
    end;
  end;
end;

procedure TMenuScene.SelectByNumber(aSlot: Integer);
begin
  // aSlot is 1-based (keys 1..8)
  if (aSlot >= 1) and (aSlot <= CMaxSlots) then
  begin
    if fScenarios[aSlot - 1].Name <> '' then
      fSelectedIndex := aSlot - 1;
  end;
end;

procedure TMenuScene.InitDemoCraft;
const
  Pivot: TPointF = (X: 14; Y: 22.5);
var
  Part: TCraftPart;
begin
  SetLength(fHullParts, 2);

  // Main body: diamond shape (stroke)
  Part.Path := BuildCraftPath([
    PointF(14, 0),
    PointF(28, 28),
    PointF(14, 45),
    PointF(0, 28)
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

  fThrustOffset := PivotOffset(PointF(14, 45), Pivot);

  SetLength(fRCSOffsets, 2);
  fRCSOffsets[0] := PivotOffset(PointF(-0.7, 28), Pivot);
  fRCSOffsets[1] := PivotOffset(PointF(28.7, 28), Pivot);

  fPlumeColor := TAlphaColors.Orange;
  fPlumeLength := 18.0;
  fPlumeWidth := 7.0;
  fRCSRadius := 5.0;

  fCraftState := Default(TCraftState);
  fCraftState.X := 100;
  fCraftState.Y := 200;
  fCraftState.Alive := True;
  fCraftState.Fuel := 100;
  fCraftState.RCSFuel := 100;

  fDriftVX := 1.2;
  fDriftVY := 0.3;
  fDriftAngularVel := 0.02;
end;

procedure TMenuScene.UpdateCraftDrift;
begin
  fCraftState.X := fCraftState.X + fDriftVX;
  fCraftState.Y := fCraftState.Y + fDriftVY;
  fCraftState.Angle := fCraftState.Angle + fDriftAngularVel;

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
      fCraftState.Thrust := 0.6 + Random * 0.4;
    end;
  end;

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
    fFadeAlpha := fFadeAlpha + CFadeSpeed;
    if fFadeAlpha >= 1.0 then
    begin
      fFadeAlpha := 1.0;
      SetFinished(fExitTarget);
    end;
  end
  else
  begin
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
  if fExiting then
    Exit;

  case AKeyCode of
    // Up arrow
    38: MoveSelection(-1);
    // Down arrow
    40: MoveSelection(1);
    // Number keys 1-8
    Ord('1')..Ord('8'):
      SelectByNumber(AKeyCode - Ord('0'));
    // Enter: launch selected scenario
    13:
      begin
        if (fSelectedIndex >= 0) and (fScenarios[fSelectedIndex].Name <> '') then
        begin
          fExitTarget := sidPlay;
          fExiting := True;
        end;
      end;
    // E key: open selected scenario's world in editor
    Ord('E'):
      begin
        if (fSelectedIndex >= 0) and (fScenarios[fSelectedIndex].Name <> '') then
        begin
          fEditorFilePath := TPath.Combine(
            TPath.Combine(ExtractFilePath(ParamStr(0)), 'worlds'),
            fScenarios[fSelectedIndex].WorldID);
          fExitTarget := sidEditor;
          fExiting := True;
        end;
      end;
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
  Rect: TRectF;
  Paint: ISkPaint;
  Font: ISkFont;
  Typeface: ISkTypeface;
  TextBounds: TRectF;
  TextX, TextY: Single;
  I: Integer;
  SlotText: string;
  LineHeight: Single;
begin
  Viewport.ViewLeft := 0;
  Viewport.ViewRight := AWidth;
  Viewport.ViewTop := 0;
  Viewport.ViewBottom := AHeight;
  Viewport.ScreenWidth := AWidth;
  Viewport.ScreenHeight := AHeight;

  fCanvasWidth := AWidth;
  fCanvasHeight := AHeight;

  // 1. Starfield background
  fRenderer.RenderStarfield(ACanvas, AWidth, AHeight, fTime);

  // 2. Demo craft
  fRenderer.RenderCraft(ACanvas, Viewport, fCraftState, fHullParts);
  fRenderer.RenderEffects(ACanvas, Viewport, fCraftState, fThrustOffset,
    fRCSOffsets, fPlumeColor, fPlumeLength, fPlumeWidth, fRCSRadius);

  // 3. Title
  Typeface := TSkTypeface.MakeFromName('Consolas', TSkFontStyle.Bold);
  Font := TSkFont.Create(Typeface, 52);
  Paint := TSkPaint.Create;
  Paint.Color := TAlphaColors.White;
  Paint.AntiAlias := True;

  Font.MeasureText('LUNAR LANDER', TextBounds, Paint);
  TextX := (AWidth - TextBounds.Width) / 2;
  ACanvas.DrawSimpleText('LUNAR LANDER', TextX, AHeight * 0.22, Font, Paint);

  // 4. Scenario slot list
  Typeface := TSkTypeface.MakeFromName('Consolas', TSkFontStyle.Normal);
  Font := TSkFont.Create(Typeface, 20);
  LineHeight := 28;
  TextY := AHeight * 0.36;

  for I := 0 to CMaxSlots - 1 do
  begin
    Paint := TSkPaint.Create;
    Paint.AntiAlias := True;

    if fScenarios[I].Name <> '' then
    begin
      SlotText := IntToStr(I + 1) + '. ' + fScenarios[I].Name;
      if I = fSelectedIndex then
        Paint.Color := TAlphaColors.Yellow
      else
        Paint.Color := $CCFFFFFF;
    end
    else
    begin
      SlotText := IntToStr(I + 1) + '. <empty>';
      Paint.Color := $55FFFFFF;
    end;

    // Prefix selected line with cursor
    if I = fSelectedIndex then
      SlotText := '> ' + SlotText
    else
      SlotText := '  ' + SlotText;

    Font.MeasureText(SlotText, TextBounds, Paint);
    TextX := (AWidth - TextBounds.Width) / 2;
    ACanvas.DrawSimpleText(SlotText, TextX, TextY + I * LineHeight, Font, Paint);
  end;

  // 5. Hints below the slot list
  TextY := TextY + CMaxSlots * LineHeight + 24;
  Font := TSkFont.Create(Typeface, 16);

  // Pulsing Enter prompt
  Paint := TSkPaint.Create;
  Paint.AntiAlias := True;
  Paint.Color := TAlphaColor(
    Cardinal(Round(160 + 80 * Abs(Sin(fTime * 2.0)))) shl 24 or $00FFFFFF);
  SlotText := 'Enter = Play    E = Edit';
  Font.MeasureText(SlotText, TextBounds, Paint);
  TextX := (AWidth - TextBounds.Width) / 2;
  ACanvas.DrawSimpleText(SlotText, TextX, TextY, Font, Paint);

  // 6. Fade overlay
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
