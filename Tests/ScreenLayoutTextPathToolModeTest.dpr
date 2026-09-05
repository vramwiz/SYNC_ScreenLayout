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
  ScreenLayoutTextPathCharacterInteraction in
    '..\Source\Editor\Interaction\ScreenLayoutTextPathCharacterInteraction.pas',
  ScreenLayoutTextPathGeometry in
    '..\Source\Core\Geometry\ScreenLayoutTextPathGeometry.pas',
  ScreenLayoutShapeCreation in
    '..\Source\Editor\Creation\ScreenLayoutShapeCreation.pas',
  ScreenLayoutDocument in '..\Source\Core\Model\ScreenLayoutDocument.pas',
  ScreenLayoutDocumentJsonReader in
    '..\Source\Persistence\ScreenLayoutDocumentJsonReader.pas',
  ScreenLayoutDocumentJsonWriter in
    '..\Source\Persistence\ScreenLayoutDocumentJsonWriter.pas',
  ScreenLayoutEditHistory in
    '..\Source\Core\Model\ScreenLayoutEditHistory.pas',
  ScreenLayoutGroupCommands in
    '..\Source\Core\Commands\Layer\ScreenLayoutGroupCommands.pas',
  ScreenLayoutTextCommands in
    '..\Source\Core\Commands\Text\ScreenLayoutTextCommands.pas',
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
  RotationPoint: TPoint;
  TextBounds: TRectF;
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
    Check(Interaction.MouseMove([ssLeft, ssAlt], 100, 45),
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

    Check(TryGetScreenLayoutTextPathBounds(Layer, TextBounds),
      'placed text bounds were not calculated');
    Geometry := BuildSelectionGeometry(Rect(
      Round(TextBounds.Left + 100), Round(TextBounds.Top + 50),
      Round(TextBounds.Right + 100), Round(TextBounds.Bottom + 50)),
      SelectionFrameOffset(0, 1));
    RotationPoint := Geometry.PrimaryRotationHandle.CenterPoint;
    Check(Interaction.MouseDown(mbLeft, [], RotationPoint.X,
      RotationPoint.Y), 'text path rotation did not start');
    Check(Interaction.MouseMove([ssLeft], 150, 40),
      'text path rotation did not update');
    Check(Interaction.MouseUp(mbLeft),
      'text path rotation did not commit');
    Vertices := Layer.EditablePathVertices;
    Check(not SameValue(Layer.RotationDegrees, 0.0, 0.5) and
      not SameValue(Vertices[0].Position.Y, Vertices[2].Position.Y, 0.5),
      'text path rotation did not rotate frame and path together');
    History.Undo;
    Vertices := Layer.EditablePathVertices;
    Check(SameValue(Layer.RotationDegrees, 0.0, 0.5) and
      SameValue(Vertices[0].Position.X, -40.0, 0.5) and
      SameValue(Vertices[2].Position.X, 40.0, 0.5),
      'text path rotation undo did not restore the whole object');

    Check(TryGetScreenLayoutTextPathBounds(Layer, TextBounds),
      'placed text bounds disappeared before resize');
    Geometry := BuildSelectionGeometry(Rect(
      Round(TextBounds.Left + 100), Round(TextBounds.Top + 50),
      Round(TextBounds.Right + 100), Round(TextBounds.Bottom + 50)),
      SelectionFrameOffset(0, 1));
    Check(Interaction.MouseDown(mbLeft, [],
      Geometry.Handles[vshBottomRight].CenterPoint.X,
      Geometry.Handles[vshBottomRight].CenterPoint.Y),
      'placed text resize did not start');
    Check(Interaction.MouseMove([ssLeft],
      Geometry.Handles[vshBottomRight].CenterPoint.X + 30,
      Geometry.Handles[vshBottomRight].CenterPoint.Y + 30),
      'placed text resize did not update');
    Check(Interaction.MouseUp(mbLeft),
      'placed text resize did not commit');
    Vertices := Layer.EditablePathVertices;
    Check((Layer.FontSize > 20.0) and
      SameValue(Vertices[0].Position.X, -40.0, 0.5) and
      SameValue(Vertices[2].Position.X, 40.0, 0.5),
      'placed text resize changed the path instead of the text size');
    History.Undo;
    Check(SameValue(Layer.FontSize, 20.0, 0.01),
      'placed text resize undo did not restore the font size');
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

procedure CheckCharacterPlacementCells;
var
  I: Integer;
  Layer: TScreenLayoutTextPathLayer;
  Placements: TArray<TScreenLayoutTextPathPlacement>;
  Vertices: TArray<TScreenLayoutVertex>;
begin
  SetLength(Vertices, 2);
  Vertices[0].Position := TPointF.Create(0, 0);
  Vertices[0].Kind := slvkSharp;
  Vertices[0].OutgoingSegment := slskLine;
  Vertices[1].Position := TPointF.Create(200, 0);
  Vertices[1].Kind := slvkSharp;
  Vertices[1].OutgoingSegment := slskLine;
  Layer := TScreenLayoutTextPathLayer.Create('Text Path',
    TRectF.Create(0, -20, 200, 0), 'ABC', 'Yu Gothic UI', 20, 200,
    clWhite, Vertices);
  try
    Placements := BuildScreenLayoutTextPathPlacements(Layer);
    Check(Length(Placements) = 3,
      'text path was not expanded into character placement cells');
    for I := 0 to High(Placements) do
    begin
      Check(SameValue(Placements[I].Anchor.X,
        (Placements[I].Corners[2].X + Placements[I].Corners[3].X) * 0.5,
        0.001) and SameValue(Placements[I].Anchor.Y,
        (Placements[I].Corners[2].Y + Placements[I].Corners[3].Y) * 0.5,
        0.001), 'character cell bottom center is not its path anchor');
      Check(SameValue(Placements[I].Anchor.Y, 0.0, 0.001),
        'character cell bottom center is not on the path');
    end;
  finally
    Layer.Free;
  end;
end;

procedure CheckTextPathAttachmentSides;
var
  Attachment: TScreenLayoutTextPathAttachment;
  EdgeCenter: TPointF;
  Layer: TScreenLayoutTextPathLayer;
  Placement: TScreenLayoutTextPathPlacement;
  Placements: TArray<TScreenLayoutTextPathPlacement>;
  Vertices: TArray<TScreenLayoutVertex>;
begin
  SetLength(Vertices, 2);
  Vertices[0].Position := TPointF.Create(0, 0);
  Vertices[0].Kind := slvkSharp;
  Vertices[0].OutgoingSegment := slskLine;
  Vertices[1].Position := TPointF.Create(200, 0);
  Vertices[1].Kind := slvkSharp;
  Vertices[1].OutgoingSegment := slskLine;
  Layer := TScreenLayoutTextPathLayer.Create('Text Path',
    TRectF.Create(0, -20, 200, 20), 'A', 'Yu Gothic UI', 20, 200,
    clWhite, Vertices);
  try
    for Attachment := Low(TScreenLayoutTextPathAttachment) to
      High(TScreenLayoutTextPathAttachment) do
    begin
      Layer.Attachment := Attachment;
      Placements := BuildScreenLayoutTextPathPlacements(Layer);
      Check(Length(Placements) = 1,
        'attachment side did not produce a character placement');
      Placement := Placements[0];
      case Attachment of
        sltpaTop:
          EdgeCenter := TPointF.Create(
            (Placement.Corners[0].X + Placement.Corners[1].X) * 0.5,
            (Placement.Corners[0].Y + Placement.Corners[1].Y) * 0.5);
        sltpaLeft:
          EdgeCenter := TPointF.Create(
            (Placement.Corners[0].X + Placement.Corners[3].X) * 0.5,
            (Placement.Corners[0].Y + Placement.Corners[3].Y) * 0.5);
        sltpaRight:
          EdgeCenter := TPointF.Create(
            (Placement.Corners[1].X + Placement.Corners[2].X) * 0.5,
            (Placement.Corners[1].Y + Placement.Corners[2].Y) * 0.5);
      else
        EdgeCenter := TPointF.Create(
          (Placement.Corners[2].X + Placement.Corners[3].X) * 0.5,
          (Placement.Corners[2].Y + Placement.Corners[3].Y) * 0.5);
      end;
      Check(SameValue(EdgeCenter.X, Placement.Anchor.X, 0.001) and
        SameValue(EdgeCenter.Y, Placement.Anchor.Y, 0.001),
        Format('attachment side %d was not centered on the path',
          [Ord(Attachment)]));
      Check(SameValue(Placement.Anchor.Y, 0.0, 0.001),
        'attachment anchor left the path');
    end;
    Layer.Attachment := sltpaLeft;
    Placement := BuildScreenLayoutTextPathPlacements(Layer)[0];
    Check(SameValue(Placement.AngleDegrees, 90.0, 0.001),
      'left attachment did not rotate clockwise from the path');
    Layer.Attachment := sltpaRight;
    Placement := BuildScreenLayoutTextPathPlacements(Layer)[0];
    Check(SameValue(Placement.AngleDegrees, -90.0, 0.001),
      'right attachment did not rotate counterclockwise from the path');
  finally
    Layer.Free;
  end;
end;

procedure CheckIndividualCharacterResize;
var
  CharacterGeometry: TVectArtSelectionGeometry;
  CharacterPathOffsets: TArray<Single>;
  CharacterPositionManual: TArray<Boolean>;
  CharacterPoint: TPoint;
  CharacterScales: TArray<Single>;
  Document: TVectArtDocument;
  HandlePoint: TPoint;
  History: TVectArtEditHistory;
  Interaction: TVectArtCanvasInteraction;
  Layer: TScreenLayoutTextPathLayer;
  OriginalPathDistance: Single;
  Placements: TArray<TScreenLayoutTextPathPlacement>;
  Vertices: TArray<TScreenLayoutVertex>;
begin
  Document := TVectArtDocument.Create;
  History := TVectArtEditHistory.Create;
  Interaction := TVectArtCanvasInteraction.Create;
  try
    Document.SetCanvasSize(300, 120);
    SetLength(Vertices, 2);
    Vertices[0].Position := TPointF.Create(-100, 20);
    Vertices[0].Kind := slvkSharp;
    Vertices[0].OutgoingSegment := slskLine;
    Vertices[1].Position := TPointF.Create(100, 20);
    Vertices[1].Kind := slvkSharp;
    Vertices[1].OutgoingSegment := slskLine;
    Layer := TScreenLayoutTextPathLayer.Create('Text Path',
      TRectF.Create(-100, 0, 100, 20), 'ABC', 'Yu Gothic UI', 20, 200,
      clWhite, Vertices);
    Document.InsertLayer(1, Layer);
    Document.SelectedIndex := 1;
    Interaction.EditHistory := History;
    Interaction.Configure(Document, Rect(0, 0, 300, 120), 1);
    Check(Length(Layer.CharacterScales) = 0,
      'new text path has unexpected character scales');
    Placements := BuildScreenLayoutTextPathPlacements(Layer);
    CharacterPoint := Point(Round(Placements[1].Anchor.X + 150),
      Round(Placements[1].Anchor.Y + 60 - Placements[1].CellHeight * 0.5));
    Check(Interaction.MouseDown(mbLeft, [], CharacterPoint.X,
      CharacterPoint.Y), 'character selection did not start');
    Check(Interaction.MouseUp(mbLeft),
      'character selection did not finish');
    Check(Length(Layer.CharacterScales) = 0,
      'character selection changed character scales');
    Check(Interaction.SelectedTextPathCharacterGeometry(
      CharacterGeometry), 'selected character frame was not created');
    HandlePoint := Point(
      CharacterGeometry.Handles[vshTopRight].Right + 4,
      CharacterGeometry.Handles[vshTopRight].CenterPoint.Y);
    Check(Interaction.MouseDown(mbLeft, [], HandlePoint.X, HandlePoint.Y),
      'expanded individual character resize hit area did not respond');
    Check(Interaction.MouseMove([ssLeft], HandlePoint.X + 20,
      HandlePoint.Y - 20), 'individual character resize did not update');
    Check(Interaction.MouseUp(mbLeft),
      'individual character resize did not commit');
    CharacterScales := Layer.CharacterScales;
    Check((Length(CharacterScales) >= 2) and
      SameValue(CharacterScales[0], 1.0, 0.001) and
      (CharacterScales[1] > 1.0),
      'individual character resize changed an unexpected character');
    Placements := BuildScreenLayoutTextPathPlacements(Layer);
    Check(SameValue(Placements[1].Anchor.Y, 20.0, 0.001) and
      SameValue(Placements[1].Anchor.Y,
        (Placements[1].Corners[2].Y + Placements[1].Corners[3].Y) * 0.5,
        0.001), 'resized character bottom center left the path');
    Vertices := Layer.EditablePathVertices;
    Check(SameValue(Vertices[0].Position.X, -100.0) and
      SameValue(Vertices[1].Position.X, 100.0),
      'individual character resize changed the path');
    History.Undo;
    CharacterScales := Layer.CharacterScales;
    Check(Length(CharacterScales) = 0,
      Format('individual character resize undo restored %d scales',
        [Length(CharacterScales)]));
    History.Redo;
    CharacterScales := Layer.CharacterScales;
    Check((Length(CharacterScales) >= 2) and
      (CharacterScales[1] > 1.0),
      'individual character resize redo did not restore the scale');
    Placements := BuildScreenLayoutTextPathPlacements(Layer);
    OriginalPathDistance := Placements[1].PathDistance;
    CharacterPoint := Point(Round(Placements[1].Anchor.X + 150),
      Round(Placements[1].Anchor.Y + 60 -
        Placements[1].CellHeight * 0.5));
    Check(Interaction.MouseDown(mbLeft, [], CharacterPoint.X,
      CharacterPoint.Y), 'individual character move did not start');
    Check(Interaction.MouseMove([ssLeft], CharacterPoint.X + 25,
      CharacterPoint.Y), 'individual character move did not update');
    Check(Interaction.MouseUp(mbLeft),
      'individual character move did not commit');
    Placements := BuildScreenLayoutTextPathPlacements(Layer);
    CharacterPathOffsets := Layer.CharacterPathOffsets;
    CharacterPositionManual := Layer.CharacterPositionManual;
    Check((Length(CharacterPathOffsets) >= 2) and
      (Length(CharacterPositionManual) >= 2) and
      CharacterPositionManual[1] and
      SameValue(Placements[1].PathDistance,
        OriginalPathDistance + 25, 1.0) and
      SameValue(Placements[1].Anchor.Y, 20.0, 0.001),
      Format('individual character move distance was %.2f from %.2f; '
        + 'offset count was %d', [Placements[1].PathDistance,
          OriginalPathDistance, Length(CharacterPathOffsets)]));
    History.Undo;
    Check((Length(Layer.CharacterPathOffsets) = 0) and
      (Length(Layer.CharacterPositionManual) = 0),
      'individual character move undo did not restore its position');
    History.Redo;
    Check((Length(Layer.CharacterPathOffsets) >= 2) and
      (Length(Layer.CharacterPositionManual) >= 2) and
      Layer.CharacterPositionManual[1],
      'individual character move redo did not restore its position');
    Layer.Text := 'XYZ';
    Check((Length(Layer.CharacterPathOffsets) = 0) and
      (Length(Layer.CharacterPositionManual) = 0) and
      (Length(Layer.CharacterScales) = 0),
      'changing text did not discard individual character transforms');
  finally
    Interaction.Free;
    History.Free;
    Document.Free;
  end;
end;

procedure CheckTextPathCollisionHandling;
var
  CharacterInteraction: TScreenLayoutTextPathCharacterInteraction;
  CornerDistance: Single;
  Document: TVectArtDocument;
  History: TVectArtEditHistory;
  Layer: TScreenLayoutTextPathLayer;
  OriginalPathDistance: Single;
  Placements: TArray<TScreenLayoutTextPathPlacement>;
  StartPoint: TPoint;
  Vertices: TArray<TScreenLayoutVertex>;
begin
  Document := TVectArtDocument.Create;
  History := TVectArtEditHistory.Create;
  CharacterInteraction := TScreenLayoutTextPathCharacterInteraction.Create;
  SetLength(Vertices, 2);
  Vertices[0].Position := TPointF.Create(0, 0);
  Vertices[0].Kind := slvkSharp;
  Vertices[0].OutgoingSegment := slskLine;
  Vertices[1].Position := TPointF.Create(400, 0);
  Vertices[1].Kind := slvkSharp;
  Vertices[1].OutgoingSegment := slskLine;
  Layer := TScreenLayoutTextPathLayer.Create('Text Path',
    TRectF.Create(0, -30, 400, 0), 'ABC', 'Yu Gothic UI', 24, 400,
    clWhite, Vertices);
  try
    Document.SetCanvasSize(500, 500);
    Document.InsertLayer(1, Layer);
    Document.SelectedIndex := 1;
    Placements := BuildScreenLayoutTextPathPlacements(Layer);
    Check(Length(Placements) = 3,
      'collision test could not measure the characters');
    CornerDistance := Placements[0].AdvanceWidth +
      Placements[1].AdvanceWidth;
    SetLength(Vertices, 3);
    Vertices[0].Position := TPointF.Create(0, 0);
    Vertices[0].Kind := slvkSharp;
    Vertices[0].OutgoingSegment := slskLine;
    Vertices[1].Position := TPointF.Create(CornerDistance, 0);
    Vertices[1].Kind := slvkSharp;
    Vertices[1].OutgoingSegment := slskLine;
    Vertices[2].Position := TPointF.Create(CornerDistance, -200);
    Vertices[2].Kind := slvkSharp;
    Vertices[2].OutgoingSegment := slskLine;
    Layer.AssignEditablePathVertices(Vertices);
    Placements := BuildScreenLayoutTextPathPlacements(Layer);
    Check((Length(Placements) = 3) and
      Placements[2].CollisionAdjusted and
      not Placements[2].CollidesWithPrevious,
      'automatic text path collision was not resolved');
    OriginalPathDistance := Placements[2].PathDistance;
    CharacterInteraction.Configure(Document, History,
      Rect(0, 0, 500, 500), 1);
    CharacterInteraction.SelectedCharacter := 2;
    StartPoint := Point(Round(Placements[2].Anchor.X + 250),
      Round(Placements[2].Anchor.Y + 250));
    Check(CharacterInteraction.BeginDragAt(StartPoint.X, StartPoint.Y) =
      sltpcdmMove, 'collision-adjusted character move did not start');
    Check(CharacterInteraction.DragTo([], StartPoint.X, StartPoint.Y),
      'initial character move did not update');
    Placements := BuildScreenLayoutTextPathPlacements(Layer);
    Check(SameValue(Placements[2].PathDistance, OriginalPathDistance, 0.01),
      Format('first manual conversion moved the character from %.2f to %.2f',
        [OriginalPathDistance, Placements[2].PathDistance]));
    CharacterInteraction.EndDrag;
    Layer.CharacterPathOffsets := nil;
    Layer.CharacterPositionManual := [False, False, True];
    Placements := BuildScreenLayoutTextPathPlacements(Layer);
    Check((Length(Placements) = 3) and
      not Placements[2].CollisionAdjusted and
      Placements[2].CollidesWithPrevious,
      'manual character position did not suppress collision correction');
  finally
    CharacterInteraction.Free;
    History.Free;
    Document.Free;
  end;
end;

procedure CheckPersistenceAndRendering;
var
  Buffer: TVectArtRenderBuffer;
  ClonedLayer: TVectArtLayer;
  Document: TVectArtDocument;
  ErrorMessage: string;
  I: Integer;
  Layer: TScreenLayoutTextPathLayer;
  Loaded: TVectArtDocument;
  LoadedLayer: TScreenLayoutTextPathLayer;
  BlackInputPixelCount: Integer;
  NearPathPixelCount: Integer;
  OutlinedInputPixelCount: Integer;
  PlainInputPixelCount: Integer;
  Serialized: string;
  Vertices: TArray<TScreenLayoutVertex>;
  WhiteInputPixelCount: Integer;
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
    Layer.CharacterPathOffsets := [0.0, 12.0, -4.0];
    Layer.CharacterPositionManual := [False, True, True];
    Layer.CharacterScales := [1.0, 1.5, 0.75];
    Layer.Attachment := sltpaRight;
    Document.InsertLayer(1, Layer);

    ClonedLayer := CloneScreenLayoutLayer(Layer, 'Text Path Copy');
    try
      Check((ClonedLayer is TScreenLayoutTextPathLayer) and
        (TScreenLayoutTextPathLayer(ClonedLayer).Attachment =
          sltpaRight) and
        (Length(TScreenLayoutTextPathLayer(
          ClonedLayer).CharacterPathOffsets) = 3) and
        SameValue(TScreenLayoutTextPathLayer(
          ClonedLayer).CharacterPathOffsets[1], 12.0, 0.0001) and
        (Length(TScreenLayoutTextPathLayer(
          ClonedLayer).CharacterPositionManual) = 3) and
        TScreenLayoutTextPathLayer(
          ClonedLayer).CharacterPositionManual[1] and
        (Length(TScreenLayoutTextPathLayer(ClonedLayer).CharacterScales) =
          3) and SameValue(TScreenLayoutTextPathLayer(
            ClonedLayer).CharacterScales[1], 1.5, 0.0001),
        'text path clone did not preserve individual character scales');
    finally
      ClonedLayer.Free;
    end;

    Serialized := SerializeVectArtDocument(Document);
    Check(Pos('"type":"textPath"', Serialized) > 0,
      'text path JSON type was not serialized');
    Check(Pos('"pathAttachment":"right"', Serialized) > 0,
      'text path attachment was not serialized');
    Check(TryDeserializeVectArtDocument(Serialized, Loaded, ErrorMessage),
      'text path JSON was not loaded: ' + ErrorMessage);
    Check((Loaded.LayerCount = 2) and
      (Loaded[1] is TScreenLayoutTextPathLayer),
      'text path JSON was restored as another layer type');
    LoadedLayer := TScreenLayoutTextPathLayer(Loaded[1]);
    Check(LoadedLayer.Attachment = sltpaRight,
      'text path attachment was not restored');
    Vertices := LoadedLayer.EditablePathVertices;
    Check((Length(Vertices) = 3) and
      SameValue(Vertices[0].Position.X, -60.0) and
      SameValue(Vertices[2].Position.Y, 20.0),
      'contained path vertices changed during JSON round trip');
    Check(SameValue(LoadedLayer.LetterSpacingRatio, 0.0, 0.0001),
      'text path JSON restored discarded letter spacing');
    Check((Length(LoadedLayer.CharacterScales) = 3) and
      SameValue(LoadedLayer.CharacterScales[1], 1.5, 0.0001),
      'text path JSON did not restore individual character scales');
    Check((Length(LoadedLayer.CharacterPathOffsets) = 3) and
      SameValue(LoadedLayer.CharacterPathOffsets[1], 12.0, 0.0001),
      'text path JSON did not restore individual character positions');
    Check((Length(LoadedLayer.CharacterPositionManual) = 3) and
      LoadedLayer.CharacterPositionManual[1],
      'text path JSON did not restore manual character position flags');
    LoadedLayer.Attachment := sltpaBottom;

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
        clWhite);
    finally
      TTextRendererSkiaRuntime.Release;
    end;
    OutlinedInputPixelCount := 0;
    BlackInputPixelCount := 0;
    WhiteInputPixelCount := 0;
    for Y := 5 to 35 do
      for X := 20 to 179 do
      begin
        if Buffer.Pixels[Y * 200 + X].A <> 0 then
          Inc(OutlinedInputPixelCount);
        if (Buffer.Pixels[Y * 200 + X].R = 0) and
          (Buffer.Pixels[Y * 200 + X].G = 0) and
          (Buffer.Pixels[Y * 200 + X].B = 0) and
          (Buffer.Pixels[Y * 200 + X].A = 255) then
          Inc(BlackInputPixelCount);
        if (Buffer.Pixels[Y * 200 + X].R = 255) and
          (Buffer.Pixels[Y * 200 + X].G = 255) and
          (Buffer.Pixels[Y * 200 + X].B = 255) and
          (Buffer.Pixels[Y * 200 + X].A = 255) then
          Inc(WhiteInputPixelCount);
      end;
    Check(OutlinedInputPixelCount > PlainInputPixelCount,
      'text input contrast outline was not rendered');
    Check((BlackInputPixelCount > 0) and (WhiteInputPixelCount > 0),
      'text input preview did not use black text and a white outline');
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
    Check(Interaction.MouseMove([ssLeft, ssAlt], 105, 55),
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
  CheckCharacterPlacementCells;
  CheckTextPathAttachmentSides;
  CheckIndividualCharacterResize;
  CheckTextPathCollisionHandling;
  CheckPersistenceAndRendering;
  Writeln('PASS');
end.
