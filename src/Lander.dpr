program Lander;

uses
  Vcl.Forms,
  f_Main in 'f_Main.pas' {MainForm},
  u_Models in 'u_Models.pas',
  u_SceneBase in 'u_SceneBase.pas',
  u_SceneManager in 'u_SceneManager.pas',
  u_Physics in 'u_Physics.pas',
  u_Terrain in 'u_Terrain.pas',
  u_Landing in 'u_Landing.pas',
  u_Scoring in 'u_Scoring.pas',
  u_FlightRenderer in 'u_FlightRenderer.pas',
  u_MenuScene in 'u_MenuScene.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
