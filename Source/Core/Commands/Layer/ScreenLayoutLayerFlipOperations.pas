// 現在選択を共通軸で左右・上下反転し、全レイヤー型を1件のUndo／Redoとして扱う。
unit ScreenLayoutLayerFlipOperations;

interface

uses
  ScreenLayoutDocument, ScreenLayoutEditHistory, ScreenLayoutEditorState;

type
  TScreenLayoutFlipDirection = (slfdHorizontal, slfdVertical);

// トップレベルまたは開いたグループの現在選択を反転できる場合にTrueを返す。
function CanFlipScreenLayoutSelection(Document: TVectArtDocument;
  EditorState: TVectArtEditorState): Boolean;
// 選択全体の外接範囲中央を軸に反転し、履歴へ適用済みコマンドを追加する。
procedure FlipScreenLayoutSelection(Document: TVectArtDocument;
  EditHistory: TVectArtEditHistory; EditorState: TVectArtEditorState;
  Direction: TScreenLayoutFlipDirection);

implementation

uses
  System.Generics.Collections, System.Math, System.SysUtils, System.Types,
  ScreenLayoutEditCommands, ScreenLayoutFilters, ScreenLayoutGroupCommands,
  ScreenLayoutLayerGeometry, ScreenLayoutPaintStyles,
  ScreenLayoutPatternStyle, ScreenLayoutTextureStyle, ScreenLayoutProjectiveTransform;

type
  TScreenLayoutFlipLayersCommand = class(TVectArtEditCommand)
  private
    FAfter: TObjectList<TVectArtLayer>;
    FBefore: TObjectList<TVectArtLayer>;
    FDocument: TVectArtDocument;
    FTargets: TArray<TVectArtLayer>;
    procedure Apply(const Values: TObjectList<TVectArtLayer>);
  public
    constructor Create(ADocument: TVectArtDocument;
      const Targets: TArray<TVectArtLayer>; const AxisCenter: TPointF;
      Direction: TScreenLayoutFlipDirection);
    destructor Destroy; override;
    procedure Execute; override;
    procedure Undo; override;
  end;

function ReflectPoint(const Point, AxisCenter: TPointF;
  Direction: TScreenLayoutFlipDirection): TPointF;
begin
  Result := Point;
  if Direction = slfdHorizontal then
    Result.X := 2 * AxisCenter.X - Point.X
  else
    Result.Y := 2 * AxisCenter.Y - Point.Y;
end;

procedure ReflectBoundsCenter(var Bounds: TRectF; const AxisCenter: TPointF;
  Direction: TScreenLayoutFlipDirection);
var
  Center: TPointF;
  ReflectedCenter: TPointF;
begin
  Center := Bounds.CenterPoint;
  ReflectedCenter := ReflectPoint(Center, AxisCenter, Direction);
  Bounds.Offset(ReflectedCenter.X - Center.X, ReflectedCenter.Y - Center.Y);
end;

procedure ReflectCornerRadii(var Radii: TScreenLayoutCornerRadii;
  Direction: TScreenLayoutFlipDirection);
var
  Value: Single;
begin
  if Direction = slfdHorizontal then
  begin
    Value := Radii.TopLeft;
    Radii.TopLeft := Radii.TopRight;
    Radii.TopRight := Value;
    Value := Radii.BottomLeft;
    Radii.BottomLeft := Radii.BottomRight;
    Radii.BottomRight := Value;
  end
  else
  begin
    Value := Radii.TopLeft;
    Radii.TopLeft := Radii.BottomLeft;
    Radii.BottomLeft := Value;
    Value := Radii.TopRight;
    Radii.TopRight := Radii.BottomRight;
    Radii.BottomRight := Value;
  end;
end;

procedure ReflectPaintStyle(var Style: TScreenLayoutPaintStyle;
  Direction: TScreenLayoutFlipDirection);
var
  Pattern: TScreenLayoutPatternStyle;
  PointValue: TPointF;
  Texture: TScreenLayoutTextureStyle;
begin
  PointValue := Style.LinearStart;
  if Direction = slfdHorizontal then
    PointValue.X := 1 - PointValue.X
  else
    PointValue.Y := 1 - PointValue.Y;
  Style.LinearStart := PointValue;
  PointValue := Style.LinearEnd;
  if Direction = slfdHorizontal then
    PointValue.X := 1 - PointValue.X
  else
    PointValue.Y := 1 - PointValue.Y;
  Style.LinearEnd := PointValue;

  Pattern := Style.Pattern;
  if Direction = slfdHorizontal then
    Pattern.FlipHorizontal := not Pattern.FlipHorizontal
  else
    Pattern.FlipVertical := not Pattern.FlipVertical;
  Style.Pattern := Pattern;

  Texture := Style.Texture;
  if Direction = slfdHorizontal then
    Texture.FlipHorizontal := not Texture.FlipHorizontal
  else
    Texture.FlipVertical := not Texture.FlipVertical;
  Style.Texture := Texture;
