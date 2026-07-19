unit u_SceneBase;

interface

uses
  System.Skia, u_Models;

type
  // Key state passed to HandleInput.
  TKeyState = (ksDown, ksUp);

  // Abstract base class for all game scenes.
  // Scenes own their own logic, rendering, and exit/entrance animations.
  TGameScene = class abstract
  private
    FFinished: Boolean;
    FNextSceneID: TSceneID;
  protected
    procedure SetFinished(ANextSceneID: TSceneID);
  public
    // Receives key events forwarded from the form.
    procedure HandleInput(AKeyCode: Word; AKeyState: TKeyState); virtual; abstract;

    // Called each timer tick for physics/logic updates.
    procedure Tick; virtual; abstract;

    // Draws on the flight view TSkPaintBox.
    procedure Render(const ACanvas: ISkCanvas; AWidth, AHeight: Integer); virtual; abstract;

    // Draws on the control panel TSkPaintBox.
    // Virtual with empty default — scenes that don't use the panel (e.g. Menu)
    // simply don't override this.
    procedure RenderPanel(const ACanvas: ISkCanvas; AWidth, AHeight: Integer); virtual;

    // True when the scene has completed and is ready to be replaced.
    property Finished: Boolean read FFinished;

    // Identifies which scene to create next after this one finishes.
    property NextSceneID: TSceneID read FNextSceneID;
  end;

implementation

{ TGameScene }

procedure TGameScene.SetFinished(ANextSceneID: TSceneID);
begin
  FFinished := True;
  FNextSceneID := ANextSceneID;
end;

procedure TGameScene.RenderPanel(const ACanvas: ISkCanvas; AWidth, AHeight: Integer);
begin
  // Empty default — scenes that don't use the panel need not override.
end;

end.
