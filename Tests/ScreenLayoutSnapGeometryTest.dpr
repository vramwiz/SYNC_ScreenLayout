program ScreenLayoutSnapGeometryTest;

{$APPTYPE CONSOLE}

uses
  System.Classes,
  System.Math,
  System.SysUtils,
  System.Types,
  Vcl.Controls,
  Vcl.Graphics,
  ScreenLayoutDocument in
    '..\Source\Core\Model\ScreenLayoutDocument.pas',
  ScreenLayoutEditorState in
    '..\Source\Core\Model\ScreenLayoutEditorState.pas',
  ScreenLayoutEditHistory in
    '..\Source\Core\Model\ScreenLayoutEditHistory.pas',
  ScreenLayoutSnapGeometry in
    '..\Source\Core\Geometry\ScreenLayoutSnapGeometry.pas',
  ScreenLayoutGeometry in
    '..\Source\Core\Geometry\ScreenLayoutGeometry.pas',
  ScreenLayoutShapeCreation in
    '..\Source\Editor\Creation\ScreenLayoutShapeCreation.pas',
  ScreenLayoutCanvasInteraction in
    '..\Source\Editor\Interaction\ScreenLayoutCanvasInteraction.pas',
  ScreenLayoutSelectionGeometry in
    '..\Source\Editor\Interaction\ScreenLayoutSelectionGeometry.pas',
  ScreenLayoutGroupInteraction in
    '..\Source\Editor\Interaction\ScreenLayoutGroupInteraction.pas';

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
    raise Exception.Create(MessageText);
end;

function HasHighlightedGuide(
  const Guides: TArray<TScreenLayoutSnapGuide>): Boolean; forward;
function HasGuideAxis(const Guides: TArray<TScreenLayoutSnapGuide>;
  Axis: TScreenLayoutSnapAxis): Boolean; forward;

procedure CheckMoveModifiers;
var
  Document: TVectArtDocument;
  Interaction: TVectArtCanvasInteraction;
  Moving: TVectArtRectangleLayer;
begin
  Document := TVectArtDocument.Create;
  Interaction := TVectArtCanvasInteraction.Create;
  try
    Document.SetCanvasSize(400, 300);
    Document.InsertLayer(Document.LayerCount,
      TVectArtRectangleLayer.Create('Target',
        TRectF.Create(40, 30, 80, 70), clRed));
    Moving := TVectArtRectangleLayer.Create('Moving',
      TRectF.Create(-80, -40, -60, -20), clBlue);
    Document.InsertLayer(Document.LayerCount, Moving);
    Document.SetSelectedLayers([2]);
    Interaction.Configure(Document, Rect(0, 0, 400, 300), 1);

    Check(Interaction.MouseDown(mbLeft, [], 130, 120),
      'Object move did not start');
    Check(Interaction.MouseMove([ssLeft], 228, 169),
      'Snapped object move did not update');
    Check(SameValue(Moving.Bounds.Left, 20.0) and
      SameValue(Moving.Bounds.Top, 10.0) and
      HasHighlightedGuide(Interaction.SnapGuides),
      'Object move did not snap to the target object');
    Interaction.MouseUp(mbLeft);

    Moving.Bounds := TRectF.Create(-80, -40, -60, -20);
    Check(Interaction.MouseDown(mbLeft, [], 130, 120),
      'Alt object move did not start');
    Check(Interaction.MouseMove([ssLeft, ssAlt], 228, 169),
      'Alt object move did not update');
    Check(SameValue(Moving.Bounds.Left, 18.0) and
      SameValue(Moving.Bounds.Top, 9.0) and
      (Length(Interaction.SnapGuides) = 0),
      'Alt did not disable object move snapping');
    Interaction.MouseUp(mbLeft);
  finally
    Interaction.Free;
    Document.Free;
  end;
end;

procedure CheckOverlappingLayerSelection;
var
  BottomLayer: TVectArtRectangleLayer;
  Document: TVectArtDocument;
  HitLayers: TArray<Integer>;
  Interaction: TVectArtCanvasInteraction;
  MiddleLayer: TVectArtRectangleLayer;
  TopLayer: TVectArtRectangleLayer;
