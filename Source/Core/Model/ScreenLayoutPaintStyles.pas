// 塗り、線、文字、フィルターで共有する描画スタイルの最小モデルを定義する。
// 各モードの値を同時保持し、切替後も以前の設定を復元できるようにする。
unit ScreenLayoutPaintStyles;

interface

uses
  System.Types, Vcl.Graphics;

type
  TScreenLayoutPaintKind = (slpkSolid, slpkGradient, slpkPattern,
    slpkTexture);
  TScreenLayoutGradientKind = (slgkLinear, slgkRadial, slgkRectangle);

  TScreenLayoutGradientStop = record
    Id: Integer;       // 選択とUndo後も同じ中間点を識別する正のID。
    Offset: Single;    // 始点を0、終点を1とする線上の比率。
    Color: TColor;     // この中間点で使用するVCL色。
    Opacity: Single;   // 将来の点別透明度に使う0..1の保持値。
  end;

const
  SCREEN_LAYOUT_GRADIENT_STOP_NONE = 0;
  SCREEN_LAYOUT_GRADIENT_START_STOP_ID = -1;
  SCREEN_LAYOUT_GRADIENT_END_STOP_ID = -2;

type

  TScreenLayoutPaintStyle = record
  private
    FKind: TScreenLayoutPaintKind;       // 現在採用している描画モード。
    FSolidColor: TColor;                 // 単色モードへ戻した場合に復元する色。
    FGradientKind: TScreenLayoutGradientKind; // 保持中のグラデーション種別。
    FGradientInitialized: Boolean;       // グラデーション値を初期化済みならTrue。
    FGradientStartColor: TColor;         // 始点の色。
    FGradientEndColor: TColor;           // 終点の色。
    FGradientStops: TArray<TScreenLayoutGradientStop>; // 比率順の中間点。
    FNextGradientStopId: Integer;        // 次に割り当てる中間点ID。
    FLinearStart: TPointF;               // ローカル範囲に対する始点の正規化座標。
    FLinearEnd: TPointF;                 // ローカル範囲に対する終点の正規化座標。
    procedure SetSolidColor(const Value: TColor);
    procedure SetGradientStartColor(const Value: TColor);
    procedure SetGradientEndColor(const Value: TColor);
    procedure SortGradientStops;
  public
    // 単色を初期値とし、将来切り替える各描画モードの保持領域も初期化する。
    class function Solid(const Color: TColor): TScreenLayoutPaintStyle;
      static;
    // 動的配列を含む全モードの保持値が等しい場合にTrueを返す。
    function SameAs(const Value: TScreenLayoutPaintStyle): Boolean;
    // 未初期化の場合だけ、BaseColorから既定の左から右への線形グラデーションを準備する。
    procedure PrepareLinearGradient(const BaseColor: TColor);
    // 現在の見た目を変えない補間色で中間点を追加し、安定した正のIDを返す。
    function AddGradientStop(Offset: Single): Integer;
    // 端点と中間点を補間し、指定比率で描画される色を返す。
    function GradientColorAt(Offset: Single): TColor;
    // 呼び出し側の変更が内部配列へ波及しない複製を返す。
    function GetGradientStops: TArray<TScreenLayoutGradientStop>;
    // 始点、終点、または安定IDで指定した中間点の色を返す。
    function GetGradientStopColor(Id: Integer; out Value: TColor): Boolean;
    // 中間点を端点の内側へ制限して移動し、IDは維持する。
    function MoveGradientStop(Id: Integer; Offset: Single): Boolean;
    // 中間点だけを削除する。始点と終点の予約IDには適用しない。
    function RemoveGradientStop(Id: Integer): Boolean;
    // 指定した端点または中間点だけの色を変更する。
    function SetGradientStopColor(Id: Integer; Value: TColor): Boolean;
    // JSON復元などで受け取った中間点を複製し、比率順と次回IDを正規化する。
    procedure SetGradientStops(const Value: TArray<TScreenLayoutGradientStop>);
    property Kind: TScreenLayoutPaintKind read FKind write FKind;
    property SolidColor: TColor read FSolidColor write SetSolidColor;
    property GradientKind: TScreenLayoutGradientKind read FGradientKind
      write FGradientKind;
    property GradientStartColor: TColor read FGradientStartColor
      write SetGradientStartColor;
    property GradientEndColor: TColor read FGradientEndColor
      write SetGradientEndColor;
    property LinearStart: TPointF read FLinearStart write FLinearStart;
    property LinearEnd: TPointF read FLinearEnd write FLinearEnd;
  end;

implementation

uses
  System.Math, Winapi.Windows;

function InterpolateColor(Color1, Color2: TColor; Ratio: Single): TColor;
var
  RGB1: TColor;
  RGB2: TColor;