end;

procedure ReflectLayerFilters(Layer: TVectArtLayer;
  Direction: TScreenLayoutFlipDirection);
var
  I: Integer;
  Shadow: TScreenLayoutShadowFilter;
begin
  for I := 0 to Layer.FilterCount - 1 do
    if Layer.Filters[I] is TScreenLayoutShadowFilter then
    begin
      Shadow := TScreenLayoutShadowFilter(Layer.Filters[I]);
      if Direction = slfdHorizontal then
        Shadow.OffsetX := -Shadow.OffsetX
      else
        Shadow.OffsetY := -Shadow.OffsetY;
    end;
end;

procedure ReflectVertices(var Vertices: TArray<TScreenLayoutVertex>;
  const AxisCenter: TPointF; Direction: TScreenLayoutFlipDirection);
var
  I: Integer;
begin
  Vertices := Copy(Vertices);
  for I := 0 to High(Vertices) do
  begin
    Vertices[I].Position := ReflectPoint(Vertices[I].Position,
      AxisCenter, Direction);
    if Direction = slfdHorizontal then
    begin
      Vertices[I].IncomingControl.X := -Vertices[I].IncomingControl.X;
      Vertices[I].OutgoingControl.X := -Vertices[I].OutgoingControl.X;
    end
    else
    begin
      Vertices[I].IncomingControl.Y := -Vertices[I].IncomingControl.Y;
      Vertices[I].OutgoingControl.Y := -Vertices[I].OutgoingControl.Y;
    end;
  end;
end;

procedure ReflectLayer(Layer: TVectArtLayer; const AxisCenter: TPointF;
  Direction: TScreenLayoutFlipDirection);
var
  Transform: TScreenLayoutTransform;
  Arc: TScreenLayoutArcLayer;
  ArcShape: TScreenLayoutEllipseArcShapeLayer;
  Bounds: TRectF;
  Contours: TArray<TScreenLayoutContour>;
  Group: TScreenLayoutGroupLayer;
  I: Integer;
  Image: TVectArtImageLayer;
  Points: TVectArtImagePoints;
  Radii: TScreenLayoutCornerRadii;
  Rectangle: TVectArtRectangleLayer;
  RectangleLine: TScreenLayoutRectangleLineLayer;
  Style: TScreenLayoutPaintStyle;
  Text: TScreenLayoutTextLayer;
  TextPath: TScreenLayoutTextPathLayer;
  Vertices: TArray<TScreenLayoutVertex>;
