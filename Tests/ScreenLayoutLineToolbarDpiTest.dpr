program ScreenLayoutLineToolbarDpiTest;

{$APPTYPE CONSOLE}

uses
  System.Math,
  System.SysUtils,
  Winapi.Windows,
  Vcl.Forms,
  ScreenLayoutDocument in '..\Source\Core\Model\ScreenLayoutDocument.pas',
  ScreenLayoutEditorState in
    '..\Source\Core\Model\ScreenLayoutEditorState.pas',
  ScreenLayoutEditHistory in
    '..\Source\Core\Model\ScreenLayoutEditHistory.pas',
  ScreenLayoutLineToolbar in
    '..\Source\Shell\Toolbars\ScreenLayoutLineToolbar.pas';

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
    raise Exception.Create(MessageText);
end;

var
  Document: TVectArtDocument;
  ExpectedTrackWidth: Integer;
  ExpectedWidth: Integer;
  Form: TForm;
  History: TVectArtEditHistory;
  PPI: Integer;
  State: TVectArtEditorState;
  Toolbar: TVectArtLineToolbarControl;

begin
  SetProcessDPIAware;
  Application.Initialize;
  Form := TForm.Create(nil);
  Document := TVectArtDocument.Create;
  History := TVectArtEditHistory.Create;
  State := TVectArtEditorState.Create;
  try
    Toolbar := TVectArtLineToolbarControl.CreateForHost(Form, Form);
    Toolbar.Document := Document;
    Toolbar.EditHistory := History;
    Toolbar.EditorState := State;
    State.ActivateTool(vetLine);
    Toolbar.RefreshState;

    PPI := Toolbar.CurrentPPI;
    ExpectedWidth := MulDiv(350, PPI, 96);
    ExpectedTrackWidth := Max(ExpectedWidth - MulDiv(256, PPI, 96),
      MulDiv(60, PPI, 96));
    Check(Toolbar.Width = ExpectedWidth, Format(
      'line toolbar width was reset without DPI scaling: PPI=%d Width=%d',
      [PPI, Toolbar.Width]));
    Check(Toolbar.StrokeWidthTrackBar.Visible,
      'stroke width trackbar is hidden');
    Check(Toolbar.StrokeWidthTrackBar.Left = MulDiv(40, PPI, 96),
      'stroke width trackbar left position is not DPI scaled');
    Check(Toolbar.StrokeWidthTrackBar.Width = ExpectedTrackWidth,
      'stroke width trackbar width is not DPI scaled');
    Check(Toolbar.StrokeWidthTrackBar.Left +
      Toolbar.StrokeWidthTrackBar.Width <= Toolbar.StrokeWidthEdit.Left,
      'stroke width trackbar overlaps the numeric edit');
    Check(Toolbar.StrokeWidthModeButton(slwmUniform).Left >=
      Toolbar.StrokeWidthEdit.Left + Toolbar.StrokeWidthEdit.Width,
      'uniform-width button overlaps the numeric edit');
    Check(Toolbar.StrokeWidthModeButton(slwmVariable).Left +
      Toolbar.StrokeWidthModeButton(slwmVariable).Width <=
      Toolbar.DetailsButton.Left,
      'variable-width button overlaps the details button');
    Writeln(Format('PASS line toolbar DPI layout: %d DPI', [PPI]));
  finally
    State.Free;
    History.Free;
    Document.Free;
    Form.Free;
  end;
end.
