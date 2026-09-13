program ScreenLayoutObjectEditingShortcutsTest;

{$APPTYPE CONSOLE}

uses
  Winapi.Windows, Winapi.ActiveX, System.SysUtils, System.Types, System.Classes,
  Vcl.Controls, Vcl.Forms, Vcl.Graphics, Vcl.Clipbrd,
  ScreenLayoutMainForm, ScreenLayoutCanvas, ScreenLayoutDocument, ScreenLayoutEditorState;

type
  TCanvasAccess = class(TVectArtCanvasControl);

procedure Check(Value: Boolean; const MessageText: string);
begin
  if not Value then raise Exception.Create(MessageText);
end;

function FindCanvas(Control: TWinControl): TVectArtCanvasControl;
var
  I: Integer;
begin
  if Control is TVectArtCanvasControl then Exit(TVectArtCanvasControl(Control));
  for I := 0 to Control.ControlCount - 1 do
    if Control.Controls[I] is TWinControl then
    begin
      Result := FindCanvas(TWinControl(Control.Controls[I]));
      if Result <> nil then Exit;
    end;
  Result := nil;
end;

procedure Run;
var
  Form: TMainForm;
  Canvas: TVectArtCanvasControl;
  Key: Word;
  TextLayer: TScreenLayoutTextLayer;
  OriginalClipboard: IDataObject;
begin
  OleGetClipboard(OriginalClipboard);
  Form := TMainForm.Create(nil);
  try
    Form.Show;
    Canvas := FindCanvas(Form);
    Check(Canvas <> nil, 'canvas missing');
    Canvas.SetFocus;
    Form.Document.InsertLayer(1, TVectArtRectangleLayer.Create('Rectangle',
      TRectF.Create(0, 0, 50, 50), clRed));
    Form.Document.SetSelectedLayers([1]);
    Key := Ord('C');
    Form.FormKeyDown(Form, Key, [ssCtrl]);
    Check(Key = 0, 'copy shortcut not handled');
    Key := Ord('V');
    Form.FormKeyDown(Form, Key, [ssCtrl]);
    Check((Key = 0) and (Form.Document.LayerCount = 3), 'paste shortcut');
    Key := VK_DELETE;
    Form.FormKeyDown(Form, Key, []);
    Check((Key = 0) and (Form.Document.LayerCount = 2), 'delete shortcut');
    Key := Ord('Z');
    Form.FormKeyDown(Form, Key, [ssCtrl]);
    Check(Form.Document.LayerCount = 3, 'undo shortcut');
    Key := Ord('A');
    Form.FormKeyDown(Form, Key, [ssCtrl]);
    Check(Form.Document.SelectionCount = 2, 'select all shortcut');
    TextLayer := TScreenLayoutTextLayer.Create('Text', TRectF.Create(0, 0, 120, 40),
      'abc', 'Segoe UI', 24, 120, clBlack);
    Form.Document.InsertLayer(3, TextLayer);
    Form.Document.SetSelectedLayers([3]);
    TCanvasAccess(Canvas).DblClick;
    Check(Canvas.TextEditing, 'text editing did not start');
    Key := Ord('C');
    Form.FormKeyDown(Form, Key, [ssCtrl]);
    Check(Key = Ord('C'), 'text copy intercepted by object handler');
    Key := VK_DELETE;
    Form.FormKeyDown(Form, Key, []);
    Check((Key = VK_DELETE) and (Form.Document.LayerCount = 4), 'text delete removed object');
    Key := Ord('V');
    Form.FormKeyDown(Form, Key, [ssCtrl]);
    Check((Key = Ord('V')) and (Form.Document.LayerCount = 4), 'text paste duplicated object');
    Writeln('PASS: Ctrl+C/V/A/Z, Delete, text editing priority');
  finally
    Form.Free;
    if OriginalClipboard <> nil then
    begin
      OleSetClipboard(OriginalClipboard);
      OleFlushClipboard;
    end
    else Clipboard.Clear;
  end;
end;

begin
  OleInitialize(nil);
  try
    Application.Initialize;
    try
      Run;
    except
      on E: Exception do
      begin
        Writeln(E.ClassName, ': ', E.Message);
        ExitCode := 1;
      end;
    end;
  finally
    OleUninitialize;
  end;
end.