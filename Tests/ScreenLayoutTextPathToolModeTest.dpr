program ScreenLayoutTextPathToolModeTest;

{$APPTYPE CONSOLE}

uses
  System.Classes,
  System.Math,
  System.SysUtils,
  System.Types,
  Vcl.Controls,
  Vcl.Graphics,
  ScreenLayoutCanvasInteraction in
    '..\Source\Editor\Interaction\ScreenLayoutCanvasInteraction.pas',
  ScreenLayoutGeometry in
    '..\Source\Core\Geometry\ScreenLayoutGeometry.pas',
  ScreenLayoutSelectionGeometry in
    '..\Source\Editor\Interaction\ScreenLayoutSelectionGeometry.pas',
  ScreenLayoutShapeCreation in
    '..\Source\Editor\Creation\ScreenLayoutShapeCreation.pas',
  ScreenLayoutDocument in '..\Source\Core\Model\ScreenLayoutDocument.pas',
  ScreenLayoutDocumentJsonReader in
    '..\Source\Persistence\ScreenLayoutDocumentJsonReader.pas',
  ScreenLayoutDocumentJsonWriter in
    '..\Source\Persistence\ScreenLayoutDocumentJsonWriter.pas',
  ScreenLayoutEditHistory in
    '..\Source\Core\Model\ScreenLayoutEditHistory.pas',
  ScreenLayoutTextCommands in
    '..\Source\Core\Commands\ScreenLayoutTextCommands.pas',
  ScreenLayoutEditorState in
    '..\Source\Core\Model\ScreenLayoutEditorState.pas',
  ScreenLayoutRenderer in '..\Source\Rendering\ScreenLayoutRenderer.pas',
  TextRendererSkiaRuntime in
    '..\Lib\TextRenderer\TextRendererSkiaRuntime.pas';

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
    raise Exception.Create(MessageText);
end;

procedure CheckTextPathFrameTransform;
var
  Document: TVectArtDocument;
  Geometry: TVectArtSelectionGeometry;
  History: TVectArtEditHistory;
  I: Integer;
  Interaction: TVectArtCanvasInteraction;
  Layer: TScreenLayoutTextPathLayer;
  LogicalQuad: TVectArtQuad;
  RotationPoint: TPoint;
  ScreenQuad: TVectArtScreenQuad;
  Vertices: TArray<TScreenLayoutVertex>;
begin
  Document := TVectArtDocument.Create;
  History := TVectArtEditHistory.Create;
  Interaction := TVectArtCanvasInteraction.Create;
  try
    Document.SetCanvasSize(200, 100);
    SetLength(Vertices, 3);
    for I := 0 to High(Vertices) do
    begin
      Vertices[I].Kind := slvkSharp;
      Vertices[I].OutgoingSegment := slskLine;
    end;
    Vertices[0].Position := TPointF.Create(-40, 0);
    Vertices[1].Position := TPointF.Create(0, 0);
    Vertices[2].Position := TPointF.Create(40, 0);
    Layer := TScreenLayoutTextPathLayer.Create('Text Path',
      TRectF.Create(-40, -20, 40, 0), 'ABC', 'Yu Gothic UI', 20, 80,
      clWhite, Vertices);
    Document.InsertLayer(1, Layer);
    Document.SelectedIndex := 1;
    Interaction.EditHistory := History;
    Interaction.Configure(Document, Rect(0, 0, 200, 100), 1);

    Check(Interaction.MouseDown(mbLeft, [], 90, 40),
      'text path frame move did not start');
    Check(Interaction.MouseMove([ssLeft], 100, 45),
      'text path frame move did not update');
    Check(Interaction.MouseUp(mbLeft),
      'text path frame move did not commit');
    Vertices := Layer.EditablePathVertices;
    Check(SameValue(Layer.Bounds.Left, -30.0) and
      SameValue(Layer.Bounds.Top, -15.0) and
      SameValue(Vertices[0].Position.X, -30.0) and
      SameValue(Vertices[0].Position.Y, 5.0),
      'text path frame move did not move bounds and path together');
    History.Undo;
    Vertices := Layer.EditablePathVertices;
    Check(SameValue(Layer.Bounds.Left, -40.0) and
      SameValue(Vertices[0].Position.X, -40.0) and
      SameValue(Vertices[0].Position.Y, 0.0),
      'text path frame move undo did not restore the whole object');

    LogicalQuad := RectangleCorners(Layer.Bounds, Layer.RotationDegrees);
    for I := 0 to High(ScreenQuad) do
      ScreenQuad[I] := Point(Round(LogicalQuad[I].X + 100),
        Round(LogicalQuad[I].Y + 50));
    Geometry := BuildRotatedSelectionGeometry(ScreenQuad,
      SelectionFrameOffset(0, 1));
    RotationPoint := Geometry.PrimaryRotationHandle.CenterPoint;
    Check(Interaction.MouseDown(mbLeft, [], RotationPoint.X,
      RotationPoint.Y), 'text path rotation did not start');
    Check(Interaction.MouseMove([ssLeft], 150, 40),
      'text path rotation did not update');
    Check(Interaction.MouseUp(mbLeft),
      'text path rotation did not commit');
    Vertices := Layer.EditablePathVertices;
    Check(SameValue(Layer.RotationDegrees, 90.0, 0.5) and
      SameValue(Vertices[0].Position.X, Vertices[1].Position.X, 0.5) and
      SameValue(Vertices[1].Position.X, Vertices[2].Position.X, 0.5),
      'text path rotation did not rotate frame and path together');
    History.Undo;
    Vertices := Layer.EditablePathVertices;
    Check(SameValue(Layer.RotationDegrees, 0.0, 0.5) and
      SameValue(Vertices[0].Position.X, -40.0, 0.5) and
      SameValue(Vertices[2].Position.X, 40.0, 0.5),
      'text path rotation undo did not restore the whole object');
  finally
    Interaction.Free;
    History.Free;
    Document.Free;
  end;
