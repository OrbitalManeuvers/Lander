unit u_PlayScene;

interface

uses
  System.Types, System.UITypes, System.Skia, Winapi.Windows,
  u_Models, u_SceneBase, u_FlightRenderer, u_Scenarios, u_Scoring,
  u_PanelRenderer, u_FontManager;

type
  // Core gameplay scene: physics simulation, terrain rendering,
  // input handling, landing/crash detection.
  TPlayScene = class(TGameScene)
  private
    fScenario: TScenario;
    fCraftState: TCraftState;
    fRenderer: TFlightRenderer;
    fScoreKeeper: TScoreKeeper;
    fPanelRenderer: TPanelRenderer;
    fFontManager: TFontManager;
    fViewport: TViewport;
    fTime: Single;
    fFlightTime: Single;  // Elapsed flight time in seconds
    fCameraX: Single;  // Current camera center X (lazy-follows craft)
    fCameraGroundY: Single;  // Locked ground Y when entering zoomed-in mode
    fZoomedIn: Boolean;  // True = landing view, False = full terrain view
    fOutcome: TPlayOutcome;
    fReturnScene: TSceneID;  // Where to go on ESC (menu or editor)

    // Crash respawn state
    fCrashTimer: Single;  // Countdown after crash before respawn (0 = not crashing)

    // Pause state
    fPaused: Boolean;
    fPauseConfirm: Boolean;  // True = ESC pressed once (waiting for 2nd ESC or C)

    procedure InitCraftState;
    function GetTransformedHull: TPointFArray;
    procedure RenderPauseOverlay(const aCanvas: ISkCanvas; aWidth, aHeight: Integer);
  public
    constructor Create(const aScenario: TScenario; aReturnScene: TSceneID;
      aScoreKeeper: TScoreKeeper);
    destructor Destroy; override;
    function RequiredLayout: TLayoutMode; override;

    procedure HandleInput(aKeyCode: Word; aKeyState: TKeyState); override;
    procedure Tick; override;
    procedure Render(const aCanvas: ISkCanvas; aWidth, aHeight: Integer); override;
    procedure RenderPanel(const aCanvas: ISkCanvas; aWidth, aHeight: Integer); override;

    property Outcome: TPlayOutcome read fOutcome;
    property PanelRenderer: TPanelRenderer read fPanelRenderer;

    // Transfers ownership of the panel renderer to the caller.
    function DetachPanelRenderer: TPanelRenderer;
  end;

implementation

uses
  System.SysUtils, System.Math, u_Physics, u_Terrain, u_Landing;

{ TPlayScene }

constructor TPlayScene.Create(const aScenario: TScenario; aReturnScene: TSceneID;
  aScoreKeeper: TScoreKeeper);
begin
  inherited Create;
  fScenario := aScenario;
  fReturnScene := aReturnScene;
  fRenderer := TFlightRenderer.Create;
  fScoreKeeper := aScoreKeeper;  // Borrowed reference, not owned
  fTime := 0;
  fFlightTime := 0;
  fCrashTimer := 0;

  // Pre-build terrain paths for rendering
  fRenderer.SetTerrain(fScenario.World.Terrain, fScenario.World.Pads);

  // Initialize craft state from scenario start conditions
  InitCraftState;

  // Camera starts centered on the craft's starting X position.
  fCameraX := fScenario.Start.X;

  // Initialize panel renderer
  fFontManager := TFontManager.Create;
  fFontManager.RegisterFonts(ExtractFilePath(ParamStr(0)));
  fPanelRenderer := TPanelRenderer.Create;
  fPanelRenderer.Init(fScenario.Craft, fScenario.World, fFontManager);
end;

destructor TPlayScene.Destroy;
begin
  fPanelRenderer.Free;
  fFontManager.Free;
  fRenderer.Free;
  inherited;
end;

