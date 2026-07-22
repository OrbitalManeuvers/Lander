unit u_FontManager;

interface

uses System.Generics.Defaults,
  System.SysUtils, System.Classes, System.Generics.Collections,
  System.IOUtils, System.Skia;

type
  // Loads, registers, and caches custom typefaces from bundled .ttf files.
  // Provides ISkTypeface instances by family name with Consolas fallback.
  TFontManager = class
  private
    fTypefaces: TDictionary<string, ISkTypeface>;
    fFallback: ISkTypeface;
  public
    constructor Create;
    destructor Destroy; override;

    // Registers all .ttf files found in the given directory.
    // Skips any file that fails to load.
    procedure RegisterFonts(const aFontsDir: string);

    // Returns the cached typeface matching aFamily, or Consolas fallback
    // if the family is empty or not registered.
    function GetTypeface(const aFamily: string): ISkTypeface;
  end;

implementation

constructor TFontManager.Create;
begin
  inherited Create;
  fTypefaces := TDictionary<string, ISkTypeface>.Create(
    TIStringComparer.Ordinal);
  fFallback := TSkTypeface.MakeFromName('Consolas', TSkFontStyle.Normal);
end;

destructor TFontManager.Destroy;
begin
  fTypefaces.Free;
  inherited;
end;

procedure TFontManager.RegisterFonts(const aFontsDir: string);
var
  Files: TArray<string>;
  FilePath: string;
  Stream: TMemoryStream;
  Typeface: ISkTypeface;
  FamilyName: string;
begin
  if not TDirectory.Exists(aFontsDir) then
    Exit;

  Files := TDirectory.GetFiles(aFontsDir, '*.ttf');
  for FilePath in Files do
  begin
    Stream := TMemoryStream.Create;
    try
      try
        Stream.LoadFromFile(FilePath);
        Stream.Position := 0;
        Typeface := TSkTypeface.MakeFromStream(Stream);
        if Typeface <> nil then
        begin
          FamilyName := Typeface.FamilyName;
          if (FamilyName <> '') and not fTypefaces.ContainsKey(FamilyName) then
            fTypefaces.Add(FamilyName, Typeface);
        end;
      except
        // Skip failed .ttf files — continue registering remaining
      end;
    finally
      Stream.Free;
    end;
  end;
end;

function TFontManager.GetTypeface(const aFamily: string): ISkTypeface;
begin
  if (aFamily <> '') and fTypefaces.TryGetValue(aFamily, Result) then
    Exit;
  Result := fFallback;
end;

end.
