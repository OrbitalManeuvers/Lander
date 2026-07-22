unit u_PanelComputed;

interface

uses
  System.UITypes, System.Math;

// Returns fuel percentage clamped to [0..1]. Returns 0 if aCapacity = 0.
function ComputeFuelPercent(aFuel, aCapacity: Single): Single;

// Returns RCS percentage clamped to [0..1]. Returns 0 if aCapacity = 0.
function ComputeRCSPercent(aRCS, aCapacity: Single): Single;

// Returns estimated time-to-suicide-burn in seconds, clamped to max 999.9.
// Returns -1 when unavailable (ascending, no terrain/negative altitude, or
// deceleration <= 0).
function ComputeTimeToBurn(aVY, aAltitude, aThrustPower, aMass,
  aGravity: Single): Single;

// Returns gauge bar color based on fill percentage:
// green when > 50%, amber when 20%-50%, red when < 20%.
function GetGaugeColor(aPercent: Single): TAlphaColor;

// Returns velocity color based on absolute VY vs max landing speed:
// green when <= MaxSpeed, amber when <= 2x MaxSpeed, red when > 2x MaxSpeed.
function GetVelocityColor(aAbsVY, aMaxSpeed: Single): TAlphaColor;

implementation

function ComputeFuelPercent(aFuel, aCapacity: Single): Single;
begin
  if aCapacity <= 0 then
    Exit(0);
  Result := EnsureRange(aFuel / aCapacity, 0.0, 1.0);
end;

function ComputeRCSPercent(aRCS, aCapacity: Single): Single;
begin
  if aCapacity <= 0 then
    Exit(0);
  Result := EnsureRange(aRCS / aCapacity, 0.0, 1.0);
end;

function ComputeTimeToBurn(aVY, aAltitude, aThrustPower, aMass,
  aGravity: Single): Single;
var
  Decel: Single;
begin
  // Unavailable: ascending or hovering (VY <= 0 means not descending)
  if aVY <= 0 then
    Exit(-1);

  // Unavailable: no terrain below (negative altitude)
  if aAltitude < 0 then
    Exit(-1);

  // Compute net deceleration: thrust acceleration minus gravity
  if aMass <= 0 then
    Exit(-1);

  Decel := (aThrustPower / aMass) - aGravity;

  // Unavailable: insufficient thrust to overcome gravity
  if Decel <= 0 then
    Exit(-1);

  // Time = velocity / deceleration
  Result := aVY / Decel;

  // Clamp to max display value
  Result := Min(Result, 999.9);
end;

function GetGaugeColor(aPercent: Single): TAlphaColor;
begin
  if aPercent < 0.20 then
    Result := $FFFF3333   // Red
  else if aPercent <= 0.50 then
    Result := $FFFFAA00   // Amber
  else
    Result := $FF33FF66;  // Green
end;

function GetVelocityColor(aAbsVY, aMaxSpeed: Single): TAlphaColor;
begin
  if aAbsVY <= aMaxSpeed then
    Result := $FF33FF66   // Green
  else if aAbsVY <= aMaxSpeed * 2 then
    Result := $FFFFAA00   // Amber
  else
    Result := $FFFF3333;  // Red
end;

end.