begin
  Document := TVectArtDocument.Create;
  Interaction := TVectArtCanvasInteraction.Create;
  try
    Document.SetCanvasSize(400, 300);
    BottomLayer := TVectArtRectangleLayer.Create('Bottom',
      TRectF.Create(-20, -20, 20, 20), clRed);
    MiddleLayer := TVectArtRectangleLayer.Create('Middle',
      TRectF.Create(-20, -20, 20, 20), clGreen);
    TopLayer := TVectArtRectangleLayer.Create('Top',
      TRectF.Create(-20, -20, 20, 20), clBlue);
    Document.InsertLayer(Document.LayerCount, BottomLayer);
    Document.InsertLayer(Document.LayerCount, MiddleLayer);
    Document.InsertLayer(Document.LayerCount, TopLayer);
    Document.SetSelectedLayers([2]);
    Interaction.Configure(Document, Rect(0, 0, 400, 300), 1);
    HitLayers := Interaction.LayersAt(200, 150);
    Check((Length(HitLayers) = 3) and (HitLayers[0] = 3) and
      (HitLayers[1] = 2) and (HitLayers[2] = 1),
      'Overlapping layer candidates were not returned front to back');

    Check(Interaction.MouseDown(mbLeft, [], 200, 150),
      'Protected overlap drag did not start');
    Check(Interaction.MouseMove([ssLeft], 220, 150),
      'Protected overlap drag did not update');
    Check(Interaction.MouseUp(mbLeft),
      'Protected overlap drag did not finish');
    Check(SameValue(MiddleLayer.Bounds.Left, 0.0) and
      SameValue(TopLayer.Bounds.Left, -20.0) and
      SameValue(BottomLayer.Bounds.Left, -20.0) and
      (Document.SelectedIndex = 2),
      'Top layer stole a drag from the selected middle layer');

    MiddleLayer.Bounds := TRectF.Create(-20, -20, 20, 20);
    Check(Interaction.MouseDown(mbLeft, [], 200, 150) and
      Interaction.MouseUp(mbLeft), 'Normal overlap click was not handled');
    Check(Document.SelectedIndex = 3,
      'Normal click did not select the top layer');

    Document.SetSelectedLayers([2]);
    Check(Interaction.MouseDown(mbLeft, [ssAlt], 200, 150) and
      Interaction.MouseUp(mbLeft), 'Select-behind click was not handled');
    Check(Document.SelectedIndex = 1,
      'Alt click did not select the layer behind the current selection');

    Check(Interaction.MouseDown(mbLeft, [ssAlt], 200, 150) and
      Interaction.MouseUp(mbLeft), 'Wrapped select-behind was not handled');
    Check(Document.SelectedIndex = 3,
      'Alt click did not wrap from the bottom to the top layer');
  finally
    Interaction.Free;
    Document.Free;
  end;
end;

procedure CheckOpenGroupChildMoveSnap;
var
  Child: TVectArtRectangleLayer;
  Document: TVectArtDocument;
  GroupDrag: TScreenLayoutGroupDrag;
  ParentGroup: TScreenLayoutGroupLayer;
begin
  Document := TVectArtDocument.Create;
  GroupDrag := TScreenLayoutGroupDrag.Create;
  try
    Document.SetCanvasSize(400, 300);
    Document.InsertLayer(Document.LayerCount,
      TVectArtRectangleLayer.Create('Target',
        TRectF.Create(40, 30, 80, 70), clRed));
    ParentGroup := TScreenLayoutGroupLayer.Create('Parent');
    Child := TVectArtRectangleLayer.Create('Child',
      TRectF.Create(-80, -40, -60, -20), clBlue);
    ParentGroup.AddChild(Child);
    Document.InsertLayer(Document.LayerCount, ParentGroup);

    GroupDrag.BeginMove(Document, [Child], Point(130, 120));
    Check(GroupDrag.UpdateMoveOrResize([], 228, 169, 1),
      'Open-group child move did not update');
    Check(SameValue(Child.Bounds.Left, 20.0) and
      SameValue(Child.Bounds.Top, 10.0) and
      HasHighlightedGuide(GroupDrag.SnapGuides),
      'Open-group child did not snap to the outside target');
    GroupDrag.Finish(nil);
  finally
    GroupDrag.Free;
    Document.Free;
  end;
