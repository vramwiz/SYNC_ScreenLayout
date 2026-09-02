program ScreenLayoutLayerListInteractionTest;

{$APPTYPE CONSOLE}

uses
  System.Classes,
  System.SysUtils,
  System.Types,
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
    '..\Source\Layers\ScreenLayoutLayerRenderer.pas',
  ScreenLayoutGroupChildCommands in
    '..\Source\Core\Commands\ScreenLayoutGroupChildCommands.pas',
  ScreenLayoutLayerList in '..\Source\Layers\ScreenLayoutLayerList.pas',
  VerticalScrollBarControl in
    '..\Lib\VerticalScrollBar\VerticalScrollBarControl.pas';

type
  TTestLayerListControl = class(TVectArtLayerListControl)
  public
    procedure PressExpandButton(const Shift: TShiftState);
    procedure PressGroupRow(const Shift: TShiftState);
  end;

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
    raise Exception.Create(MessageText);
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
