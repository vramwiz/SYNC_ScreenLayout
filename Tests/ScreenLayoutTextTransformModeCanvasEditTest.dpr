program ScreenLayoutTextTransformModeCanvasEditTest;

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
  ScreenLayoutDocument in '..\Source\Core\Model\ScreenLayoutDocument.pas',
  ScreenLayoutEditHistory in
    '..\Source\Core\Model\ScreenLayoutEditHistory.pas',
  ScreenLayoutGroupInteraction in
    '..\Source\Editor\Interaction\ScreenLayoutGroupInteraction.pas',
  ScreenLayoutSelectionGeometry in
    '..\Source\Editor\Interaction\ScreenLayoutSelectionGeometry.pas';

const
  CANVAS_CENTER = 200;

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
    raise Exception.Create(MessageText);
end;

function BottomRightHandle(const Bounds: TRectF): TPoint;
var
  Geometry: TVectArtSelectionGeometry;
  LayerRect: TRect;
begin
  LayerRect := Rect(Round(CANVAS_CENTER + Bounds.Left),
    Round(CANVAS_CENTER + Bounds.Top),
    Round(CANVAS_CENTER + Bounds.Right),
    Round(CANVAS_CENTER + Bounds.Bottom));
  Geometry := BuildSelectionGeometry(LayerRect,
    SelectionFrameOffset(0, 1.0));
  Result := Point(
    (Geometry.Handles[vshBottomRight].Left +
      Geometry.Handles[vshBottomRight].Right) div 2,
    (Geometry.Handles[vshBottomRight].Top +
      Geometry.Handles[vshBottomRight].Bottom) div 2);
end;

procedure DragResize(Interaction: TVectArtCanvasInteraction;
  const Shift: TShiftState; const StartPoint, EndPoint: TPoint);
var
  DragShift: TShiftState;
begin
  Check(Interaction.MouseDown(mbLeft, Shift, StartPoint.X, StartPoint.Y),
    'text resize handle did not start a drag');
  DragShift := Shift + [ssLeft];
  Check(Interaction.MouseMove(DragShift, EndPoint.X, EndPoint.Y),
    'text resize drag was not handled');
  Check(Interaction.MouseUp(mbLeft), 'text resize drag was not committed');
end;

procedure CheckUniformScale(const BeforeBounds, AfterBounds: TRectF;
  const MessageText: string);
begin
  Check(SameValue(AfterBounds.Width / BeforeBounds.Width,
    AfterBounds.Height / BeforeBounds.Height, 0.0001), MessageText);
end;

procedure Run;
var
  BeforeBounds: TRectF;
  Data: TScreenLayoutTextData;
  Document: TVectArtDocument;
  EndPoint: TPoint;
  GroupDrag: TScreenLayoutGroupDrag;
  History: TVectArtEditHistory;
  Interaction: TVectArtCanvasInteraction;
  StartPoint: TPoint;
  TextLayer: TScreenLayoutTextLayer;
