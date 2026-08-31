// 複数の閉輪郭をSkiaの単一Pathへ変換し、描画とヒット判定で共有する。
unit ScreenLayoutShapePath;

interface

uses
  System.Skia, ScreenLayoutDocument;

// Shapeの塗り規則、直線、3次ベジェ、閉輪郭を反映したPathを返す。
function BuildScreenLayoutShapePath(
  ShapeLayer: TScreenLayoutShapeLayer): ISkPath;

implementation

uses
  System.Types;

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

end.
