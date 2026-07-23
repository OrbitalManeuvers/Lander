unit u_Models;

interface

uses
  System.Types, System.UITypes, System.Skia;

type
  // Scene identifier for scene manager transitions.
  TSceneID = (sidMenu, sidPlay, sidResult, sidEditor);

  TFeatureKind = (fkJagged, fkRollingHills, fkCanyon, fkMountain, fkCrater, fkCliff, fkFlat, fkRidgeLine, fkChaos);

  // A landing pad within the terrain polyline.
  TPad = record
    StartIndex: Integer;   // Index into terrain array (start of flat segment)
    EndIndex: Integer;     // Index into terrain array (end of flat segment)
    PointValue: Integer;   // Score awarded for successful landing
  end;

  // Thresholds for evaluating a successful landing.
  TLandingCriteria = record
    MaxSpeed: Single;      // Maximum resultant velocity magnitude
    MaxAngle: Single;      // Maximum deviation from vertical (degrees)
  end;

  // Real-time mutable state of the craft during gameplay.
  // Updated by the physics engine each tick.
  // Angle convention: 0 = up, positive angular velocity = clockwise.
  TCraftState = record
    X: Single;              // World position X
    Y: Single;              // World position Y
    VX: Single;             // Velocity X component
    VY: Single;             // Velocity Y component
    Angle: Single;          // Facing angle (0 = up, CW positive, radians)
    AngularVel: Single;     // Angular velocity (persists, no implicit damping)
    Fuel: Single;           // Main thruster fuel remaining
    RCSFuel: Single;        // RCS fuel remaining
    Thrust: Single;         // Current throttle level (0.0 = off, 1.0 = full)
    RotatingLeft: Boolean;  // RCS firing left (counter-clockwise)
    RotatingRight: Boolean; // RCS firing right (clockwise)
    SASActive: Boolean;     // Stability assist active
    Alive: Boolean;         // Craft not yet crashed
  end;

  // Instrument type identifiers for the control panel.
  TInstrumentKind = (ikFuelGauge, ikRCSGauge, ikVelocity, ikAltimeter,
    ikAttitude, ikSASIndicator, ikLandingGuidance);

  // Instrument descriptor for panel layout.
  TInstrument = record
    Kind: TInstrumentKind;
  end;

  TInstrumentArray = array of TInstrument;
  TPadArray = array of TPad;
  TTerrainArray = array of TPointF;

  // Snapshot of panel-relevant values for freeze behavior on Result scene.
  TPanelState = record
    Fuel: Single;
    RCSFuel: Single;
    VX: Single;
    VY: Single;
    Altitude: Single;
    Angle: Single;
    SASActive: Boolean;
    Frozen: Boolean;
  end;

  // A visual part of the craft hull. Drawn in array order (back to front).
  TCraftPart = record
    Path: ISkPath;
    Color: TAlphaColor;
    Style: TSkPaintStyle;  // Stroke, Fill, or StrokeAndFill
    StrokeWidth: Single;   // Only used when Style includes Stroke
  end;

  TCraftPartArray = array of TCraftPart;

  TPointFArray = array of TPointF;

  // Outcome data from a play session, passed to the result scene.
  TPlayOutcome = record
    Success: Boolean;        // True = landed, False = crashed
    FailSpeed: Boolean;      // Crash reason: too fast
    FailAngle: Boolean;      // Crash reason: too tilted
    FailPad: Boolean;        // Crash reason: not on a pad
    PadPoints: Integer;      // Points from pad (0 if crash or off-pad)
    FuelBonus: Integer;      // Fuel bonus (0 if crash)
    TotalScore: Integer;     // Sum of all scoring
    LivesRemaining: Integer; // Lives after this outcome
  end;

  TEditorCursor = record
    GridX: Integer;         // cursor left edge in grid units (multiply by 10 for world X)
    GridWidth: Integer;     // cursor width in grid units (minimum 1)
    Altitude: Single;       // world Y altitude for feature placement
  end;

  // Static definition of a craft's characteristics.
  // Loaded once, never mutated during play.
  TCraftProfile = class
  private
    fName: string;
    fHullParts: TCraftPartArray;    // Visual parts drawn in order
    fCollisionPath: ISkPath;        // Simplified outer boundary for collision detection
    fThrustOffset: TPointF;         // Engine nozzle position relative to center
    fRCSOffsets: TPointFArray;      // RCS thruster positions on hull
    fPlumeLength: Single;           // Main plume length in craft units
    fPlumeWidth: Single;            // Main plume width in craft units
    fRCSRadius: Single;             // RCS puff radius in craft units
    fMass: Single;
    fThrustPower: Single;
    fFuelCapacity: Single;
    fBurnRate: Single;
    fRCSFuelCapacity: Single;
    fRCSBurnRate: Single;
    fRCSThrust: Single;
    fPlumeColor: TAlphaColor;
    fHasSAS: Boolean;
    fHasThrottleControl: Boolean;
    fPanelFontFamily: string;
    fLandingCriteria: TLandingCriteria;
    fInstruments: TInstrumentArray;
    fCollisionPoints: TPointFArray;
  public
    property Name: string read fName write fName;
    property HullParts: TCraftPartArray read fHullParts write fHullParts;
    property CollisionPath: ISkPath read fCollisionPath write fCollisionPath;
    property ThrustOffset: TPointF read fThrustOffset write fThrustOffset;
    property RCSOffsets: TPointFArray read fRCSOffsets write fRCSOffsets;
    property PlumeLength: Single read fPlumeLength write fPlumeLength;
    property PlumeWidth: Single read fPlumeWidth write fPlumeWidth;
    property RCSRadius: Single read fRCSRadius write fRCSRadius;
    property Mass: Single read fMass write fMass;
    property ThrustPower: Single read fThrustPower write fThrustPower;
    property FuelCapacity: Single read fFuelCapacity write fFuelCapacity;
    property BurnRate: Single read fBurnRate write fBurnRate;
    property RCSFuelCapacity: Single read fRCSFuelCapacity write fRCSFuelCapacity;
    property RCSBurnRate: Single read fRCSBurnRate write fRCSBurnRate;
    property RCSThrust: Single read fRCSThrust write fRCSThrust;
    property PlumeColor: TAlphaColor read fPlumeColor write fPlumeColor;
    property HasSAS: Boolean read fHasSAS write fHasSAS;
    property HasThrottleControl: Boolean read fHasThrottleControl write fHasThrottleControl;
    property PanelFontFamily: string read fPanelFontFamily write fPanelFontFamily;
    property LandingCriteria: TLandingCriteria read fLandingCriteria write fLandingCriteria;
    property Instruments: TInstrumentArray read fInstruments write fInstruments;
    property CollisionPoints: TPointFArray read fCollisionPoints write fCollisionPoints;
  end;

  // Static definition of a world/level.
  // Contains terrain geometry and landing pad definitions.
  TWorldProfile = class
  private
    FName: String;
    FGravity: Single;
    FTerrain: TTerrainArray;
    FPads: TPadArray;
    FTerrainColor: TAlphaColor;
    FPadColor: TAlphaColor;
  public
    property Name: String read FName write FName;
    property Gravity: Single read FGravity write FGravity;
    property Terrain: TTerrainArray read FTerrain write FTerrain;
    property Pads: TPadArray read FPads write FPads;
    property TerrainColor: TAlphaColor read FTerrainColor write FTerrainColor;
    property PadColor: TAlphaColor read FPadColor write FPadColor;
  end;

