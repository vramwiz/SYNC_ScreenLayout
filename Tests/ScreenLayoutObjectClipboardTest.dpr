program ScreenLayoutObjectClipboardTest;

{$APPTYPE CONSOLE}

uses
  Winapi.Windows, Winapi.ActiveX, System.SysUtils, System.Types, Vcl.Forms, Vcl.Clipbrd, Vcl.Graphics, Vcl.ExtCtrls,
  ScreenLayoutDocument, ScreenLayoutEditorState, ScreenLayoutEditHistory,
  ScreenLayoutObjectClipboard, ScreenLayoutLayerOperations, ScreenLayoutDocumentJson,
  ScreenLayoutGroupCommands, ScreenLayoutObjectContextMenu, VectArtDarkPopupMenu;

procedure Check(Value: Boolean; const MessageText: string);
begin
  if not Value then raise Exception.Create(MessageText);
end;

procedure ClickItem(Menu: TScreenLayoutObjectContextMenu; const Caption: string);
var
  I: Integer;
  Panel: TPanel;
begin
  Menu.ShowForObject(nil, Point(0, 0));
  for I := 0 to Menu.Menu.Popup.ControlCount - 1 do
    if Menu.Menu.Popup.Controls[I] is TPanel then
    begin
      Panel := TPanel(Menu.Menu.Popup.Controls[I]);
      if (Panel.Caption = Caption) or (Pos(Caption + '    ', Panel.Caption) = 1) then
      begin
        Check(Assigned(Panel.OnClick), 'menu handler missing: ' + Caption);
        Panel.OnClick(Panel);
        Exit;
      end;
    end;
  raise Exception.Create('menu item missing: ' + Caption);
end;

procedure Run;
var
  Document, Other: TVectArtDocument;
  State: TVectArtEditorState;
  History: TVectArtEditHistory;
  Operations: TVectArtLayerOperations;
  Group, PastedGroup: TScreenLayoutGroupLayer;
  Rectangle: TVectArtRectangleLayer;
  TextLayer: TScreenLayoutTextLayer;
  Before: string;
  OriginalClipboard: IDataObject;
  Form: TForm;
  Menu: TScreenLayoutObjectContextMenu;
begin
  OleGetClipboard(OriginalClipboard);
  Document := TVectArtDocument.Create;
  Other := TVectArtDocument.Create;
  State := TVectArtEditorState.Create;
  History := TVectArtEditHistory.Create;
  Operations := TVectArtLayerOperations.Create;
  Form := TForm.Create(nil);
  Menu := TScreenLayoutObjectContextMenu.Create(Form, Form, nil, Document, State);
  Menu.EditHistory := History;
  try
    Operations.Document := Document;
    Operations.EditorState := State;
    Operations.EditHistory := History;
    Rectangle := TVectArtRectangleLayer.Create('Rectangle', TRectF.Create(10, 20, 60, 80), clRed);
    Document.InsertLayer(1, Rectangle);
    Group := TScreenLayoutGroupLayer.Create('Group');
    TextLayer := TScreenLayoutTextLayer.Create('Text', TRectF.Create(0, 0, 100, 40),
      'clipboard text', 'Segoe UI', 24, 100, clBlack);
    TextLayer.Text := 'clipboard text';
    Group.AddChild(TextLayer);
    Group.Opacity := 0.6;
    Document.InsertLayer(2, Group);
    Document.SetSelectedLayers([2, 1]);
    Before := SerializeVectArtDocument(Document);
    CopyObjects(Document, State);
    Check(not History.CanUndo, 'copy created history');
    Check(CanPasteObjects(State), 'custom format missing');
    Check(not Clipboard.HasFormat(CF_BITMAP), 'bitmap format exported');
    Check(not Clipboard.HasFormat(CF_UNICODETEXT), 'text format exported');
    Rectangle.FillColor := clBlue;
    PasteObjects(Other, nil, nil);
    Check(Other.LayerCount = 3, 'cross-document paste failed');
    Check(TVectArtRectangleLayer(Other[1]).FillColor = clRed, 'copy was not a snapshot');
    Check(Other[1] <> Rectangle, 'paste shared ownership');
    PastedGroup := TScreenLayoutGroupLayer(Other[2]);
    Check((PastedGroup.ChildCount = 1) and (PastedGroup[0] <> TextLayer), 'group was not deeply copied');
    Check(TScreenLayoutTextLayer(PastedGroup[0]).Text = 'clipboard text', 'text lost');
    Check(Abs(PastedGroup.Opacity - 0.6) < 0.001, 'group opacity lost');
    Rectangle.FillColor := clRed;
    PasteObjects(Document, State, History);
    Check((Document.LayerCount = 5) and (Document.SelectionCount = 2), 'batch paste selection');
    History.Undo;
    Check(SerializeVectArtDocument(Document) = Before, 'paste undo did not restore document');
    Check(not History.CanUndo, 'paste created multiple history entries');
    History.Redo;
    Check(Document.LayerCount = 5, 'paste redo');
    History.Undo;
    State.OpenGroupInDocument(Document, Group);
    State.SetOpenGroupChildren([TextLayer]);
    PasteObjects(Document, State, History);
    Check((Group.ChildCount = 3) and (State.OpenGroupChildCount = 2), 'paste into group');
    History.Undo;
    Check((Group.ChildCount = 1) and (State.OpenGroupChild = TextLayer), 'group paste undo selection');
    History.Redo;
    Check(Group.ChildCount = 3, 'group paste redo');
    CopyObjects(Document, State);
    Check(Length(ClipboardSelection(Document, State)) = 2, 'group selection scope');
    Check(Operations.CanExecute(vlaDelete), 'group delete disabled');
    Operations.Execute(vlaDelete);
    Check(Group.ChildCount = 1, 'group batch delete');
    History.Undo;
    Check(Group.ChildCount = 3, 'group delete undo');
    State.OpenGroup := nil;
    Document.SetSelectedLayers([2, 1]);
    Check(Operations.CanExecute(vlaDelete), 'mixed group delete disabled');
    Operations.Execute(vlaDelete);
    Check(Document.LayerCount = 1, 'mixed group delete');
    History.Undo;
    Check(Document.LayerCount = 3, 'mixed group delete undo');
    Group.Locked := True;
    Check(not Operations.CanExecute(vlaDelete), 'locked selection deletable');
    CopyObjects(Document, State);
    Check(CanPasteObjects(State), 'locked selection not copyable');
    Clipboard.AsText := 'external text';
    Check(not CanPasteObjects(State), 'plain text accepted as objects');
    PasteObjects(Document, State, History);
    Check(Document.LayerCount = 3, 'plain text changed document');
    Group.Locked := False;
    Document.SetSelectedLayers([1]);
    ClickItem(Menu, 'コピー');
    Document.SetSelectedLayers([]);
    ClickItem(Menu, '貼り付け');
    Check(Document.LayerCount = 4, 'menu paste failed');
    ClickItem(Menu, '削除');
    Check(Document.LayerCount = 3, 'menu delete failed');
    History.Undo;
    Check(Document.LayerCount = 4, 'menu delete did not record undo');
    ClickItem(Menu, '切り取り');
    Check(Document.LayerCount = 3, 'menu cut failed');
    ClickItem(Menu, '貼り付け');
    Check(Document.LayerCount = 4, 'cut payload missing');
    Writeln('PASS: snapshot, cross-document, group, selection, history, deletion, locks, private format');
  finally
    Form.Free;
    Operations.Free;
    History.Free;
    State.Free;
    Other.Free;
    Document.Free;
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