program ScreenLayoutCanvasCreationOverlapTest;

{$APPTYPE CONSOLE}

uses
  System.Classes,
  System.Math,
  System.SysUtils,
  System.Types,
  Winapi.Messages,
  Winapi.Windows,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.Graphics,
  ScreenLayoutCanvas in '..\Source\Editor\ScreenLayoutCanvas.pas',
  ScreenLayoutContext in '..\Source\Core\Model\ScreenLayoutContext.pas',
  ScreenLayoutDocument in '..\Source\Core\Model\ScreenLayoutDocument.pas',
  ScreenLayoutEditHistory in
    '..\Source\Core\Model\ScreenLayoutEditHistory.pas',
  ScreenLayoutEditorState in
    '..\Source\Core\Model\ScreenLayoutEditorState.pas',
  ScreenLayoutObjectPropertiesFrame in
    '..\Source\ObjectProperties\ScreenLayoutObjectPropertiesFrame.pas',
  TextRendererSkiaRuntime in
    '..\Lib\TextRenderer\TextRendererSkiaRuntime.pas';

type
  TDocumentRefreshHarness = class
  public
    Frame: TObjectPropertiesFrame;
    procedure DocumentChanged(Sender: TObject);
  end;

  TTestCanvasControl = class(TVectArtCanvasControl)
  public
    procedure ClickAt(const PointValue: TPoint);
    procedure DoubleClickSelected;
    procedure DragCreate(const StartPoint, EndPoint: TPoint);
    procedure DragWithButton(Button: TMouseButton;
      const StartPoint, EndPoint: TPoint);
  end;

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
    raise Exception.Create(MessageText);
end;

procedure TDocumentRefreshHarness.DocumentChanged(Sender: TObject);
begin
  Frame.RefreshFromDocument;
end;

procedure TTestCanvasControl.DragCreate(const StartPoint,
  EndPoint: TPoint);
begin
  MouseDown(mbLeft, [], StartPoint.X, StartPoint.Y);
  MouseMove([ssLeft], EndPoint.X, EndPoint.Y);
  MouseUp(mbLeft, [], EndPoint.X, EndPoint.Y);
end;

procedure TTestCanvasControl.DragWithButton(Button: TMouseButton;
  const StartPoint, EndPoint: TPoint);
var
  Shift: TShiftState;
begin
  case Button of
    mbLeft: Shift := [ssLeft];
    mbRight: Shift := [ssRight];
    mbMiddle: Shift := [ssMiddle];
  else
    Shift := [];
  end;
  MouseDown(Button, [], StartPoint.X, StartPoint.Y);
  MouseMove(Shift, EndPoint.X, EndPoint.Y);
  MouseUp(Button, [], EndPoint.X, EndPoint.Y);
end;

procedure TTestCanvasControl.ClickAt(const PointValue: TPoint);
begin
  MouseDown(mbLeft, [], PointValue.X, PointValue.Y);
  MouseUp(mbLeft, [], PointValue.X, PointValue.Y);
end;

procedure TTestCanvasControl.DoubleClickSelected;
begin
  DblClick;
end;

procedure Run;
var
  CanvasControl: TTestCanvasControl;
  CanvasBoundsBeforePan: TRect;
  Child: TVectArtRectangleLayer;
  Context: IVectArtDesignerContext;
  Document: TVectArtDocument;
  EditorState: TVectArtEditorState;
  Form: TForm;
  Group: TScreenLayoutGroupLayer;
  Harness: TDocumentRefreshHarness;
  History: TVectArtEditHistory;
  PropertiesFrame: TObjectPropertiesFrame;
  ResizedBounds: TRectF;
  ResizedWrapWidth: Single;