procedure TPlayScene.InitCraftState;
begin
  fCraftState := Default(TCraftState);
  fCraftState.X := fScenario.Start.X;
  fCraftState.Y := fScenario.Start.Y;
  fCraftState.VX := fScenario.Start.VX;
  fCraftState.VY := fScenario.Start.VY;
  fCraftState.Angle := fScenario.Start.Angle;
  fCraftState.Fuel := fScenario.Craft.FuelCapacity;
  fCraftState.RCSFuel := fScenario.Craft.RCSFuelCapacity;
  fCraftState.Alive := True;
end;

function TPlayScene.GetTransformedHull: TPointFArray;
const
  CollisionMargin = 2.0;  // Detect contact slightly before visual overlap
var
  I: Integer;
  CosA, SinA: Single;
  RotX, RotY: Single;
  Points: TPointFArray;
begin
  Points := fScenario.Craft.CollisionPoints;
  SetLength(Result, Length(Points));
  CosA := Cos(fCraftState.Angle);
  SinA := Sin(fCraftState.Angle);

  for I := 0 to High(Points) do
  begin
    // Rotate vertex by craft angle, then translate to craft world position.
    // Subtract CollisionMargin from Y so contact registers before visual overlap.
    RotX := Points[I].X * CosA - Points[I].Y * SinA;
    RotY := Points[I].X * SinA + Points[I].Y * CosA;
    Result[I] := PointF(RotX + fCraftState.X, RotY + fCraftState.Y + CollisionMargin);
  end;
end;

procedure TPlayScene.HandleInput(aKeyCode: Word; aKeyState: TKeyState);
begin
  // Pause controls take priority
  if fPaused then
  begin
    if aKeyState <> ksDown then
      Exit;
    case aKeyCode of
      VK_ESCAPE:
        begin
          // Second ESC: exit to return scene (menu or editor)
          SetFinished(fReturnScene);
        end;
      Ord('C'):
        begin
          // Continue: unpause
          fPaused := False;
          fPauseConfirm := False;
        end;
    end;
    Exit;
  end;

  // Normal flight controls
  case aKeyCode of
    VK_ESCAPE:
      begin
        if aKeyState = ksDown then
        begin
          fPaused := True;
          fPauseConfirm := True;
          // Kill active inputs so craft doesn't drift with keys held
          fCraftState.Thrust := 0;
          fCraftState.RotatingLeft := False;
          fCraftState.RotatingRight := False;
        end;
      end;
    VK_UP:
      begin
        if aKeyState = ksDown then
          fCraftState.Thrust := 1.0
        else
          fCraftState.Thrust := 0.0;
      end;
    VK_LEFT:
      begin
        fCraftState.RotatingLeft := (aKeyState = ksDown);
      end;
    VK_RIGHT:
      begin
        fCraftState.RotatingRight := (aKeyState = ksDown);
      end;
    Ord('T'):
      begin
        if (aKeyState = ksDown) and fScenario.Craft.HasSAS then
          fCraftState.SASActive := not fCraftState.SASActive;
      end;
  end;
end;

procedure TPlayScene.Tick;
var
  HullPoints: TPointFArray;
  Contact: TContactResult;
  Landing: TLandingResult;
begin
  if fPaused then
    Exit;

  // Handle crash delay timer (craft is dead, waiting to respawn or game over)
  if fCrashTimer > 0 then
  begin
    fCrashTimer := fCrashTimer - 0.05;
    fTime := fTime + 1.0;
    if fCrashTimer <= 0 then
    begin
      fCrashTimer := 0;
      if fScoreKeeper.IsGameOver then
      begin
        // No lives left — go to result scene
        fPanelRenderer.UpdateChrome(fFlightTime, fScoreKeeper.Lives, fScoreKeeper.Score);
        fPanelRenderer.CaptureSnapshot(fCraftState,
          CalcAltitude(fCraftState.X, fCraftState.Y, fScenario.World));
        SetFinished(sidResult);
      end
      else
      begin
        // Respawn: reset craft state, unfreeze panel, resume flight
        InitCraftState;
        fPanelRenderer.Unfreeze;
        fZoomedIn := False;
        fCameraX := fScenario.Start.X;
      end;
    end;
    Exit;
  end;

  if not fCraftState.Alive then
    Exit;

  // Increment time for starfield animation
  fTime := fTime + 1.0;
  fFlightTime := fFlightTime + 0.05;

  // Run physics simulation (delta=1.0 since physics is per-tick)
