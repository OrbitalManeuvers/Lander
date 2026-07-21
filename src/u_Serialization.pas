unit u_Serialization;

interface

uses System.JSON,
  u_Models;

// Keeps file I/O out of base classes

type
  TCraftHelper = class helper for TCraftProfile
  private
    function GetJSON: TJSONObject;
    procedure SetJSON(const Value: TJSONObject);
  public
    property AsJSON: TJSONObject read GetJSON write SetJSON;
  end;

  TWorldHelper = class helper for TWorldProfile
  private
    function GetJSON: TJSONObject;
    procedure SetJSON(const Value: TJSONObject);
  public
    property AsJSON: TJSONObject read GetJSON write SetJSON;
  end;

// Standalone file I/O for world profiles
procedure SaveWorldToJSON(aWorld: TWorldProfile; const aFilePath: string);
function LoadWorldFromJSON(const aFilePath: string): TWorldProfile;

implementation

uses
  System.SysUtils, System.IOUtils, System.Types, System.UITypes,
  System.Generics.Collections;

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

  // World JSON keys
  KEY_GRAVITY = 'gravity';
  KEY_WIND = 'wind';
  KEY_TERRAIN_COLOR = 'terrainColor';
  KEY_PAD_COLOR = 'padColor';
  KEY_TERRAIN = 'terrain';
  KEY_PADS = 'pads';
  KEY_X = 'x';
  KEY_Y = 'y';
  KEY_START_INDEX = 'startIndex';
  KEY_END_INDEX = 'endIndex';
  KEY_POINT_VALUE = 'pointValue';


type
  { TSimpleJSONReader }
  TSimpleJSONReader = class helper for TJSONObject
    function StrValue(aKey: string): string;
    function IntValue(aKey: string): Integer;
    function FloatValue(aKey: string): Single;
  end;


type
  TTerrainArrayHelper = record helper for TTerrainArray
  private
    function GetJSON: TJSONArray;
    procedure SetJSON(const Value: TJSONArray);
  public
    property AsJSON: TJSONArray read GetJSON write SetJSON;
  end;


{ TTerrainArrayHelper }

procedure TTerrainArrayHelper.SetJSON(const Value: TJSONArray);
var
  i: Integer;
  obj: TJSONObject;
begin
  SetLength(Self, Value.Count);
  for i := 0 to Value.Count - 1 do
  begin
    obj := Value.Items[i] as TJSONObject;
    Self[i] := PointF(obj.FloatValue(KEY_X), obj.FloatValue(KEY_Y));
  end;
end;

function TTerrainArrayHelper.GetJSON: TJSONArray;
var
  i: Integer;
  obj: TJSONObject;
begin
  Result := TJSONArray.Create;
  for i := 0 to High(Self) do
  begin
    obj := TJSONObject.Create;
    obj.AddPair(KEY_X, TJSONNumber.Create(Self[i].X));
    obj.AddPair(KEY_Y, TJSONNumber.Create(Self[i].Y));
    Result.AddElement(obj);
  end;
end;

{ TCraftHelper }

procedure TCraftHelper.SetJSON(const Value: TJSONObject);
var
  jArr: TJSONArray;
begin
  Self.Name := Value.StrValue(KEY_NAME);

  if Value.TryGetValue(KEY_RCS_OFFSETS, jArr) then
  begin
    var rcs: TTerrainArray;
    rcs := nil;
    rcs.AsJSON := jArr;
    Self.RCSOffsets := TPointFArray(rcs);
  end;

  //

end;

function TCraftHelper.GetJSON: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair(KEY_NAME, Self.Name);


end;


{ TWorldHelper }

function TWorldHelper.GetJSON: TJSONObject;
var
  padsArr: TJSONArray;
  padObj: TJSONObject;
  i: Integer;
