// Shapeと基本図形をSkia Pathへ変換し、描画、ヒット判定、論理演算で共有する。
unit ScreenLayoutShapePath;

interface

uses
  System.Skia, ScreenLayoutDocument;

// Shapeの塗り規則、直線、3次ベジェ、閉輪郭を反映したPathを返す。
function BuildScreenLayoutShapePath(
  ShapeLayer: TScreenLayoutShapeLayer): ISkPath;
// 回転と縦横半径を反映した閉じた楕円Pathを返す。
function BuildScreenLayoutEllipsePath(
  EllipseLayer: TScreenLayoutEllipseLayer): ISkPath;
function BuildScreenLayoutEllipseLinePath(
  EllipseLine: TScreenLayoutEllipseLineLayer): ISkPath;
// 開始角と時計回り掃引角を反映した開いた楕円弧Pathを返す。
function BuildScreenLayoutArcPath(ArcLayer: TScreenLayoutArcLayer): ISkPath;
function BuildScreenLayoutEllipseArcShapePath(
  ShapeLayer: TScreenLayoutEllipseArcShapeLayer): ISkPath;
// Shape、Rectangle、角丸Rectangle、楕円、楕円弧図形を塗り領域の論理演算Pathへ変換する。
function BuildScreenLayoutBooleanPath(Layer: TVectArtLayer): ISkPath;

implementation

uses
  System.Math, System.Types, ScreenLayoutEllipseGeometry,
  ScreenLayoutGeometry;

function RectanglePathPoint(RectangleLayer: TVectArtRectangleLayer;
  const PointValue: TPointF): TPointF;
var
  Center: TPointF;
begin
  Center := TPointF.Create((RectangleLayer.Bounds.Left +
    RectangleLayer.Bounds.Right) * 0.5, (RectangleLayer.Bounds.Top +
    RectangleLayer.Bounds.Bottom) * 0.5);
  Result := RotatePointAround(PointValue, Center,
    RectangleLayer.RotationDegrees);
end;

function EllipsePathPoint(EllipseLayer: TScreenLayoutEllipseLayer;
  OffsetX, OffsetY: Single): TPointF;
var
  Center: TPointF;
begin
  Center := TPointF.Create((EllipseLayer.Bounds.Left +
    EllipseLayer.Bounds.Right) * 0.5, (EllipseLayer.Bounds.Top +
    EllipseLayer.Bounds.Bottom) * 0.5);
  Result := RotatePointAround(TPointF.Create(Center.X + OffsetX,
    Center.Y + OffsetY), Center, EllipseLayer.RotationDegrees);
end;

function BuildScreenLayoutRectanglePath(
  RectangleLayer: TVectArtRectangleLayer): ISkPath;
var
  Builder: ISkPathBuilder;
  Corners: TVectArtQuad;
begin
  Corners := RectangleCorners(RectangleLayer.Bounds,
    RectangleLayer.RotationDegrees);
  Builder := TSkPathBuilder.Create;
  Builder.MoveTo(Corners[0]);
  Builder.LineTo(Corners[1]);
  Builder.LineTo(Corners[2]);
  Builder.LineTo(Corners[3]);
  Builder.Close;
  Result := Builder.Detach;
end;

function BuildScreenLayoutRoundedRectanglePath(
  Layer: TScreenLayoutRoundedRectangleLayer): ISkPath;
const
  KAPPA = 0.5522847498;
var
  Bounds: TRectF;
  Builder: ISkPathBuilder;
  Radii: TScreenLayoutCornerRadii;
