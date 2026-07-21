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
    fEditorFilePath: string;  // World file path for editor scene

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

    // Starts the editor with a specific world file.
    procedure StartEditor(const aFilePath: string);

    property CurrentScene: TGameScene read fCurrentScene;
    property LayoutMode: TLayoutMode read fLayoutMode;

    property OnLayoutChange: TNotifyEvent read fOnLayoutChange write fOnLayoutChange;
  end;

implementation

uses
  System.IOUtils,
  u_MenuScene, u_PlayScene, u_ResultScene, u_EditorScene, u_Scenarios,
  u_Serialization;

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

procedure TSceneManager.StartEditor(const aFilePath: string);
begin
  fEditorFilePath := aFilePath;
  FreeAndNil(fCurrentScene);
  ApplyLayout(GetSceneLayout(sidEditor));
  fCurrentScene := CreateScene(sidEditor);
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
var
  Outcome: TPlayOutcome;
  Scenario: TScenario;
begin
  // Extract outcome from play scene before destroying it
  if (aSceneID = sidResult) and (fCurrentScene is TPlayScene) then
    Outcome := TPlayScene(fCurrentScene).Outcome
  else
    Outcome := Default(TPlayOutcome);

  // Extract selected scenario from menu scene before destroying it
  if (aSceneID = sidPlay) and (fCurrentScene is TMenuScene) then
    Scenario := TMenuScene(fCurrentScene).SelectedScenario
  else
    Scenario := Default(TScenario);

  // Extract editor file path from menu scene before destroying it
  if (aSceneID = sidEditor) and (fCurrentScene is TMenuScene) then
    fEditorFilePath := TMenuScene(fCurrentScene).EditorFilePath;

  // Destroy current scene (screen is guaranteed black at this point)
  FreeAndNil(fCurrentScene);

  // Reconfigure layout based on the next scene's requirements
  ApplyLayout(GetSceneLayout(aSceneID));

  // Create and activate the new scene
  case aSceneID of
    sidMenu:
      fCurrentScene := TMenuScene.Create;
    sidPlay:
      begin
        // Resolve the scenario: load world and craft from disk
        if Scenario.Name <> '' then
        begin
          if Scenario.World = nil then
            Scenario.World := LoadWorldFromJSON(
              TPath.Combine(TPath.Combine(ExtractFilePath(ParamStr(0)), 'worlds'),
                Scenario.WorldID));
          // Craft loading not yet implemented — fall back to BuildDefault's craft
          if Scenario.Craft = nil then
            Scenario.Craft := TScenarioBuilder.BuildDefault.Craft;
          fCurrentScene := TPlayScene.Create(Scenario);
        end
        else
          fCurrentScene := TPlayScene.Create(TScenarioBuilder.BuildDefault);
      end;
    sidResult:
      fCurrentScene := TResultScene.Create(Outcome);
    sidEditor:
      fCurrentScene := TEditorScene.Create(fEditorFilePath);
  else
    fCurrentScene := nil;
  end;
end;

function TSceneManager.GetSceneLayout(aSceneID: TSceneID): TLayoutMode;
begin
  case ASceneID of
    sidMenu:
      Result := lmFullWindow;
    sidPlay, sidResult, sidEditor:
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
    sidResult:
      Result := TResultScene.Create(Default(TPlayOutcome));
    sidEditor:
      Result := TEditorScene.Create(fEditorFilePath);
  else
    Result := nil;
  end;
end;

end.