begin
  Ratio := EnsureRange(Ratio, 0.0, 1.0);
  RGB1 := ColorToRGB(Color1);
  RGB2 := ColorToRGB(Color2);
  Result := RGB(
    Round(GetRValue(RGB1) + (GetRValue(RGB2) - GetRValue(RGB1)) * Ratio),
    Round(GetGValue(RGB1) + (GetGValue(RGB2) - GetGValue(RGB1)) * Ratio),
    Round(GetBValue(RGB1) + (GetBValue(RGB2) - GetBValue(RGB1)) * Ratio));
end;

function TScreenLayoutPaintStyle.AddGradientStop(Offset: Single): Integer;
var
  Stop: TScreenLayoutGradientStop;
begin
  Offset := EnsureRange(Offset, 0.0001, 0.9999);
  if FNextGradientStopId <= 0 then
    FNextGradientStopId := 1;
  Stop.Id := FNextGradientStopId;
  Inc(FNextGradientStopId);
  Stop.Offset := Offset;
  Stop.Color := GradientColorAt(Offset);
  Stop.Opacity := 1.0;
  FGradientStops := Copy(FGradientStops);
  SetLength(FGradientStops, Length(FGradientStops) + 1);
  FGradientStops[High(FGradientStops)] := Stop;
  SortGradientStops;
  Result := Stop.Id;
end;

function TScreenLayoutPaintStyle.GetGradientStops:
  TArray<TScreenLayoutGradientStop>;
begin
  Result := Copy(FGradientStops);
end;

function TScreenLayoutPaintStyle.GetGradientStopColor(Id: Integer;
  out Value: TColor): Boolean;
var
  Stop: TScreenLayoutGradientStop;
begin
  if Id = SCREEN_LAYOUT_GRADIENT_START_STOP_ID then
  begin
    Value := FGradientStartColor;
    Exit(True);
  end;
  if Id = SCREEN_LAYOUT_GRADIENT_END_STOP_ID then
  begin
    Value := FGradientEndColor;
    Exit(True);
  end;
  for Stop in FGradientStops do
    if Stop.Id = Id then
    begin
      Value := Stop.Color;
      Exit(True);
    end;
  Value := clNone;
  Result := False;
end;

function TScreenLayoutPaintStyle.GradientColorAt(Offset: Single): TColor;
var
  I: Integer;
  LeftColor: TColor;
  LeftOffset: Single;
  RightColor: TColor;
  RightOffset: Single;
begin
  Offset := EnsureRange(Offset, 0.0, 1.0);
  LeftColor := FGradientStartColor;
  LeftOffset := 0.0;
  RightColor := FGradientEndColor;
  RightOffset := 1.0;
  for I := 0 to High(FGradientStops) do
    if FGradientStops[I].Offset <= Offset then
    begin
      LeftColor := FGradientStops[I].Color;
      LeftOffset := FGradientStops[I].Offset;
    end
    else
    begin
      RightColor := FGradientStops[I].Color;
      RightOffset := FGradientStops[I].Offset;
      Break;
    end;
  if SameValue(LeftOffset, RightOffset) then
    Exit(LeftColor);
  Result := InterpolateColor(LeftColor, RightColor,
    (Offset - LeftOffset) / (RightOffset - LeftOffset));
end;

function TScreenLayoutPaintStyle.MoveGradientStop(Id: Integer;
  Offset: Single): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to High(FGradientStops) do
    if FGradientStops[I].Id = Id then
    begin
      Offset := EnsureRange(Offset, 0.0001, 0.9999);
      if SameValue(FGradientStops[I].Offset, Offset) then
        Exit;
      FGradientStops := Copy(FGradientStops);
      FGradientStops[I].Offset := Offset;
      SortGradientStops;
      Exit(True);
    end;
end;

function TScreenLayoutPaintStyle.RemoveGradientStop(Id: Integer): Boolean;
var
  I: Integer;
  J: Integer;
begin
  Result := False;
  for I := 0 to High(FGradientStops) do
    if FGradientStops[I].Id = Id then
    begin
      FGradientStops := Copy(FGradientStops);
      for J := I to High(FGradientStops) - 1 do
        FGradientStops[J] := FGradientStops[J + 1];
      SetLength(FGradientStops, Length(FGradientStops) - 1);
      Exit(True);
    end;
end;

function TScreenLayoutPaintStyle.SetGradientStopColor(Id: Integer;
  Value: TColor): Boolean;
var
  I: Integer;
begin
  Value := ColorToRGB(Value);
  if Id = SCREEN_LAYOUT_GRADIENT_START_STOP_ID then
  begin
    Result := ColorToRGB(FGradientStartColor) <> Value;
    if Result then
      FGradientStartColor := Value;
    Exit;
  end;
  if Id = SCREEN_LAYOUT_GRADIENT_END_STOP_ID then
  begin
    Result := ColorToRGB(FGradientEndColor) <> Value;
    if Result then
      FGradientEndColor := Value;
    Exit;
  end;
  for I := 0 to High(FGradientStops) do
    if FGradientStops[I].Id = Id then
    begin
      Result := ColorToRGB(FGradientStops[I].Color) <> Value;
      if Result then
      begin
        FGradientStops := Copy(FGradientStops);
        FGradientStops[I].Color := Value;
      end;
      Exit;
    end;
  Result := False;
