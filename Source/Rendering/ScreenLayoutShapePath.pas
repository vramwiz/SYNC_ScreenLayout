// 複数の閉輪郭をSkiaの単一Pathへ変換し、描画とヒット判定で共有する。
unit ScreenLayoutShapePath;

interface

uses
  System.Skia, ScreenLayoutDocument;

// Shapeの塗り規則、直線、3次ベジェ、閉輪郭を反映したPathを返す。
function BuildScreenLayoutShapePath(
  ShapeLayer: TScreenLayoutShapeLayer): ISkPath;
// Shape、Rectangle、角丸Rectangleを塗り領域の論理演算Pathへ変換する。
function BuildScreenLayoutBooleanPath(Layer: TVectArtLayer): ISkPath;

implementation

uses
  System.Types, ScreenLayoutGeometry;

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
  if Layer is TScreenLayoutRoundedRectangleLayer then
    Exit(BuildScreenLayoutRoundedRectanglePath(
      TScreenLayoutRoundedRectangleLayer(Layer)));
  if Layer is TVectArtRectangleLayer then
    Exit(BuildScreenLayoutRectanglePath(TVectArtRectangleLayer(Layer)));
  Result := nil;
end;

end.