end;

procedure CheckSingleLineTextPath;
var
  Layer: TScreenLayoutTextPathLayer;
  Vertices: TArray<TScreenLayoutVertex>;
begin
  SetLength(Vertices, 2);
  Vertices[0].Position := TPointF.Create(0, 0);
  Vertices[1].Position := TPointF.Create(100, 0);
  Layer := TScreenLayoutTextPathLayer.Create('Text Path',
    TRectF.Create(0, -20, 100, 0), 'A' + sLineBreak + 'B',
    'Yu Gothic UI', 20, 100, clWhite, Vertices);
  try
    Check(Layer.Text = 'A B',
      'text path constructor retained a line break');
    Layer.Text := 'C'#13'D'#10'E';
    Check(Layer.Text = 'C D E',
      'text path accepted a line break after creation');
  finally
    Layer.Free;
  end;
end;

procedure CheckPersistenceAndRendering;
var
  Buffer: TVectArtRenderBuffer;
  Document: TVectArtDocument;
  ErrorMessage: string;
  I: Integer;
  Layer: TScreenLayoutTextPathLayer;
  Loaded: TVectArtDocument;
  LoadedLayer: TScreenLayoutTextPathLayer;
  NearPathPixelCount: Integer;
  OutlinedInputPixelCount: Integer;
  PlainInputPixelCount: Integer;
  Serialized: string;
  Vertices: TArray<TScreenLayoutVertex>;
  X: Integer;
  Y: Integer;
