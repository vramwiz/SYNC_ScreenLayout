program ScreenLayoutCanvasCreationOverlapTest;

{$APPTYPE CONSOLE}

uses
  System.Classes,
  System.SysUtils,
  System.Types,
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
    procedure DragCreate(const StartPoint, EndPoint: TPoint);
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

procedure Run;
var
  CanvasControl: TTestCanvasControl;
  Child: TVectArtRectangleLayer;
  Context: IVectArtDesignerContext;
  Document: TVectArtDocument;
  EditorState: TVectArtEditorState;
  Form: TForm;
  Group: TScreenLayoutGroupLayer;
  Harness: TDocumentRefreshHarness;
  History: TVectArtEditHistory;
  PropertiesFrame: TObjectPropertiesFrame;
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
