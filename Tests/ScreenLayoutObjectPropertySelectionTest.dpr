// グループ編集終了直後でもトップレベルの線選択を属性GUIへ渡せることを検証する。
program ScreenLayoutObjectPropertySelectionTest;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Types,
  Vcl.Graphics,
  ScreenLayoutDocument in '..\Source\Core\Model\ScreenLayoutDocument.pas',
  ScreenLayoutEditCommands in '..\Source\Core\Commands\ScreenLayoutEditCommands.pas',
  ScreenLayoutEditHistory in '..\Source\Core\Model\ScreenLayoutEditHistory.pas',
  ScreenLayoutEditorState in '..\Source\Core\Model\ScreenLayoutEditorState.pas',
  ScreenLayoutContext in '..\Source\Core\Model\ScreenLayoutContext.pas',
  ScreenLayoutObjectPropertyCommands in
    '..\Source\ObjectProperties\ScreenLayoutObjectPropertyCommands.pas',
  ScreenLayoutObjectPropertySelection in
    '..\Source\ObjectProperties\ScreenLayoutObjectPropertySelection.pas';

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
    raise Exception.Create(MessageText);
end;

var
  Context: IVectArtDesignerContext;
  Data: TVectArtPathData;
  Document: TVectArtDocument;
  EditorState: TVectArtEditorState;
  History: TVectArtEditHistory;
  Index: Integer;
  Layers: TArray<TVectArtLayer>;
  StaleChild: TVectArtRectangleLayer;
begin
  Document := TVectArtDocument.Create;
  History := TVectArtEditHistory.Create;
  EditorState := TVectArtEditorState.Create;
  try
    Context := TVectArtDesignerContext.Create(Document, History, EditorState);
    SetLength(Data.Vertices, 2);
    Data.Vertices[0].Position := TPointF.Create(0, 0);
    Data.Vertices[1].Position := TPointF.Create(100, 50);
    Data.Vertices[0].OutgoingSegment := slskLine;
    Data.Vertices[0].Kind := slvkSharp;
    Data.Vertices[1].OutgoingSegment := slskLine;
    Data.Vertices[1].Kind := slvkSharp;
    Data.Closed := False;
    Data.LineCap := vlcSquare;
    Data.Locked := False;
    Data.Name := 'Line 1';
    Data.Opacity := 1;
    Data.StrokeColor := clBlack;
    Data.MifStrokeStyle := vssSolid;
    Data.StrokeWidth := 1;
    Data.Visible := True;
    Index := Document.InsertPath(Document.LayerCount, Data);
    Document.SetSelectedLayers([Index]);
    Check(Index > 0, 'Path insertion failed');
    Check(Document.SelectionCount = 1, 'Document selection was not set');
    Check(Document[Index] is TVectArtPathLayer,
      'Inserted layer is not a path');

    StaleChild := TVectArtRectangleLayer.Create('Stale child',
      TRectF.Create(0, 0, 10, 10), clWhite);
    try
      EditorState.OpenGroupChild := StaleChild;
      Check(EditorState.OpenGroup = nil, 'Unexpected open group');
      Check(Length(ScreenLayoutSelectedOpacityLayers(Context)) = 1,
        'Top-level selection was hidden');
      Layers := ScreenLayoutSelectedLineLayers(Context);
      Check(Length(Layers) = 1, 'Top-level line selection was hidden');
      Check(Layers[0] = Document[Index], 'Unexpected line selection');
    finally
      EditorState.OpenGroupChild := nil;
      StaleChild.Free;
    end;
  finally
    Context := nil;
    EditorState.Free;
    History.Free;
    Document.Free;
  end;
  Writeln('PASS');
end.
