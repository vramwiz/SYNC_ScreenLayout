program ScreenLayoutLayerListInteractionTest;

{$APPTYPE CONSOLE}

uses
  System.Classes,
  System.SysUtils,
  System.Types,
  Winapi.Windows,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.Graphics,
  ScreenLayoutDocument in '..\Source\Core\Model\ScreenLayoutDocument.pas',
  ScreenLayoutEditCommands in
    '..\Source\Core\Commands\ScreenLayoutEditCommands.pas',
  ScreenLayoutEditHistory in
    '..\Source\Core\Model\ScreenLayoutEditHistory.pas',
  ScreenLayoutEditorState in
    '..\Source\Core\Model\ScreenLayoutEditorState.pas',
  ScreenLayoutRenderer in '..\Source\Rendering\ScreenLayoutRenderer.pas',
  ScreenLayoutLayerRenderer in
    '..\Source\Layers\List\ScreenLayoutLayerRenderer.pas',
  ScreenLayoutGroupChildCommands in
    '..\Source\Core\Commands\Layer\Group\ScreenLayoutGroupChildCommands.pas',
  ScreenLayoutLayerList in '..\Source\Layers\List\ScreenLayoutLayerList.pas',
  VerticalScrollBarControl in
    '..\Lib\VerticalScrollBar\VerticalScrollBarControl.pas';

type
  TTestLayerListControl = class(TVectArtLayerListControl)
  public
    procedure ClickRow(Row: Integer; const Shift: TShiftState);
    procedure PressRow(Row: Integer);
    procedure ReleaseRow(Row: Integer);
    procedure DragRow(Row, TargetRow: Integer);
    function RowY(Row: Integer): Integer;
    procedure PressExpandButton(const Shift: TShiftState);
    procedure PressGroupRow(const Shift: TShiftState);
  end;

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
    raise Exception.Create(MessageText);
end;

function TTestLayerListControl.RowY(Row: Integer): Integer;
begin
  Result := ClientHeight - MulDiv(8 + 41 + (Row - 1) * 88, CurrentPPI, 96);
end;

procedure TTestLayerListControl.ClickRow(Row: Integer; const Shift: TShiftState);
begin
  MouseDown(mbLeft, Shift, 250, RowY(Row));
  MouseUp(mbLeft, Shift, 250, RowY(Row));
end;

procedure TTestLayerListControl.PressRow(Row: Integer);
begin
  MouseDown(mbLeft, [], 250, RowY(Row));
end;

procedure TTestLayerListControl.ReleaseRow(Row: Integer);
begin
  MouseUp(mbLeft, [], 250, RowY(Row));
end;

procedure TTestLayerListControl.DragRow(Row, TargetRow: Integer);
begin
  MouseDown(mbLeft, [], 250, RowY(Row));
  MouseMove([ssLeft], 250, RowY(TargetRow) - MulDiv(35, CurrentPPI, 96));
  MouseUp(mbLeft, [], 250, RowY(TargetRow) - MulDiv(35, CurrentPPI, 96));
end;

procedure TestSelection;
var
  Control: TTestLayerListControl;
  Document: TVectArtDocument;
  State: TVectArtEditorState;
  Form: TForm;
  Group: TScreenLayoutGroupLayer;
  I: Integer;