begin
  Result := TJSONObject.Create;
  Result.AddPair(KEY_NAME, Self.Name);
  Result.AddPair(KEY_GRAVITY, TJSONNumber.Create(Self.Gravity));
  Result.AddPair(KEY_WIND, TJSONNumber.Create(Self.Wind));
  Result.AddPair(KEY_TERRAIN_COLOR, IntToHex(Self.TerrainColor, 8));
  Result.AddPair(KEY_PAD_COLOR, IntToHex(Self.PadColor, 8));

  // Terrain array
  Result.AddPair(KEY_TERRAIN, Self.Terrain.AsJSON);

  // Pads array
  padsArr := TJSONArray.Create;
  for i := 0 to High(Self.Pads) do
  begin
    padObj := TJSONObject.Create;
    padObj.AddPair(KEY_START_INDEX, TJSONNumber.Create(Self.Pads[i].StartIndex));
    padObj.AddPair(KEY_END_INDEX, TJSONNumber.Create(Self.Pads[i].EndIndex));
    padObj.AddPair(KEY_POINT_VALUE, TJSONNumber.Create(Self.Pads[i].PointValue));
    padsArr.AddElement(padObj);
  end;
  Result.AddPair(KEY_PADS, padsArr);
end;

procedure TWorldHelper.SetJSON(const Value: TJSONObject);
var
  terrainArr: TJSONArray;
  padsArr: TJSONArray;
  padObj: TJSONObject;
  i: Integer;
  colorStr: string;
  terrain: TTerrainArray;
begin
  Self.Name := Value.StrValue(KEY_NAME);
  Self.Gravity := Value.FloatValue(KEY_GRAVITY);
  Self.Wind := Value.FloatValue(KEY_WIND);

  // Parse terrain color from hex string
  colorStr := Value.StrValue(KEY_TERRAIN_COLOR);
  if colorStr <> '' then
    Self.TerrainColor := TAlphaColor(StrToUInt('$' + colorStr))
  else
    Self.TerrainColor := $FFB0B0B0;

  // Parse pad color from hex string
  colorStr := Value.StrValue(KEY_PAD_COLOR);
  if colorStr <> '' then
    Self.PadColor := TAlphaColor(StrToUInt('$' + colorStr))
  else
    Self.PadColor := $FF00E060;

  // Parse terrain points
  if Value.TryGetValue(KEY_TERRAIN, terrainArr) then
  begin
    terrain := nil;
    terrain.AsJSON := terrainArr;
    Self.Terrain := terrain;
  end;

  // Parse pads
  if Value.TryGetValue(KEY_PADS, padsArr) then
  begin
    var pads: TPadArray;
    SetLength(pads, padsArr.Count);
    for i := 0 to padsArr.Count - 1 do
    begin
      padObj := padsArr.Items[i] as TJSONObject;
      pads[i].StartIndex := padObj.IntValue(KEY_START_INDEX);
      pads[i].EndIndex := padObj.IntValue(KEY_END_INDEX);
      pads[i].PointValue := padObj.IntValue(KEY_POINT_VALUE);
    end;
    Self.Pads := pads;
  end;
end;

{ Standalone world I/O }

procedure SaveWorldToJSON(aWorld: TWorldProfile; const aFilePath: string);
var
  json: TJSONObject;
  content: string;
begin
  json := aWorld.AsJSON;
  try
    content := json.Format(2);
    TFile.WriteAllText(aFilePath, content, TEncoding.UTF8);
  finally
    json.Free;
  end;
end;

function LoadWorldFromJSON(const aFilePath: string): TWorldProfile;
var
  content: string;
  json: TJSONObject;
begin
  Result := TWorldProfile.Create;
  content := TFile.ReadAllText(aFilePath, TEncoding.UTF8);
  json := TJSONObject.ParseJSONValue(content) as TJSONObject;
  try
    if json <> nil then
      Result.AsJSON := json;
  finally
    json.Free;
  end;
end;

{ TSimpleJSONReader }
function TSimpleJSONReader.IntValue(aKey: string): Integer;
begin
  Result := -1;
  var aValue: Integer;
  if Self.TryGetValue(aKey, aValue) then
    Result := aValue;
end;

function TSimpleJSONReader.FloatValue(aKey: string): Single;
var
  aValue: Double;
begin
  Result := 0;
  if Self.TryGetValue(aKey, aValue) then
    Result := Single(aValue);
end;

function TSimpleJSONReader.StrValue(aKey: string): string;
begin
  Result := '';
  var aValue: string;
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


end.