begin
  Document := TVectArtDocument.Create;
  EditorState := TVectArtEditorState.Create;
  History := TVectArtEditHistory.Create;
  Form := TForm.Create(nil);
  CanvasControl := TTestCanvasControl.Create(Form);
  PropertiesFrame := TObjectPropertiesFrame.Create(Form);
  Harness := TDocumentRefreshHarness.Create;
  try
    Document.SetCanvasSize(200, 200);
    Child := TVectArtRectangleLayer.Create('Existing',
      TRectF.Create(-40, -40, 40, 40), clRed);
    Group := TScreenLayoutGroupLayer.Create('Open group');
    Group.AddChild(Child);
    Document.InsertLayer(Document.LayerCount, Group);
    Document.SelectedIndex := 1;
    EditorState.OpenGroup := Group;
    EditorState.OpenGroupChild := Child;

    CanvasControl.Parent := Form;
    CanvasControl.SetBounds(0, 0, 300, 300);
    CanvasControl.Document := Document;
    CanvasControl.EditHistory := History;
    CanvasControl.EditorState := EditorState;
    PropertiesFrame.Parent := Form;
    PropertiesFrame.SetBounds(300, 0, 180, 300);
    Context := TVectArtDesignerContext.Create(Document, History,
      EditorState);
    PropertiesFrame.Context := Context;
    Harness.Frame := PropertiesFrame;
    Document.OnChanged := Harness.DocumentChanged;
    EditorState.CurrentTool := vetRectangle;
    Form.SetBounds(-10000, -10000, 320, 340);
    Form.Show;
    Application.ProcessMessages;

    CanvasControl.DragCreate(Point(120, 120), Point(180, 180));
    Check(EditorState.CurrentTool = vetRectangle,
      'document refresh cancelled the rectangle creation tool');
    Check(Document.LayerCount = 3,
      'drawing over an open-group child selected it instead of creating');
    Check(Document[2] is TVectArtRectangleLayer,
      'overlapping rectangle was not created');
    Check(Document.SelectedIndex = 2,
      'newly created overlapping rectangle was not selected');

    EditorState.OpenGroup := nil;
    EditorState.CurrentTool := vetText;
    CanvasControl.DragCreate(Point(190, 90), Point(235, 130));
    Check(Document.LayerCount = 4,
      'text frame was not created for the focus-finish test');
    Check(Document[3] is TScreenLayoutTextLayer,
      'created text frame has the wrong layer type');
    Check(Form.ActiveControl <> nil,
      'text input control did not receive focus');
    SendMessage(Form.ActiveControl.Handle, WM_CHAR, Ord('A'), 0);
    Application.ProcessMessages;
    Check(TScreenLayoutTextLayer(Document[3]).Text = 'A',
      'test text was not committed through the input control');
    CanvasControl.ClickAt(Point(150, 150));
    Check(EditorState.CurrentTool = vetSelect,
      'clicking outside edited text did not activate selection mode');
    Check(Document.LayerCount = 4,
      'clicking outside edited text created another text frame');
    Check(TScreenLayoutTextLayer(Document[3]).Text = 'A',
      'clicking outside edited text did not preserve committed input');
    Check(Document.SelectedIndex = 2,
      Format('the finish click was not continued as a selection click (%d)',
        [Document.SelectedIndex]));

    ResizedBounds := TRectF.Create(-70, -35, 65, 55);
    ResizedWrapWidth := TScreenLayoutTextLayer(Document[3]).WrapWidth;
    TScreenLayoutTextLayer(Document[3]).Bounds := ResizedBounds;
    Document.SelectedIndex := 3;
    CanvasControl.DoubleClickSelected;
    Check(Form.ActiveControl <> nil,
      'existing text input control did not receive focus');
    SendMessage(Form.ActiveControl.Handle, WM_CHAR, Ord('B'), 0);
    Application.ProcessMessages;
    CanvasControl.ClickAt(Point(150, 150));
    Check(SameValue(TScreenLayoutTextLayer(Document[3]).Bounds.Left,
      ResizedBounds.Left) and
      SameValue(TScreenLayoutTextLayer(Document[3]).Bounds.Top,
      ResizedBounds.Top) and
      SameValue(TScreenLayoutTextLayer(Document[3]).Bounds.Right,
      ResizedBounds.Right) and
      SameValue(TScreenLayoutTextLayer(Document[3]).Bounds.Bottom,
      ResizedBounds.Bottom),
      're-editing text reset the resized bounds');
    Check(SameValue(TScreenLayoutTextLayer(Document[3]).WrapWidth,
      ResizedWrapWidth),
      're-editing text changed the existing wrap width');

    CanvasBoundsBeforePan := CanvasControl.CanvasBounds;
    CanvasControl.DragWithButton(mbRight, Point(20, 20), Point(40, 45));
    Check(CanvasControl.CanvasBounds = CanvasBoundsBeforePan,
      'right-button drag still moved the canvas');
    CanvasControl.DragWithButton(mbMiddle, Point(20, 20), Point(40, 45));
    Check((CanvasControl.CanvasBounds.Left = CanvasBoundsBeforePan.Left + 20) and
      (CanvasControl.CanvasBounds.Top = CanvasBoundsBeforePan.Top + 25),
      'middle-button drag did not move the canvas');
  finally
    Document.OnChanged := nil;
    PropertiesFrame.Context := nil;
    Context := nil;
    Harness.Free;
    PropertiesFrame.Free;
    CanvasControl.Free;
    Form.Free;
    History.Free;
    EditorState.Free;
    Document.Free;
  end;
end;

begin
  try
    Application.Initialize;
    TTextRendererSkiaRuntime.Acquire(
      ExtractFilePath(ParamStr(0)) + 'sk4d.dll');
    try
      Run;
    finally
      TTextRendererSkiaRuntime.Release;
    end;
    Writeln('PASS');
  except
    on E: Exception do
    begin
      Writeln('FAIL: ' + E.ClassName + ': ' + E.Message);
      Halt(1);
    end;
  end;
end.
