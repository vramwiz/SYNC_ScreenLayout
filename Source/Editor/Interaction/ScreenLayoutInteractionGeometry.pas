// キャンバス操作で使う、UI状態を持たない距離・外接範囲計算を提供する。
unit ScreenLayoutInteractionGeometry;

interface

uses
  System.Types, ScreenLayoutDocument;

// 画像の4隅を包含する論理座標の外接矩形を返す。
function ImagePointsBounds(const Points: TVectArtImagePoints): TRectF;
// 符号を維持しながら画像の辺長を操作可能な最小値へ制限する。
function ClampImageDimension(Value, OriginalValue: Single): Single;
// 点から線分までの距離と、線分上の最近点を表す0～1の比率を返す。
function DistanceToSegmentParameter(const PointValue, StartPoint,
  EndPoint: TPointF; out Parameter: Single): Single;
// 点から線分までの最短距離を返す。
function DistanceToSegment(const PointValue, StartPoint,
  EndPoint: TPointF): Single;
// 点から楕円弧の輪郭までの近似距離を返す。
function ArcDistanceToPoint(ArcLayer: TScreenLayoutArcLayer;
  const PointValue: TPointF): Single;
// 点から閉じた楕円線の輪郭までの近似距離を返す。
function EllipseLineDistanceToPoint(LineLayer: TScreenLayoutEllipseLineLayer;
  const PointValue: TPointF): Single;
// 点から角丸四角形線の輪郭までの近似距離を返す。
function RoundedRectangleLineDistanceToPoint(
  LineLayer: TScreenLayoutRoundedRectangleLineLayer;
  const PointValue: TPointF): Single;
// 図形または線の角丸四角形から、変形に必要な共通値を取得する。
function RoundedRectangleValues(Layer: TVectArtLayer; out Bounds: TRectF;
  out Radii: TScreenLayoutCornerRadii; out RotationDegrees: Single): Boolean;
// 開始角から終了角までの時計回り角度を0～360度で返す。
function ClockwiseAngleDelta(StartAngle, EndAngle: Single): Single;

implementation

uses
  System.Math, ScreenLayoutEllipseGeometry, ScreenLayoutGeometry;

const
  MIN_IMAGE_DIMENSION = 16.0;
  ARC_HIT_TEST_SEGMENTS = 64;

function ImagePointsBounds(const Points: TVectArtImagePoints): TRectF;
var
  I: Integer;
begin
  Result := TRectF.Create(Points[0], Points[0]);
  for I := 1 to High(Points) do
  begin
    Result.Left := Min(Result.Left, Points[I].X);
    Result.Top := Min(Result.Top, Points[I].Y);
    Result.Right := Max(Result.Right, Points[I].X);
    Result.Bottom := Max(Result.Bottom, Points[I].Y);
  end;
end;

function ClampImageDimension(Value, OriginalValue: Single): Single;
begin
  if Abs(Value) >= MIN_IMAGE_DIMENSION then
    Exit(Value);
  if not SameValue(Value, 0.0) then
    Result := Sign(Value) * MIN_IMAGE_DIMENSION
  else if OriginalValue < 0 then
    Result := -MIN_IMAGE_DIMENSION
  else
    Result := MIN_IMAGE_DIMENSION;
end;

function DistanceToSegmentParameter(const PointValue, StartPoint,
  EndPoint: TPointF; out Parameter: Single): Single;
var
  DX: Single;
  DY: Single;
  Projection: Single;
  SegmentLengthSquared: Single;
begin
  DX := EndPoint.X - StartPoint.X;
  DY := EndPoint.Y - StartPoint.Y;
  SegmentLengthSquared := DX * DX + DY * DY;
  if SegmentLengthSquared > 0 then
    Projection := EnsureRange(((PointValue.X - StartPoint.X) * DX +
      (PointValue.Y - StartPoint.Y) * DY) / SegmentLengthSquared, 0.0, 1.0)
  else
    Projection := 0;
  Result := Hypot(PointValue.X - (StartPoint.X + Projection * DX),
    PointValue.Y - (StartPoint.Y + Projection * DY));
  Parameter := Projection;
end;

function DistanceToSegment(const PointValue, StartPoint,
  EndPoint: TPointF): Single;
var
  Parameter: Single;
begin
  Result := DistanceToSegmentParameter(PointValue, StartPoint, EndPoint,
    Parameter);
end;

function ArcDistanceToPoint(ArcLayer: TScreenLayoutArcLayer;
  const PointValue: TPointF): Single;
var
  CurrentPoint: TPointF;
  I: Integer;
  PreviousPoint: TPointF;
begin
  Result := MaxSingle;
  PreviousPoint := ScreenLayoutEllipsePoint(ArcLayer.Bounds,
    ArcLayer.RotationDegrees, ArcLayer.StartAngleDegrees);
  for I := 1 to ARC_HIT_TEST_SEGMENTS do
  begin
    CurrentPoint := ScreenLayoutEllipsePoint(ArcLayer.Bounds,
      ArcLayer.RotationDegrees, ArcLayer.StartAngleDegrees +
      ArcLayer.SweepAngleDegrees * I / ARC_HIT_TEST_SEGMENTS);
    Result := Min(Result, DistanceToSegment(PointValue, PreviousPoint,
      CurrentPoint));
    PreviousPoint := CurrentPoint;
  end;
end;

function EllipseLineDistanceToPoint(LineLayer: TScreenLayoutEllipseLineLayer;
  const PointValue: TPointF): Single;
var
  CurrentPoint: TPointF;
  I: Integer;
  PreviousPoint: TPointF;