begin
  Bounds := Layer.Bounds;
  Radii := ClampScreenLayoutCornerRadii(Bounds, Layer.CornerRadii);
  Builder := TSkPathBuilder.Create;
  Builder.MoveTo(RectanglePathPoint(Layer,
    TPointF.Create(Bounds.Left + Radii.TopLeft, Bounds.Top)));
  Builder.LineTo(RectanglePathPoint(Layer,
    TPointF.Create(Bounds.Right - Radii.TopRight, Bounds.Top)));
  if Radii.TopRight > 0 then
    Builder.CubicTo(RectanglePathPoint(Layer,
      TPointF.Create(Bounds.Right - Radii.TopRight * (1 - KAPPA),
        Bounds.Top)), RectanglePathPoint(Layer,
      TPointF.Create(Bounds.Right,
        Bounds.Top + Radii.TopRight * (1 - KAPPA))),
      RectanglePathPoint(Layer, TPointF.Create(Bounds.Right,
        Bounds.Top + Radii.TopRight)));
  Builder.LineTo(RectanglePathPoint(Layer, TPointF.Create(Bounds.Right,
    Bounds.Bottom - Radii.BottomRight)));
  if Radii.BottomRight > 0 then
    Builder.CubicTo(RectanglePathPoint(Layer,
      TPointF.Create(Bounds.Right,
        Bounds.Bottom - Radii.BottomRight * (1 - KAPPA))),
      RectanglePathPoint(Layer,
      TPointF.Create(Bounds.Right - Radii.BottomRight * (1 - KAPPA),
        Bounds.Bottom)), RectanglePathPoint(Layer,
      TPointF.Create(Bounds.Right - Radii.BottomRight, Bounds.Bottom)));
  Builder.LineTo(RectanglePathPoint(Layer,
    TPointF.Create(Bounds.Left + Radii.BottomLeft, Bounds.Bottom)));
  if Radii.BottomLeft > 0 then
    Builder.CubicTo(RectanglePathPoint(Layer,
      TPointF.Create(Bounds.Left + Radii.BottomLeft * (1 - KAPPA),
        Bounds.Bottom)), RectanglePathPoint(Layer,
      TPointF.Create(Bounds.Left,
        Bounds.Bottom - Radii.BottomLeft * (1 - KAPPA))),
      RectanglePathPoint(Layer, TPointF.Create(Bounds.Left,
        Bounds.Bottom - Radii.BottomLeft)));
  Builder.LineTo(RectanglePathPoint(Layer, TPointF.Create(Bounds.Left,
    Bounds.Top + Radii.TopLeft)));
  if Radii.TopLeft > 0 then
    Builder.CubicTo(RectanglePathPoint(Layer,
      TPointF.Create(Bounds.Left,
        Bounds.Top + Radii.TopLeft * (1 - KAPPA))),
      RectanglePathPoint(Layer,
      TPointF.Create(Bounds.Left + Radii.TopLeft * (1 - KAPPA),
        Bounds.Top)), RectanglePathPoint(Layer,
      TPointF.Create(Bounds.Left + Radii.TopLeft, Bounds.Top)));
  Builder.Close;
  Result := Builder.Detach;
end;

function BuildScreenLayoutEllipsePath(
  EllipseLayer: TScreenLayoutEllipseLayer): ISkPath;
const
  KAPPA = 0.5522847498;
var
  Builder: ISkPathBuilder;
  RadiusX: Single;
  RadiusY: Single;
begin
  RadiusX := Abs(EllipseLayer.Bounds.Right - EllipseLayer.Bounds.Left) * 0.5;
  RadiusY := Abs(EllipseLayer.Bounds.Bottom - EllipseLayer.Bounds.Top) * 0.5;
  Builder := TSkPathBuilder.Create;
  Builder.MoveTo(EllipsePathPoint(EllipseLayer, RadiusX, 0.0));
  Builder.CubicTo(EllipsePathPoint(EllipseLayer, RadiusX, KAPPA * RadiusY),
    EllipsePathPoint(EllipseLayer, KAPPA * RadiusX, RadiusY),
    EllipsePathPoint(EllipseLayer, 0.0, RadiusY));
  Builder.CubicTo(EllipsePathPoint(EllipseLayer, -KAPPA * RadiusX, RadiusY),
    EllipsePathPoint(EllipseLayer, -RadiusX, KAPPA * RadiusY),
    EllipsePathPoint(EllipseLayer, -RadiusX, 0.0));
  Builder.CubicTo(EllipsePathPoint(EllipseLayer, -RadiusX,
    -KAPPA * RadiusY), EllipsePathPoint(EllipseLayer,
    -KAPPA * RadiusX, -RadiusY), EllipsePathPoint(EllipseLayer,
    0.0, -RadiusY));
  Builder.CubicTo(EllipsePathPoint(EllipseLayer, KAPPA * RadiusX,
    -RadiusY), EllipsePathPoint(EllipseLayer, RadiusX,
    -KAPPA * RadiusY), EllipsePathPoint(EllipseLayer, RadiusX, 0.0));
  Builder.Close;
  Result := Builder.Detach;
