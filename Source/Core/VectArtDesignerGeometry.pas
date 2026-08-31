// 回転を持つ図形の四隅、外接範囲、座標変換を共通計算する。
// MIF互換の線端マーカー形状生成もこの座標計算へ集約する。
unit VectArtDesignerGeometry;

interface

uses
  System.Types;

type
  TVectArtQuad = array[0..3] of TPointF;

  TVectArtMarkerGeometry = record
    PrimaryPoints: TArray<TPointF>;   // 主形状を構成する点列。
    SecondaryPoints: TArray<TPointF>; // 星形などの補助形状を構成する点列。
    PrimaryClosed: Boolean;           // 主形状の終点を始点へ接続する指定。
    SecondaryClosed: Boolean;         // 補助形状の終点を始点へ接続する指定。
    Filled: Boolean;                  // 閉じた主形状を塗りつぶす指定。
  end;

function NormalizeAngleDegrees(Value: Single): Single;
function RotatePointAround(const Point, Center: TPointF;
  AngleDegrees: Single): TPointF;
function RectangleCorners(const Bounds: TRectF;
  RotationDegrees: Single): TVectArtQuad;
function QuadBounds(const Quad: TVectArtQuad): TRectF;
function PointsBounds(const Points: TArray<TPointF>): TRectF;
function PointInRotatedRectangle(const Point: TPointF; const Bounds: TRectF;
  RotationDegrees: Single): Boolean;
function PointInPolygon(const Point: TPointF;
  const Polygon: TArray<TPointF>): Boolean;
// MIFマーカー番号、線幅、倍率から描画用の点列と閉領域情報を生成する。
function BuildMifLineMarkerGeometry(MarkerKind: Integer; const Tip,
  InsidePoint: TPointF; StrokeWidth, MarkerSize: Single): TVectArtMarkerGeometry;

implementation

uses
  System.Math;

function NormalizeAngleDegrees(Value: Single): Single;
begin
  Result := Value - Floor((Value + 180.0) / 360.0) * 360.0;
  if Result >= 180.0 then
    Result := Result - 360.0;
end;

function RotatePointAround(const Point, Center: TPointF;
  AngleDegrees: Single): TPointF;
var
  Cosine: Extended;
  DX: Single;
  DY: Single;
  Radians: Extended;
  Sine: Extended;
begin
  Radians := DegToRad(AngleDegrees);
  SinCos(Radians, Sine, Cosine);
  DX := Point.X - Center.X;
  DY := Point.Y - Center.Y;
  Result.X := Center.X + DX * Cosine - DY * Sine;
  Result.Y := Center.Y + DX * Sine + DY * Cosine;
end;

function RectangleCorners(const Bounds: TRectF;
  RotationDegrees: Single): TVectArtQuad;
var
  Center: TPointF;
begin
  Center := TPointF.Create((Bounds.Left + Bounds.Right) * 0.5,
    (Bounds.Top + Bounds.Bottom) * 0.5);
  Result[0] := RotatePointAround(TPointF.Create(Bounds.Left, Bounds.Top),
    Center, RotationDegrees);
  Result[1] := RotatePointAround(TPointF.Create(Bounds.Right, Bounds.Top),
    Center, RotationDegrees);
  Result[2] := RotatePointAround(TPointF.Create(Bounds.Right, Bounds.Bottom),
    Center, RotationDegrees);
  Result[3] := RotatePointAround(TPointF.Create(Bounds.Left, Bounds.Bottom),
    Center, RotationDegrees);
end;

function QuadBounds(const Quad: TVectArtQuad): TRectF;
var
  I: Integer;
begin
  Result := TRectF.Create(Quad[0], Quad[0]);
  for I := 1 to High(Quad) do
  begin
    Result.Left := Min(Result.Left, Quad[I].X);
    Result.Top := Min(Result.Top, Quad[I].Y);
    Result.Right := Max(Result.Right, Quad[I].X);
    Result.Bottom := Max(Result.Bottom, Quad[I].Y);
  end;
end;

function PointsBounds(const Points: TArray<TPointF>): TRectF;
var
  I: Integer;
begin
  if Length(Points) = 0 then
    Exit(TRectF.Empty);
  Result := TRectF.Create(Points[0], Points[0]);
  for I := 1 to High(Points) do
  begin
    Result.Left := Min(Result.Left, Points[I].X);
    Result.Top := Min(Result.Top, Points[I].Y);
    Result.Right := Max(Result.Right, Points[I].X);
    Result.Bottom := Max(Result.Bottom, Points[I].Y);
  end;
end;

function PointInRotatedRectangle(const Point: TPointF; const Bounds: TRectF;
  RotationDegrees: Single): Boolean;
var
  Center: TPointF;
  LocalPoint: TPointF;
begin
  Center := TPointF.Create((Bounds.Left + Bounds.Right) * 0.5,
    (Bounds.Top + Bounds.Bottom) * 0.5);
  LocalPoint := RotatePointAround(Point, Center, -RotationDegrees);
  Result := (LocalPoint.X >= Bounds.Left) and
    (LocalPoint.X <= Bounds.Right) and (LocalPoint.Y >= Bounds.Top) and
    (LocalPoint.Y <= Bounds.Bottom);
end;

