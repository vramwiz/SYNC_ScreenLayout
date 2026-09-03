program ScreenLayoutBlurCanvasEditTest;

{$APPTYPE CONSOLE}

uses
  System.Classes,
  System.Math,
  System.SysUtils,
  System.Types,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.Graphics,
  ScreenLayoutCanvas in '..\Source\Editor\ScreenLayoutCanvas.pas',
  ScreenLayoutDocument in '..\Source\Core\Model\ScreenLayoutDocument.pas',
  ScreenLayoutEditHistory in
    '..\Source\Core\Model\ScreenLayoutEditHistory.pas',
  ScreenLayoutEditorState in
    '..\Source\Core\Model\ScreenLayoutEditorState.pas',
  ScreenLayoutFilters in '..\Source\Core\Model\ScreenLayoutFilters.pas',
  TextRendererSkiaRuntime in
    '..\Lib\TextRenderer\TextRendererSkiaRuntime.pas';

type
  TTestCanvasControl = class(TVectArtCanvasControl)
  public
    procedure Drag(const StartPoint, EndPoint: TPoint);
  end;

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
    raise Exception.Create(MessageText);
end;

procedure TTestCanvasControl.Drag(const StartPoint, EndPoint: TPoint);
begin
  MouseDown(mbLeft, [], StartPoint.X, StartPoint.Y);
  MouseMove([ssLeft], EndPoint.X, EndPoint.Y);
  MouseUp(mbLeft, [], EndPoint.X, EndPoint.Y);
end;

procedure Run;
var
  Blur: TScreenLayoutBlurFilter;
  CanvasControl: TTestCanvasControl;
  Data: TVectArtRectangleData;
  Document: TVectArtDocument;
  EditorState: TVectArtEditorState;
  Form: TForm;
  History: TVectArtEditHistory;
  Layer: TVectArtLayer;
  RightHandle: TPoint;
begin
  Document := TVectArtDocument.Create;
  EditorState := TVectArtEditorState.Create;
  History := TVectArtEditHistory.Create;
  Form := TForm.Create(nil);
  CanvasControl := TTestCanvasControl.Create(Form);
  try
    Document.SetCanvasSize(200, 200);
    Data.Bounds := TRectF.Create(-40, -30, 40, 30);
    Data.FillColor := clWhite;
    Data.Locked := False;
    Data.Name := 'Blurred';
    Data.Opacity := 1.0;
    Data.RotationDegrees := 0.0;
    Data.Visible := True;
    Document.InsertRectangle(1, Data);
    Document.SetSelectedLayers([1]);
    Layer := Document[1];
    Blur := TScreenLayoutBlurFilter.Create;
    Blur.Radius := 4;
    Layer.AddFilter(Blur);
    EditorState.SelectFilter(Layer, Blur);

    CanvasControl.Parent := Form;
    CanvasControl.SetBounds(0, 0, 300, 300);
    CanvasControl.Document := Document;
    CanvasControl.EditHistory := History;
    CanvasControl.EditorState := EditorState;
    Form.SetBounds(-10000, -10000, 320, 340);
    Form.Show;
    Application.ProcessMessages;

    RightHandle := Point(CanvasControl.CanvasBounds.Left + 100 + 40 + 12,
      CanvasControl.CanvasBounds.Top + 100);
    CanvasControl.Drag(RightHandle,
      Point(RightHandle.X + 30, RightHandle.Y));
    Check(SameValue(Blur.Radius, 14.0),
      'right handle did not update blur radius');
    Check(History.CanUndo, 'blur drag was not added to history');
    History.Undo;
    Check(SameValue(Blur.Radius, 4.0), 'blur drag undo failed');
    History.Redo;
    Check(SameValue(Blur.Radius, 14.0), 'blur drag redo failed');

    RightHandle := Point(CanvasControl.CanvasBounds.Left + 100 + 40 + 42,
      CanvasControl.CanvasBounds.Top + 100);
    CanvasControl.Drag(RightHandle,
      Point(RightHandle.X + 300, RightHandle.Y));
    Check(SameValue(Blur.Radius, 50.0),
      'blur radius was not clamped to slider maximum');
  finally
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
