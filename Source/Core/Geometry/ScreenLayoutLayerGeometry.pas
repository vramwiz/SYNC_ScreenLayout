// 任意レイヤーとグループ子孫の外接範囲取得、平行移動を再帰的に提供する。
unit ScreenLayoutLayerGeometry;

interface

uses
  System.Types, ScreenLayoutDocument;

function TryGetScreenLayoutLayerBounds(Layer: TVectArtLayer;
  out Bounds: TRectF): Boolean;
procedure RotateScreenLayoutLayer(Layer: TVectArtLayer;
  const Center: TPointF; Degrees: Single);
procedure ScaleScreenLayoutLayer(Layer: TVectArtLayer;
  const SourceBounds, TargetBounds: TRectF);
procedure TranslateScreenLayoutLayer(Layer: TVectArtLayer; DX, DY: Single);

implementation

uses
  System.Math, ScreenLayoutEllipseGeometry, ScreenLayoutGeometry,
  ScreenLayoutPathOperations, ScreenLayoutShapeOperations,
  ScreenLayoutTextPathGeometry;

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

function ScaleLayerPoint(const Point: TPointF;
  const SourceBounds, TargetBounds: TRectF): TPointF;
begin
  Result := TPointF.Create(
    TargetBounds.Left + (Point.X - SourceBounds.Left) /
      Max(SourceBounds.Width, 0.0001) * TargetBounds.Width,
    TargetBounds.Top + (Point.Y - SourceBounds.Top) /
      Max(SourceBounds.Height, 0.0001) * TargetBounds.Height);
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
  if Layer is TScreenLayoutTextPathLayer then
  begin
    Result := TryGetScreenLayoutTextPathBounds(
      TScreenLayoutTextPathLayer(Layer), Bounds);
    Exit;
  end
  else if Layer is TVectArtImageLayer then
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

procedure RotateScreenLayoutLayer(Layer: TVectArtLayer;
  const Center: TPointF; Degrees: Single);
var
  Bounds: TRectF;
  BoundsCenter: TPointF;
  Contours: TArray<TScreenLayoutContour>;
  GroupLayer: TScreenLayoutGroupLayer;
  I: Integer;
  ImageLayer: TVectArtImageLayer;
  NewCenter: TPointF;
  Points: TVectArtImagePoints;
  TextPathLayer: TScreenLayoutTextPathLayer;
  Vertices: TArray<TScreenLayoutVertex>;