begin
  Form := TForm.Create(nil);
  Document := TVectArtDocument.Create;
  State := TVectArtEditorState.Create;
  try
    for I := 1 to 3 do
      Document.InsertLayer(I, TVectArtRectangleLayer.Create('R' + IntToStr(I),
        TRectF.Create(0, 0, 10, 10), clRed));
    Group := TScreenLayoutGroupLayer.Create('Group');
    for I := 1 to 3 do
      Group.AddChild(TVectArtRectangleLayer.Create('Child' + IntToStr(I),
        TRectF.Create(0, 0, 10, 10), clBlue));
    Document.InsertLayer(4, Group);
    Control := TTestLayerListControl.Create(Form);
    Control.Parent := Form;
    Control.SetBounds(0, 0, 400, 800);
    Control.EditorState := State;
    Control.Document := Document;
    Form.SetBounds(-10000, -10000, 420, 840);
    Form.Show;
    Application.ProcessMessages;
    Control.ClickRow(1, []);
    Check(Document.SelectionCount = 1, 'plain click did not select');
    Control.ClickRow(3, [ssCtrl]);
    Check((Document.SelectionCount = 2) and Document.IsLayerSelected(1) and
      Document.IsLayerSelected(3), 'Ctrl click did not add');
    Control.ClickRow(3, [ssCtrl, ssDouble]);
    Check((Document.SelectionCount = 1) and Document.IsLayerSelected(1), 'Ctrl click did not toggle off');
    Control.ClickRow(1, []);
    Control.ClickRow(3, [ssShift]);
    Check(Document.SelectionCount = 3, 'Shift range selection failed');
    Control.ClickRow(2, [ssShift]);
    Check((Document.SelectionCount = 2) and not Document.IsLayerSelected(3), 'Shift range did not shrink');
    Control.ClickRow(4, [ssCtrl, ssDouble]);
    Check((Document.SelectionCount = 3) and (State.OpenGroup = nil), 'Ctrl double-click opened group');
    Control.ClickRow(3, [ssCtrl, ssShift]);
    Check(Document.SelectionCount = 4, 'Ctrl+Shift did not add range');
    Control.PressRow(2);
    Check(Document.SelectionCount = 4, 'mouse down lost multiple drag selection');
    Control.ReleaseRow(2);
    Check((Document.SelectionCount = 1) and Document.IsLayerSelected(2), 'plain click did not collapse selection');
    Document.SetSelectedLayers([1, 2]);
    Document[1].Locked := True;
    Control.ClickRow(2, []);
    Check(Document.SelectionCount = 1, 'locked drag source prevented click collapse');
    Document[1].Locked := False;
    Document.SetSelectedLayers([1, 2]);
    Control.DragRow(1, 3);
    Check((Document.SelectionCount = 2) and (Document[1].Name = 'R3') and
      (Document[2].Name = 'R1') and (Document[3].Name = 'R2'), 'multiple drag was broken');
    Control.Document := nil;
    State.OpenGroup := Group;
    Control.Document := Document;
    // Three document rows precede the children; the expanded group itself is row seven.
    Control.ClickRow(4, []);
    Check(State.OpenGroupChild = Group[0], 'group child click');
    Check(Document.SelectionCount = 0, 'child selection retained document selection');
    Control.ClickRow(6, [ssCtrl]);
    Check(State.OpenGroupChildCount = 2, 'group Ctrl add');
    Control.ClickRow(6, [ssCtrl]);
    Check(State.OpenGroupChildCount = 1, 'group Ctrl remove');
    Control.ClickRow(4, []);
    Control.ClickRow(6, [ssShift]);
    Check(State.OpenGroupChildCount = 3, 'group Shift range');
    Control.ClickRow(5, []);
    Check((State.OpenGroupChildCount = 1) and (State.OpenGroupChild = Group[1]), 'group plain collapse');
    Control.Document := nil;
    Control.Document := Document;
    State.OpenGroupChild := Group[0];
    Control.ClickRow(6, [ssShift]);
    Check(State.OpenGroupChildCount = 3, 'Shift did not use canvas child selection anchor');
  finally
    Form.Free;
    State.Free;
    Document.Free;
  end;
end;

procedure TTestLayerListControl.PressExpandButton(
  const Shift: TShiftState);
begin
  MouseDown(mbLeft, Shift, 150, 150);
end;

procedure TTestLayerListControl.PressGroupRow(const Shift: TShiftState);
begin
  MouseDown(mbLeft, Shift, 250, 150);
end;

var
  Control: TTestLayerListControl;
  Document: TVectArtDocument;
  EditorState: TVectArtEditorState;
  Form: TForm;
  Group: TScreenLayoutGroupLayer;
begin
  Application.Initialize;
  TestSelection;
  Document := TVectArtDocument.Create;
  EditorState := TVectArtEditorState.Create;
  Form := TForm.Create(nil);
  Control := TTestLayerListControl.Create(Form);
  try
    Group := TScreenLayoutGroupLayer.Create('Group');
    Group.AddChild(TVectArtRectangleLayer.Create('Child',
      TRectF.Create(0, 0, 10, 10), clRed));
    Document.InsertLayer(Document.LayerCount, Group);
    Control.Parent := Form;
    Control.SetBounds(0, 0, 400, 220);
    Control.Document := Document;
    Control.EditorState := EditorState;
    Form.SetBounds(-10000, -10000, 420, 260);
    Form.Show;
    Application.ProcessMessages;

    Control.PressExpandButton([]);
    Check(EditorState.OpenGroup = nil,
      'A single expand-button click opened the group');
    Control.PressExpandButton([ssDouble]);
    Check(EditorState.OpenGroup = Group,
      'A double expand-button click did not open the group');

    Control.PressGroupRow([]);
    Check(EditorState.OpenGroup = Group,
      'A single group-row click closed the group');
    Control.PressGroupRow([ssDouble]);
    Check(EditorState.OpenGroup = nil,
      'A double group-row click did not close the group');

    Control.PressGroupRow([ssDouble]);
    Check(EditorState.OpenGroup = Group,
      'A double group-row click did not reopen the group');
    Control.PressExpandButton([]);
    Check(EditorState.OpenGroup = Group,
      'A single expand-button click closed the group');
    Control.PressExpandButton([ssDouble]);
    Check(EditorState.OpenGroup = nil,
      'A double expand-button click did not close the group');
  finally
    Form.Free;
    EditorState.Free;
    Document.Free;
  end;
  Writeln('PASS');
end.