end;

procedure CheckResizeAndRotationModifiers;
var
  Document: TVectArtDocument;
  Geometry: TVectArtSelectionGeometry;
  HandlePoint: TPoint;
  Interaction: TVectArtCanvasInteraction;
  Moving: TVectArtRectangleLayer;
  RotationPoint: TPoint;
begin
  Document := TVectArtDocument.Create;
  Interaction := TVectArtCanvasInteraction.Create;
  try
    Document.SetCanvasSize(400, 300);
    Document.InsertLayer(Document.LayerCount,
      TVectArtRectangleLayer.Create('Target',
        TRectF.Create(40, 30, 80, 70), clRed));
    Moving := TVectArtRectangleLayer.Create('Moving',
      TRectF.Create(-80, -40, -60, -20), clBlue);
    Document.InsertLayer(Document.LayerCount, Moving);
    Document.SetSelectedLayers([2]);
    Interaction.Configure(Document, Rect(0, 0, 400, 300), 1);
    Geometry := BuildSelectionGeometry(Rect(120, 110, 140, 130),
      SelectionFrameOffset(0, 1));
    HandlePoint := Geometry.Handles[vshRight].CenterPoint;

    Check(Interaction.MouseDown(mbLeft, [], HandlePoint.X, HandlePoint.Y),
      'Object resize did not start');
    Check(Interaction.MouseMove([ssLeft], HandlePoint.X + 98,
      HandlePoint.Y), 'Snapped object resize did not update');
    Check(SameValue(Moving.Bounds.Right, 40.0) and
      HasHighlightedGuide(Interaction.SnapGuides),
      'Object resize did not snap its moving edge');
    Interaction.MouseUp(mbLeft);

    Moving.Bounds := TRectF.Create(-80, -40, -60, -20);
    Check(Interaction.MouseDown(mbLeft, [], HandlePoint.X, HandlePoint.Y),
      'Alt object resize did not start');
    Check(Interaction.MouseMove([ssLeft, ssAlt], HandlePoint.X + 98,
      HandlePoint.Y), 'Alt object resize did not update');
    Check(SameValue(Moving.Bounds.Right, 38.0) and
      (Length(Interaction.SnapGuides) = 0),
      'Alt did not disable object resize snapping');
    Interaction.MouseUp(mbLeft);

    Moving.Bounds := TRectF.Create(-50, -25, 50, 25);
    Geometry := BuildSelectionGeometry(Rect(150, 125, 250, 175),
      SelectionFrameOffset(0, 1));
    RotationPoint := Geometry.PrimaryRotationHandle.CenterPoint;
    Check(Interaction.MouseDown(mbLeft, [], RotationPoint.X,
      RotationPoint.Y), 'Major-angle rotation snap did not start');
    Check(Interaction.MouseMove([ssLeft], 241, 106),
      'Major-angle rotation snap did not update');
    Check(SameValue(Moving.RotationDegrees, 45.0, 0.1) and
      Interaction.RotationSnapped,
      'Rotation did not snap to the nearby 45-degree angle');
    Interaction.MouseUp(mbLeft);

    Moving.RotationDegrees := 0;
    Check(Interaction.MouseDown(mbLeft, [], RotationPoint.X,
      RotationPoint.Y), '30-degree rotation snap did not start');
    Check(Interaction.MouseMove([ssLeft], 228, 101),
      '30-degree rotation snap did not update');
    Check(SameValue(Moving.RotationDegrees, 30.0, 0.1) and
      Interaction.RotationSnapped,
      'Rotation did not snap to the nearby 30-degree angle');
    Interaction.MouseUp(mbLeft);

    Moving.RotationDegrees := 0;
    Check(Interaction.MouseDown(mbLeft, [], RotationPoint.X,
      RotationPoint.Y), 'Alt rotation did not start');
    Check(Interaction.MouseMove([ssLeft, ssAlt], 241, 106),
      'Alt rotation did not update');
    Check((Moving.RotationDegrees > 42.0) and
      (Moving.RotationDegrees < 44.0),
      'Alt did not disable major-angle rotation snapping');
    Check(not Interaction.RotationSnapped,
      'Alt rotation incorrectly displayed the snap indicator');
    Interaction.MouseUp(mbLeft);

    Moving.RotationDegrees := 0;
    Check(Interaction.MouseDown(mbLeft, [], RotationPoint.X,
      RotationPoint.Y), 'Constrained rotation did not start');
    Check(Interaction.MouseMove([ssLeft, ssShift], 221, 94),
      'Constrained rotation did not update');
    Check(SameValue(Moving.RotationDegrees, 15.0, 0.1),
      'Shift did not constrain rotation to 15 degree increments');
    Interaction.MouseUp(mbLeft);
  finally
    Interaction.Free;
    Document.Free;
  end;
