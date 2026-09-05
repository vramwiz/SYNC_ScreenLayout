program ScreenLayoutCreationPaintStyleTest;

{$APPTYPE CONSOLE}

uses
  System.Classes,
  System.Math,
  System.SysUtils,
  System.Types,
  Vcl.Controls,
  Vcl.Graphics,
  ScreenLayoutDocument in '..\Source\Core\Model\ScreenLayoutDocument.pas',
  ScreenLayoutEditHistory in
    '..\Source\Core\Commands\ScreenLayoutEditHistory.pas',
  ScreenLayoutEditorState in
    '..\Source\Core\Model\ScreenLayoutEditorState.pas',
  ScreenLayoutPaintStyles in
    '..\Source\Core\Model\ScreenLayoutPaintStyles.pas',
  ScreenLayoutShapeCreation in
    '..\Source\Editor\Creation\ScreenLayoutShapeCreation.pas';

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
    raise Exception.Create(MessageText);
end;

procedure DragCreate(Creation: TVectArtShapeCreation;
  const StartPoint, EndPoint: TPoint);
begin
  Check(Creation.MouseDown(mbLeft, [], StartPoint.X, StartPoint.Y),
    'creation mouse down was not accepted');
  Creation.MouseMove([ssLeft], EndPoint.X, EndPoint.Y);
  Check(Creation.MouseUp(mbLeft, [], EndPoint.X, EndPoint.Y),
    'creation mouse up was not accepted');
end;

procedure Run;
var
  Creation: TVectArtShapeCreation;
  Document: TVectArtDocument;
  EditorState: TVectArtEditorState;
  History: TVectArtEditHistory;
  Style: TScreenLayoutPaintStyle;
begin
  Document := TVectArtDocument.Create;
  EditorState := TVectArtEditorState.Create;
  History := TVectArtEditHistory.Create;
  Creation := TVectArtShapeCreation.Create;
  try
    Check((Ord(slpkSolid) = 0) and (Ord(slpkGradient) = 1) and
      (Ord(slpkPattern) = 2) and (Ord(slpkTexture) = 3),
      'paint kinds are not stable');
    Style := TScreenLayoutPaintStyle.Solid(clFuchsia);
    EditorState.CreationPaintStyle := Style;
    Check((EditorState.CreationPaintStyle.Kind = slpkSolid) and
      (ColorToRGB(EditorState.CreationColor) = ColorToRGB(clFuchsia)),
      'solid creation paint was not stored');
    Check((ColorToRGB(EditorState.LineStrokeColor) = ColorToRGB(clFuchsia)) and
      (ColorToRGB(EditorState.RectangleFillColor) = ColorToRGB(clFuchsia)),
      'legacy creation colors did not use the common paint');
    Style.PrepareLinearGradient(clFuchsia);
    Style.Kind := slpkGradient;
    Style.GradientEndColor := clAqua;
    Style.LinearStart := TPointF.Create(0.25, 0.5);
    Style.LinearEnd := TPointF.Create(0.75, 0.5);
    EditorState.CreationPaintStyle := Style;
    Check((EditorState.CreationPaintStyle.Kind = slpkGradient) and
      (ColorToRGB(EditorState.CreationPaintStyle.GradientStartColor) =
       ColorToRGB(clFuchsia)) and
      (ColorToRGB(EditorState.CreationPaintStyle.GradientEndColor) =
       ColorToRGB(clAqua)) and
      SameValue(EditorState.CreationPaintStyle.LinearStart.X, 0.25) and
      SameValue(EditorState.CreationPaintStyle.LinearEnd.X, 0.75),
      'linear gradient mode did not retain its colors and direction');
    Style.Kind := slpkSolid;
    EditorState.CreationPaintStyle := Style;
    Check(ColorToRGB(EditorState.CreationColor) = ColorToRGB(clFuchsia),
      'returning to solid mode lost the solid color');

    Document.SetCanvasSize(200, 200);
    EditorState.CurrentTool := vetLine;
    Creation.Configure(Document, History, EditorState,
      Rect(0, 0, 200, 200), 1.0);
    DragCreate(Creation, Point(20, 100), Point(180, 100));
    Check((Document[1] is TVectArtPathLayer) and
      (ColorToRGB(TVectArtPathLayer(Document[1]).StrokeColor) =
       ColorToRGB(clFuchsia)),
      'line did not adopt the creation paint color');

    EditorState.CurrentTool := vetRectangle;
    Creation.Configure(Document, History, EditorState,
      Rect(0, 0, 200, 200), 1.0);
    DragCreate(Creation, Point(40, 40), Point(90, 90));
    Check((Document[2] is TVectArtRectangleLayer) and
      (ColorToRGB(TVectArtRectangleLayer(Document[2]).FillColor) =
       ColorToRGB(clFuchsia)),
      'filled shape did not adopt the creation paint color');

    EditorState.CurrentTool := vetTextPath;
    Creation.Configure(Document, History, EditorState,
      Rect(0, 0, 200, 200), 1.0);
    Check(Creation.MouseDown(mbLeft, [], 30, 130),
      'text path start was not accepted');
    Check(Creation.MouseDown(mbLeft, [], 160, 130),
      'text path end was not accepted');
    Check(Creation.FinishPath(False), 'text path was not created');
    Check((Document[3] is TScreenLayoutTextPathLayer) and
      (ColorToRGB(TScreenLayoutTextPathLayer(Document[3]).FillColor) =
       ColorToRGB(clFuchsia)),
      'text path did not adopt the creation paint color');

    Style.Kind := slpkGradient;
    EditorState.CreationPaintStyle := Style;
    EditorState.CurrentTool := vetRectangle;
    Creation.Configure(Document, History, EditorState,
      Rect(0, 0, 200, 200), 1.0);
    DragCreate(Creation, Point(100, 40), Point(180, 90));
    Check((Document[4] is TVectArtRectangleLayer) and
      (Document[4].PaintStyle.Kind = slpkGradient) and
      (ColorToRGB(Document[4].PaintStyle.GradientStartColor) =
       ColorToRGB(clFuchsia)) and
      (ColorToRGB(Document[4].PaintStyle.GradientEndColor) =
       ColorToRGB(clAqua)),
      'new layer did not adopt the complete gradient paint');
    History.Undo;
    History.Redo;
    Check((Document[4].PaintStyle.Kind = slpkGradient) and
      (ColorToRGB(Document[4].PaintStyle.GradientEndColor) =
       ColorToRGB(clAqua)),
      'insert undo/redo did not preserve the gradient paint');
  finally
    Creation.Free;
    History.Free;
    EditorState.Free;
    Document.Free;
  end;
end;

begin
  try
    Run;
    Writeln('PASS');
  except
    on E: Exception do
    begin
      Writeln('FAIL: ' + E.ClassName + ': ' + E.Message);
      Halt(1);
    end;
  end;
end.
