// 配置支援命令の数値・矩形・スナップショット内パスを厳密に検証する。
unit ScreenLayoutAutomationArguments;

interface

uses System.JSON, System.Types, ScreenLayoutDocument;

// 有限の範囲内数値を返す。省略時だけ既定値を使う。
function AutomationNumber(Root: TJSONObject; const Name: string;
  DefaultValue, Minimum, Maximum: Double): Double;
// 型が文字列であることを検証し、省略時は既定値を返す。
function AutomationString(Root: TJSONObject; const Name, DefaultValue: string): string;
// 四辺が有限で正の面積を持つ文書座標矩形を返す。
function AutomationRect(Value: TJSONValue): TRectF;
// 矩形をJSONへ変換する。所有権は呼出側。
function AutomationRectJson(const Bounds: TRectF): TJSONObject;
// 現在のJSON階層パスを解決する。親の非表示・ロックも返す。
function AutomationLayer(Document: TVectArtDocument; const Path: string;
  out Visible, Locked: Boolean): TVectArtLayer;

implementation

uses System.SysUtils, System.Math;

function AutomationNumber(Root: TJSONObject; const Name: string;
  DefaultValue, Minimum, Maximum: Double): Double;
var Value: TJSONValue;
begin
  Value := Root.GetValue(Name);
  if Value = nil then Exit(DefaultValue);
  if not (Value is TJSONNumber) then
    raise EArgumentException.Create(Name + ' must be a number.');
  Result := TJSONNumber(Value).AsDouble;
  if IsNan(Result) or IsInfinite(Result) or (Result < Minimum) or (Result > Maximum) then
    raise EArgumentException.Create(Name + ' is out of range.');
end;

function AutomationString(Root: TJSONObject; const Name, DefaultValue: string): string;
var Value: TJSONValue;
begin
  Value := Root.GetValue(Name);
  if Value = nil then Exit(DefaultValue);
  if not (Value is TJSONString) then
    raise EArgumentException.Create(Name + ' must be a string.');
  Result := Value.Value;
end;

function AutomationRect(Value: TJSONValue): TRectF;
var Root: TJSONObject;
begin
  if not (Value is TJSONObject) then
    raise EArgumentException.Create('A rectangle object is required.');
  Root := TJSONObject(Value);
  if (Root.GetValue('left') = nil) or (Root.GetValue('top') = nil) or
    (Root.GetValue('right') = nil) or (Root.GetValue('bottom') = nil) then
    raise EArgumentException.Create('Rectangle requires left, top, right, bottom.');
  Result := TRectF.Create(AutomationNumber(Root, 'left', 0, -100000, 100000),
    AutomationNumber(Root, 'top', 0, -100000, 100000),
    AutomationNumber(Root, 'right', 0, -100000, 100000),
    AutomationNumber(Root, 'bottom', 0, -100000, 100000));
  if (Result.Width <= 0) or (Result.Height <= 0) then
    raise EArgumentException.Create('Rectangle must have positive width and height.');
end;

function AutomationRectJson(const Bounds: TRectF): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('left', TJSONNumber.Create(Bounds.Left));
  Result.AddPair('top', TJSONNumber.Create(Bounds.Top));
  Result.AddPair('right', TJSONNumber.Create(Bounds.Right));
  Result.AddPair('bottom', TJSONNumber.Create(Bounds.Bottom));
end;

function AutomationLayer(Document: TVectArtDocument; const Path: string;
  out Visible, Locked: Boolean): TVectArtLayer;
var Parts: TArray<string>; I, Index: Integer; Group: TScreenLayoutGroupLayer;
begin
  Result := nil;
  Visible := True;
  Locked := False;
  Parts := Path.Split(['/']);
  if (Length(Parts) < 3) or (Parts[0] <> '') or not Odd(Length(Parts)) then
    raise EArgumentException.Create('Invalid layer_path.');
  I := 1;
  while I < Length(Parts) do
  begin
    if (Parts[I] <> 'layers') or not TryStrToInt(Parts[I + 1], Index) or
      (Index < 0) or (IntToStr(Index) <> Parts[I + 1]) then
      raise EArgumentException.Create('Invalid layer_path.');
    if Result = nil then
    begin
      if Index >= Document.LayerCount - 1 then
        raise EArgumentException.Create('layer_path is out of range.');
      Result := Document[Index + 1];
    end
    else
    begin
      if not (Result is TScreenLayoutGroupLayer) then
        raise EArgumentException.Create('layer_path parent is not a group.');
      Group := TScreenLayoutGroupLayer(Result);
      if Index >= Group.ChildCount then
        raise EArgumentException.Create('layer_path is out of range.');
      Result := Group[Index];
    end;
    Visible := Visible and Result.Visible;
    Locked := Locked or Result.Locked;
    Inc(I, 2);
  end;
end;

end.