begin
  if Layer = nil then
    Exit;
  if not Layer.Transform.IsIdentity then
  begin
    Transform := TScreenLayoutTransform.Identity;
    if Direction = slfdHorizontal then
    begin Transform.Values[0] := -1; Transform.Values[2] := 2*AxisCenter.X end
    else begin Transform.Values[4] := -1; Transform.Values[5] := 2*AxisCenter.Y end;
    Layer.Transform := Layer.Transform.ThenApply(Transform);
    Exit;
  end;
  ReflectLayerFilters(Layer, Direction);
  if Layer is TScreenLayoutGroupLayer then
  begin
    Group := TScreenLayoutGroupLayer(Layer);
    for I := 0 to Group.ChildCount - 1 do
      ReflectLayer(Group[I], AxisCenter, Direction);
    Exit;
  end;

  if Layer is TScreenLayoutTextPathLayer then
  begin
    TextPath := TScreenLayoutTextPathLayer(Layer);
    Vertices := TextPath.EditablePathVertices;
    ReflectVertices(Vertices, AxisCenter, Direction);
    TextPath.AssignEditablePathVertices(Vertices);
    Bounds := TextPath.Bounds;
    ReflectBoundsCenter(Bounds, AxisCenter, Direction);
    TextPath.Bounds := Bounds;
    TextPath.RotationDegrees := -TextPath.RotationDegrees;
    if Direction = slfdHorizontal then
      TextPath.FlipHorizontal := not TextPath.FlipHorizontal
    else
      TextPath.FlipVertical := not TextPath.FlipVertical;
    Style := TextPath.PaintStyle;
    ReflectPaintStyle(Style, Direction);
    TextPath.PaintStyle := Style;
    Exit;
  end;

  if Layer is TScreenLayoutTextLayer then
  begin
    Text := TScreenLayoutTextLayer(Layer);
    Bounds := Text.Bounds;
    ReflectBoundsCenter(Bounds, AxisCenter, Direction);
    Text.Bounds := Bounds;
    Text.RotationDegrees := -Text.RotationDegrees;
    if Direction = slfdHorizontal then
      Text.FlipHorizontal := not Text.FlipHorizontal
    else
      Text.FlipVertical := not Text.FlipVertical;
    Exit;
  end;

  Style := Layer.PaintStyle;
  ReflectPaintStyle(Style, Direction);
  Layer.PaintStyle := Style;

  if Layer is TVectArtImageLayer then
  begin
    Image := TVectArtImageLayer(Layer);
    Points := Image.Points;
    for I := 0 to High(Points) do
      Points[I] := ReflectPoint(Points[I], AxisCenter, Direction);
    Image.Points := Points;
  end
  else if Layer is TVectArtPathLayer then
  begin
    Vertices := TVectArtPathLayer(Layer).Vertices;
    ReflectVertices(Vertices, AxisCenter, Direction);
    TVectArtPathLayer(Layer).Vertices := Vertices;
  end
  else if Layer is TScreenLayoutShapeLayer then
  begin
    Contours := TScreenLayoutShapeLayer(Layer).Contours;
    for I := 0 to High(Contours) do
      ReflectVertices(Contours[I].Vertices, AxisCenter, Direction);
    TScreenLayoutShapeLayer(Layer).Contours := Contours;
  end
  else if Layer is TScreenLayoutArcLayer then
  begin
    Arc := TScreenLayoutArcLayer(Layer);
    Bounds := Arc.Bounds;
    ReflectBoundsCenter(Bounds, AxisCenter, Direction);
    Arc.Bounds := Bounds;
    Arc.RotationDegrees := -Arc.RotationDegrees;
    if Direction = slfdHorizontal then
      Arc.StartAngleDegrees := 180 - Arc.StartAngleDegrees -
        Arc.SweepAngleDegrees
    else
      Arc.StartAngleDegrees := -Arc.StartAngleDegrees -
        Arc.SweepAngleDegrees;
  end
  else if Layer is TScreenLayoutRectangleLineLayer then
  begin
    RectangleLine := TScreenLayoutRectangleLineLayer(Layer);
    Bounds := RectangleLine.Bounds;
    ReflectBoundsCenter(Bounds, AxisCenter, Direction);
    RectangleLine.Bounds := Bounds;
    RectangleLine.RotationDegrees := -RectangleLine.RotationDegrees;
    if Layer is TScreenLayoutRoundedRectangleLineLayer then
    begin
      Radii := TScreenLayoutRoundedRectangleLineLayer(Layer).CornerRadii;
      ReflectCornerRadii(Radii, Direction);
      TScreenLayoutRoundedRectangleLineLayer(Layer).CornerRadii := Radii;
    end;
  end
  else if Layer is TVectArtRectangleLayer then
  begin
    Rectangle := TVectArtRectangleLayer(Layer);
    Bounds := Rectangle.Bounds;
    ReflectBoundsCenter(Bounds, AxisCenter, Direction);
    Rectangle.Bounds := Bounds;
    Rectangle.RotationDegrees := -Rectangle.RotationDegrees;
    if Layer is TScreenLayoutRoundedRectangleLayer then
    begin
      Radii := TScreenLayoutRoundedRectangleLayer(Layer).CornerRadii;
      ReflectCornerRadii(Radii, Direction);
      TScreenLayoutRoundedRectangleLayer(Layer).CornerRadii := Radii;
    end;
    if Layer is TScreenLayoutEllipseArcShapeLayer then
    begin
      ArcShape := TScreenLayoutEllipseArcShapeLayer(Layer);
      if Direction = slfdHorizontal then
        ArcShape.StartAngleDegrees := 180 - ArcShape.StartAngleDegrees -
          ArcShape.SweepAngleDegrees
      else
        ArcShape.StartAngleDegrees := -ArcShape.StartAngleDegrees -
          ArcShape.SweepAngleDegrees;
    end;
  end;
end;

procedure AssignTransformValues(Source, Target: TVectArtLayer);
var
  I: Integer;
