// 任意レイヤーとグループ子孫の外接範囲取得、平行移動を再帰的に提供する。
unit ScreenLayoutLayerGeometry;

interface

uses
  System.Types, ScreenLayoutDocument;

function TryGetScreenLayoutLayerBounds(Layer: TVectArtLayer;
  out Bounds: TRectF): Boolean;
procedure TranslateScreenLayoutLayer(Layer: TVectArtLayer; DX, DY: Single);

implementation

uses
  System.Math, ScreenLayoutEllipseGeometry, ScreenLayoutGeometry,
  ScreenLayoutPathOperations, ScreenLayoutShapeOperations;

function ScreenLayoutImagePointsBounds(
  const Points: TVectArtImagePoints): TRectF;
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

function TryGetScreenLayoutLayerBounds(Layer: TVectArtLayer;
  out Bounds: TRectF): Boolean;
var
  ArcLayer: TScreenLayoutArcLayer;
  ChildBounds: TRectF;
  GroupLayer: TScreenLayoutGroupLayer;
  I: Integer;
  RectangleLayer: TVectArtRectangleLayer;
  RectangleLine: TScreenLayoutRectangleLineLayer;
begin
  Result := False;
  Bounds := TRectF.Empty;
  if Layer = nil then
    Exit;
  if Layer is TScreenLayoutGroupLayer then
  begin
    GroupLayer := TScreenLayoutGroupLayer(Layer);
    for I := 0 to GroupLayer.ChildCount - 1 do
      if GroupLayer[I].Visible and
        TryGetScreenLayoutLayerBounds(GroupLayer[I], ChildBounds) then
      begin
        if not Result then
          Bounds := ChildBounds
        else
        begin
          Bounds.Left := Min(Bounds.Left, ChildBounds.Left);
          Bounds.Top := Min(Bounds.Top, ChildBounds.Top);
          Bounds.Right := Max(Bounds.Right, ChildBounds.Right);
          Bounds.Bottom := Max(Bounds.Bottom, ChildBounds.Bottom);
        end;
        Result := True;
      end;
    Exit;
  end;
  if Layer is TVectArtImageLayer then
    Bounds := ScreenLayoutImagePointsBounds(TVectArtImageLayer(Layer).Points)
  else if Layer is TVectArtPathLayer then
    Bounds := ScreenLayoutPathVerticesBounds(TVectArtPathLayer(Layer).Vertices)
  else if Layer is TScreenLayoutShapeLayer then
    Bounds := ScreenLayoutShapeContoursBounds(
      TScreenLayoutShapeLayer(Layer).Contours)
  else if Layer is TScreenLayoutRectangleLineLayer then
  begin
    RectangleLine := TScreenLayoutRectangleLineLayer(Layer);
    Bounds := QuadBounds(RectangleCorners(RectangleLine.Bounds,
      RectangleLine.RotationDegrees));
  end
  else if Layer is TScreenLayoutArcLayer then
  begin
    ArcLayer := TScreenLayoutArcLayer(Layer);
    Bounds := ScreenLayoutEllipseBounds(ArcLayer.Bounds,
      ArcLayer.RotationDegrees);
  end
  else if Layer is TVectArtRectangleLayer then
  begin
    RectangleLayer := TVectArtRectangleLayer(Layer);
    Bounds := QuadBounds(RectangleCorners(RectangleLayer.Bounds,
      RectangleLayer.RotationDegrees));
  end
  else
    Exit;
  Result := True;
end;

procedure TranslateScreenLayoutLayer(Layer: TVectArtLayer; DX, DY: Single);
var
  Bounds: TRectF;
  Contours: TArray<TScreenLayoutContour>;
  GroupLayer: TScreenLayoutGroupLayer;
  I: Integer;
  ImageLayer: TVectArtImageLayer;
  Points: TVectArtImagePoints;
  Vertices: TArray<TScreenLayoutVertex>;
begin
  if Layer is TScreenLayoutGroupLayer then
  begin
    GroupLayer := TScreenLayoutGroupLayer(Layer);
    for I := 0 to GroupLayer.ChildCount - 1 do
      TranslateScreenLayoutLayer(GroupLayer[I], DX, DY);
  end
  else if Layer is TVectArtImageLayer then
  begin
    ImageLayer := TVectArtImageLayer(Layer);
    Points := ImageLayer.Points;
    for I := 0 to High(Points) do
      Points[I].Offset(DX, DY);
    ImageLayer.Points := Points;
  end
  else if Layer is TVectArtPathLayer then
  begin
    Vertices := TranslateScreenLayoutPathVertices(
      TVectArtPathLayer(Layer).Vertices, DX, DY);
    TVectArtPathLayer(Layer).Vertices := Vertices;
  end
  else if Layer is TScreenLayoutShapeLayer then
  begin
    Contours := TranslateScreenLayoutShapeContours(
      TScreenLayoutShapeLayer(Layer).Contours, DX, DY);
    TScreenLayoutShapeLayer(Layer).Contours := Contours;
  end
  else if Layer is TScreenLayoutRectangleLineLayer then
  begin
    Bounds := TScreenLayoutRectangleLineLayer(Layer).Bounds;
    Bounds.Offset(DX, DY);
    TScreenLayoutRectangleLineLayer(Layer).Bounds := Bounds;
  end
  else if Layer is TScreenLayoutArcLayer then
  begin
    Bounds := TScreenLayoutArcLayer(Layer).Bounds;
    Bounds.Offset(DX, DY);
    TScreenLayoutArcLayer(Layer).Bounds := Bounds;
  end
  else if Layer is TVectArtRectangleLayer then
  begin
    Bounds := TVectArtRectangleLayer(Layer).Bounds;
    Bounds.Offset(DX, DY);
    TVectArtRectangleLayer(Layer).Bounds := Bounds;
  end;
end;

end.
