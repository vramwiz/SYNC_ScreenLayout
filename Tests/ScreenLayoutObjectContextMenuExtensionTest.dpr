program ScreenLayoutObjectContextMenuExtensionTest;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Types,
  Vcl.Forms,
  Vcl.Graphics,
  Vcl.ExtCtrls,
  ScreenLayoutDocument in
    '..\Source\Core\Model\ScreenLayoutDocument.pas',
  ScreenLayoutEditorState in
    '..\Source\Core\Model\ScreenLayoutEditorState.pas',
  ScreenLayoutEditHistory in
    '..\Source\Core\Model\ScreenLayoutEditHistory.pas',
  ScreenLayoutObjectContextMenu in
    '..\Source\Shell\Menus\ScreenLayoutObjectContextMenu.pas',
  ScreenLayoutTextContextMenu in
    '..\Source\Shell\Menus\ScreenLayoutTextContextMenu.pas',
  ScreenLayoutTransformContextMenu in
    '..\Source\Shell\Menus\ScreenLayoutTransformContextMenu.pas',
  ScreenLayoutArrangementContextMenu in
    '..\Source\Shell\Menus\ScreenLayoutArrangementContextMenu.pas',
  VectArtDarkMenuGroup in
    '..\Lib\DarkMenu\VectArtDarkMenuGroup.pas',
  VectArtDarkPopupMenu in
    '..\Lib\DarkMenu\VectArtDarkPopupMenu.pas';

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
    raise Exception.Create(MessageText);
end;

function FindMenuItem(Menu: TVectArtDarkPopupMenu;
  const Caption: string): Boolean;
var
  I: Integer;
begin
  for I := 0 to Menu.Popup.ControlCount - 1 do
    if (Menu.Popup.Controls[I] is TPanel) and
      (TPanel(Menu.Popup.Controls[I]).Caption = Caption) then
      Exit(True);
  Result := False;
end;

procedure Run;
var
  ContextMenu: TScreenLayoutObjectContextMenu;
  Document: TVectArtDocument;
  Form: TForm;
  Group: TScreenLayoutGroupLayer;
  History: TVectArtEditHistory;
  MenuGroup: TVectArtDarkMenuGroup;
  RectangleData: TVectArtRectangleData;
  State: TVectArtEditorState;
  TextData: TScreenLayoutTextData;
begin
  Form := TForm.Create(nil);
  Document := TVectArtDocument.Create;
  State := TVectArtEditorState.Create;
  History := TVectArtEditHistory.Create;
  try
    MenuGroup := TVectArtDarkMenuGroup.Create(Form);
    ContextMenu := TScreenLayoutObjectContextMenu.Create(Form, Form,
      MenuGroup, Document, State);
    ContextMenu.RegisterContributor(TScreenLayoutTextMenuContributor.Create(
      ContextMenu, nil));
    ContextMenu.RegisterContributor(
      TScreenLayoutArrangementMenuContributor.Create(ContextMenu, Document,
        History, State));
    ContextMenu.RegisterContributor(
      TScreenLayoutTransformMenuContributor.Create(ContextMenu, Document,
        History, State));

    RectangleData := Default(TVectArtRectangleData);
    RectangleData.Bounds := TRectF.Create(-50, -50, 50, 50);
    RectangleData.Name := 'Rectangle';
    RectangleData.Opacity := 1;
    RectangleData.Visible := True;
    Document.InsertRectangle(1, RectangleData);
    Document.SelectedIndex := 1;
    ContextMenu.ShowForObject(nil, Point(0, 0));
    Check(FindMenuItem(ContextMenu.Menu, '切り取り    Ctrl+X'),
      'name and shortcut item caption compatibility was lost');
    Check(FindMenuItem(ContextMenu.Menu, '変形  >'),
      'common transform submenu was not added');
    Check(not FindMenuItem(ContextMenu.Menu, '整列と均等配置  >'),
      'arrangement submenu was added for a single selection');
    Check(not FindMenuItem(ContextMenu.Menu, 'テキストの分解  >'),
      'text-only item was added for a rectangle');

    TextData := Default(TScreenLayoutTextData);
    TextData.Bounds := TRectF.Create(-80, -20, 80, 20);
    TextData.FontFamily := 'Segoe UI';
    TextData.FontSize := 32;
    TextData.Name := 'Text';
    TextData.Opacity := 1;
    TextData.Text := 'Sample';
    TextData.TextColor := clWhite;
    TextData.Visible := True;
    TextData.WrapWidth := 160;
    Document.InsertText(2, TextData);
    Document.SelectedIndex := 2;
    ContextMenu.ShowForObject(nil, Point(0, 0), [2, 1]);
    Check(FindMenuItem(ContextMenu.Menu, 'テキストの分解  >'),
      'registered text item was not added for a top-level text layer');
    Check(FindMenuItem(ContextMenu.Menu, 'この位置のレイヤー  >'),
      'overlapping layer selection submenu was not added');
    Document.SetSelectedLayers([1, 2]);
    ContextMenu.ShowForObject(nil, Point(0, 0));
    Check(FindMenuItem(ContextMenu.Menu, '整列と均等配置  >'),
      'arrangement submenu was not added for a multiple selection');
    Check(not FindMenuItem(ContextMenu.Menu, 'テキストの分解  >'),
      'single-text item was added for a mixed multiple selection');

    Group := TScreenLayoutGroupLayer.Create('Group');
    Group.AddChild(TScreenLayoutTextLayer.Create('Child Text',
      TRectF.Create(-40, -10, 40, 10), 'Child', 'Segoe UI', 20, 80,
      clWhite));
    Document.InsertLayer(3, Group);
    State.OpenGroup := Group;
    State.OpenGroupChild := Group[0];
    ContextMenu.ShowForObject(nil, Point(0, 0));
    Check(FindMenuItem(ContextMenu.Menu, 'テキストの分解  >'),
      'registered text item was not added for an open-group text layer');
  finally
    History.Free;
    State.Free;
    Document.Free;
    Form.Free;
  end;
end;

begin
  Application.Initialize;
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