//  PhysicsTick(fCraftState, fScenario.Craft, fScenario.World, 1.0);
  PhysicsTick(fCraftState, fScenario.Craft, fScenario.World, 0.05);

  // Update panel renderer with current state (after physics, before collision)
  fPanelRenderer.UpdateState(fCraftState);
  fPanelRenderer.UpdateChrome(fFlightTime, fScoreKeeper.Lives, fScoreKeeper.Score);

  // Transform hull vertices to world space for collision testing
  HullPoints := GetTransformedHull;

  // Test hull against terrain
  Contact := TestHullCollision(HullPoints, fScenario.World);

  if Contact.Hit then
  begin
    // Evaluate landing criteria
    Landing := EvaluateLanding(fCraftState, Contact, fScenario.Criteria, False);

    if Landing.Success then
    begin
      // Successful landing — compute outcome and award score
      fOutcome := Default(TPlayOutcome);
      fOutcome.Success := True;

      if Contact.IsPad and (Contact.PadIndex >= 0) then
        fOutcome.PadPoints := fScenario.World.Pads[Contact.PadIndex].PointValue
      else
        fOutcome.PadPoints := 0;

      if fScenario.Craft.FuelCapacity > 0 then
        fOutcome.FuelBonus := Round(fCraftState.Fuel / fScenario.Craft.FuelCapacity * 100)
      else
        fOutcome.FuelBonus := 0;

      fOutcome.TotalScore := fOutcome.PadPoints + fOutcome.FuelBonus;

      if Contact.IsPad and (Contact.PadIndex >= 0) then
        fScoreKeeper.AwardLanding(
          fScenario.World.Pads[Contact.PadIndex].PointValue,
          fCraftState.Fuel,
          fScenario.Craft.FuelCapacity);

      fOutcome.LivesRemaining := fScoreKeeper.Lives;
      fCraftState.Alive := False;
      fPanelRenderer.UpdateChrome(fFlightTime, fScoreKeeper.Lives, fScoreKeeper.Score);
      fPanelRenderer.CaptureSnapshot(fCraftState,
        CalcAltitude(fCraftState.X, fCraftState.Y, fScenario.World));
      SetFinished(sidResult);
    end
    else
    begin
      // Crash — decrement lives and start crash delay
      fScoreKeeper.ApplyCrash;

      fOutcome := Default(TPlayOutcome);
      fOutcome.Success := False;
      fOutcome.FailSpeed := Landing.FailSpeed;
      fOutcome.FailAngle := Landing.FailAngle;
      fOutcome.FailPad := Landing.FailPad;
      fOutcome.PadPoints := 0;
      fOutcome.FuelBonus := 0;
      fOutcome.TotalScore := 0;
      fOutcome.LivesRemaining := fScoreKeeper.Lives;

      fCraftState.Alive := False;
      fCrashTimer := 2.0;  // 2 second delay before respawn/game over
      fPanelRenderer.UpdateChrome(fFlightTime, fScoreKeeper.Lives, fScoreKeeper.Score);
    end;
  end;
end;

procedure TPlayScene.Render(const aCanvas: ISkCanvas; aWidth, aHeight: Integer);
const
  // Altitude threshold: below this → zoomed in, above this → zoomed out.
  ZoomInAltitude = 150.0;
  ZoomOutAltitude = 300.0;
  // Zoomed-in view height in world units.
  LandingViewHeight = 400.0;
  TargetAspect = 3.0 / 2.0;
  Margin = 30.0;  // Breathing room above craft in zoomed-in mode