begin
  Document := TVectArtDocument.Create;
  History := TVectArtEditHistory.Create;
  Interaction := TVectArtCanvasInteraction.Create;
  GroupDrag := TScreenLayoutGroupDrag.Create;
  try
    Document.SetCanvasSize(200, 200);
    Data := Default(TScreenLayoutTextData);
    Data.Bounds := TRectF.Create(-50, -25, 50, 25);
    Data.FontFamily := 'Yu Gothic UI';
    Data.FontSize := 20;
    Data.Name := 'Text';
    Data.Opacity := 1.0;
    Data.Text := 'AB';
    Data.TextColor := clWhite;
    Data.Visible := True;
    Data.WrapWidth := 100;
    Document.InsertText(1, Data);
    Document.SetSelectedLayers([1]);
    TextLayer := TScreenLayoutTextLayer(Document[1]);
    Check(TextLayer.TransformMode = slttmUniformScale,
      'new text did not default to uniform scale');
    Interaction.EditHistory := History;
    Interaction.Configure(Document, Rect(0, 0, 400, 400), 1.0);

    BeforeBounds := TextLayer.Bounds;
    StartPoint := BottomRightHandle(BeforeBounds);
    EndPoint := Point(StartPoint.X + 40, StartPoint.Y);
    DragResize(Interaction, [], StartPoint, EndPoint);
    CheckUniformScale(BeforeBounds, TextLayer.Bounds,
      'plain drag did not preserve the stored uniform mode');
    History.Undo;

    Interaction.Configure(Document, Rect(0, 0, 400, 400), 1.0);
    BeforeBounds := TextLayer.Bounds;
    StartPoint := BottomRightHandle(BeforeBounds);
    EndPoint := Point(StartPoint.X + 40, StartPoint.Y);
    DragResize(Interaction, [ssCtrl], StartPoint, EndPoint);
    Check(TextLayer.TransformMode = slttmFrameFit,
      'Ctrl drag did not switch to frame fit');
    Check(not SameValue(TextLayer.Bounds.Width / BeforeBounds.Width,
      TextLayer.Bounds.Height / BeforeBounds.Height, 0.0001),
      'frame fit unexpectedly preserved the aspect ratio');
    History.Undo;
    Check(TextLayer.TransformMode = slttmUniformScale,
      'Ctrl drag undo did not restore the previous mode');
    History.Redo;
    Check(TextLayer.TransformMode = slttmFrameFit,
      'Ctrl drag redo did not restore frame fit');

    Interaction.Configure(Document, Rect(0, 0, 400, 400), 1.0);
    BeforeBounds := TextLayer.Bounds;
    StartPoint := BottomRightHandle(BeforeBounds);
    EndPoint := Point(StartPoint.X + 30, StartPoint.Y);
    DragResize(Interaction, [], StartPoint, EndPoint);
    Check(SameValue(TextLayer.Bounds.Height, BeforeBounds.Height),
      'plain drag did not retain the stored frame-fit mode');

    Interaction.Configure(Document, Rect(0, 0, 400, 400), 1.0);
    BeforeBounds := TextLayer.Bounds;
    StartPoint := BottomRightHandle(BeforeBounds);
    EndPoint := Point(StartPoint.X + 30, StartPoint.Y);
    DragResize(Interaction, [ssShift], StartPoint, EndPoint);
    Check(TextLayer.TransformMode = slttmUniformScale,
      'Shift drag did not switch to uniform scale');
    CheckUniformScale(BeforeBounds, TextLayer.Bounds,
      'Shift drag did not preserve the aspect ratio');
    History.Undo;
    Check(TextLayer.TransformMode = slttmFrameFit,
      'Shift drag undo did not restore frame fit');
    History.Redo;
    Check(TextLayer.TransformMode = slttmUniformScale,
      'Shift drag redo did not restore uniform scale');

    BeforeBounds := TextLayer.Bounds;
    GroupDrag.BeginResize(Document, [TextLayer], Point(0, 0), vshRight,
      BeforeBounds);
    Check(GroupDrag.UpdateMoveOrResize([ssCtrl, ssLeft], 30, 0, 1.0),
      'open-group text resize was not handled');
    Check(GroupDrag.Finish(History),
      'open-group text resize was not committed');
    Check(TextLayer.TransformMode = slttmFrameFit,
      'open-group Ctrl drag did not switch to frame fit');
    Check(SameValue(TextLayer.Bounds.Height, BeforeBounds.Height),
      'open-group frame fit changed the untouched dimension');
    History.Undo;
    Check(TextLayer.TransformMode = slttmUniformScale,
      'open-group text resize undo did not restore the mode');
    History.Redo;
    Check(TextLayer.TransformMode = slttmFrameFit,
      'open-group text resize redo did not restore the mode');
  finally
    GroupDrag.Free;
    Interaction.Free;
    History.Free;
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