begin
  if Layer is TScreenLayoutGroupLayer then
  begin
    GroupLayer := TScreenLayoutGroupLayer(Layer);
    for I := 0 to GroupLayer.ChildCount - 1 do
      RotateScreenLayoutLayer(GroupLayer[I], Center, Degrees);
  end
  else if Layer is TScreenLayoutTextPathLayer then
  begin
    TextPathLayer := TScreenLayoutTextPathLayer(Layer);
    Vertices := RotateScreenLayoutPathVertices(
      TextPathLayer.EditablePathVertices, Center, Degrees);
    TextPathLayer.AssignEditablePathVertices(Vertices);
    TextPathLayer.RotationDegrees := TextPathLayer.RotationDegrees + Degrees;
  end
  else if Layer is TVectArtImageLayer then
  begin
    ImageLayer := TVectArtImageLayer(Layer);
    Points := ImageLayer.Points;
    for I := 0 to High(Points) do
      Points[I] := RotatePointAround(Points[I], Center, Degrees);
    ImageLayer.Points := Points;
  end
  else if Layer is TVectArtPathLayer then
  begin
    Vertices := RotateScreenLayoutPathVertices(
      TVectArtPathLayer(Layer).Vertices, Center, Degrees);
    TVectArtPathLayer(Layer).Vertices := Vertices;
  end
  else if Layer is TScreenLayoutShapeLayer then
  begin
    Contours := RotateScreenLayoutShapeContours(
      TScreenLayoutShapeLayer(Layer).Contours, Center, Degrees);
    TScreenLayoutShapeLayer(Layer).Contours := Contours;
  end
  else if Layer is TScreenLayoutRectangleLineLayer then
  begin
    Bounds := TScreenLayoutRectangleLineLayer(Layer).Bounds;
    BoundsCenter := TPointF.Create(Bounds.CenterPoint.X, Bounds.CenterPoint.Y);
    NewCenter := RotatePointAround(BoundsCenter, Center, Degrees);
    Bounds.Offset(NewCenter.X - BoundsCenter.X, NewCenter.Y - BoundsCenter.Y);
    TScreenLayoutRectangleLineLayer(Layer).Bounds := Bounds;
    TScreenLayoutRectangleLineLayer(Layer).RotationDegrees :=
      TScreenLayoutRectangleLineLayer(Layer).RotationDegrees + Degrees;
  end
  else if Layer is TScreenLayoutArcLayer then
  begin
    Bounds := TScreenLayoutArcLayer(Layer).Bounds;
    BoundsCenter := TPointF.Create(Bounds.CenterPoint.X, Bounds.CenterPoint.Y);
    NewCenter := RotatePointAround(BoundsCenter, Center, Degrees);
    Bounds.Offset(NewCenter.X - BoundsCenter.X, NewCenter.Y - BoundsCenter.Y);
    TScreenLayoutArcLayer(Layer).Bounds := Bounds;
    TScreenLayoutArcLayer(Layer).RotationDegrees :=
      TScreenLayoutArcLayer(Layer).RotationDegrees + Degrees;
  end
  else if Layer is TVectArtRectangleLayer then
  begin
    Bounds := TVectArtRectangleLayer(Layer).Bounds;
    BoundsCenter := TPointF.Create(Bounds.CenterPoint.X, Bounds.CenterPoint.Y);
    NewCenter := RotatePointAround(BoundsCenter, Center, Degrees);
    Bounds.Offset(NewCenter.X - BoundsCenter.X, NewCenter.Y - BoundsCenter.Y);
    TVectArtRectangleLayer(Layer).Bounds := Bounds;
    TVectArtRectangleLayer(Layer).RotationDegrees :=
      TVectArtRectangleLayer(Layer).RotationDegrees + Degrees;
  end;
end;

procedure ScaleScreenLayoutLayer(Layer: TVectArtLayer;
  const SourceBounds, TargetBounds: TRectF);
var
  Bounds: TRectF;
  Contours: TArray<TScreenLayoutContour>;
  GroupLayer: TScreenLayoutGroupLayer;
  I: Integer;
  ImageLayer: TVectArtImageLayer;
  Points: TVectArtImagePoints;
  Radii: TScreenLayoutCornerRadii;
  ScaleValue: Single;
  TextPathLayer: TScreenLayoutTextPathLayer;
  Vertices: TArray<TScreenLayoutVertex>;
