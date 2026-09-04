program ScreenLayoutVertexEditingModeTest;

{$APPTYPE CONSOLE}

uses
  System.Classes,
  System.SysUtils,
  System.Types,
  Vcl.Controls,
  ScreenLayoutCanvasInteraction in
    '..\Source\Editor\Interaction\ScreenLayoutCanvasInteraction.pas',
  ScreenLayoutDocument in '..\Source\Core\Model\ScreenLayoutDocument.pas',
  ScreenLayoutEditHistory in
    '..\Source\Core\Model\ScreenLayoutEditHistory.pas';

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
    raise Exception.Create(MessageText);
end;

var
  CaptureNeeded: Boolean;
  Document: TVectArtDocument;
  History: TVectArtEditHistory;
  Index: Integer;
  Interaction: TVectArtCanvasInteraction;
  Kind: TScreenLayoutVertexKind;
  PathLayer: TVectArtPathLayer;
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
    Index := Document.InsertLayer(Document.LayerCount,
      TVectArtPathLayer.Create('Line', Vertices, False));
    Document.SelectedIndex := Index;
    PathLayer := TVectArtPathLayer(Document[Index]);

    Interaction.EditHistory := History;
    Interaction.Configure(Document, Rect(0, 0, 200, 100), 1);
    Interaction.SetVertexStructureEditing(False, False);

    Check(Interaction.CursorAt(100, 50) = crCross,
      Format('Select tool vertex cursor was %d instead of %d',
        [Interaction.CursorAt(100, 50), crCross]));
    Check(Interaction.CursorAt(80, 50) = crSizeAll,
      'Select tool did not use the object move cursor on a segment');

    Check(not Interaction.MouseDownSelectedVertex(mbRight, [], 100, 50,
      CaptureNeeded), 'Select tool deleted a vertex');
    Check(Length(PathLayer.Vertices) = 3,
      'Select tool changed the vertex count after right click');
    Check(not Interaction.MouseDownSelectedVertex(mbLeft, [], 80, 50,
      CaptureNeeded), 'Select tool inserted a vertex');
    Check(Length(PathLayer.Vertices) = 3,
      'Select tool changed the vertex count on a segment');

    Check(Interaction.MouseDownSelectedVertex(mbLeft, [], 100, 50,
      CaptureNeeded) and CaptureNeeded,
      'Select tool could not start an existing vertex drag');
    Check(Length(Interaction.SelectedShapeVertexKindButtons) = 0,
      'Select tool exposed structural vertex controls');
    Check(Interaction.MouseMove([ssLeft], 105, 55),
      'Select tool could not drag an existing vertex');
    Check(Interaction.MouseUp(mbLeft),
      'Select tool did not finish the vertex drag');
    Vertices := PathLayer.Vertices;
    Check((Vertices[1].Position.X = 5) and
      (Vertices[1].Position.Y = 5),
      'Dragged vertex was not updated');

    Interaction.Configure(Document, Rect(0, 0, 200, 100), 1);
    Interaction.SetVertexStructureEditing(True, False);
    Check(Interaction.SelectedPathVertexKind(Kind) and
      (Kind = slvkSharp),
      'Path edit did not report the selected sharp vertex');
    Check(Interaction.SetSelectedPathVertexKind(slvkBezier),
      'Path edit could not change the selected vertex kind');
    Check(Interaction.SelectedPathVertexKind(Kind) and
      (Kind = slvkBezier) and
      (PathLayer.Vertices[1].Kind = slvkBezier),
      'Path edit mode and selected vertex kind diverged');
    Check(Length(Interaction.SelectedShapeVertexKindButtons) = 0,
      'Path edit exposed the removed vertex kind buttons');
    Check(Interaction.SetSelectedPathVertexKind(slvkSharp),
      'Path edit could not restore the selected vertex to sharp');
    Check(Interaction.MouseDownSelectedVertex(mbLeft, [], 82, 52,
      CaptureNeeded) and not CaptureNeeded,
      'Path edit did not insert a vertex from a segment click');
    Check(Length(PathLayer.Vertices) = 4,
      'Path edit did not add a vertex');
    Check(Interaction.MouseDownSelectedVertex(mbRight, [], 82, 52,
      CaptureNeeded), 'Path edit did not delete a vertex with right click');
    Check(Length(PathLayer.Vertices) = 3,
      'Path edit did not restore the vertex count after deletion');
  finally
    Interaction.Free;
    History.Free;
    Document.Free;
  end;
  Writeln('PASS');
end.