var
  TerrainVP: TViewport;
  Altitude: Single;
  ViewWidth, ViewHeight: Single;
begin
  // Get terrain bounds as baseline (used for zoomed-out mode).
  TerrainVP := fRenderer.ViewportFromTerrain(
    fScenario.World.Terrain, Single(aWidth), Single(aHeight));

  // Calculate altitude above terrain.
  Altitude := CalcAltitude(fCraftState.X, fCraftState.Y, fScenario.World);
  if Altitude < 0 then
    Altitude := 9999;  // No terrain below — treat as high altitude

  // Determine view mode based on altitude and velocity.
  if not fZoomedIn then
  begin
    // Currently zoomed out — switch to zoomed in when close to ground
    // and descending (VY > 0 means moving downward in this coord system).
    if (Altitude < ZoomInAltitude) and (fCraftState.VY >= 0) then
    begin
      fZoomedIn := True;
      // Lock the ground Y at the moment we enter zoomed-in mode
      fCameraGroundY := fCraftState.Y + Altitude;
      fCameraX := fCraftState.X;
    end;
  end
  else
  begin
    // Currently zoomed in — switch back to zoomed out.
    // Two triggers (either one causes zoom-out):
    //
    // 1. Velocity-aware: the faster the craft is rising (VY < 0),
    //    the earlier we zoom out. Effective threshold lowers with speed.
    //    Base threshold at 200 altitude, each unit of upward velocity
    //    reduces it by 3 units of altitude.
    // 2. Hard ceiling: craft approaching top of locked viewport — must
    //    flip to keep it visible.
    var EffectiveZoomOut: Single;
    EffectiveZoomOut := ZoomOutAltitude;
    if fCraftState.VY < 0 then
      EffectiveZoomOut := ZoomOutAltitude + fCraftState.VY * 3.0;
    // Clamp so we never require impossibly low altitude to zoom out
    if EffectiveZoomOut < ZoomInAltitude + 20 then
      EffectiveZoomOut := ZoomInAltitude + 20;

    // Hard ceiling: if craft Y is near the top of the locked viewport
    var TopMargin: Single;
    TopMargin := fCameraGroundY + 50 - LandingViewHeight + 40;
    // TopMargin = viewport top + 40 units of breathing room

    if (Altitude > EffectiveZoomOut) or (fCraftState.Y < TopMargin) then
      fZoomedIn := False;
  end;

  if not fZoomedIn then
  begin
    // MODE 1: Zoomed Out — entire terrain visible, no camera movement.
    fViewport := TerrainVP;
  end
  else
  begin
    // MODE 2: Zoomed In (Landing) — fixed camera anchored to ground.
    // Terrain stays rock-solid; craft moves freely within the frame.
    ViewHeight := LandingViewHeight;
    ViewWidth := ViewHeight * TargetAspect;

    // Horizontal dead zone: 60% of view width is flyable without scrolling.
    // That's 30% of view width on each side of center.
    var DeadZoneX: Single;
    DeadZoneX := ViewWidth * 0.30;

    if fCraftState.X > fCameraX + DeadZoneX then
      fCameraX := fCraftState.X - DeadZoneX
    else if fCraftState.X < fCameraX - DeadZoneX then
      fCameraX := fCraftState.X + DeadZoneX;

    fViewport.ViewLeft := fCameraX - ViewWidth / 2;
    fViewport.ViewRight := fCameraX + ViewWidth / 2;

    // Clamp to terrain edges and reconcile camera X.
    if fViewport.ViewLeft < TerrainVP.ViewLeft then
    begin
      fViewport.ViewLeft := TerrainVP.ViewLeft;
      fViewport.ViewRight := TerrainVP.ViewLeft + ViewWidth;
      fCameraX := fViewport.ViewLeft + ViewWidth / 2;
    end;
    if fViewport.ViewRight > TerrainVP.ViewRight then
    begin
      fViewport.ViewRight := TerrainVP.ViewRight;
      fViewport.ViewLeft := TerrainVP.ViewRight - ViewWidth;
      fCameraX := fViewport.ViewLeft + ViewWidth / 2;
    end;

    // Vertical: track downward if craft approaches viewport bottom.
    // Camera only pans down (never up — upward escape triggers zoom-out).
    var BottomLimit: Single;
    BottomLimit := fCameraGroundY + 50 - 40;  // 40 units above viewport bottom edge
    if fCraftState.Y > BottomLimit then
      fCameraGroundY := fCraftState.Y - 50 + 40;

    fViewport.ViewBottom := fCameraGroundY + 50;
    fViewport.ViewTop := fViewport.ViewBottom - ViewHeight;
  end;

  fViewport.ScreenWidth := Single(aWidth);
  fViewport.ScreenHeight := Single(aHeight);

  // Delegate full render pass to the flight renderer
  fRenderer.RenderFrame(aCanvas, Single(aWidth), Single(aHeight), fTime * 0.016,
    fViewport, fCraftState,
    fScenario.Craft.HullParts,
    fScenario.Craft.ThrustOffset,
    fScenario.Craft.RCSOffsets,
    fScenario.Craft.PlumeColor,
    fScenario.World.TerrainColor,
    fScenario.World.PadColor,
    fScenario.Craft.PlumeLength,
    fScenario.Craft.PlumeWidth,
    fScenario.Craft.RCSRadius);

  // Draw pause overlay on top of everything
  if fPaused then
    RenderPauseOverlay(aCanvas, aWidth, aHeight);
