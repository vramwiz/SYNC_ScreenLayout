program ScreenLayoutLayerTreePositionTest;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Types,
  Vcl.Graphics,
  ScreenLayoutDocument in '..\Source\Core\Model\ScreenLayoutDocument.pas',
  ScreenLayoutEditorState in
    '..\Source\Core\Model\ScreenLayoutEditorState.pas',
  ScreenLayoutRenderer in '..\Source\Rendering\ScreenLayoutRenderer.pas',
  ScreenLayoutLayerRenderer in
    '..\Source\Layers\ScreenLayoutLayerRenderer.pas';

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
    raise Exception.Create(MessageText);
end;

function FindLayerIndex(Renderer: TVectArtLayerRenderer;
  Layer: TVectArtLayer): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 1 to 20 do
    if Renderer.LayerAt(I) = Layer then
      Exit(I);
end;

var
  Bounds: TRect;
  Document: TVectArtDocument;
  EditorState: TVectArtEditorState;
  Group: TScreenLayoutGroupLayer;
  I: Integer;
  Index: Integer;
  Renderer: TVectArtLayerRenderer;
  TopBefore: Integer;
begin
  Document := TVectArtDocument.Create;
  EditorState := TVectArtEditorState.Create;
  Renderer := TVectArtLayerRenderer.Create;
  try
    Group := TScreenLayoutGroupLayer.Create('Group');
    for I := 1 to 4 do
      Group.AddChild(TVectArtRectangleLayer.Create('Child ' + I.ToString,
        TRectF.Create(0, 0, 10, 10), clRed));
    Document.InsertLayer(Document.LayerCount, Group);
    for I := 1 to 3 do
      Document.InsertLayer(Document.LayerCount,
        TVectArtRectangleLayer.Create('Top ' + I.ToString,
          TRectF.Create(0, 0, 10, 10), clBlue));
    Renderer.Document := Document;
    Renderer.EditorState := EditorState;
    Bounds := Rect(0, 0, 400, 220);
    Renderer.MaximumScrollOffset(Bounds);
    Index := FindLayerIndex(Renderer, Group);
    Check(Index > 0, 'Closed group was not listed');
    TopBefore := Renderer.LayerItemRect(Bounds, Index).Top;

    EditorState.OpenGroupInDocument(Document, Group);
    Renderer.MaximumScrollOffset(Bounds);
    Index := FindLayerIndex(Renderer, Group);
    Check(Renderer.LayerItemRect(Bounds, Index).Top = TopBefore,
      'Opening moved the group row');
    Check(Renderer.LayerAt(Index - 1) = Group[Group.ChildCount - 1],
      'Children were not expanded below the group row');

    EditorState.OpenGroup := nil;
    Renderer.MaximumScrollOffset(Bounds);
    Index := FindLayerIndex(Renderer, Group);
    Check(Renderer.LayerItemRect(Bounds, Index).Top = TopBefore,
      'Closing moved the group row');
  finally
    Renderer.Free;
    EditorState.Free;
    Document.Free;
  end;
  Writeln('PASS');
end.
