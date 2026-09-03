// 配置プリセットの中心原点計算と、全面変形を含むUndoを検証する。
program ScreenLayoutGeometryPresetTest;

{$APPTYPE CONSOLE}

uses
  System.Math,
  System.SysUtils,
  System.Types,
  Vcl.Forms,
  Vcl.Graphics,
  ScreenLayoutDocument in '..\Source\Core\Model\ScreenLayoutDocument.pas',
  ScreenLayoutEditHistory in
    '..\Source\Core\Model\ScreenLayoutEditHistory.pas',
  ScreenLayoutEditorState in
    '..\Source\Core\Model\ScreenLayoutEditorState.pas',
  ScreenLayoutGeometryPropertiesFrame;

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
    raise Exception.Create(MessageText);
end;

procedure CheckBounds(const Bounds: TRectF; Left, Top, Right,
  Bottom: Single; const MessageText: string);
begin
  Check(SameValue(Bounds.Left, Left) and SameValue(Bounds.Top, Top) and
    SameValue(Bounds.Right, Right) and SameValue(Bounds.Bottom, Bottom),
    MessageText);
end;

var
  Document: TVectArtDocument;
  EditorState: TVectArtEditorState;
  Frame: TScreenLayoutGeometryPropertiesFrame;
  History: TVectArtEditHistory;
  Host: TForm;
  Index: Integer;
  RectangleLayer: TVectArtRectangleLayer;
begin
  Application.Initialize;
  Document := TVectArtDocument.Create;
  EditorState := TVectArtEditorState.Create;
  Host := TForm.CreateNew(nil);
  Frame := TScreenLayoutGeometryPropertiesFrame.Create(Host);
  Frame.Parent := Host;
  History := TVectArtEditHistory.Create;
  try
    Document.SetCanvasSize(200, 100);
    RectangleLayer := TVectArtRectangleLayer.Create('Rectangle',
      TRectF.Create(-10, -5, 10, 5), clRed);
    Index := Document.InsertLayer(Document.LayerCount, RectangleLayer);
    Document.SelectedIndex := Index;
    Frame.Document := Document;
    Frame.EditHistory := History;
    Frame.EditorState := EditorState;

    Frame.ApplyPreset(slgpTopLeft);
    CheckBounds(RectangleLayer.Bounds, -100, -50, -80, -40,
      'Top-left preset did not align the object to the canvas');
    Check(History.CanUndo, 'Alignment preset was not added to history');
    History.Undo;
    CheckBounds(RectangleLayer.Bounds, -10, -5, 10, 5,
      'Alignment preset undo did not restore the object');

    Frame.ApplyPreset(slgpFillCanvas);
    CheckBounds(RectangleLayer.Bounds, -100, -50, 100, 50,
      'Fill-canvas preset did not stretch the object');
    Check(History.CanUndo, 'Fill-canvas preset was not added to history');
    History.Undo;
    CheckBounds(RectangleLayer.Bounds, -10, -5, 10, 5,
      'Fill-canvas preset undo did not restore the object');
  finally
    History.Free;
    Host.Free;
    EditorState.Free;
    Document.Free;
  end;
  Writeln('PASS');
end.