begin
  Document := TVectArtDocument.Create;
  Loaded := TVectArtDocument.Create;
  Buffer := TVectArtRenderBuffer.Create;
  try
    Document.SetCanvasSize(200, 100);
    Document.CanvasLayer.Transparent := True;
    SetLength(Vertices, 3);
    for I := 0 to High(Vertices) do
    begin
      Vertices[I].Kind := slvkSharp;
      Vertices[I].OutgoingSegment := slskLine;
    end;
    Vertices[0].Position := TPointF.Create(-60, 20);
    Vertices[1].Position := TPointF.Create(0, 20);
    Vertices[2].Position := TPointF.Create(60, 20);
    Layer := TScreenLayoutTextPathLayer.Create('Text Path',
      TRectF.Create(-60, -40, 60, -20), 'Text path', 'Yu Gothic UI',
      24, 120, clWhite, Vertices);
    Layer.LetterSpacingRatio := 0.1;
    Document.InsertLayer(1, Layer);

    Serialized := SerializeVectArtDocument(Document);
    Check(Pos('"type":"textPath"', Serialized) > 0,
      'text path JSON type was not serialized');
    Check(TryDeserializeVectArtDocument(Serialized, Loaded, ErrorMessage),
      'text path JSON was not loaded: ' + ErrorMessage);
    Check((Loaded.LayerCount = 2) and
      (Loaded[1] is TScreenLayoutTextPathLayer),
      'text path JSON was restored as another layer type');
    LoadedLayer := TScreenLayoutTextPathLayer(Loaded[1]);
    Vertices := LoadedLayer.EditablePathVertices;
    Check((Length(Vertices) = 3) and
      SameValue(Vertices[0].Position.X, -60.0) and
      SameValue(Vertices[2].Position.Y, 20.0),
      'contained path vertices changed during JSON round trip');
    Check(SameValue(LoadedLayer.LetterSpacingRatio, 0.0, 0.0001),
      'text path JSON restored discarded letter spacing');

    TTextRendererSkiaRuntime.Acquire(
      ExtractFilePath(ParamStr(0)) + 'sk4d.dll');
    try
      RenderVectArtDocument(Loaded, Buffer, 200, 100);
    finally
      TTextRendererSkiaRuntime.Release;
    end;
    NearPathPixelCount := 0;
    for Y := 45 to 70 do
      for X := 20 to 179 do
        if Buffer.Pixels[Y * 200 + X].A <> 0 then
          Inc(NearPathPixelCount);
    Check(NearPathPixelCount > 0,
      'text was not rendered with its lower edge on the contained path');

    TTextRendererSkiaRuntime.Acquire(
      ExtractFilePath(ParamStr(0)) + 'sk4d.dll');
    try
      RenderVectArtDocument(Loaded, Buffer, 200, 100, 0, LoadedLayer);
    finally
      TTextRendererSkiaRuntime.Release;
    end;
    PlainInputPixelCount := 0;
    for Y := 5 to 35 do
      for X := 20 to 179 do
        if Buffer.Pixels[Y * 200 + X].A <> 0 then
          Inc(PlainInputPixelCount);
    Check(PlainInputPixelCount > 0,
      'text input preview still adopted the contained path');

    TTextRendererSkiaRuntime.Acquire(
      ExtractFilePath(ParamStr(0)) + 'sk4d.dll');
    try
      RenderVectArtDocument(Loaded, Buffer, 200, 100, 0, LoadedLayer,
        clBlack);
    finally
      TTextRendererSkiaRuntime.Release;
    end;
    OutlinedInputPixelCount := 0;
    for Y := 5 to 35 do
      for X := 20 to 179 do
        if Buffer.Pixels[Y * 200 + X].A <> 0 then
          Inc(OutlinedInputPixelCount);
    Check(OutlinedInputPixelCount > PlainInputPixelCount,
      'text input contrast outline was not rendered');
  finally
    Buffer.Free;
    Loaded.Free;
    Document.Free;
  end;
end;

procedure CheckSharedPathEditing;
var
  CaptureNeeded: Boolean;
  Document: TVectArtDocument;
  History: TVectArtEditHistory;
  Interaction: TVectArtCanvasInteraction;
  Layer: TScreenLayoutTextPathLayer;
  SpacingHandles: TScreenLayoutTextSpacingHandles;
  TextData: TScreenLayoutTextData;
  Vertices: TArray<TScreenLayoutVertex>;