end;

function EllipseLinePathPoint(EllipseLine: TScreenLayoutEllipseLineLayer;
  LocalX, LocalY: Single): TPointF;
var
  Center: TPointF;
begin
  Center := TPointF.Create((EllipseLine.Bounds.Left +
    EllipseLine.Bounds.Right) * 0.5, (EllipseLine.Bounds.Top +
    EllipseLine.Bounds.Bottom) * 0.5);
  Result := RotatePointAround(TPointF.Create(Center.X + LocalX,
    Center.Y + LocalY), Center, EllipseLine.RotationDegrees);
end;

function BuildScreenLayoutEllipseLinePath(
  EllipseLine: TScreenLayoutEllipseLineLayer): ISkPath;
const
  KAPPA = 0.5522847498;
var
  Builder: ISkPathBuilder;
  RadiusX: Single;
  RadiusY: Single;
begin
  RadiusX := Abs(EllipseLine.Bounds.Width) * 0.5;
  RadiusY := Abs(EllipseLine.Bounds.Height) * 0.5;
  Builder := TSkPathBuilder.Create;
  Builder.MoveTo(EllipseLinePathPoint(EllipseLine, RadiusX, 0));
  Builder.CubicTo(EllipseLinePathPoint(EllipseLine, RadiusX,
    KAPPA * RadiusY), EllipseLinePathPoint(EllipseLine,
    KAPPA * RadiusX, RadiusY), EllipseLinePathPoint(EllipseLine, 0, RadiusY));
  Builder.CubicTo(EllipseLinePathPoint(EllipseLine, -KAPPA * RadiusX,
    RadiusY), EllipseLinePathPoint(EllipseLine, -RadiusX,
    KAPPA * RadiusY), EllipseLinePathPoint(EllipseLine, -RadiusX, 0));
  Builder.CubicTo(EllipseLinePathPoint(EllipseLine, -RadiusX,
    -KAPPA * RadiusY), EllipseLinePathPoint(EllipseLine,
    -KAPPA * RadiusX, -RadiusY), EllipseLinePathPoint(EllipseLine, 0,
    -RadiusY));
  Builder.CubicTo(EllipseLinePathPoint(EllipseLine, KAPPA * RadiusX,
    -RadiusY), EllipseLinePathPoint(EllipseLine, RadiusX,
    -KAPPA * RadiusY), EllipseLinePathPoint(EllipseLine, RadiusX, 0));
  Builder.Close;
  Result := Builder.Detach;
end;

function ArcPathDerivative(ArcLayer: TScreenLayoutArcLayer;
  AngleDegrees: Single): TPointF;
var
  AngleRadians: Extended;
  Radii: TPointF;
begin
  Radii := ScreenLayoutEllipseRadii(ArcLayer.Bounds);
  AngleRadians := DegToRad(AngleDegrees);
  Result := RotatePointAround(TPointF.Create(-Radii.X * Sin(AngleRadians),
    Radii.Y * Cos(AngleRadians)), TPointF.Zero,
    ArcLayer.RotationDegrees);
end;

function BuildScreenLayoutArcPath(ArcLayer: TScreenLayoutArcLayer): ISkPath;
var
  Alpha: Single;
  Builder: ISkPathBuilder;
  Control1: TPointF;
  Control2: TPointF;
  EndAngle: Single;
  EndDerivative: TPointF;
  EndPoint: TPointF;
  I: Integer;
  SegmentCount: Integer;
  SegmentSweep: Single;
  StartAngle: Single;
  StartDerivative: TPointF;
  StartPoint: TPointF;
  SweepAngle: Single;
