program ScreenLayoutOutlineCanvasEditTest;

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
  CanvasControl: TTestCanvasControl;
  Data: TVectArtRectangleData;
  Document: TVectArtDocument;
  EditorState: TVectArtEditorState;
  Form: TForm;
  History: TVectArtEditHistory;
  Layer: TVectArtLayer;
  Outline: TScreenLayoutOutlineFilter;
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
    Data.Name := 'Outlined';
    Data.Opacity := 1.0;
    Data.RotationDegrees := 0.0;
    Data.Visible := True;
    Document.InsertRectangle(1, Data);
    Document.SetSelectedLayers([1]);
    Layer := Document[1];
    Outline := TScreenLayoutOutlineFilter.Create;
    Outline.Width := 4;
    Layer.AddFilter(Outline);
    EditorState.SelectFilter(Layer, Outline);

    CanvasControl.Parent := Form;
    CanvasControl.SetBounds(0, 0, 300, 300);
    CanvasControl.Document := Document;
    CanvasControl.EditHistory := History;
    CanvasControl.EditorState := EditorState;
    Form.SetBounds(-10000, -10000, 320, 340);
    Form.Show;
    Application.ProcessMessages;

    RightHandle := Point(CanvasControl.CanvasBounds.Left + 100 + 40 + 4,
      CanvasControl.CanvasBounds.Top + 100);
    CanvasControl.Drag(RightHandle,
      Point(RightHandle.X + 10, RightHandle.Y));
    Check(SameValue(Outline.Width, 14.0),
      'right handle did not update outline width');
    Check(History.CanUndo, 'outline drag was not added to history');
    History.Undo;
    Check(SameValue(Outline.Width, 4.0), 'outline drag undo failed');
    History.Redo;
    Check(SameValue(Outline.Width, 14.0), 'outline drag redo failed');

    RightHandle := Point(CanvasControl.CanvasBounds.Left + 100 + 40 + 14,
      CanvasControl.CanvasBounds.Top + 100);
    CanvasControl.Drag(RightHandle,
      Point(RightHandle.X + 100, RightHandle.Y));
    Check(SameValue(Outline.Width, 40.0),
      'outline width was not clamped to slider maximum');
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