begin
  Document := TVectArtDocument.Create;
  History := TVectArtEditHistory.Create;
  Interaction := TVectArtCanvasInteraction.Create;
  try
    Document.SetCanvasSize(200, 100);
    SetLength(Vertices, 3);
    Vertices[0].Position := TPointF.Create(-40, 0);
    Vertices[1].Position := TPointF.Create(0, 0);
    Vertices[2].Position := TPointF.Create(40, 0);
    Vertices[0].OutgoingSegment := slskLine;
    Vertices[1].OutgoingSegment := slskLine;
    Vertices[2].OutgoingSegment := slskLine;
    Vertices[0].Kind := slvkSharp;
    Vertices[1].Kind := slvkSharp;
    Vertices[2].Kind := slvkSharp;
    Layer := TScreenLayoutTextPathLayer.Create('Text Path',
      TRectF.Create(-40, -20, 40, 0), 'ABC', 'Yu Gothic UI', 20, 80,
      clWhite, Vertices);
    Document.InsertLayer(1, Layer);
    Document.SelectedIndex := 1;
    Check(SameValue(Layer.WrapWidth, 0.0) and
      SameValue(Layer.LetterSpacingRatio, 0.0) and
      (Length(Layer.IndividualLetterSpacingRatios) = 0),
      'text path retained wrapping or letter spacing');
    TextData := CaptureScreenLayoutTextData(Layer);
    TextData.WrapWidth := 10;
    TextData.LetterSpacingRatio := 0.5;
    SetLength(TextData.IndividualLetterSpacingRatios, 2);
    TextData.IndividualLetterSpacingRatios[0] := 0.25;
    TextData.IndividualLetterSpacingRatios[1] := -0.25;
    Document.SetTextData(1, TextData);
    Check(SameValue(Layer.WrapWidth, 0.0) and
      SameValue(Layer.LetterSpacingRatio, 0.0) and
      (Length(Layer.IndividualLetterSpacingRatios) = 0),
      'text path accepted wrapping or letter spacing through document data');
    Interaction.EditHistory := History;
    Interaction.Configure(Document, Rect(0, 0, 200, 100), 1);
    Interaction.SetVertexStructureEditing(True, False);
    Check(not Interaction.SelectedTextSpacingHandles(SpacingHandles) and
      (Length(Interaction.SelectedTextIndividualSpacingHandles) = 0),
      'text path exposed text spacing controls');

    Check(Layer.Kind = vlkTextPath,
      'text path layer did not retain its dedicated kind');
    Check(Layer.SupportsPathEditing,
      'text path layer did not expose shared path editing');
    Check(Length(Interaction.SelectedPathVertexRects) = 3,
      'shared path interaction did not expose text path vertices');
    Check(Length(Interaction.SelectedPathPoints) = 3,
      'shared path interaction did not expose the text path guide');
    Check(Interaction.MouseDownSelectedVertex(mbLeft, [], 100, 50,
      CaptureNeeded) and CaptureNeeded,
      'shared path interaction could not start a text path vertex drag');
    Check(Interaction.MouseMove([ssLeft], 105, 55),
      'shared path interaction could not drag a text path vertex');
    Check(Interaction.MouseUp(mbLeft),
      'shared path interaction did not commit a text path vertex drag');
    Vertices := Layer.EditablePathVertices;
    Check((Vertices[1].Position.X = 5) and
      (Vertices[1].Position.Y = 5),
      'text path vertex was not updated');
    Check(SameValue(Layer.Bounds.Top, -20.0) and
      SameValue(Layer.Bounds.Bottom, 5.0),
      'text path frame did not follow the edited path');
    Check(History.CanUndo, 'text path vertex drag was not added to history');
    History.Undo;
    Vertices := Layer.EditablePathVertices;
    Check((Vertices[1].Position.X = 0) and
      (Vertices[1].Position.Y = 0),
      'text path vertex undo did not use the shared path command');
    Check(SameValue(Layer.Bounds.Top, -20.0) and
      SameValue(Layer.Bounds.Bottom, 0.0),
      'text path frame undo did not follow the restored path');
  finally
    Interaction.Free;
    History.Free;
    Document.Free;
  end;
end;

procedure CheckTextPathCreation;
var
  Creation: TVectArtShapeCreation;
  Document: TVectArtDocument;
  EditorState: TVectArtEditorState;
  History: TVectArtEditHistory;
  Layer: TScreenLayoutTextPathLayer;
  Vertices: TArray<TScreenLayoutVertex>;