end;

procedure CheckRotationReset;
var
  Document: TVectArtDocument;
  Geometry: TVectArtSelectionGeometry;
  History: TVectArtEditHistory;
  I: Integer;
  Interaction: TVectArtCanvasInteraction;
  LogicalQuad: TVectArtQuad;
  PathLayer: TVectArtPathLayer;
  RectangleLayer: TVectArtRectangleLayer;
  RotationPoint: TPoint;
  ScreenQuad: TVectArtScreenQuad;
  Vertices: TArray<TScreenLayoutVertex>;
begin
  Document := TVectArtDocument.Create;
  History := TVectArtEditHistory.Create;
  Interaction := TVectArtCanvasInteraction.Create;
  try
    Document.SetCanvasSize(400, 300);
    RectangleLayer := TVectArtRectangleLayer.Create('Rectangle',
      TRectF.Create(-50, -25, 50, 25), clBlue);
    Document.InsertLayer(Document.LayerCount, RectangleLayer);
    Document.SetRectangleRotation(1, 30);
    Document.SetSelectedLayers([1]);
    Interaction.EditHistory := History;
    Interaction.Configure(Document, Rect(0, 0, 400, 300), 1);
    Check(Interaction.CanResetSelectedRotation,
      'Rectangle rotation was not reported as resettable');

    LogicalQuad := RectangleCorners(RectangleLayer.Bounds,
      RectangleLayer.RotationDegrees);
    for I := 0 to High(ScreenQuad) do
      ScreenQuad[I] := Point(Round(LogicalQuad[I].X) + 200,
        Round(LogicalQuad[I].Y) + 150);
    Geometry := BuildRotatedSelectionGeometry(ScreenQuad,
      SelectionFrameOffset(0, 1));
    RotationPoint := Geometry.PrimaryRotationHandle.CenterPoint;
    Interaction.MouseDown(mbLeft, [ssDouble], RotationPoint.X,
      RotationPoint.Y);
    Check(SameValue(RectangleLayer.RotationDegrees, 0.0) and
      not Interaction.Dragging and History.CanUndo,
      'Rotation handle double click did not reset to zero');
    History.Undo;
    Check(SameValue(RectangleLayer.RotationDegrees, 30.0),
      'Undo did not restore the rotation before reset');
    History.Redo;
    Check(SameValue(RectangleLayer.RotationDegrees, 0.0),
      'Redo did not restore the zero-degree rotation');

    SetLength(Vertices, 2);
    Vertices[0].Position := TPointF.Create(-20, 0);
    Vertices[1].Position := TPointF.Create(20, 0);
    Vertices[0].Kind := slvkSharp;
    Vertices[1].Kind := slvkSharp;
    Vertices[0].OutgoingSegment := slskLine;
    Vertices[1].OutgoingSegment := slskLine;
    PathLayer := TVectArtPathLayer.Create('Path', Vertices, False);
    Document.InsertLayer(Document.LayerCount, PathLayer);
    Document.SetSelectedLayers([2]);
    Check(not Interaction.CanResetSelectedRotation,
      'Baked path rotation was incorrectly reported as resettable');
  finally
    Interaction.Free;
    History.Free;
    Document.Free;
  end;
