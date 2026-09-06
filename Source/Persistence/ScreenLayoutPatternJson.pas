// パターンIDと数値・色だけを保存し、文書変更前に必須項目と重複・範囲を検証する。
unit ScreenLayoutPatternJson;

interface

uses System.JSON, ScreenLayoutPatternStyle;

// 呼び出し側所有のJSONを生成する。展開画像は含めない。
function WriteScreenLayoutPattern(const Style: TScreenLayoutPatternStyle): TJSONObject;
// 不明ID、欠落、重複、型違い、範囲外をEConvertErrorで拒否する。
function ReadScreenLayoutPattern(Json: TJSONObject): TScreenLayoutPatternStyle;

implementation

uses System.SysUtils, System.Math, Vcl.Graphics;

function UniqueValue(Json: TJSONObject; const Name: string; ValueClass: TClass): TJSONValue;
var Pair: TJSONPair; Count: Integer;
begin
  Result := nil;
  Count := 0;
  for Pair in Json do if Pair.JsonString.Value = Name then
  begin
    Inc(Count);
    Result := Pair.JsonValue;
  end;
  if (Count <> 1) or (Result = nil) or not Result.InheritsFrom(ValueClass) then
    raise EConvertError.Create('Invalid or duplicate pattern field: ' + Name);
end;

function Number(Json: TJSONObject; const Name: string; Minimum, Maximum: Double): Double;
begin
  Result := TJSONNumber(UniqueValue(Json, Name, TJSONNumber)).AsDouble;
  if IsNan(Result) or IsInfinite(Result) or (Result < Minimum) or (Result > Maximum) then
    raise EConvertError.Create('Pattern field out of range: ' + Name);
end;

function OptionalBoolean(Json: TJSONObject; const Name: string): Boolean;
var
  Value: TJSONValue;
begin
  Value := Json.GetValue(Name);
  if Value = nil then
    Exit(False);
  if not (Value is TJSONBool) then
    raise EConvertError.Create('Invalid pattern field: ' + Name);
  Result := TJSONBool(Value).AsBoolean;
end;

function WriteScreenLayoutPattern(const Style: TScreenLayoutPatternStyle): TJSONObject;
var Params, Colors, Color: TJSONObject; V: TScreenLayoutPatternValue; C: TScreenLayoutPatternColor;
begin
  Result := TJSONObject.Create;
  try
    Result.AddPair('type', 'pattern');
    Result.AddPair('patternId', Style.Id);
    Result.AddPair('flipHorizontal', TJSONBool.Create(Style.FlipHorizontal));
    Result.AddPair('flipVertical', TJSONBool.Create(Style.FlipVertical));
    Params := TJSONObject.Create;
    Result.AddPair('parameters', Params);
    for V in Style.Values do Params.AddPair(V.Id, TJSONNumber.Create(V.Value));
    Colors := TJSONObject.Create;
    Result.AddPair('colors', Colors);
    for C in Style.Colors do
    begin
      Color := TJSONObject.Create;
      Colors.AddPair(C.Id, Color);
      Color.AddPair('color', TJSONNumber.Create(Integer(C.Color)));
      Color.AddPair('opacity', TJSONNumber.Create(C.Opacity));
    end;
  except
    Result.Free;
    raise;
  end;
end;

function ReadScreenLayoutPattern(Json: TJSONObject): TScreenLayoutPatternStyle;
var
  Params, Colors, Color: TJSONObject;
  P: TScreenLayoutPatternParameter;
  C, DefaultSlot: TScreenLayoutPatternColor;
  Kind: TScreenLayoutPatternKind;
  N: Double;
begin
  if UniqueValue(Json, 'type', TJSONString).Value <> 'pattern' then
    raise EConvertError.Create('Invalid pattern type');
  Kind := ScreenLayoutPatternKind(UniqueValue(Json, 'patternId', TJSONString).Value);
  Result := TScreenLayoutPatternStyle.Create(Kind, clBlack);
  Result.FlipHorizontal := OptionalBoolean(Json, 'flipHorizontal');
  Result.FlipVertical := OptionalBoolean(Json, 'flipVertical');
  Params := TJSONObject(UniqueValue(Json, 'parameters', TJSONObject));
  Colors := TJSONObject(UniqueValue(Json, 'colors', TJSONObject));
  if Params.Count <> Length(Result.Values) then raise EConvertError.Create('Invalid pattern parameter count');
  if Colors.Count <> Length(Result.Colors) then raise EConvertError.Create('Invalid pattern color count');
  for P in ScreenLayoutPatternParameters(Kind) do
    Result.SetNumber(P.Id, Number(Params, P.Id, P.Minimum, P.Maximum));
  for DefaultSlot in Result.Colors do
  begin
    C := DefaultSlot;
    Color := TJSONObject(UniqueValue(Colors, C.Id, TJSONObject));
    N := Number(Color, 'color', 0, $FFFFFF);
    if Frac(N) <> 0 then raise EConvertError.Create('Invalid pattern color');
    C.Color := TColor(Trunc(N));
    C.Opacity := Number(Color, 'opacity', 0, 1);
    Result.SetSlot(C);
  end;
end;

end.
