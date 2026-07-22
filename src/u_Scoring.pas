unit u_Scoring;

interface

type
  // Tracks score accumulation and remaining lives.
  // Simple state class — no rendering, no scene dependencies.
  TScoreKeeper = class
  private
    fScore: Integer;
    fLives: Integer;
  public
    const
      MaxLives = 3;
      FuelBonusMultiplier = 100;

    constructor Create;

    // Awards points for a successful landing.
    // aPadPointValue: base points from the pad's PointValue.
    // aFuelRemaining: fuel left at time of landing.
    // aFuelCapacity: total fuel capacity (for percentage calc).
    procedure AwardLanding(aPadPointValue: Integer; aFuelRemaining: Single;
      aFuelCapacity: Single);

    // Decrements lives by 1 on crash. Clamped at 0.
    procedure ApplyCrash;

    // Resets score and lives to starting values.
    procedure Reset;

    // True when lives = 0.
    function IsGameOver: Boolean;

    property Score: Integer read fScore;
    property Lives: Integer read fLives;
  end;

implementation

uses
  System.Math;

constructor TScoreKeeper.Create;
begin
  inherited Create;
  fScore := 0;
  fLives := MaxLives;
end;

procedure TScoreKeeper.AwardLanding(aPadPointValue: Integer;
  aFuelRemaining: Single; aFuelCapacity: Single);
var
  FuelBonus: Integer;
begin
  // Fuel bonus = remaining fuel as percentage × multiplier, rounded.
  if aFuelCapacity > 0 then
    FuelBonus := Round(aFuelRemaining / aFuelCapacity * FuelBonusMultiplier)
  else
    FuelBonus := 0;

  fScore := fScore + aPadPointValue + FuelBonus;
end;

procedure TScoreKeeper.ApplyCrash;
begin
  // Decrement lives by exactly 1, clamped at 0 (Property 8).
  fLives := Max(fLives - 1, 0);
end;

procedure TScoreKeeper.Reset;
begin
  // Score persists — only reset lives
  fLives := MaxLives;
end;

function TScoreKeeper.IsGameOver: Boolean;
begin
  Result := fLives = 0;
end;

end.