end;

procedure CheckVertexSnap;
var
  CaptureNeeded: Boolean;
  Document: TVectArtDocument;
  Interaction: TVectArtCanvasInteraction;
  PathLayer: TVectArtPathLayer;
  Vertices: TArray<TScreenLayoutVertex>;
begin
  Document := TVectArtDocument.Create;
  Interaction := TVectArtCanvasInteraction.Create;
  try
    Document.SetCanvasSize(400, 300);
    Document.InsertLayer(Document.LayerCount,
      TVectArtRectangleLayer.Create('Target',
        TRectF.Create(40, 30, 80, 70), clRed));
    SetLength(Vertices, 2);
    Vertices[0].Position := TPointF.Create(0, 0);
    Vertices[1].Position := TPointF.Create(20, 0);
    Vertices[0].Kind := slvkSharp;
    Vertices[1].Kind := slvkSharp;
    Vertices[0].OutgoingSegment := slskLine;
    Vertices[1].OutgoingSegment := slskLine;
    PathLayer := TVectArtPathLayer.Create('Path', Vertices, False);
    Document.InsertLayer(Document.LayerCount, PathLayer);
    Document.SetSelectedLayers([2]);
    Interaction.Configure(Document, Rect(0, 0, 400, 300), 1);
    Interaction.SetVertexStructureEditing(True, False);

    Check(Interaction.MouseDownSelectedVertex(mbLeft, [], 200, 150,
      CaptureNeeded) and CaptureNeeded, 'Vertex drag did not start');
    Check(Interaction.MouseMove([ssLeft], 238, 178),
      'Snapped vertex drag did not update');
    Vertices := PathLayer.Vertices;
    Check(SameValue(Vertices[0].Position.X, 40.0) and
      SameValue(Vertices[0].Position.Y, 30.0) and
      HasHighlightedGuide(Interaction.SnapGuides),
      'Vertex did not snap to the target object');
    Interaction.MouseUp(mbLeft);

    Check(Interaction.MouseDownSelectedVertex(mbLeft, [], 240, 180,
      CaptureNeeded) and CaptureNeeded,
      'Own-vertex alignment drag did not start');
    Check(Interaction.MouseMove([ssLeft], 218, 190),
      'Own-vertex alignment drag did not update');
    Vertices := PathLayer.Vertices;
    Check(SameValue(Vertices[0].Position.X, 20.0) and
      SameValue(Vertices[0].Position.Y, 40.0) and
      HasGuideAxis(Interaction.SnapGuides, slsaX),
      'Vertex did not align to its own other vertex with a vertical guide');
    Interaction.MouseUp(mbLeft);
  finally
    Interaction.Free;
    Document.Free;
  end;
end;

function HasHighlightedGuide(
  const Guides: TArray<TScreenLayoutSnapGuide>): Boolean;
var
  Guide: TScreenLayoutSnapGuide;
begin
  Result := False;
  for Guide in Guides do
    if Guide.HighlightTarget then
      Exit(True);
end;

function HasGuideAxis(const Guides: TArray<TScreenLayoutSnapGuide>;
  Axis: TScreenLayoutSnapAxis): Boolean;
var
  Guide: TScreenLayoutSnapGuide;
begin
  Result := False;
  for Guide in Guides do
    if Guide.Axis = Axis then
      Exit(True);
end;

procedure CheckCreationModifiers;
var
  Creation: TVectArtShapeCreation;
  Document: TVectArtDocument;
  EditorState: TVectArtEditorState;
  EndPoint: TPoint;
  History: TVectArtEditHistory;
  Points: TArray<TPoint>;
  StartPoint: TPoint;
