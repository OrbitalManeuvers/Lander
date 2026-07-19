unit u_Landing;

interface

uses
  u_Models, u_Terrain;

type
  // Outcome of a landing evaluation.
  TLandingResult = record
    Success: Boolean;       // True if all criteria met, False = crash
    FailSpeed: Boolean;     // True if speed exceeded MaxSpeed
    FailAngle: Boolean;     // True if angle deviation exceeded MaxAngle
    FailPad: Boolean;       // True if contact was not on a pad (when required)
    FailGear: Boolean;      // True if gear was retracted (when required)
  end;

// Evaluates whether a terrain contact constitutes a successful landing or a crash.
// Pure function — no side effects, deterministic (Property 6).
// aState: craft state at moment of contact.
// aContact: collision result from TestHullCollision.
// aCriteria: thresholds for a successful landing.
// aHasRetractableGear: whether the craft has retractable gear (from TCraftProfile).
// Returns a TLandingResult indicating success/failure and which criteria failed.
function EvaluateLanding(const aState: TCraftState; const aContact: TContactResult;
  const aCriteria: TLandingCriteria; aHasRetractableGear: Boolean): TLandingResult;

implementation

uses
  System.Math;

function EvaluateLanding(const aState: TCraftState; const aContact: TContactResult;
  const aCriteria: TLandingCriteria; aHasRetractableGear: Boolean): TLandingResult;
var
  Speed: Single;
  AngleDeviation: Single;
begin
  Result.Success := True;
  Result.FailSpeed := False;
  Result.FailAngle := False;
  Result.FailPad := False;
  Result.FailGear := False;

  // Check pad requirement
  if aCriteria.MustBeOnPad and (not aContact.IsPad) then
  begin
    Result.FailPad := True;
    Result.Success := False;
  end;

  // Check speed magnitude against MaxSpeed
  Speed := Sqrt(aState.VX * aState.VX + aState.VY * aState.VY);
  if Speed > aCriteria.MaxSpeed then
  begin
    Result.FailSpeed := True;
    Result.Success := False;
  end;

  // Check angle deviation from vertical (0 = up).
  // Convert radians to degrees for comparison with MaxAngle (in degrees).
  AngleDeviation := Abs(aState.Angle) * (180.0 / Pi);
  if AngleDeviation > aCriteria.MaxAngle then
  begin
    Result.FailAngle := True;
    Result.Success := False;
  end;
end;

end.