end;

procedure TPlayScene.RenderPanel(const aCanvas: ISkCanvas; aWidth, aHeight: Integer);
begin
  fPanelRenderer.RenderPanel(aCanvas, Single(aWidth), Single(aHeight));
end;

procedure TPlayScene.RenderPauseOverlay(const aCanvas: ISkCanvas; aWidth, aHeight: Integer);
var
  Paint: ISkPaint;
  Font: ISkFont;
  Typeface: ISkTypeface;
  TextBounds: TRectF;
  TextX: Single;
begin
  // Semi-transparent dark overlay to dim the scene
  Paint := TSkPaint.Create;
  Paint.Style := TSkPaintStyle.Fill;
  Paint.Color := $AA000000;  // ~67% black
  aCanvas.DrawRect(RectF(0, 0, aWidth, aHeight), Paint);

  // "PAUSED" title
  Typeface := TSkTypeface.MakeFromName('Consolas', TSkFontStyle.Bold);
  Font := TSkFont.Create(Typeface, 40);
  Paint := TSkPaint.Create;
  Paint.Color := TAlphaColors.White;
  Paint.AntiAlias := True;

  Font.MeasureText('PAUSED', TextBounds, Paint);
  TextX := (aWidth - TextBounds.Width) / 2;
  aCanvas.DrawSimpleText('PAUSED', TextX, aHeight * 0.42, Font, Paint);

  // Instructions
  Typeface := TSkTypeface.MakeFromName('Consolas', TSkFontStyle.Normal);
  Font := TSkFont.Create(Typeface, 20);
  Paint := TSkPaint.Create;
  Paint.Color := $CCFFFFFF;
  Paint.AntiAlias := True;

  Font.MeasureText('ESC = Exit    C = Continue', TextBounds, Paint);
  TextX := (aWidth - TextBounds.Width) / 2;
  aCanvas.DrawSimpleText('ESC = Exit    C = Continue', TextX, aHeight * 0.52, Font, Paint);
end;

function TPlayScene.RequiredLayout: TLayoutMode;
begin
  Result := lmBottomPanel;
end;

function TPlayScene.DetachPanelRenderer: TPanelRenderer;
begin
  Result := fPanelRenderer;
  fPanelRenderer := nil;
end;

end.