function PointInPolygon(const Point: TPointF;
  const Polygon: TArray<TPointF>): Boolean;
var
  I: Integer;
  J: Integer;
begin
  Result := False;
  if Length(Polygon) < 3 then
    Exit;
  J := High(Polygon);
  for I := 0 to High(Polygon) do
  begin
    if ((Polygon[I].Y > Point.Y) <> (Polygon[J].Y > Point.Y)) and
      (Point.X < (Polygon[J].X - Polygon[I].X) *
      (Point.Y - Polygon[I].Y) / (Polygon[J].Y - Polygon[I].Y) +
      Polygon[I].X) then
      Result := not Result;
    J := I;
  end;
end;

function BuildMifLineMarkerGeometry(MarkerKind: Integer; const Tip,
  InsidePoint: TPointF; StrokeWidth, MarkerSize: Single): TVectArtMarkerGeometry;
var
  Angle: Double;
  Center: TPointF;
  HalfWidth: Single;
  I: Integer;
  InnerRadius: Single;
  LengthValue: Single;
  Radius: Single;
  UnitX: Single;
  UnitY: Single;
  Distance: Single;

  function LocalPoint(Along, Across: Single): TPointF;
  begin
    Result := TPointF.Create(Tip.X + UnitX * Along - UnitY * Across,
      Tip.Y + UnitY * Along + UnitX * Across);
  end;

begin
  Result := Default(TVectArtMarkerGeometry);
  if MarkerKind = 0 then Exit;
  Distance := Hypot(InsidePoint.X - Tip.X, InsidePoint.Y - Tip.Y);
  if Distance <= 0 then Exit;
  UnitX := (InsidePoint.X - Tip.X) / Distance;
  UnitY := (InsidePoint.Y - Tip.Y) / Distance;
  MarkerSize := Max(MarkerSize, 1.0);
  LengthValue := Max(StrokeWidth * MarkerSize, MarkerSize * 2);
  HalfWidth := LengthValue * 0.45;
  case MarkerKind of
    2: // open arrow
      begin
        Result.PrimaryPoints := [LocalPoint(LengthValue, -HalfWidth), Tip,
          LocalPoint(LengthValue, HalfWidth)];
      end;
    1: // filled arrow, retained internal ordinal
      begin
        Result.PrimaryPoints := [Tip,
          LocalPoint(LengthValue, -HalfWidth),
          LocalPoint(LengthValue, HalfWidth)];
        Result.PrimaryClosed := True;
        Result.Filled := True;
      end;
    3: // wide arrow
      begin
        Result.PrimaryPoints := [Tip,
          LocalPoint(LengthValue * 0.72, -HalfWidth * 1.25),
          LocalPoint(LengthValue * 0.72, HalfWidth * 1.25)];
        Result.PrimaryClosed := True;
        Result.Filled := True;
      end;
    4: // circle
      begin
        Radius := HalfWidth;
        Center := LocalPoint(Radius, 0);
        SetLength(Result.PrimaryPoints, 20);
        for I := 0 to High(Result.PrimaryPoints) do
        begin
          Angle := I * 2 * Pi / Length(Result.PrimaryPoints);
          Result.PrimaryPoints[I] := TPointF.Create(
            Center.X + Cos(Angle) * Radius,
            Center.Y + Sin(Angle) * Radius);
        end;
        Result.PrimaryClosed := True;
        Result.Filled := True;
      end;
    5: // diamond
      begin
        Result.PrimaryPoints := [Tip,
          LocalPoint(LengthValue * 0.5, -HalfWidth),
          LocalPoint(LengthValue, 0),
          LocalPoint(LengthValue * 0.5, HalfWidth)];
        Result.PrimaryClosed := True;
        Result.Filled := True;
      end;
    6: // concave arrow
      begin
        Result.PrimaryPoints := [Tip,
          LocalPoint(LengthValue, -HalfWidth),
          LocalPoint(LengthValue * 0.68, 0),
          LocalPoint(LengthValue, HalfWidth)];
        Result.PrimaryClosed := True;
        Result.Filled := True;
      end;
    7: // compact arrow
      begin
        Result.PrimaryPoints := [Tip,
          LocalPoint(LengthValue * 0.62, -HalfWidth * 0.55),
          LocalPoint(LengthValue * 0.62, HalfWidth * 0.55)];
        Result.PrimaryClosed := True;
        Result.Filled := True;
      end;
    8: // slash
      begin
        Result.PrimaryPoints := [LocalPoint(LengthValue * 0.25, -HalfWidth),
          LocalPoint(LengthValue * 0.75, HalfWidth)];
      end;
    9: // star
      begin
        Radius := HalfWidth * 1.15;
        InnerRadius := Radius * 0.42;
        Center := LocalPoint(Radius, 0);
        SetLength(Result.PrimaryPoints, 10);
        for I := 0 to High(Result.PrimaryPoints) do
        begin
          Angle := Pi + I * Pi / 5;
          if Odd(I) then Distance := InnerRadius else Distance := Radius;
          Result.PrimaryPoints[I] := TPointF.Create(
            Center.X + Cos(Angle) * Distance,
            Center.Y + Sin(Angle) * Distance);
        end;
        Result.PrimaryClosed := True;
        Result.Filled := True;
      end;
  end;
end;

end.
