unit u_SceneManager;

interface

uses System.Classes,
  System.SysUtils, System.Skia, Vcl.Controls, Vcl.ExtCtrls, Vcl.Skia,
  u_Models, u_SceneBase;

type
  // Layout mode for the form surfaces.
  TLayoutMode = (lmFullWindow, lmPanelAndFlight);

  // Owns the active scene and swaps scenes when one signals completion.
  // Controls layout mode (full-window vs panel+flight).
  // Forwards Tick, Render, HandleInput, and RenderPanel calls to the current scene.
  // Does NOT manage transition animations — scenes own their own exit/entrance visuals.
  TSceneManager = class
  private
    fCurrentScene: TGameScene;
    fLayoutMode: TLayoutMode;
    fOnLayoutChange: TNotifyEvent;

    procedure ApplyLayout(aMode: TLayoutMode);
    procedure TransitionToScene(aSceneID: TSceneID);
    function CreateScene(aSceneID: TSceneID): TGameScene;
    function GetSceneLayout(aSceneID: TSceneID): TLayoutMode;
  public
    constructor Create;
    destructor Destroy; override;

    // Called each timer tick. Forwards to current scene and checks for transition.
    procedure Tick;

    // Called from flight view OnDraw. Forwards to current scene Render.
    procedure Render(const aCanvas: ISkCanvas; aWidth, aHeight: Integer);

    // Called from panel OnDraw. Forwards to current scene RenderPanel.
    procedure RenderPanel(const aCanvas: ISkCanvas; aWidth, aHeight: Integer);

    // Forwards key events to the current scene.
    procedure HandleInput(aKeyCode: Word; aKeyState: TKeyState);

    // Starts the scene manager with an initial scene.
    procedure Start(aInitialSceneID: TSceneID);

    property CurrentScene: TGameScene read fCurrentScene;
    property LayoutMode: TLayoutMode read fLayoutMode;

    property OnLayoutChange: TNotifyEvent read fOnLayoutChange write fOnLayoutChange;
  end;

implementation

uses
  u_MenuScene, u_PlayScene, u_Scenarios;

{ TSceneManager }

constructor TSceneManager.Create;
begin
  inherited Create;
  fCurrentScene := nil;
  fLayoutMode := lmFullWindow;
end;

destructor TSceneManager.Destroy;
begin
  fCurrentScene.Free;
  inherited;
end;

procedure TSceneManager.Start(aInitialSceneID: TSceneID);
begin
  FreeAndNil(fCurrentScene);
  ApplyLayout(GetSceneLayout(AInitialSceneID));
  fCurrentScene := CreateScene(AInitialSceneID);
end;

procedure TSceneManager.Tick;
begin
  if fCurrentScene = nil then
    Exit;

  fCurrentScene.Tick;

  // Check if the scene signalled completion
  if fCurrentScene.Finished then
    TransitionToScene(fCurrentScene.NextSceneID);
end;

procedure TSceneManager.Render(const aCanvas: ISkCanvas; aWidth, aHeight: Integer);
begin
  if fCurrentScene <> nil then
    fCurrentScene.Render(ACanvas, AWidth, AHeight);
end;

procedure TSceneManager.RenderPanel(const aCanvas: ISkCanvas; aWidth, aHeight: Integer);
begin
  if fCurrentScene <> nil then
    fCurrentScene.RenderPanel(aCanvas, aWidth, aHeight);
end;

procedure TSceneManager.HandleInput(aKeyCode: Word; aKeyState: TKeyState);
begin
  if fCurrentScene <> nil then
    fCurrentScene.HandleInput(aKeyCode, aKeyState);
end;

procedure TSceneManager.TransitionToScene(aSceneID: TSceneID);
begin
  // Destroy current scene (screen is guaranteed black at this point)
  FreeAndNil(fCurrentScene);

  // Reconfigure layout based on the next scene's requirements
  ApplyLayout(GetSceneLayout(aSceneID));

  // Create and activate the new scene
  fCurrentScene := CreateScene(aSceneID);
end;

function TSceneManager.GetSceneLayout(aSceneID: TSceneID): TLayoutMode;
begin
  case ASceneID of
    sidMenu:
      Result := lmFullWindow;
    sidPlay, sidResult:
      Result := lmPanelAndFlight;
  else
    Result := lmFullWindow;
  end;
end;

procedure TSceneManager.ApplyLayout(aMode: TLayoutMode);
begin
  if fLayoutMode = AMode then
    Exit;

  fLayoutMode := AMode;
  if Assigned(fOnLayoutChange) then
    fOnLayoutChange(Self);
end;

function TSceneManager.CreateScene(aSceneID: TSceneID): TGameScene;
begin
  case aSceneID of
    sidMenu:
      Result := TMenuScene.Create;
    sidPlay:
      Result := TPlayScene.Create(TScenarioBuilder.BuildDefault);
  else
    // Placeholder for other scenes — will be added in later tasks.
    Result := nil;
  end;
end;

end.