begin
  Result := MaxSingle;
  PreviousPoint := ScreenLayoutEllipsePoint(LineLayer.Bounds,
    LineLayer.RotationDegrees, 0);
  for I := 1 to ARC_HIT_TEST_SEGMENTS * 2 do
  begin
    CurrentPoint := ScreenLayoutEllipsePoint(LineLayer.Bounds,
      LineLayer.RotationDegrees, 360 * I / (ARC_HIT_TEST_SEGMENTS * 2));
    Result := Min(Result, DistanceToSegment(PointValue, PreviousPoint,
      CurrentPoint));
    PreviousPoint := CurrentPoint;
  end;
end;

function RoundedRectangleLineDistanceToPoint(
  LineLayer: TScreenLayoutRoundedRectangleLineLayer;
  const PointValue: TPointF): Single;
const
  ARC_SEGMENTS = 8;
var
  Angle: Single;
  Center: TPointF;
  Corner: Integer;
  CurrentPoint: TPointF;
  I: Integer;
  LocalPoint: TPointF;
  PreviousPoint: TPointF;
  Radii: TScreenLayoutCornerRadii;
  Radius: Single;
  StartAngle: Single;
begin
  Center := TPointF.Create((LineLayer.Bounds.Left + LineLayer.Bounds.Right) *
    0.5, (LineLayer.Bounds.Top + LineLayer.Bounds.Bottom) * 0.5);
  LocalPoint := RotatePointAround(PointValue, Center,
    -LineLayer.RotationDegrees);
  Radii := ClampScreenLayoutCornerRadii(LineLayer.Bounds,
    LineLayer.CornerRadii);
  Result := Min(
    DistanceToSegment(LocalPoint,
      TPointF.Create(LineLayer.Bounds.Left + Radii.TopLeft,
        LineLayer.Bounds.Top),
      TPointF.Create(LineLayer.Bounds.Right - Radii.TopRight,
        LineLayer.Bounds.Top)),
    DistanceToSegment(LocalPoint,
      TPointF.Create(LineLayer.Bounds.Right,
        LineLayer.Bounds.Top + Radii.TopRight),
      TPointF.Create(LineLayer.Bounds.Right,
        LineLayer.Bounds.Bottom - Radii.BottomRight)));
  Result := Min(Result, DistanceToSegment(LocalPoint,
    TPointF.Create(LineLayer.Bounds.Right - Radii.BottomRight,
      LineLayer.Bounds.Bottom),
    TPointF.Create(LineLayer.Bounds.Left + Radii.BottomLeft,
      LineLayer.Bounds.Bottom)));
  Result := Min(Result, DistanceToSegment(LocalPoint,
    TPointF.Create(LineLayer.Bounds.Left,
      LineLayer.Bounds.Bottom - Radii.BottomLeft),
    TPointF.Create(LineLayer.Bounds.Left,
      LineLayer.Bounds.Top + Radii.TopLeft)));
  for Corner := 0 to 3 do
  begin
    case Corner of
      0:
        begin
          Radius := Radii.TopRight;
          Center := TPointF.Create(LineLayer.Bounds.Right - Radius,
            LineLayer.Bounds.Top + Radius);
          StartAngle := -90;
        end;
      1:
        begin
          Radius := Radii.BottomRight;
          Center := TPointF.Create(LineLayer.Bounds.Right - Radius,
            LineLayer.Bounds.Bottom - Radius);
          StartAngle := 0;
        end;
      2:
        begin
          Radius := Radii.BottomLeft;
          Center := TPointF.Create(LineLayer.Bounds.Left + Radius,
            LineLayer.Bounds.Bottom - Radius);
          StartAngle := 90;
        end;
    else
      Radius := Radii.TopLeft;
      Center := TPointF.Create(LineLayer.Bounds.Left + Radius,
        LineLayer.Bounds.Top + Radius);
      StartAngle := 180;
    end;
    PreviousPoint := TPointF.Create(Center.X + Radius *
      Cos(DegToRad(StartAngle)), Center.Y + Radius * Sin(DegToRad(StartAngle)));
    for I := 1 to ARC_SEGMENTS do
    begin
      Angle := StartAngle + 90 * I / ARC_SEGMENTS;
      CurrentPoint := TPointF.Create(Center.X + Radius * Cos(DegToRad(Angle)),
        Center.Y + Radius * Sin(DegToRad(Angle)));
      Result := Min(Result, DistanceToSegment(LocalPoint, PreviousPoint,
        CurrentPoint));
      PreviousPoint := CurrentPoint;
    end;
  end;
end;

function RoundedRectangleValues(Layer: TVectArtLayer; out Bounds: TRectF;
  out Radii: TScreenLayoutCornerRadii; out RotationDegrees: Single): Boolean;
begin
  Result := Layer is TScreenLayoutRoundedRectangleLayer;
  if Result then
  begin
    Bounds := TScreenLayoutRoundedRectangleLayer(Layer).Bounds;
    Radii := TScreenLayoutRoundedRectangleLayer(Layer).CornerRadii;
    RotationDegrees :=
      TScreenLayoutRoundedRectangleLayer(Layer).RotationDegrees;
    Exit;
  end;
  Result := Layer is TScreenLayoutRoundedRectangleLineLayer;
  if Result then
  begin
    Bounds := TScreenLayoutRoundedRectangleLineLayer(Layer).Bounds;
    Radii := TScreenLayoutRoundedRectangleLineLayer(Layer).CornerRadii;
    RotationDegrees :=
      TScreenLayoutRoundedRectangleLineLayer(Layer).RotationDegrees;
  end;
end;

function ClockwiseAngleDelta(StartAngle, EndAngle: Single): Single;
begin
  Result := NormalizeScreenLayoutEllipseAngleDegrees(EndAngle - StartAngle);
end;

end.