begin
  if (SourceBounds.Width <= 0.0001) or
    (SourceBounds.Height <= 0.0001) then
    Exit;
  if Layer is TScreenLayoutGroupLayer then
  begin
    GroupLayer := TScreenLayoutGroupLayer(Layer);
    for I := 0 to GroupLayer.ChildCount - 1 do
      ScaleScreenLayoutLayer(GroupLayer[I], SourceBounds, TargetBounds);
  end
  else if Layer is TScreenLayoutTextPathLayer then
  begin
    TextPathLayer := TScreenLayoutTextPathLayer(Layer);
    Vertices := ScaleScreenLayoutPathVertices(
      TextPathLayer.EditablePathVertices, SourceBounds, TargetBounds);
    TextPathLayer.AssignEditablePathVertices(Vertices);
    // 非等方のグループ変形でも逆変換時に元の文字サイズへ正確に戻せる倍率を使う。
    ScaleValue := Sqrt(Abs(TargetBounds.Width / SourceBounds.Width) *
      Abs(TargetBounds.Height / SourceBounds.Height));
    TextPathLayer.FontSize := Max(TextPathLayer.FontSize * ScaleValue, 1.0);
  end
  else if Layer is TVectArtImageLayer then
  begin
    ImageLayer := TVectArtImageLayer(Layer);
    Points := ImageLayer.Points;
    for I := 0 to High(Points) do
      Points[I] := ScaleLayerPoint(Points[I], SourceBounds, TargetBounds);
    ImageLayer.Points := Points;
  end
  else if Layer is TVectArtPathLayer then
  begin
    Vertices := ScaleScreenLayoutPathVertices(
      TVectArtPathLayer(Layer).Vertices, SourceBounds, TargetBounds);
    TVectArtPathLayer(Layer).Vertices := Vertices;
  end
  else if Layer is TScreenLayoutShapeLayer then
  begin
    Contours := ScaleScreenLayoutShapeContours(
      TScreenLayoutShapeLayer(Layer).Contours, SourceBounds, TargetBounds);
    TScreenLayoutShapeLayer(Layer).Contours := Contours;
  end
  else if Layer is TScreenLayoutRectangleLineLayer then
  begin
    Bounds := TScreenLayoutRectangleLineLayer(Layer).Bounds;
    Bounds := TRectF.Create(ScaleLayerPoint(Bounds.TopLeft, SourceBounds,
      TargetBounds), ScaleLayerPoint(Bounds.BottomRight, SourceBounds,
      TargetBounds));
    TScreenLayoutRectangleLineLayer(Layer).Bounds := Bounds;
    if Layer is TScreenLayoutRoundedRectangleLineLayer then
    begin
      ScaleValue := Min(Abs(TargetBounds.Width / SourceBounds.Width),
        Abs(TargetBounds.Height / SourceBounds.Height));
      Radii := TScreenLayoutRoundedRectangleLineLayer(Layer).CornerRadii;
      Radii.TopLeft := Radii.TopLeft * ScaleValue;
      Radii.TopRight := Radii.TopRight * ScaleValue;
      Radii.BottomRight := Radii.BottomRight * ScaleValue;
      Radii.BottomLeft := Radii.BottomLeft * ScaleValue;
      TScreenLayoutRoundedRectangleLineLayer(Layer).CornerRadii := Radii;
    end;
  end
  else if Layer is TScreenLayoutArcLayer then
  begin
    Bounds := TScreenLayoutArcLayer(Layer).Bounds;
    Bounds := TRectF.Create(ScaleLayerPoint(Bounds.TopLeft, SourceBounds,
      TargetBounds), ScaleLayerPoint(Bounds.BottomRight, SourceBounds,
      TargetBounds));
    TScreenLayoutArcLayer(Layer).Bounds := Bounds;
  end
  else if Layer is TVectArtRectangleLayer then
  begin
    Bounds := TVectArtRectangleLayer(Layer).Bounds;
    Bounds := TRectF.Create(ScaleLayerPoint(Bounds.TopLeft, SourceBounds,
      TargetBounds), ScaleLayerPoint(Bounds.BottomRight, SourceBounds,
      TargetBounds));
    TVectArtRectangleLayer(Layer).Bounds := Bounds;
    if Layer is TScreenLayoutRoundedRectangleLayer then
    begin
      ScaleValue := Min(Abs(TargetBounds.Width / SourceBounds.Width),
        Abs(TargetBounds.Height / SourceBounds.Height));
      Radii := TScreenLayoutRoundedRectangleLayer(Layer).CornerRadii;
      Radii.TopLeft := Radii.TopLeft * ScaleValue;
      Radii.TopRight := Radii.TopRight * ScaleValue;
      Radii.BottomRight := Radii.BottomRight * ScaleValue;
      Radii.BottomLeft := Radii.BottomLeft * ScaleValue;
      TScreenLayoutRoundedRectangleLayer(Layer).CornerRadii := Radii;
    end;
  end;
end;

procedure TranslateScreenLayoutLayer(Layer: TVectArtLayer; DX, DY: Single);
var
  Bounds: TRectF;
  Contours: TArray<TScreenLayoutContour>;
  GroupLayer: TScreenLayoutGroupLayer;
  I: Integer;
  ImageLayer: TVectArtImageLayer;
  Points: TVectArtImagePoints;
  TextPathLayer: TScreenLayoutTextPathLayer;
  Vertices: TArray<TScreenLayoutVertex>;
begin
  if Layer is TScreenLayoutGroupLayer then
  begin
    GroupLayer := TScreenLayoutGroupLayer(Layer);
    for I := 0 to GroupLayer.ChildCount - 1 do
      TranslateScreenLayoutLayer(GroupLayer[I], DX, DY);
  end
  else if Layer is TScreenLayoutTextPathLayer then
  begin
    TextPathLayer := TScreenLayoutTextPathLayer(Layer);
    Vertices := TranslateScreenLayoutPathVertices(
      TextPathLayer.EditablePathVertices, DX, DY);
    TextPathLayer.AssignEditablePathVertices(Vertices);
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
