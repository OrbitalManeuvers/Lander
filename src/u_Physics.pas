unit u_Physics;

interface

uses
  u_Models;

// Updates craft state for one physics tick.
// Pure calculation — no rendering, no input awareness.
procedure PhysicsTick(var State: TCraftState; Profile: TCraftProfile;
  World: TWorldProfile; Delta: Single);

implementation

uses
  System.Math;

procedure PhysicsTick(var State: TCraftState; Profile: TCraftProfile;
  World: TWorldProfile; Delta: Single);
var
  ThrustAcc: Single;
  AngAcc: Single;
  SASDamp: Single;
  RCSCost: Single;
begin
  if not State.Alive then
    Exit;

  // --- Apply gravity ---
  State.VY := State.VY + World.Gravity * Delta;

  // --- Apply main thrust ---
  if (State.Thrust > 0) and (State.Fuel > 0) then
  begin
    // Acceleration = ThrustPower * throttle level
    ThrustAcc := Profile.ThrustPower * State.Thrust * Delta;

    // Thrust direction: Angle=0 means up, so thrust opposes gravity.
    // Sin(Angle) for X component, -Cos(Angle) for Y component.
    State.VX := State.VX + Sin(State.Angle) * ThrustAcc;
    State.VY := State.VY - Cos(State.Angle) * ThrustAcc;

    // Deplete fuel proportional to throttle
    State.Fuel := State.Fuel - Profile.BurnRate * State.Thrust * Delta;
  end;

  // --- Clamp main fuel at zero (Property 1) ---
  if State.Fuel < 0 then
    State.Fuel := 0;

  // --- Apply RCS angular acceleration ---
  AngAcc := 0;

  if (State.RotatingLeft or State.RotatingRight) and (State.RCSFuel > 0) then
  begin
    // RCSThrust is angular acceleration magnitude
    if State.RotatingLeft then
      AngAcc := AngAcc - Profile.RCSThrust * Delta;  // Counter-clockwise (negative)
    if State.RotatingRight then
      AngAcc := AngAcc + Profile.RCSThrust * Delta;  // Clockwise (positive)

    State.AngularVel := State.AngularVel + AngAcc;

    // Deplete RCS fuel while rotating
    RCSCost := Profile.RCSBurnRate * Delta;
    State.RCSFuel := State.RCSFuel - RCSCost;
  end;

  // --- Apply SAS auto-damping ---
  if State.SASActive and Profile.HasSAS and (State.RCSFuel > 0) and
     (not State.RotatingLeft) and (not State.RotatingRight) then
  begin
    if Abs(State.AngularVel) > 0.001 then
    begin
      // Damp angular velocity toward zero using RCS thrust
      SASDamp := Profile.RCSThrust * Delta;

      if Abs(State.AngularVel) <= SASDamp then
      begin
        // Close enough to zero — snap to zero
        State.AngularVel := 0;
      end
      else
      begin
        // Reduce angular velocity toward zero
        if State.AngularVel > 0 then
          State.AngularVel := State.AngularVel - SASDamp
        else
          State.AngularVel := State.AngularVel + SASDamp;
      end;

      // SAS costs RCS fuel
      RCSCost := Profile.RCSBurnRate * Delta;
      State.RCSFuel := State.RCSFuel - RCSCost;
    end;
  end;

  // --- Clamp RCS fuel at zero (Property 1) ---
  if State.RCSFuel < 0 then
    State.RCSFuel := 0;

  // --- Integrate angular velocity into angle ---
  State.Angle := State.Angle + State.AngularVel * Delta;

  // Normalize angle to [-Pi, Pi]
  while State.Angle > Pi do
    State.Angle := State.Angle - 2 * Pi;
  while State.Angle < -Pi do
    State.Angle := State.Angle + 2 * Pi;

  // --- Integrate velocity into position ---
  State.X := State.X + State.VX * Delta;
  State.Y := State.Y + State.VY * Delta;
end;

end.
