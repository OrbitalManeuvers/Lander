unit u_PanelLayout;

interface

uses
  System.Types, u_Models;

type
  // A computed slot: which instrument kind and its bounding rect on the panel.
  TSlot = record
    Kind: TInstrumentKind;
    Rect: TRectF;
  end;

// Computes bounding rects for each instrument slot in a horizontal flow layout.
// Slot widths per kind: Fuel=50, RCS=45, Velocity=90, Altimeter=80,
// Attitude=120, SAS=40, LandingGuidance=90.
// Uniform spacing of 6px between slots, left/right margins of 8px.
// Skips ikSASIndicator when aHasSAS = False.
// Excludes any slot whose left edge >= aPanelWidth.
// Returns empty array when aInstruments is empty.
function ComputeSlots(const aInstruments: TInstrumentArray;
  aPanelWidth, aPanelHeight: Single; aHasSAS: Boolean): TArray<TSlot>;

implementation

const
  CMargin = 8.0;
  CSpacing = 6.0;

function SlotWidth(aKind: TInstrumentKind): Single;
begin
  case aKind of
    ikFuelGauge:       Result := 50;
    ikRCSGauge:        Result := 45;
    ikVelocity:        Result := 90;
    ikAltimeter:       Result := 80;
    ikAttitude:        Result := 120;
    ikSASIndicator:    Result := 40;
    ikLandingGuidance: Result := 90;
  else
    Result := 60;
  end;
end;

function ComputeSlots(const aInstruments: TInstrumentArray;
  aPanelWidth, aPanelHeight: Single; aHasSAS: Boolean): TArray<TSlot>;
var
  I, Count: Integer;
  X, W: Single;
  Slot: TSlot;
begin
  SetLength(Result, 0);
  if Length(aInstruments) = 0 then
    Exit;

  X := CMargin;
  Count := 0;

  for I := 0 to High(aInstruments) do
  begin
    // Skip SAS indicator when craft has no SAS
    if (aInstruments[I].Kind = ikSASIndicator) and (not aHasSAS) then
      Continue;

    // Add spacing before all slots except the first
    if Count > 0 then
      X := X + CSpacing;

    // Clip: exclude slots whose left edge is at or beyond panel width
    if X >= aPanelWidth then
      Break;

    W := SlotWidth(aInstruments[I].Kind);

    Slot.Kind := aInstruments[I].Kind;
    Slot.Rect := TRectF.Create(X, 0, X + W, aPanelHeight);

    SetLength(Result, Count + 1);
    Result[Count] := Slot;
    Inc(Count);

    X := X + W;
  end;
end;

end.
