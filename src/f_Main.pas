unit f_Main;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  System.Types,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, System.Skia, Vcl.ExtCtrls, Vcl.Skia,

  u_SceneManager, u_FlightRenderer;

type
  TMainForm = class(TForm)
    GameTimer: TTimer;
    MainView: TSkAnimatedPaintBox;
    LeftView: TSkAnimatedPaintBox;
    BottomView: TSkAnimatedPaintBox;
    procedure GameTimerTick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure MainViewAnimationDraw(ASender: TObject; const ACanvas: ISkCanvas;
      const ADest: TRectF; const AProgress: Double; const AOpacity: Single);
    procedure LeftViewAnimationDraw(ASender: TObject; const ACanvas: ISkCanvas;
      const ADest: TRectF; const AProgress: Double; const AOpacity: Single);
    procedure BottomViewAnimationDraw(ASender: TObject;
      const ACanvas: ISkCanvas; const ADest: TRectF; const AProgress: Double;
      const AOpacity: Single);
  private
    fSceneManager: TSceneManager;
    fTime: Single;
    procedure HandleLayoutChange(Sender: TObject);
  public

  end;

var
  MainForm: TMainForm;

implementation

uses
  u_SceneBase, u_Models;

{$R *.dfm}

procedure TMainForm.FormCreate(Sender: TObject);
begin
  fSceneManager := TSceneManager.Create;
  fSceneManager.OnLayoutChange := HandleLayoutChange;

  fTime := 0.0;
  HandleLayoutChange(nil);
  MainView.ControlStyle := MainView.ControlStyle + [csOpaque];
  LeftView.ControlStyle := LeftView.ControlStyle + [csOpaque];
  BottomView.ControlStyle := BottomView.ControlStyle + [csOpaque];

  fSceneManager.Start(sidMenu);

  GameTimer.Enabled := True;
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  fSceneManager.Free;
end;

procedure TMainForm.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  fSceneManager.HandleInput(Key, ksDown);
end;

procedure TMainForm.FormKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  fSceneManager.HandleInput(Key, ksUp);
end;

procedure TMainForm.GameTimerTick(Sender: TObject);
begin
  fTime := fTime + 0.016; // ~16ms per tick at 60 FPS
  fSceneManager.Tick;
end;

procedure TMainForm.HandleLayoutChange(Sender: TObject);
begin
  LeftView.Visible := fSceneManager.LayoutMode = lmLeftPanel;
  BottomView.Visible := fSceneManager.LayoutMode = lmBottomPanel;
end;

procedure TMainForm.MainViewAnimationDraw(ASender: TObject; const ACanvas: ISkCanvas;
  const ADest: TRectF; const AProgress: Double; const AOpacity: Single);
begin
  if Assigned(fSceneManager) then
    fSceneManager.Render(ACanvas, Round(aDest.Width), Round(ADest.Height));
end;

procedure TMainForm.LeftViewAnimationDraw(ASender: TObject;
  const ACanvas: ISkCanvas; const ADest: TRectF; const AProgress: Double;
  const AOpacity: Single);
begin
  if Assigned(fSceneManager) and (ASender as TControl).Visible then
    fSceneManager.RenderPanel(aCanvas, Round(aDest.Width), Round(ADest.Height));
end;

procedure TMainForm.BottomViewAnimationDraw(ASender: TObject;
  const ACanvas: ISkCanvas; const ADest: TRectF; const AProgress: Double;
  const AOpacity: Single);
begin
  if Assigned(fSceneManager) and (ASender as TControl).Visible then
    fSceneManager.RenderPanel(aCanvas, Round(aDest.Width), Round(ADest.Height));
end;


end.