// Craft authoring helpers — author in grid space (0,0 = top-left),
// these functions subtract the pivot to produce centered paths/offsets.

// Builds a closed or open ISkPath from grid-space points, subtracting the pivot.
function BuildCraftPath(const aPoints: array of TPointF;
  const aPivot: TPointF; aClosed: Boolean): ISkPath;

// Offsets a single point from grid space to pivot-centered space.
function PivotOffset(const aPoint, aPivot: TPointF): TPointF;

implementation

function BuildCraftPath(const aPoints: array of TPointF;
  const aPivot: TPointF; aClosed: Boolean): ISkPath;
var
  Builder: ISkPathBuilder;
  I: Integer;
begin
  Result := nil;
  if Length(aPoints) < 2 then
    Exit;

  Builder := TSkPathBuilder.Create;
  Builder.MoveTo(PointF(aPoints[0].X - aPivot.X, aPoints[0].Y - aPivot.Y));
  for I := 1 to High(aPoints) do
    Builder.LineTo(PointF(aPoints[I].X - aPivot.X, aPoints[I].Y - aPivot.Y));
  if aClosed then
    Builder.Close;
  Result := Builder.Detach;
end;

function PivotOffset(const aPoint, aPivot: TPointF): TPointF;
begin
  Result := PointF(aPoint.X - aPivot.X, aPoint.Y - aPivot.Y);
end;

end.