begin
  Creation := TVectArtShapeCreation.Create;
  Document := TVectArtDocument.Create;
  EditorState := TVectArtEditorState.Create;
  History := TVectArtEditHistory.Create;
  try
    Document.SetCanvasSize(400, 300);
    Document.InsertLayer(Document.LayerCount,
      TVectArtRectangleLayer.Create('Target',
        TRectF.Create(40, 30, 80, 70), clRed));
    EditorState.ActivateTool(vetLine);
    Creation.Configure(Document, History, EditorState,
      Rect(0, 0, 400, 300), 1);

    Check(Creation.MouseDown(mbLeft, [ssAlt], 238, 178) and
      Creation.PreviewLine(StartPoint, EndPoint),
      'Alt line creation did not start');
    Check((StartPoint.X = 238) and (StartPoint.Y = 178) and
      (Length(Creation.SnapGuides) = 0),
      'Alt did not disable point snapping');
    Creation.CancelPath;

    Check(Creation.MouseDown(mbLeft, [], 238, 178) and
      Creation.PreviewLine(StartPoint, EndPoint),
      'Snapped line creation did not start');
    Check((StartPoint.X = 240) and (StartPoint.Y = 180) and
      HasHighlightedGuide(Creation.SnapGuides),
      'Line start did not snap to the target object');
    Creation.CancelPath;

    Check(Creation.MouseDown(mbLeft, [], 100, 100),
      'Constrained line creation did not start');
    Check(Creation.MouseMove([ssLeft, ssShift], 150, 120) and
      Creation.PreviewLine(StartPoint, EndPoint),
      'Constrained line preview was not available');
    Check((EndPoint.X = 150) and (EndPoint.Y = StartPoint.Y),
      'Shift did not constrain the second point horizontally');
    Creation.CancelPath;

    EditorState.ActivateTool(vetPath);
    Creation.Configure(Document, History, EditorState,
      Rect(0, 0, 400, 300), 1);
    Check(Creation.MouseDown(mbLeft, [], 100, 100),
      'Angle-snapped path creation did not place its first vertex');
    Check(Creation.MouseMove([], 151, 128) and
      Creation.PreviewPath(Points),
      'Angle-snapped path preview was not available');
    Check((Length(Points) = 2) and
      (Abs(RadToDeg(ArcTan2(Points[1].Y - Points[0].Y,
        Points[1].X - Points[0].X)) - 30.0) < 1.0) and
      HasGuideAxis(Creation.SnapGuides, slsaAngle),
      'Path segment did not snap to 30 degrees from its previous vertex');
    Creation.CancelPath;

    Check(Creation.MouseDown(mbLeft, [ssAlt], 100, 100),
      'Alt path creation did not place its first vertex');
    Check(Creation.MouseMove([ssAlt], 151, 128) and
      Creation.PreviewPath(Points),
      'Alt path preview was not available');
    Check((Length(Points) = 2) and (Points[1] = Point(151, 128)) and
      not HasGuideAxis(Creation.SnapGuides, slsaAngle),
      'Alt did not disable path segment angle snapping');
    Creation.CancelPath;

    Check(Creation.MouseDown(mbLeft, [], 113, 100),
      'Path creation did not place its first vertex');
    Check(Creation.MouseMove([], 115, 160) and
      Creation.PreviewPath(Points),
      'Path creation did not preview its second vertex');
    Check((Length(Points) = 2) and (Points[1].X = Points[0].X) and
      HasGuideAxis(Creation.SnapGuides, slsaX),
      'New path vertex did not align to its own vertex with a vertical guide');
  finally
    Creation.Free;
    History.Free;
    EditorState.Free;
    Document.Free;
  end;
end;

procedure CheckFreehandCreation;
var
  Creation: TVectArtShapeCreation;
  Document: TVectArtDocument;
  EditorState: TVectArtEditorState;
  History: TVectArtEditHistory;
  PathLayer: TVectArtPathLayer;
  PreviewPoints: TArray<TPoint>;
