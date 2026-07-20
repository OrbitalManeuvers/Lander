object MainForm: TMainForm
  Left = 0
  Top = 0
  Caption = 'Lander'
  ClientHeight = 883
  ClientWidth = 1431
  Color = 2236962
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -13
  Font.Name = 'Segoe UI'
  Font.Style = []
  KeyPreview = True
  StyleElements = [seFont, seBorder]
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  OnKeyDown = FormKeyDown
  OnKeyUp = FormKeyUp
  TextHeight = 17
  object PBFlight: TSkAnimatedPaintBox
    AlignWithMargins = True
    Left = 245
    Top = 4
    Width = 1182
    Height = 875
    Margins.Left = 4
    Margins.Top = 4
    Margins.Right = 4
    Margins.Bottom = 4
    Align = alClient
    BackendRender = HardwareAcceleration
    OnAnimationDraw = PBFlightAnimationDraw
    ExplicitWidth = 857
    ExplicitHeight = 596
  end
  object PBPanel: TSkAnimatedPaintBox
    AlignWithMargins = True
    Left = 4
    Top = 4
    Width = 233
    Height = 875
    Margins.Left = 4
    Margins.Top = 4
    Margins.Right = 4
    Margins.Bottom = 4
    Align = alLeft
    OnAnimationDraw = PBPanelAnimationDraw
    ExplicitHeight = 596
  end
  object GameTimer: TTimer
    Enabled = False
    Interval = 16
    OnTimer = GameTimerTick
    Left = 264
    Top = 40
  end
end