begin
  Creation := TVectArtShapeCreation.Create;
  Document := TVectArtDocument.Create;
  EditorState := TVectArtEditorState.Create;
  History := TVectArtEditHistory.Create;
  try
    Document.SetCanvasSize(200, 100);
    EditorState.ActivateTool(vetText);
    EditorState.ActivateTool(vetText);
    Creation.Configure(Document, History, EditorState,
      Rect(0, 0, 200, 100), 1);
    Check(not Creation.KeyDown(Ord('B'), []) and
      not Creation.KeyDown(Ord('V'), []) and
      (EditorState.NextVertexKind = slvkSharp),
      'B/V still changed the path vertex mode');
    Check(Creation.MouseDown(mbLeft, [], 60, 50),
      'text path creation did not accept the first point');
    Check(Creation.MouseDown(mbLeft, [], 140, 50),
      'text path creation did not accept the second point');
    Check(Creation.FinishPath(False),
      'text path creation did not finish');
    Check((Document.LayerCount = 2) and
      (Document[1] is TScreenLayoutTextPathLayer),
      'text path creation did not insert a text path layer');
    Layer := TScreenLayoutTextPathLayer(Document[1]);
    Vertices := Layer.EditablePathVertices;
    Check((Length(Vertices) = 2) and
      (Vertices[0].Position.X = -40) and
      (Vertices[1].Position.X = 40),
      'text path creation did not reuse open path coordinates');
    Check(Layer.Text = 'Text',
      'text path creation did not set the initial text');
    History.Undo;
    Check(Document.LayerCount = 1,
      'text path creation undo did not remove the layer');
    History.Redo;
    Check((Document.LayerCount = 2) and
      (Document[1] is TScreenLayoutTextPathLayer),
      'text path creation redo did not restore the layer');
  finally
    Creation.Free;
    History.Free;
    EditorState.Free;
    Document.Free;
  end;
end;

procedure CheckDeferredTextPathCreation;
var
  BeforeSelection: TArray<Integer>;
  Creation: TVectArtShapeCreation;
  Document: TVectArtDocument;
  EditorState: TVectArtEditorState;
  History: TVectArtEditHistory;
  LayerIndex: Integer;
begin
  Creation := TVectArtShapeCreation.Create;
  Document := TVectArtDocument.Create;
  EditorState := TVectArtEditorState.Create;
  History := TVectArtEditHistory.Create;
  try
    Document.SetCanvasSize(200, 100);
    EditorState.ActivateTool(vetText);
    EditorState.ActivateTool(vetText);
    Creation.DeferTextPathHistory := True;
    Creation.Configure(Document, History, EditorState,
      Rect(0, 0, 200, 100), 1);
    Check(Creation.MouseDown(mbLeft, [], 60, 50) and
      Creation.MouseDown(mbLeft, [], 140, 50) and
      Creation.FinishPath(False),
      'deferred text path creation did not finish');
    Check(not History.CanUndo,
      'text path insertion was recorded before initial text input');
    Check(Creation.TakeCreatedTextPath(LayerIndex, BeforeSelection) and
      (LayerIndex = 1),
      'deferred text path was not handed to initial text input');
    Check((Document[LayerIndex] is TScreenLayoutTextPathLayer) and
      (TScreenLayoutTextPathLayer(Document[LayerIndex]).Text = 'Text'),
      'initial text path value is not the selected default text');
    Check(not Creation.TakeCreatedTextPath(LayerIndex, BeforeSelection),
      'deferred text path handoff was not consumed');
  finally
    Creation.Free;
    History.Free;
    EditorState.Free;
    Document.Free;
  end;
end;

var
  EditorState: TVectArtEditorState;
begin
  EditorState := TVectArtEditorState.Create;
  try
    EditorState.ActivateTool(vetText);
    Check(EditorState.CurrentTool = vetText,
      'first text activation did not select normal text');
    EditorState.ActivateTool(vetText);
    Check(EditorState.CurrentTool = vetTextPath,
      'repeated text activation did not select text path');
    EditorState.ActivateTool(vetText);
    Check(EditorState.CurrentTool = vetText,
      'third text activation did not return to normal text');
    EditorState.ActivateTool(vetSelect);
    EditorState.ActivateTool(vetText);
    Check(EditorState.CurrentTool = vetText,
      'text activation from another tool did not start in normal mode');
    EditorState.NextVertexKind := slvkSharp;
    EditorState.ActivateTool(vetPath);
    EditorState.ActivateTool(vetPath);
    Check((EditorState.CurrentTool = vetPath) and
      (EditorState.NextVertexKind = slvkBezier),
      'repeated path activation did not toggle the vertex mode');
  finally
    EditorState.Free;
  end;
  CheckTextPathCreation;
  CheckDeferredTextPathCreation;
  CheckSharedPathEditing;
  CheckTextPathFrameTransform;
  CheckSingleLineTextPath;
  CheckPersistenceAndRendering;
  Writeln('PASS');
end.