begin
  Target.Transform := Source.Transform;
  Target.FlipHorizontal := Source.FlipHorizontal;
  Target.FlipVertical := Source.FlipVertical;
  Target.PaintStyle := Source.PaintStyle;
  for I := 0 to Min(Source.FilterCount, Target.FilterCount) - 1 do
    if (Source.Filters[I] is TScreenLayoutShadowFilter) and
      (Target.Filters[I] is TScreenLayoutShadowFilter) then
    begin
      TScreenLayoutShadowFilter(Target.Filters[I]).OffsetX :=
        TScreenLayoutShadowFilter(Source.Filters[I]).OffsetX;
      TScreenLayoutShadowFilter(Target.Filters[I]).OffsetY :=
        TScreenLayoutShadowFilter(Source.Filters[I]).OffsetY;
    end;
  if (Source is TScreenLayoutGroupLayer) and
    (Target is TScreenLayoutGroupLayer) then
  begin
    for I := 0 to Min(TScreenLayoutGroupLayer(Source).ChildCount,
      TScreenLayoutGroupLayer(Target).ChildCount) - 1 do
      AssignTransformValues(TScreenLayoutGroupLayer(Source)[I],
        TScreenLayoutGroupLayer(Target)[I]);
    Exit;
  end;
  if (Source is TScreenLayoutTextPathLayer) and
    (Target is TScreenLayoutTextPathLayer) then
    TScreenLayoutTextPathLayer(Target).AssignEditablePathVertices(
      TScreenLayoutTextPathLayer(Source).EditablePathVertices);
  if (Source is TVectArtImageLayer) and (Target is TVectArtImageLayer) then
    TVectArtImageLayer(Target).Points := TVectArtImageLayer(Source).Points
  else if (Source is TVectArtPathLayer) and (Target is TVectArtPathLayer) then
    TVectArtPathLayer(Target).Vertices := TVectArtPathLayer(Source).Vertices
  else if (Source is TScreenLayoutShapeLayer) and
    (Target is TScreenLayoutShapeLayer) then
    TScreenLayoutShapeLayer(Target).Contours :=
      TScreenLayoutShapeLayer(Source).Contours
  else if (Source is TScreenLayoutArcLayer) and
    (Target is TScreenLayoutArcLayer) then
  begin
    TScreenLayoutArcLayer(Target).Bounds := TScreenLayoutArcLayer(Source).Bounds;
    TScreenLayoutArcLayer(Target).RotationDegrees :=
      TScreenLayoutArcLayer(Source).RotationDegrees;
    TScreenLayoutArcLayer(Target).StartAngleDegrees :=
      TScreenLayoutArcLayer(Source).StartAngleDegrees;
    TScreenLayoutArcLayer(Target).SweepAngleDegrees :=
      TScreenLayoutArcLayer(Source).SweepAngleDegrees;
  end
  else if (Source is TScreenLayoutRectangleLineLayer) and
    (Target is TScreenLayoutRectangleLineLayer) then
  begin
    TScreenLayoutRectangleLineLayer(Target).Bounds :=
      TScreenLayoutRectangleLineLayer(Source).Bounds;
    TScreenLayoutRectangleLineLayer(Target).RotationDegrees :=
      TScreenLayoutRectangleLineLayer(Source).RotationDegrees;
    if (Source is TScreenLayoutRoundedRectangleLineLayer) and
      (Target is TScreenLayoutRoundedRectangleLineLayer) then
      TScreenLayoutRoundedRectangleLineLayer(Target).CornerRadii :=
        TScreenLayoutRoundedRectangleLineLayer(Source).CornerRadii;
  end
  else if (Source is TVectArtRectangleLayer) and
    (Target is TVectArtRectangleLayer) then
  begin
    TVectArtRectangleLayer(Target).Bounds := TVectArtRectangleLayer(Source).Bounds;
    TVectArtRectangleLayer(Target).RotationDegrees :=
      TVectArtRectangleLayer(Source).RotationDegrees;
    if (Source is TScreenLayoutRoundedRectangleLayer) and
      (Target is TScreenLayoutRoundedRectangleLayer) then
      TScreenLayoutRoundedRectangleLayer(Target).CornerRadii :=
        TScreenLayoutRoundedRectangleLayer(Source).CornerRadii;
    if (Source is TScreenLayoutEllipseArcShapeLayer) and
      (Target is TScreenLayoutEllipseArcShapeLayer) then
    begin
      TScreenLayoutEllipseArcShapeLayer(Target).StartAngleDegrees :=
        TScreenLayoutEllipseArcShapeLayer(Source).StartAngleDegrees;
      TScreenLayoutEllipseArcShapeLayer(Target).SweepAngleDegrees :=
        TScreenLayoutEllipseArcShapeLayer(Source).SweepAngleDegrees;
    end;
  end;