begin
  Builder := TSkPathBuilder.Create;
  SweepAngle := EnsureRange(ArcLayer.SweepAngleDegrees, 0.0, 360.0);
  StartAngle := ArcLayer.StartAngleDegrees;
  StartPoint := ScreenLayoutEllipsePoint(ArcLayer.Bounds,
    ArcLayer.RotationDegrees, StartAngle);
  Builder.MoveTo(StartPoint);
  if SweepAngle <= 0.0001 then
    Exit(Builder.Detach);
  SegmentCount := Max(Ceil(SweepAngle / 90.0), 1);
  SegmentSweep := SweepAngle / SegmentCount;
  for I := 0 to SegmentCount - 1 do
  begin
    EndAngle := StartAngle + SegmentSweep;
    StartPoint := ScreenLayoutEllipsePoint(ArcLayer.Bounds,
      ArcLayer.RotationDegrees, StartAngle);
    EndPoint := ScreenLayoutEllipsePoint(ArcLayer.Bounds,
      ArcLayer.RotationDegrees, EndAngle);
    StartDerivative := ArcPathDerivative(ArcLayer, StartAngle);
    EndDerivative := ArcPathDerivative(ArcLayer, EndAngle);
    Alpha := 4.0 / 3.0 * Tan(DegToRad(SegmentSweep) * 0.25);
    Control1 := TPointF.Create(StartPoint.X + Alpha * StartDerivative.X,
      StartPoint.Y + Alpha * StartDerivative.Y);
    Control2 := TPointF.Create(EndPoint.X - Alpha * EndDerivative.X,
      EndPoint.Y - Alpha * EndDerivative.Y);
    Builder.CubicTo(Control1, Control2, EndPoint);
    StartAngle := EndAngle;
  end;
  Result := Builder.Detach;
end;

function EllipseArcShapeDerivative(
  ShapeLayer: TScreenLayoutEllipseArcShapeLayer;
  AngleDegrees: Single): TPointF;
var
  AngleRadians: Extended;
  Radii: TPointF;
begin
  Radii := ScreenLayoutEllipseRadii(ShapeLayer.Bounds);
  AngleRadians := DegToRad(AngleDegrees);
  Result := RotatePointAround(TPointF.Create(-Radii.X * Sin(AngleRadians),
    Radii.Y * Cos(AngleRadians)), TPointF.Zero,
    ShapeLayer.RotationDegrees);
end;

function BuildScreenLayoutEllipseArcShapePath(
  ShapeLayer: TScreenLayoutEllipseArcShapeLayer): ISkPath;
var
  Alpha: Single;
  Builder: ISkPathBuilder;
  Center: TPointF;
  Control1: TPointF;
  Control2: TPointF;
  EndAngle: Single;
  EndDerivative: TPointF;
  EndPoint: TPointF;
  I: Integer;
  SegmentCount: Integer;
  SegmentSweep: Single;
  StartAngle: Single;
  StartDerivative: TPointF;
  StartPoint: TPointF;
  SweepAngle: Single;
begin
  Builder := TSkPathBuilder.Create;
  Center := TPointF.Create((ShapeLayer.Bounds.Left + ShapeLayer.Bounds.Right) *
    0.5, (ShapeLayer.Bounds.Top + ShapeLayer.Bounds.Bottom) * 0.5);
  SweepAngle := EnsureRange(ShapeLayer.SweepAngleDegrees, 0.0, 360.0);
  StartAngle := ShapeLayer.StartAngleDegrees;
  StartPoint := ScreenLayoutEllipsePoint(ShapeLayer.Bounds,
    ShapeLayer.RotationDegrees, StartAngle);
  Builder.MoveTo(Center);
  Builder.LineTo(StartPoint);
  if SweepAngle > 0.0001 then
  begin
    SegmentCount := Max(Ceil(SweepAngle / 90.0), 1);
    SegmentSweep := SweepAngle / SegmentCount;
    for I := 0 to SegmentCount - 1 do
    begin
      EndAngle := StartAngle + SegmentSweep;
      StartPoint := ScreenLayoutEllipsePoint(ShapeLayer.Bounds,
        ShapeLayer.RotationDegrees, StartAngle);
      EndPoint := ScreenLayoutEllipsePoint(ShapeLayer.Bounds,
        ShapeLayer.RotationDegrees, EndAngle);
      StartDerivative := EllipseArcShapeDerivative(ShapeLayer, StartAngle);
      EndDerivative := EllipseArcShapeDerivative(ShapeLayer, EndAngle);
      Alpha := 4.0 / 3.0 * Tan(DegToRad(SegmentSweep) * 0.25);
      Control1 := TPointF.Create(StartPoint.X + Alpha * StartDerivative.X,
        StartPoint.Y + Alpha * StartDerivative.Y);
      Control2 := TPointF.Create(EndPoint.X - Alpha * EndDerivative.X,
        EndPoint.Y - Alpha * EndDerivative.Y);
      Builder.CubicTo(Control1, Control2, EndPoint);
      StartAngle := EndAngle;
    end;
  end;
  Builder.LineTo(Center);
  Builder.Close;
  Result := Builder.Detach;
