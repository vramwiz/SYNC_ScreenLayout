// レイヤー共通の描画スタイルから、Skia用の単色またはグラデーションシェーダーを構築する。
unit ScreenLayoutPaintRenderer;

interface

uses
  System.Skia, System.Types, System.UITypes, Vcl.Graphics,
  ScreenLayoutDocument;

// VCL色と0..1の不透明度をSkiaのアルファ色へ変換する。
function VclColorToAlphaColor(Color: TColor; Opacity: Single): TAlphaColor;
// レイヤー回転を含むDocument座標で描画スタイルをPaintへ設定する。
procedure ApplyScreenLayoutPaintStyle(const Paint: ISkPaint;
  Layer: TVectArtLayer; FallbackColor: TColor; Opacity: Single);
// 呼び出し側のCanvas変換前座標で、指定範囲へ描画スタイルを設定する。
procedure ApplyScreenLayoutPaintStyleLocal(const Paint: ISkPaint;
  Layer: TVectArtLayer; FallbackColor: TColor; Opacity: Single;
  const Bounds: TRectF);

implementation

uses
  System.Math, Winapi.Windows, ScreenLayoutLayerGeometry,
  ScreenLayoutPaintStyles;

procedure ApplyScreenLayoutPaintStyleBetween(const Paint: ISkPaint;
  Layer: TVectArtLayer; FallbackColor: TColor; Opacity: Single;
  const StartPoint, EndPoint: TPointF);
var
  Colors: TArray<TAlphaColor>;
  I: Integer;
  Positions: TArray<Single>;
  Stops: TArray<TScreenLayoutGradientStop>;
  Style: TScreenLayoutPaintStyle;
begin
  Paint.Shader := nil;
  if Layer = nil then
    Exit;
  Style := Layer.PaintStyle;
  if (Style.Kind = slpkGradient) and
    (Style.GradientKind = slgkLinear) and
    (Hypot(EndPoint.X - StartPoint.X,
      EndPoint.Y - StartPoint.Y) > 0.0001) then
  begin
    Stops := Style.GetGradientStops;
    SetLength(Colors, Length(Stops) + 2);
    SetLength(Positions, Length(Colors));
    Colors[0] := VclColorToAlphaColor(Style.GradientStartColor, Opacity);
    Positions[0] := 0.0;
    for I := 0 to High(Stops) do
    begin
      Colors[I + 1] := VclColorToAlphaColor(Stops[I].Color,
        Opacity * Stops[I].Opacity);
      Positions[I + 1] := Stops[I].Offset;
    end;
    Colors[High(Colors)] := VclColorToAlphaColor(
      Style.GradientEndColor, Opacity);
    Positions[High(Positions)] := 1.0;
    Paint.Shader := TSkShader.MakeGradientLinear(StartPoint, EndPoint,
      Colors, Positions);
    Paint.Color := TAlphaColorRec.White;
    Exit;
  end;
  Paint.Color := VclColorToAlphaColor(FallbackColor, Opacity);
end;

procedure ApplyScreenLayoutPaintStyle(const Paint: ISkPaint;
  Layer: TVectArtLayer; FallbackColor: TColor; Opacity: Single);
var
  Bounds: TRectF;
  EndPoint: TPointF;
  RotationDegrees: Single;
  StartPoint: TPointF;
begin
  if (Layer <> nil) and
    TryGetScreenLayoutLayerPaintGeometry(Layer, Bounds,
      RotationDegrees) then
  begin
    StartPoint := ScreenLayoutLayerPaintPoint(Bounds, RotationDegrees,
      Layer.PaintStyle.LinearStart);
    EndPoint := ScreenLayoutLayerPaintPoint(Bounds, RotationDegrees,
      Layer.PaintStyle.LinearEnd);
    ApplyScreenLayoutPaintStyleBetween(Paint, Layer, FallbackColor,
      Opacity, StartPoint, EndPoint);
  end
  else
  begin
    Paint.Shader := nil;
    Paint.Color := VclColorToAlphaColor(FallbackColor, Opacity);
  end;
end;

procedure ApplyScreenLayoutPaintStyleLocal(const Paint: ISkPaint;
  Layer: TVectArtLayer; FallbackColor: TColor; Opacity: Single;
  const Bounds: TRectF);
var
  EndPoint: TPointF;
  StartPoint: TPointF;
begin
  StartPoint := ScreenLayoutLayerPaintPoint(Bounds, 0.0,
    Layer.PaintStyle.LinearStart);
  EndPoint := ScreenLayoutLayerPaintPoint(Bounds, 0.0,
    Layer.PaintStyle.LinearEnd);
  ApplyScreenLayoutPaintStyleBetween(Paint, Layer, FallbackColor,
    Opacity, StartPoint, EndPoint);
end;

function VclColorToAlphaColor(Color: TColor; Opacity: Single): TAlphaColor;
var
  RGBColor: TColor;
begin
  RGBColor := ColorToRGB(Color);
  Result := TAlphaColor(
    (Cardinal(EnsureRange(Round(Opacity * 255), 0, 255)) shl 24) or
    (Cardinal(GetRValue(RGBColor)) shl 16) or
    (Cardinal(GetGValue(RGBColor)) shl 8) or
    Cardinal(GetBValue(RGBColor)));
end;

end.