end;

procedure TScreenLayoutPaintStyle.SortGradientStops;
var
  I: Integer;
  J: Integer;
  Stop: TScreenLayoutGradientStop;
begin
  for I := 1 to High(FGradientStops) do
  begin
    Stop := FGradientStops[I];
    J := I - 1;
    while (J >= 0) and (FGradientStops[J].Offset > Stop.Offset) do
    begin
      FGradientStops[J + 1] := FGradientStops[J];
      Dec(J);
    end;
    FGradientStops[J + 1] := Stop;
  end;
end;

function TScreenLayoutPaintStyle.SameAs(
  const Value: TScreenLayoutPaintStyle): Boolean;
var
  I: Integer;
begin
  Result := (FKind = Value.FKind) and
    (ColorToRGB(FSolidColor) = ColorToRGB(Value.FSolidColor)) and
    (FGradientKind = Value.FGradientKind) and
    (FGradientInitialized = Value.FGradientInitialized) and
    (ColorToRGB(FGradientStartColor) =
      ColorToRGB(Value.FGradientStartColor)) and
    (ColorToRGB(FGradientEndColor) = ColorToRGB(Value.FGradientEndColor)) and
    SameValue(FLinearStart.X, Value.FLinearStart.X) and
    SameValue(FLinearStart.Y, Value.FLinearStart.Y) and
    SameValue(FLinearEnd.X, Value.FLinearEnd.X) and
    SameValue(FLinearEnd.Y, Value.FLinearEnd.Y) and
    (FNextGradientStopId = Value.FNextGradientStopId) and
    (Length(FGradientStops) = Length(Value.FGradientStops));
  if not Result then
    Exit;
  for I := 0 to High(FGradientStops) do
    if (FGradientStops[I].Id <> Value.FGradientStops[I].Id) or
      not SameValue(FGradientStops[I].Offset,
        Value.FGradientStops[I].Offset) or
      (ColorToRGB(FGradientStops[I].Color) <>
        ColorToRGB(Value.FGradientStops[I].Color)) or
      not SameValue(FGradientStops[I].Opacity,
        Value.FGradientStops[I].Opacity) then
      Exit(False);
end;

procedure TScreenLayoutPaintStyle.PrepareLinearGradient(
  const BaseColor: TColor);
begin
  if not FGradientInitialized then
  begin
    FLinearStart := TPointF.Create(0, 0.5);
    FLinearEnd := TPointF.Create(1, 0.5);
    FGradientStartColor := ColorToRGB(BaseColor);
    FGradientEndColor := clWhite;
    FGradientInitialized := True;
    FNextGradientStopId := 1;
  end;
  FGradientKind := slgkLinear;
end;

procedure TScreenLayoutPaintStyle.SetGradientEndColor(const Value: TColor);
begin
  FGradientEndColor := ColorToRGB(Value);
end;

procedure TScreenLayoutPaintStyle.SetGradientStartColor(const Value: TColor);
begin
  FGradientStartColor := ColorToRGB(Value);
end;

procedure TScreenLayoutPaintStyle.SetGradientStops(
  const Value: TArray<TScreenLayoutGradientStop>);
var
  I: Integer;
begin
  FGradientStops := Copy(Value);
  FNextGradientStopId := 1;
  for I := 0 to High(FGradientStops) do
  begin
    FGradientStops[I].Offset := EnsureRange(FGradientStops[I].Offset,
      0.0001, 0.9999);
    FGradientStops[I].Color := ColorToRGB(FGradientStops[I].Color);
    FGradientStops[I].Opacity := EnsureRange(FGradientStops[I].Opacity,
      0.0, 1.0);
    if FGradientStops[I].Id <= 0 then
      FGradientStops[I].Id := FNextGradientStopId;
    FNextGradientStopId := Max(FNextGradientStopId,
      FGradientStops[I].Id + 1);
  end;
  SortGradientStops;
end;

procedure TScreenLayoutPaintStyle.SetSolidColor(const Value: TColor);
begin
  FSolidColor := ColorToRGB(Value);
end;

class function TScreenLayoutPaintStyle.Solid(
  const Color: TColor): TScreenLayoutPaintStyle;
begin
  Result := Default(TScreenLayoutPaintStyle);
  Result.FKind := slpkSolid;
  Result.FSolidColor := ColorToRGB(Color);
  Result.FGradientKind := slgkLinear;
  Result.FGradientInitialized := False;
  Result.FNextGradientStopId := 1;
  Result.FGradientStartColor := ColorToRGB(Color);
  Result.FGradientEndColor := clWhite;
  Result.FLinearStart := TPointF.Create(0, 0.5);
  Result.FLinearEnd := TPointF.Create(1, 0.5);
end;

end.