begin
  Creation := TVectArtShapeCreation.Create;
  Document := TVectArtDocument.Create;
  EditorState := TVectArtEditorState.Create;
  History := TVectArtEditHistory.Create;
  try
    Document.SetCanvasSize(400, 300);
    EditorState.ActivateTool(vetFreehand);
    Creation.Configure(Document, History, EditorState,
      Rect(0, 0, 400, 300), 1);
    Check(Creation.MouseDown(mbLeft, [], 100, 100),
      'Freehand stroke did not start');
    Check(Creation.MouseMove([ssLeft], 104, 102) and
      Creation.MouseMove([ssLeft], 108, 104) and
      Creation.MouseMove([ssLeft], 112, 106) and
      Creation.PreviewPath(PreviewPoints) and
      (Length(PreviewPoints) = 4),
      'Freehand stroke preview did not collect mouse samples');
    Check(Creation.MouseUp(mbLeft, [], 120, 110),
      'Freehand stroke did not finish');
    Check((Document.LayerCount = 2) and
      (Document.SelectedIndex = 1) and
      (Document[1] is TVectArtPathLayer),
      'Freehand stroke was not inserted as one path object');
    PathLayer := TVectArtPathLayer(Document[1]);
    Check((PathLayer.Name = 'Path 1') and not PathLayer.Closed and
      (Length(PathLayer.Vertices) = 2) and
      (PathLayer.Vertices[0].Kind = slvkBezier) and
      (PathLayer.Vertices[1].Kind = slvkBezier) and
      (PathLayer.Vertices[0].OutgoingSegment = slskCubicBezier) and
      History.CanUndo,
      'Freehand input was not converted to an existing smooth path');
    History.Undo;
    Check(Document.LayerCount = 1,
      'Undo did not remove the freehand stroke');
    History.Redo;
    Check((Document.LayerCount = 2) and
      (Document[1] is TVectArtPathLayer),
      'Redo did not restore the freehand stroke');
  finally
    Creation.Free;
    History.Free;
    EditorState.Free;
    Document.Free;
  end;
end;

var
  Document: TVectArtDocument;
  Guides: TArray<TScreenLayoutSnapGuide>;
  SnappedDelta: TPointF;
  SnappedPoint: TPointF;
begin
  Document := TVectArtDocument.Create;
  try
    Document.SetCanvasSize(400, 300);
    Document.InsertLayer(Document.LayerCount,
      TVectArtRectangleLayer.Create('Target',
        TRectF.Create(40, 30, 80, 70), clRed));

    Check(SnapScreenLayoutPoint(Document, TPointF.Create(38, 28), 1,
      False, SnappedPoint, Guides),
      'Point snap did not find the object edges');
    Check(SameValue(SnappedPoint.X, 40.0) and
      SameValue(SnappedPoint.Y, 30.0),
      'Point snap did not align to the object edges');
    Check(HasHighlightedGuide(Guides),
      'Object snap did not identify its target');

    Document.InsertLayer(Document.LayerCount,
      TVectArtRectangleLayer.Create('Moving',
        TRectF.Create(-80, -40, -60, -20), clBlue));
    Document.SetSelectedLayers([2]);
    Check(SnapScreenLayoutMove(Document,
      TRectF.Create(-80, -40, -60, -20), TPointF.Create(98, 49), 1,
      SnappedDelta, Guides), 'Move snap did not find the object edges');
    Check(SameValue(SnappedDelta.X, 100.0) and
      SameValue(SnappedDelta.Y, 50.0),
      'Move snap produced an unexpected delta');
    Check(HasHighlightedGuide(Guides),
      'Move snap did not identify its target');

    Check(SnapScreenLayoutPoint(Document, TPointF.Create(102, 98), 1,
      False, SnappedPoint, Guides), 'Grid fallback did not snap');
    Check(SameValue(SnappedPoint.X, 100.0) and
      SameValue(SnappedPoint.Y, 100.0),
      'Grid fallback used an unexpected coordinate');
    Check(not HasHighlightedGuide(Guides),
      'Grid fallback was reported as an object target');
  finally
    Document.Free;
  end;
  CheckCreationModifiers;
  CheckFreehandCreation;
  CheckMoveModifiers;
  CheckOverlappingLayerSelection;
  CheckOpenGroupChildMoveSnap;
  CheckResizeAndRotationModifiers;
  CheckRotationReset;
  CheckVertexSnap;
  Writeln('PASS');
end.
