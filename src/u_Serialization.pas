unit u_Serialization;

interface

uses System.JSON,
  u_Models;

type
  TCraftLoader = class helper for TCraftProfile
    procedure LoadFromJSON(const JSON: TJSONObject);
  end;

  TWorldLoader = class helper for TWorldProfile
    procedure LoadFromJSON(const JSON: TJSONObject);
  end;

implementation

const
  KEY_NAME = 'name';
  KEY_PIVOT = 'pivot';
  KEY_THRUST_OFFSET = 'thrustOffset';
  KEY_RCS_OFFSETS = 'rcsOffsets';
  KEY_PLUME_LENGTH = 'plumeLength';
  KEY_PLUME_WIDTH = 'plumeWidth';
  KEY_RCS_RADIUS = 'rcsRadius';
  KEY_PLUME_COLOR = 'plumeColor';
  KEY_MASS = 'mass';
  KEY_THRUST_POWER = 'thrustPower';
  KEY_FUEL_CAPACITY = 'fuelCapacity';
  KEY_BURN_RATE = 'burnRate';
  KEY_RCS_CAPACITY = 'rcsFuelCapacity';
  KEY_RCS_BURN_RATE = 'rcsBurnRate';
  KEY_RCS_THRUST = 'rcsThrust';


type
  { TSimpleJSONReader }
  TSimpleJSONReader = class helper for TJSONObject
    function StrValue(aKey: string): string;
    function IntValue(aKey: string): Integer;
  end;


type
  TPointFArrayLoader = record helper for TPointFArray
    procedure LoadFromJSON(const JSON: TJSONArray);
  end;


{ TPointFArrayLoader }

procedure TPointFArrayLoader.LoadFromJSON(const JSON: TJSONArray);
begin
  //
end;


{ TCraftLoader }

procedure TCraftLoader.LoadFromJSON(const JSON: TJSONObject);
var
  jArr: TJSONArray;
begin

  Self.Name := JSON.StrValue(KEY_NAME);

  if JSON.TryGetValue(KEY_RCS_OFFSETS, jArr) then
    self.RCSOffsets.LoadFromJSON(jArr);



end;

{ TWorldLoader }

procedure TWorldLoader.LoadFromJSON(const JSON: TJSONObject);
begin

end;

{ TSimpleJSONReader }
function TSimpleJSONReader.IntValue(aKey: string): Integer;
begin
  Result := -1;
  var aValue: Integer;
  if Self.TryGetValue(aKey, aValue) then
    Result := aValue;
end;

//function TSimpleJSONReader.PointValue(aKey, aXKey, aYkey: string): TPoint;
//begin
//  Result := Default(TPoint);
//  var obj: TJSONObject;
//  if Self.TryGetValue(aKey, obj) then
//  begin
//    Result.x := obj.IntValue(aXKey);
//    Result.y := obj.IntValue(aYKey);
//  end;
//end;

function TSimpleJSONReader.StrValue(aKey: string): string;
begin
  Result := '';
  var aValue: string;
  if Self.TryGetValue(aKey, aValue) then
    Result := aValue;
end;


end.
