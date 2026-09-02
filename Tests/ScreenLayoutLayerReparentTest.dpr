program ScreenLayoutLayerReparentTest;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Types,
  Vcl.Graphics,
  ScreenLayoutDocument in '..\Source\Core\Model\ScreenLayoutDocument.pas',
  ScreenLayoutEditCommands in
    '..\Source\Core\Commands\ScreenLayoutEditCommands.pas',
  ScreenLayoutEditorState in
    '..\Source\Core\Model\ScreenLayoutEditorState.pas',
  ScreenLayoutGroupChildCommands in
    '..\Source\Core\Commands\ScreenLayoutGroupChildCommands.pas';

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
  BatchCommand: TScreenLayoutReparentLayersCommand;
  Child: TVectArtRectangleLayer;
  Child2: TVectArtRectangleLayer;
  Child3: TVectArtRectangleLayer;
  Command: TScreenLayoutReparentLayersCommand;
  Document: TVectArtDocument;
  EditorState: TVectArtEditorState;
  Inner: TScreenLayoutGroupLayer;
  Root: TScreenLayoutGroupLayer;
  Sibling: TScreenLayoutGroupLayer;
begin
  Document := TVectArtDocument.Create;
  EditorState := TVectArtEditorState.Create;
  try
    Root := TScreenLayoutGroupLayer.Create('Root');
    Inner := TScreenLayoutGroupLayer.Create('Inner');
    Child := NewRectangle('Child');
    Inner.AddChild(Child);
    Root.AddChild(Inner);
    Sibling := TScreenLayoutGroupLayer.Create('Sibling');
    Document.InsertLayer(Document.LayerCount, Root);
    Document.InsertLayer(Document.LayerCount, Sibling);

    EditorState.OpenGroupInDocument(Document, Inner);
    EditorState.OpenGroupChild := Child;
    Command := TScreenLayoutReparentLayersCommand.Create(Document,
      EditorState, Inner, [0], Root, 1);
    try
      Command.Execute;
      Check(Inner.ChildCount = 0, 'Child remained in source group');
      Check((Root.ChildCount = 2) and (Root[1] = Child),
        'Child was not inserted into parent');
      Check((EditorState.OpenGroup = Root) and
        (EditorState.OpenGroupChild = Child),
        'Parent destination selection was not restored');

      Command.Undo;
      Check((Inner.ChildCount = 1) and (Inner[0] = Child),
        'Undo did not restore nested child');
      Check((EditorState.OpenGroup = Inner) and
        (EditorState.OpenGroupChild = Child),
        'Undo did not restore nested editing context');

      Command.Execute;
      Check((Root.ChildCount = 2) and (Root[1] = Child),
        'Redo did not move child to parent');
    finally
      Command.Free;
    end;

    Command := TScreenLayoutReparentLayersCommand.Create(Document,
      EditorState, Root, [1], Sibling, 0);
    try
      Command.Execute;
      Check((Sibling.ChildCount = 1) and (Sibling[0] = Child),
        'Child was not inserted into sibling group');
      Check((EditorState.OpenGroup = Sibling) and
        (EditorState.OpenGroupChild = Child),
        'Sibling destination selection was not restored');
      Command.Undo;
      Check((Root.ChildCount = 2) and (Root[1] = Child),
        'Sibling move undo failed');
    finally
      Command.Free;
    end;

    Command := TScreenLayoutReparentLayersCommand.Create(Document,
      EditorState, Root, [1], nil, 2);
    try
      Command.Execute;
      Check((Document.LayerCount = 4) and (Document[2] = Child),
        'Child was not moved to document root');
      Check((EditorState.OpenGroup = nil) and
        (Document.SelectedIndex = 2),
        'Document destination selection was not restored');
      Command.Undo;
      Check((Root.ChildCount = 2) and (Root[1] = Child),
        'Document move undo failed');
      Check((EditorState.OpenGroup = Root) and
        (EditorState.OpenGroupChild = Child),
        'Document move undo did not restore group context');
    finally
      Command.Free;
    end;

    Child2 := NewRectangle('Child 2');
    Child3 := NewRectangle('Child 3');
    Root.AddChild(Child2);
    Root.AddChild(Child3);
    EditorState.OpenGroupInDocument(Document, Root);
    EditorState.SetOpenGroupChildren([Child, Child2]);
    BatchCommand := TScreenLayoutReparentLayersCommand.Create(Document,
      EditorState, Root, [1, 2], Sibling, 0);
    try
      BatchCommand.Execute;
      Check((Sibling.ChildCount = 2) and (Sibling[0] = Child) and
        (Sibling[1] = Child2), 'Batch move did not preserve layer order');
      Check((EditorState.OpenGroup = Sibling) and
        (EditorState.OpenGroupChildCount = 2),
        'Batch destination selection was not restored');
      BatchCommand.Undo;
      Check((Root.ChildCount = 4) and (Root[1] = Child) and
        (Root[2] = Child2), 'Batch move undo failed');
      Check((EditorState.OpenGroup = Root) and
        (EditorState.OpenGroupChildCount = 2),
        'Batch move undo selection failed');
    finally
      BatchCommand.Free;
    end;

    BatchCommand := TScreenLayoutReparentLayersCommand.Create(Document,
      EditorState, Root, [1, 2], Root, 0);
    try
      BatchCommand.Execute;
      Check((Root[0] = Child) and (Root[1] = Child2) and
        (Root[2] = Inner), 'Batch reorder failed');
      BatchCommand.Undo;
      Check((Root[0] = Inner) and (Root[1] = Child) and
        (Root[2] = Child2), 'Batch reorder undo failed');
    finally
      BatchCommand.Free;
    end;

    Document.InsertLayer(Document.LayerCount, NewRectangle('Top 1'));
    Document.InsertLayer(Document.LayerCount, NewRectangle('Top 2'));
    BatchCommand := TScreenLayoutReparentLayersCommand.Create(Document,
      EditorState, nil, [3, 4], nil, 1);
    try
      BatchCommand.Execute;
      Check((Document[1].Name = 'Top 1') and
        (Document[2].Name = 'Top 2'), 'Document batch reorder failed');
      Check(Document.SelectionCount = 2,
        'Document batch reorder selection failed');
      BatchCommand.Undo;
      Check((Document[3].Name = 'Top 1') and
        (Document[4].Name = 'Top 2'), 'Document reorder undo failed');
    finally
      BatchCommand.Free;
    end;

    BatchCommand := TScreenLayoutReparentLayersCommand.Create(Document,
      EditorState, nil, [3, 4], Sibling, 0);
    try
      BatchCommand.Execute;
      Check((Sibling.ChildCount = 2) and
        (Sibling[0].Name = 'Top 1') and (Sibling[1].Name = 'Top 2'),
        'Document-to-group batch move failed');
      BatchCommand.Undo;
      Check((Document[3].Name = 'Top 1') and
        (Document[4].Name = 'Top 2'),
        'Document-to-group batch undo failed');
    finally
      BatchCommand.Free;
    end;
  finally
    EditorState.Free;
    Document.Free;
  end;
  Writeln('PASS');
end.
