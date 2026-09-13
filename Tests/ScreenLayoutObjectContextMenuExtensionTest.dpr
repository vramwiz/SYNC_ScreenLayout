program ScreenLayoutObjectContextMenuExtensionTest;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Types,
  Vcl.Controls,
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

function FindPanel(Control: TWinControl; const Caption: string): TPanel;
var
  I: Integer;
begin
  for I := 0 to Control.ControlCount - 1 do
  begin
    if (Control.Controls[I] is TPanel) and
      (TPanel(Control.Controls[I]).Caption = Caption) then
      Exit(TPanel(Control.Controls[I]));
    if Control.Controls[I] is TWinControl then
    begin
      Result := FindPanel(TWinControl(Control.Controls[I]), Caption);
      if Result <> nil then Exit;
    end;
  end;
  Result := nil;
end;

procedure Run;
var
  ContextMenu: TScreenLayoutObjectContextMenu;
  Document: TVectArtDocument;
  Form: TForm;
  Group: TScreenLayoutGroupLayer;
  History: TVectArtEditHistory;
  MenuGroup: TVectArtDarkMenuGroup;
  MenuItem: TPanel;
  ParentMenuItem: TPanel;
  ChildMenuItem: TPanel;
  NormalColor: TColor;
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
    ContextMenu.EditHistory := History;
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
    Check(FindMenuItem(ContextMenu.Menu, '重なり  >'),
      'common stacking submenu was not added');
    Check(FindMenuItem(ContextMenu.Menu, '反転  >'),
      'common flip submenu was not added');
    Check(FindMenuItem(ContextMenu.Menu, '回転  >'),
      'common rotation submenu was not added');
    Check(not FindMenuItem(ContextMenu.Menu, '整列  >'),
      'arrangement submenu was added for a single selection');
    Check(not FindMenuItem(ContextMenu.Menu, 'テキストの分解  >'),
      'text-only item was added for a rectangle');
    MenuItem := FindPanel(Form, 'コピー    Ctrl+C');
    Check(MenuItem <> nil, 'hover test item missing');
    NormalColor := MenuItem.Color;
    MenuItem.OnMouseEnter(MenuItem);
    Check(MenuItem.Color <> NormalColor, 'menu hover was not highlighted');
    MenuItem.OnMouseLeave(MenuItem);
    Check(MenuItem.Color = NormalColor, 'menu hover highlight was not cleared');
    ParentMenuItem := FindPanel(Form, '反転  >');
    Check(ParentMenuItem <> nil, 'submenu parent test item missing');
    ParentMenuItem.OnMouseEnter(ParentMenuItem);
    ParentMenuItem.OnMouseLeave(ParentMenuItem);
    ChildMenuItem := FindPanel(Form, '左右反転    Shift+H');
    Check(ChildMenuItem <> nil, 'submenu child test item missing');
    ChildMenuItem.OnMouseEnter(ChildMenuItem);
    Check(ParentMenuItem.Color <> NormalColor,
      'open submenu parent did not retain its active highlight');
    MenuItem.OnMouseEnter(MenuItem);
    Check(ParentMenuItem.Color = NormalColor,
      'submenu parent highlight was not cleared after closing its child');

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
    MenuItem := FindPanel(Form, '最背面へ    Ctrl+Shift+[');
    Check((MenuItem <> nil) and MenuItem.Enabled,
      'move-to-back command was not enabled');
    MenuItem.OnClick(MenuItem);
    Check(Document[1] is TScreenLayoutTextLayer,
      'stacking menu did not invoke the common layer operation');
    History.Undo;
    Check(Document[2] is TScreenLayoutTextLayer,
      'stacking menu undo failed');
    ContextMenu.ShowForObject(nil, Point(0, 0));
    MenuItem := FindPanel(Form, '左へ90度');
    Check((MenuItem <> nil) and MenuItem.Enabled,
      '90 degree rotation command was not enabled');
    MenuItem.OnClick(MenuItem);
    Check(Abs(TScreenLayoutTextLayer(Document[2]).RotationDegrees + 90) < 0.001,
      'rotation menu did not invoke the common layer operation');
    History.Undo;
    Check(Abs(TScreenLayoutTextLayer(Document[2]).RotationDegrees) < 0.001,
      'rotation menu undo failed');
    Document.SetSelectedLayers([1, 2]);
    ContextMenu.ShowForObject(nil, Point(0, 0));
    Check(FindMenuItem(ContextMenu.Menu, '整列  >'),
      'arrangement submenu was not added for a multiple selection');
    Check(FindMenuItem(ContextMenu.Menu, 'グループ  >'),
      'group submenu was not added');
    Check(not FindMenuItem(ContextMenu.Menu, 'テキストの分解  >'),
      'single-text item was added for a mixed multiple selection');
    MenuItem := FindPanel(Form, 'グループ化    Ctrl+G');
    Check((MenuItem <> nil) and MenuItem.Enabled,
      'group command was not enabled for a multiple selection');
    MenuItem.OnClick(MenuItem);
    Check((Document.LayerCount = 2) and
      (Document[1] is TScreenLayoutGroupLayer),
      'group menu did not invoke the existing group command');
    History.Undo;
    Check(Document.LayerCount = 3, 'group menu undo failed');
    History.Redo;
    ContextMenu.ShowForObject(nil, Point(0, 0));
    MenuItem := FindPanel(Form, 'グループ化解除    Ctrl+Shift+G');
    Check((MenuItem <> nil) and MenuItem.Enabled,
      'ungroup command was not enabled for a group selection');
    MenuItem.OnClick(MenuItem);
    Check(Document.LayerCount = 3,
      'group menu did not invoke the existing ungroup command');

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