end;

function SelectedLayers(Document: TVectArtDocument;
  EditorState: TVectArtEditorState): TArray<TVectArtLayer>;
var
  I: Integer;
  Indices: TArray<Integer>;
begin
  if (EditorState <> nil) and (EditorState.OpenGroup <> nil) then
    Exit(EditorState.GetOpenGroupChildren);
  Result := nil;
  if Document = nil then
    Exit;
  Indices := Document.GetSelectedLayerIndices;
  SetLength(Result, Length(Indices));
  for I := 0 to High(Indices) do
    Result[I] := Document[Indices[I]];
end;

function CanFlipScreenLayoutSelection(Document: TVectArtDocument;
  EditorState: TVectArtEditorState): Boolean;
var
  Layer: TVectArtLayer;
  Layers: TArray<TVectArtLayer>;
begin
  Layers := SelectedLayers(Document, EditorState);
  Result := Length(Layers) > 0;
  if not Result then
    Exit;
  for Layer in Layers do
    if (Layer = nil) or Layer.Locked or
      (Layer is TVectArtCanvasLayer) then
      Exit(False);
end;

function SelectionCenter(const Layers: TArray<TVectArtLayer>): TPointF;
var
  Bounds: TRectF;
  I: Integer;
  LayerBounds: TRectF;
  Valid: Boolean;
begin
  Bounds := TRectF.Empty;
  Valid := False;
  for I := 0 to High(Layers) do
    if TryGetScreenLayoutLayerBounds(Layers[I], LayerBounds) then
    begin
      if not Valid then
      begin
        Bounds := LayerBounds;
        Valid := True;
      end
      else
        Bounds := TRectF.Union(Bounds, LayerBounds);
    end;
  if Valid then
    Result := Bounds.CenterPoint
  else
    Result := TPointF.Zero;
end;

constructor TScreenLayoutFlipLayersCommand.Create(ADocument: TVectArtDocument;
  const Targets: TArray<TVectArtLayer>; const AxisCenter: TPointF;
  Direction: TScreenLayoutFlipDirection);
var
  AfterLayer: TVectArtLayer;
  I: Integer;
begin
  inherited Create;
  FDocument := ADocument;
  FTargets := Copy(Targets);
  FBefore := TObjectList<TVectArtLayer>.Create(True);
  FAfter := TObjectList<TVectArtLayer>.Create(True);
  for I := 0 to High(FTargets) do
  begin
    FBefore.Add(CloneScreenLayoutLayer(FTargets[I], FTargets[I].Name));
    AfterLayer := CloneScreenLayoutLayer(FTargets[I], FTargets[I].Name);
    ReflectLayer(AfterLayer, AxisCenter, Direction);
    FAfter.Add(AfterLayer);
  end;
end;

destructor TScreenLayoutFlipLayersCommand.Destroy;
begin
  FAfter.Free;
  FBefore.Free;
  inherited Destroy;
end;

procedure TScreenLayoutFlipLayersCommand.Apply(
  const Values: TObjectList<TVectArtLayer>);
var
  I: Integer;
begin
  if FDocument = nil then
    Exit;
  FDocument.BeginUpdate;
  try
    for I := 0 to Min(High(FTargets), Values.Count - 1) do
      AssignTransformValues(Values[I], FTargets[I]);
    FDocument.Changed;
  finally
    FDocument.EndUpdate;
  end;
end;

procedure TScreenLayoutFlipLayersCommand.Execute;
begin
  Apply(FAfter);
end;

procedure TScreenLayoutFlipLayersCommand.Undo;
begin
  Apply(FBefore);
end;

procedure FlipScreenLayoutSelection(Document: TVectArtDocument;
  EditHistory: TVectArtEditHistory; EditorState: TVectArtEditorState;
  Direction: TScreenLayoutFlipDirection);
var
  Command: TScreenLayoutFlipLayersCommand;
  Layers: TArray<TVectArtLayer>;
begin
  if not CanFlipScreenLayoutSelection(Document, EditorState) then
    Exit;
  Layers := SelectedLayers(Document, EditorState);
  Command := TScreenLayoutFlipLayersCommand.Create(Document, Layers,
    SelectionCenter(Layers), Direction);
  Command.Execute;
  if EditHistory <> nil then
    EditHistory.AddApplied(Command)
  else
    Command.Free;
end;

end.
