unit u_SceneManager;

interface

uses System.Classes,
  System.SysUtils, System.Skia, Vcl.Controls, Vcl.ExtCtrls, Vcl.Skia,
  u_Models, u_SceneBase, u_Scenarios;

type
  // Persistent cross-scene state that survives scene transitions.
  // Owned by the scene manager; scenes read/write through it.
  TSessionContext = class
  private
    fScenario: TScenario;         // The scenario selected on the menu
    fEditorWorld: TWorldProfile;   // Editor's working world (unsaved edits survive play)
    fEditorFilePath: string;       // File path for save operations
    fReturnScene: TSceneID;       // Where play should exit to (menu or editor)
  public
    destructor Destroy; override;
    procedure Clear;

    // Transfers world ownership to caller; internal reference becomes nil.
    function TakeEditorWorld: TWorldProfile;

    property Scenario: TScenario read fScenario write fScenario;
    property EditorWorld: TWorldProfile read fEditorWorld write fEditorWorld;
    property EditorFilePath: string read fEditorFilePath write fEditorFilePath;
    property ReturnScene: TSceneID read fReturnScene write fReturnScene;
  end;

  // Owns the active scene and swaps scenes when one signals completion.
  // Controls layout mode (full-window vs panel+flight).
  // Forwards Tick, Render, HandleInput, and RenderPanel calls to the current scene.
  // Does NOT manage transition animations — scenes own their own exit/entrance visuals.
  TSceneManager = class
  private
    fCurrentScene: TGameScene;
    fLayoutMode: TLayoutMode;
    fOnLayoutChange: TNotifyEvent;
    fSession: TSessionContext;

    procedure ApplyLayout(aMode: TLayoutMode);
    procedure TransitionToScene(aSceneID: TSceneID);
    function CreateScene(aSceneID: TSceneID): TGameScene;
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
    property Session: TSessionContext read fSession;

    property OnLayoutChange: TNotifyEvent read fOnLayoutChange write fOnLayoutChange;
  end;

implementation

uses
  System.IOUtils,
  u_MenuScene, u_PlayScene, u_ResultScene, u_EditorScene,
  u_Serialization, u_PanelRenderer;

{ TSessionContext }

destructor TSessionContext.Destroy;
begin
  if fScenario.World <> fEditorWorld then
    fScenario.World.Free;
  fScenario.Craft.Free;
  fEditorWorld.Free;
  inherited;
end;

procedure TSessionContext.Clear;
begin
  // Free scenario's owned objects, but avoid double-free if EditorWorld is the same
  if fScenario.World <> fEditorWorld then
    fScenario.World.Free;
  fScenario.Craft.Free;
  FreeAndNil(fEditorWorld);
  fScenario := Default(TScenario);
  fEditorFilePath := '';
  fReturnScene := sidMenu;
end;

function TSessionContext.TakeEditorWorld: TWorldProfile;
begin
  Result := fEditorWorld;
  fEditorWorld := nil;
end;

{ TSceneManager }

constructor TSceneManager.Create;
begin
  inherited Create;
  fCurrentScene := nil;
  fLayoutMode := lmFullWindow;
  fSession := TSessionContext.Create;
end;

destructor TSceneManager.Destroy;
begin
  fCurrentScene.Free;
  fSession.Free;
  inherited;
end;

procedure TSceneManager.Start(aInitialSceneID: TSceneID);
begin
  FreeAndNil(fCurrentScene);
  fCurrentScene := CreateScene(aInitialSceneID);
  ApplyLayout(fCurrentScene.RequiredLayout);
end;

procedure TSceneManager.Tick;
begin
  if fCurrentScene = nil then
    Exit;

  fCurrentScene.Tick;

  if fCurrentScene.Finished then
    TransitionToScene(fCurrentScene.NextSceneID);
end;

procedure TSceneManager.Render(const aCanvas: ISkCanvas; aWidth, aHeight: Integer);
begin
  if fCurrentScene <> nil then
    fCurrentScene.Render(aCanvas, aWidth, aHeight);
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
  EditorWorld: TWorldProfile;
  PanelRend: TPanelRenderer;