end;

function BuildScreenLayoutShapePath(
  ShapeLayer: TScreenLayoutShapeLayer): ISkPath;
var
  ContourIndex: Integer;
  Contours: TArray<TScreenLayoutContour>;
  NextVertex: TScreenLayoutVertex;
  PathBuilder: ISkPathBuilder;
  Vertex: TScreenLayoutVertex;
  VertexIndex: Integer;
begin
  if ShapeLayer.FillRule = slfrEvenOdd then
    PathBuilder := TSkPathBuilder.Create(TSkPathFillType.EvenOdd)
  else
    PathBuilder := TSkPathBuilder.Create(TSkPathFillType.Winding);
  Contours := ShapeLayer.Contours;
  for ContourIndex := 0 to High(Contours) do
  begin
    if Length(Contours[ContourIndex].Vertices) < 3 then
      Continue;
    PathBuilder.MoveTo(Contours[ContourIndex].Vertices[0].Position);
    for VertexIndex := 0 to High(Contours[ContourIndex].Vertices) do
    begin
      Vertex := Contours[ContourIndex].Vertices[VertexIndex];
      NextVertex := Contours[ContourIndex].Vertices[
        (VertexIndex + 1) mod Length(Contours[ContourIndex].Vertices)];
      if Vertex.OutgoingSegment = slskCubicBezier then
        PathBuilder.CubicTo(
          TPointF.Create(Vertex.Position.X + Vertex.OutgoingControl.X,
            Vertex.Position.Y + Vertex.OutgoingControl.Y),
          TPointF.Create(NextVertex.Position.X +
            NextVertex.IncomingControl.X, NextVertex.Position.Y +
            NextVertex.IncomingControl.Y), NextVertex.Position)
      else
        PathBuilder.LineTo(NextVertex.Position);
    end;
    PathBuilder.Close;
  end;
  Result := PathBuilder.Detach;
end;

function BuildScreenLayoutBooleanPath(Layer: TVectArtLayer): ISkPath;
begin
  if Layer is TScreenLayoutShapeLayer then
    Exit(BuildScreenLayoutShapePath(TScreenLayoutShapeLayer(Layer)));
  // 楕円弧図形はRectangle系の基底クラスなので、四角形より先に判定する。
  if Layer is TScreenLayoutEllipseArcShapeLayer then
    Exit(BuildScreenLayoutEllipseArcShapePath(
      TScreenLayoutEllipseArcShapeLayer(Layer)));
  if Layer is TScreenLayoutRoundedRectangleLayer then
    Exit(BuildScreenLayoutRoundedRectanglePath(
      TScreenLayoutRoundedRectangleLayer(Layer)));
  if Layer is TScreenLayoutEllipseLayer then
    Exit(BuildScreenLayoutEllipsePath(TScreenLayoutEllipseLayer(Layer)));
  if Layer is TVectArtRectangleLayer then
    Exit(BuildScreenLayoutRectanglePath(TVectArtRectangleLayer(Layer)));
  Result := nil;
end;

end.
