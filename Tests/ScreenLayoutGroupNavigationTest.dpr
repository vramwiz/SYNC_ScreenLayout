program ScreenLayoutGroupNavigationTest;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Types,
  Vcl.Graphics,
  ScreenLayoutDocument in '..\Source\Core\Model\ScreenLayoutDocument.pas',
  ScreenLayoutEditCommands in
    '..\Source\Core\Commands\ScreenLayoutEditCommands.pas',
  ScreenLayoutEditHistory in
    '..\Source\Core\Model\ScreenLayoutEditHistory.pas',
  ScreenLayoutEditorState in
    '..\Source\Core\Model\ScreenLayoutEditorState.pas',
  ScreenLayoutGroupChildCommands in
    '..\Source\Core\Commands\ScreenLayoutGroupChildCommands.pas',
  ScreenLayoutGroupCommands in
    '..\Source\Core\Commands\ScreenLayoutGroupCommands.pas';

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
    raise Exception.Create(MessageText);
end;

function NewRectangle(const Name: string): TVectArtRectangleLayer;
begin
  Result := TVectArtRectangleLayer.Create(Name,
    TRectF.Create(10, 20, 110, 120), clRed);
end;

var
  ChildA: TVectArtRectangleLayer;
  ChildB: TVectArtRectangleLayer;
  Document: TVectArtDocument;
  EditorState: TVectArtEditorState;
  GroupedChild: TScreenLayoutGroupLayer;
  History: TVectArtEditHistory;
  Inner: TScreenLayoutGroupLayer;
  Middle: TScreenLayoutGroupLayer;
  Outer: TScreenLayoutGroupLayer;
  Regrouped: TScreenLayoutGroupLayer;
  SiblingGroup: TScreenLayoutGroupLayer;
begin
  Document := TVectArtDocument.Create;
  EditorState := TVectArtEditorState.Create;
  History := TVectArtEditHistory.Create;
  try
    Outer := TScreenLayoutGroupLayer.Create('Outer');
    Middle := TScreenLayoutGroupLayer.Create('Middle');
    Inner := TScreenLayoutGroupLayer.Create('Inner');
    Inner.AddChild(NewRectangle('Nested leaf'));
    Middle.AddChild(Inner);
    Outer.AddChild(Middle);
    ChildA := NewRectangle('Child A');
    ChildB := NewRectangle('Child B');
    Outer.AddChild(ChildA);
    Outer.AddChild(ChildB);
    Document.InsertLayer(Document.LayerCount, Outer);

    EditorState.OpenGroupInDocument(Document, Inner);
    Check((EditorState.OpenGroup = Inner) and
      (EditorState.OpenGroupDepth = 3), 'Nested group path was not opened');
    EditorState.OpenParentGroup;
    Check((EditorState.OpenGroup = Middle) and
      (EditorState.OpenGroupDepth = 2), 'First Escape step failed');
    EditorState.OpenParentGroup;
    Check((EditorState.OpenGroup = Outer) and
      (EditorState.OpenGroupDepth = 1), 'Second Escape step failed');
    EditorState.OpenParentGroup;
    Check((EditorState.OpenGroup = nil) and
      (EditorState.OpenGroupDepth = 0), 'Final Escape step failed');

    EditorState.OpenGroupInDocument(Document, Outer);
    EditorState.SetOpenGroupChildren([ChildA, ChildB]);
    GroupOpenGroupChildren(Document, History, EditorState);
    Check((Outer.ChildCount = 2) and
      (Outer[1] is TScreenLayoutGroupLayer),
      'Internal group was not created');
    GroupedChild := TScreenLayoutGroupLayer(Outer[1]);
    Check((GroupedChild.ChildCount = 2) and
      (GroupedChild[0] = ChildA) and (GroupedChild[1] = ChildB),
      'Internal group did not preserve child order');
    EditorState.OpenChildGroup(GroupedChild);
    Check((EditorState.OpenGroup = GroupedChild) and
      (EditorState.OpenGroupDepth = 2),
      'New internal group was not entered');

    History.Undo;
    EditorState.ValidateOpenGroupPath(Document);
    Check((EditorState.OpenGroup = Outer) and
      (EditorState.OpenGroupDepth = 1),
      'Undo did not return to the surviving parent group');
    Check((Outer.ChildCount = 3) and (Outer[1] = ChildA) and
      (Outer[2] = ChildB), 'Undo did not restore grouped children');
    Check(EditorState.OpenGroupChildCount = 2,
      'Undo did not restore the child selection');

    History.Redo;
    EditorState.ValidateOpenGroupPath(Document);
    Check((Outer.ChildCount = 2) and
      (Outer[1] is TScreenLayoutGroupLayer),
      'Redo did not recreate the internal group');
    GroupedChild := TScreenLayoutGroupLayer(Outer[1]);
    Check((EditorState.OpenGroup = Outer) and
      (EditorState.OpenGroupChild = GroupedChild),
      'Redo did not select the recreated internal group');

    EditorState.OpenGroup := nil;
    SiblingGroup := TScreenLayoutGroupLayer.Create('Sibling');
    SiblingGroup.AddChild(NewRectangle('Sibling leaf'));
    Document.InsertLayer(Document.LayerCount, SiblingGroup);
    Document.InsertLayer(Document.LayerCount, NewRectangle('Loose layer'));
    Document.SetSelectedLayers([1, 2, 3]);
    History.Clear;
    GroupSelectedLayers(Document, History);
    Check((Document.LayerCount = 2) and
      (Document[1] is TScreenLayoutGroupLayer),
      'Top-level regrouping did not create a group');
    Regrouped := TScreenLayoutGroupLayer(Document[1]);
    Check((Regrouped.ChildCount = 3) and (Regrouped[0] = Outer) and
      (Regrouped[1] = SiblingGroup) and
      (Regrouped[2].Name = 'Loose layer'),
      'Top-level regrouping did not preserve groups and order');

    History.Undo;
    Check((Document.LayerCount = 4) and (Document[1] = Outer) and
      (Document[2] = SiblingGroup) and
      (Document[3].Name = 'Loose layer'),
      'Top-level regrouping undo failed');
    Check(Document.SelectionCount = 3,
      'Top-level regrouping undo did not restore selection');
    History.Redo;
    Check((Document.LayerCount = 2) and
      (TScreenLayoutGroupLayer(Document[1]).ChildCount = 3),
      'Top-level regrouping redo failed');
  finally
    History.Free;
    EditorState.Free;
    Document.Free;
  end;
  Writeln('PASS');
end.