begin
  PanelRend := nil;

  // --- Extract data from current scene before destroying it ---

  // Play → Result: grab outcome and panel renderer
  if (aSceneID = sidResult) and (fCurrentScene is TPlayScene) then
  begin
    Outcome := TPlayScene(fCurrentScene).Outcome;
    PanelRend := TPlayScene(fCurrentScene).DetachPanelRenderer;
  end
  else
    Outcome := Default(TPlayOutcome);

  // Menu → Play: grab selected scenario
  if (aSceneID = sidPlay) and (fCurrentScene is TMenuScene) then
  begin
    Scenario := TMenuScene(fCurrentScene).SelectedScenario;
    fSession.Scenario := Scenario;
    fSession.ReturnScene := sidMenu;
  end;

  // Menu → Editor: grab file path and store scenario for editor→play
  if (aSceneID = sidEditor) and (fCurrentScene is TMenuScene) then
  begin
    fSession.EditorFilePath := TMenuScene(fCurrentScene).EditorFilePath;
    fSession.Scenario := TMenuScene(fCurrentScene).SelectedScenario;
    fSession.ReturnScene := sidMenu;
  end;

  // Editor → Play: stash the editor's working world
  if (aSceneID = sidPlay) and (fCurrentScene is TEditorScene) then
  begin
    // Take ownership of the editor's world (editor relinquishes it)
    fSession.EditorWorld.Free;
    fSession.EditorWorld := TEditorScene(fCurrentScene).DetachWorld;
    fSession.ReturnScene := sidEditor;
  end;

  // Editor → Menu: clear editor state
  if (aSceneID = sidMenu) and (fCurrentScene is TEditorScene) then
    fSession.Clear;

  // Play → Menu (ESC from play when launched from menu): nothing special
  // Play → Editor (ESC from play when launched from editor): handled by ReturnScene

  // Destroy current scene (screen is guaranteed black at this point)
  FreeAndNil(fCurrentScene);

  // --- Create new scene ---
  case aSceneID of
    sidMenu:
      begin
        fSession.Clear;
        fCurrentScene := TMenuScene.Create;
      end;

    sidPlay:
      begin
        Scenario := fSession.Scenario;
        // Resolve world: use editor's working copy if available, else load from disk
        if fSession.EditorWorld <> nil then
          Scenario.World := fSession.EditorWorld
        else if Scenario.World = nil then
          Scenario.World := LoadWorldFromJSON(
            TPath.Combine(TPath.Combine(ExtractFilePath(ParamStr(0)), 'worlds'),
              Scenario.WorldID));
        // Craft: load from JSON file in craft/ subfolder
        if Scenario.Craft = nil then
        begin
          var CraftPath: string;
          CraftPath := TPath.Combine(
            TPath.Combine(ExtractFilePath(ParamStr(0)), 'craft'),
            Scenario.CraftID);
          if TFile.Exists(CraftPath) then
            Scenario.Craft := LoadCraftFromJSON(CraftPath)
          else
            Scenario.Craft := TScenarioBuilder.BuildBubbleCraft;
        end;
        fCurrentScene := TPlayScene.Create(Scenario, fSession.ReturnScene);
      end;

    sidResult:
      fCurrentScene := TResultScene.Create(Outcome, fSession.ReturnScene, PanelRend);

    sidEditor:
      begin
        // If we have a stashed editor world (returning from play), use it
        EditorWorld := fSession.TakeEditorWorld;
        if EditorWorld <> nil then
          fCurrentScene := TEditorScene.Create(fSession.EditorFilePath, EditorWorld)
        else
          fCurrentScene := TEditorScene.Create(fSession.EditorFilePath);
      end;
  else
    fCurrentScene := nil;
  end;

  // Reconfigure layout
  if Assigned(fCurrentScene) then
    ApplyLayout(fCurrentScene.RequiredLayout);

end;

procedure TSceneManager.ApplyLayout(aMode: TLayoutMode);
begin
  if fLayoutMode = aMode then
    Exit;

  fLayoutMode := aMode;
  if Assigned(fOnLayoutChange) then
    fOnLayoutChange(Self);
end;

function TSceneManager.CreateScene(aSceneID: TSceneID): TGameScene;
begin
  case aSceneID of
    sidMenu:
      Result := TMenuScene.Create;
    sidPlay:
      Result := TPlayScene.Create(TScenarioBuilder.BuildDefault, sidMenu);
    sidResult:
      Result := TResultScene.Create(Default(TPlayOutcome), sidMenu);
    sidEditor:
      Result := TEditorScene.Create(fSession.EditorFilePath);
  else
    Result := nil;
  end;
end;

end.
