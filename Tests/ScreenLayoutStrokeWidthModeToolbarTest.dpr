program ScreenLayoutStrokeWidthModeToolbarTest;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Types,
  Vcl.Forms,
  ScreenLayoutDocument,
  ScreenLayoutEditHistory,
  ScreenLayoutEditorState,
  ScreenLayoutLineToolbar;

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
    raise Exception.Create(MessageText);
end;

procedure Run;
var
  Data: TVectArtPathData;
  Document: TVectArtDocument;
  Form: TForm;
  History: TVectArtEditHistory;
  Path: TVectArtPathLayer;
  State: TVectArtEditorState;
  Toolbar: TVectArtLineToolbarControl;
begin
  Form := TForm.Create(nil);
  Document := TVectArtDocument.Create;
  History := TVectArtEditHistory.Create;
  State := TVectArtEditorState.Create;
  try
    Toolbar := TVectArtLineToolbarControl.CreateForHost(Form, Form);
    Toolbar.Document := Document;
    Toolbar.EditHistory := History;
    Toolbar.EditorState := State;
    State.ActivateTool(vetFreehand);
    Toolbar.RefreshState;
    Check(Toolbar.StrokeWidthModeButton(slwmUniform).Visible and
      Toolbar.StrokeWidthModeButton(slwmUniform).Selected,
      'uniform-width icon was not the creation default');
    Check(Toolbar.StrokeWidthModeButton(slwmVariable).Enabled,
      'variable-width icon was disabled for freehand creation');
    Toolbar.StrokeWidthModeButton(slwmVariable).Click;
    Check(State.StrokeWidthMode = slwmVariable,
      'variable-width icon did not update the creation mode');

    Document.SetCanvasSize(200, 200);
    Data := Default(TVectArtPathData);
    SetLength(Data.Vertices, 2);
    Data.Vertices[0].Position := TPointF.Create(-50, 0);
    Data.Vertices[0].OutgoingSegment := slskLine;
    Data.Vertices[1].Position := TPointF.Create(50, 0);
    Data.Name := 'Path';
    Data.Opacity := 1;
    Data.StrokeWidth := 20;
    Data.Visible := True;
    Document.InsertPath(1, Data);
    Document.SelectedIndex := 1;
    State.CurrentTool := vetSelect;
    Toolbar.RefreshState;
    Check(Toolbar.StrokeWidthModeButton(slwmUniform).Selected,
      'selected uniform path was not reflected in the icons');
    Toolbar.StrokeWidthModeButton(slwmVariable).Click;
    Path := TVectArtPathLayer(Document[1]);
    Check((Length(Path.WidthPoints) = 2) and History.CanUndo,
      'variable-width icon did not create an undoable width profile');
    History.Undo;
    Check(Length(Path.WidthPoints) = 0,
      'width-mode Undo did not restore the uniform path');
    History.Redo;
    Check(Length(Path.WidthPoints) = 2,
      'width-mode Redo did not restore the variable path');
    Toolbar.RefreshState;
    Toolbar.StrokeWidthModeButton(slwmUniform).Click;
    Check(Length(Path.WidthPoints) = 0,
      'uniform-width icon did not remove the width profile');
  finally
    State.Free;
    History.Free;
    Document.Free;
    Form.Free;
  end;
end;

begin
  try
    Application.Initialize;
    Run;
    Writeln('PASS stroke-width mode toolbar icons and Undo/Redo');
  except
    on E: Exception do
    begin
      Writeln('FAIL: ' + E.ClassName + ': ' + E.Message);
      ExitCode := 1;
    end;
  end;
end.
