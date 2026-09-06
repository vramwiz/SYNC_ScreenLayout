// フィルター追加が標準メニューではなく共通ダークポップアップを使用することを確認する。
program ScreenLayoutFilterMenuTest;

{$APPTYPE CONSOLE}

uses
  System.Types,
  System.SysUtils,
  Vcl.Controls,
  Vcl.ExtCtrls,
  Vcl.Forms,
  Vcl.Graphics,
  ScreenLayoutContext,
  ScreenLayoutDocument,
  ScreenLayoutEditHistory,
  ScreenLayoutEditorState,
  ScreenLayoutFilterFrame,
  VectArtDarkPopupMenu;

type
  TPanelAccess = class(TPanel);

procedure Check(Value: Boolean; const MessageText: string);
begin
  if not Value then
    raise Exception.Create(MessageText);
end;

var
  AddButton: TPanel;
  Context: IVectArtDesignerContext;
  Data: TVectArtRectangleData;
  DeleteButton: TPanel;
  Document: TVectArtDocument;
  EditorState: TVectArtEditorState;
  FilterFrame: TScreenLayoutFilterFrame;
  Form: TForm;
  HasBlurItem: Boolean;
  HasOutlineItem: Boolean;
  HasShadowItem: Boolean;
  History: TVectArtEditHistory;
  I: Integer;
  Menu: TVectArtDarkPopupMenu;
  OutlineItem: TPanel;

begin
  try
    Application.Initialize;
    Form := TForm.CreateNew(nil);
    Document := TVectArtDocument.Create;
    EditorState := TVectArtEditorState.Create;
    History := TVectArtEditHistory.Create;
    try
      Data.Bounds := TRectF.Create(-20, -20, 20, 20);
      Data.FillColor := clBlue;
      Data.Locked := False;
      Data.Name := 'Rectangle';
      Data.Opacity := 1;
      Data.Visible := True;
      Document.InsertRectangle(Document.LayerCount, Data);
      Document.SetSelectedLayers([1]);
      Context := TVectArtDesignerContext.Create(Document, History, EditorState);
      FilterFrame := TScreenLayoutFilterFrame.Create(Form);
      FilterFrame.Parent := Form;
      FilterFrame.Context := Context;
      AddButton := nil;
      DeleteButton := nil;
      for I := 0 to FilterFrame.ComponentCount - 1 do
        if (FilterFrame.Components[I] is TPanel) and
          (TPanel(FilterFrame.Components[I]).Hint = 'フィルターを追加') then
          AddButton := TPanel(FilterFrame.Components[I])
        else if (FilterFrame.Components[I] is TPanel) and
          (TPanel(FilterFrame.Components[I]).Hint =
            '選択したフィルターを削除') then
          DeleteButton := TPanel(FilterFrame.Components[I]);
      Check((AddButton <> nil) and (DeleteButton <> nil),
        'filter toolbar buttons missing');
      Check((AddButton.Width > DeleteButton.Width) and
        (AddButton.Caption = ''), 'filter add button was not enlarged');
      Check((DeleteButton.Caption <> 'x') and (DeleteButton.Caption <> 'X'),
        'filter delete button still uses an X caption');
      Check(AddButton.Enabled, 'filter add button was not enabled for selection');
      TPanelAccess(AddButton).Click;

      Menu := nil;
      for I := 0 to FilterFrame.ComponentCount - 1 do
        if FilterFrame.Components[I] is TVectArtDarkPopupMenu then
          Menu := TVectArtDarkPopupMenu(FilterFrame.Components[I]);
      Check((Menu <> nil) and Menu.Visible,
        'filter add button did not open the dark popup menu');
      Check(Menu.Popup.ControlCount = 3,
        'filter dark popup item count is wrong');
      HasOutlineItem := False;
      HasShadowItem := False;
      HasBlurItem := False;
      OutlineItem := nil;
      for I := 0 to Menu.Popup.ControlCount - 1 do
        if Menu.Popup.Controls[I] is TPanel then
        begin
          HasOutlineItem := HasOutlineItem or
            (TPanel(Menu.Popup.Controls[I]).Caption = '縁取り');
          if TPanel(Menu.Popup.Controls[I]).Caption = '縁取り' then
            OutlineItem := TPanel(Menu.Popup.Controls[I]);
          HasShadowItem := HasShadowItem or
            (TPanel(Menu.Popup.Controls[I]).Caption = '影');
          HasBlurItem := HasBlurItem or
            (TPanel(Menu.Popup.Controls[I]).Caption = 'ぼかし');
        end;
      Check(HasOutlineItem and HasShadowItem and HasBlurItem,
        'filter dark popup captions are wrong');

      TPanelAccess(AddButton).Click;
      Check(not Menu.Visible, 'second add-button click did not close the menu');
      TPanelAccess(AddButton).Click;
      TPanelAccess(OutlineItem).Click;
      Check((Document[1].FilterCount = 1) and not Menu.Visible,
        'dark popup item did not add and close');
      History.Undo;
      Check(Document[1].FilterCount = 0,
        'dark popup filter addition was not undoable');
      History.Redo;
      Check(Document[1].FilterCount = 1,
        'dark popup filter addition was not redoable');
      FilterFrame.Context := nil;
      Context := nil;
    finally
      History.Free;
      EditorState.Free;
      Document.Free;
      Form.Free;
    end;
    Writeln('PASS filter dark popup menu');
  except
    on E: Exception do
    begin
      Writeln(E.ClassName + ': ' + E.Message);
      ExitCode := 1;
    end;
  end;
end.
