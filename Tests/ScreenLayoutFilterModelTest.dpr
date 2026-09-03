program ScreenLayoutFilterModelTest;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Types,
  Vcl.Graphics,
  ScreenLayoutDocument in '..\Source\Core\Model\ScreenLayoutDocument.pas',
  ScreenLayoutFilters in '..\Source\Core\Model\ScreenLayoutFilters.pas',
  ScreenLayoutEditorState in
    '..\Source\Core\Model\ScreenLayoutEditorState.pas',
  ScreenLayoutEditCommands in '..\Source\Core\Commands\ScreenLayoutEditCommands.pas',
  ScreenLayoutEditHistory in '..\Source\Core\Model\ScreenLayoutEditHistory.pas',
  ScreenLayoutFilterCommands in '..\Source\Core\Commands\ScreenLayoutFilterCommands.pas';

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
    raise Exception.Create(MessageText);
end;

procedure Run;
var
  Blur: TScreenLayoutBlurFilter;
  Command: TVectArtEditCommand;
  Data: TVectArtRectangleData;
  Document: TVectArtDocument;
  History: TVectArtEditHistory;
  Layer: TVectArtLayer;
  NewParameters: TScreenLayoutFilter;
  OldParameters: TScreenLayoutFilter;
  Outline: TScreenLayoutOutlineFilter;
  Shadow: TScreenLayoutShadowFilter;
  State: TVectArtEditorState;
  RemovedFilter: TScreenLayoutFilter;
begin
  Document := TVectArtDocument.Create;
  History := TVectArtEditHistory.Create;
  State := TVectArtEditorState.Create;
  try
    Data.Bounds := TRectF.Create(-50, -25, 50, 25);
    Data.FillColor := clWhite;
    Data.Locked := False;
    Data.Name := 'Rectangle';
    Data.Opacity := 1.0;
    Data.RotationDegrees := 0.0;
    Data.Visible := True;
    Document.InsertRectangle(1, Data);
    Layer := Document[1];

    Outline := TScreenLayoutOutlineFilter.Create;
    Check(Outline.Enabled, 'outline must be enabled by default');
    Check(Outline.Width = 4.0, 'unexpected outline width');
    Command := TScreenLayoutAddFilterCommand.Create(Document, Layer, 0,
      Outline);
    Command.Execute;
    History.AddApplied(Command);
    Check(Layer.FilterCount = 1, 'outline was not inserted');
    History.Undo;
    Check(Layer.FilterCount = 0, 'add undo did not remove outline');
    History.Redo;
    Check(Layer.Filters[0] = Outline, 'add redo changed filter identity');

    Command := TScreenLayoutSetFilterEnabledCommand.Create(Document,
      Outline, True, False);
    Command.Execute;
    History.AddApplied(Command);
    Check(not Outline.Enabled, 'enabled command was not applied');
    History.Undo;
    Check(Outline.Enabled, 'enabled undo failed');
    History.Redo;
    Check(not Outline.Enabled, 'enabled redo failed');

    OldParameters := Outline.Clone;
    NewParameters := Outline.Clone;
    try
      TScreenLayoutOutlineFilter(NewParameters).Width := 16.0;
      Command := TScreenLayoutSetFilterParametersCommand.Create(Document,
        Outline, OldParameters, NewParameters);
      Command.Execute;
      History.AddApplied(Command);
    finally
      NewParameters.Free;
      OldParameters.Free;
    end;
    Check(Outline.Width = 16.0, 'parameter command was not applied');
    History.Undo;
    Check(Outline.Width = 4.0, 'parameter undo failed');
    History.Redo;
    Check(Outline.Width = 16.0, 'parameter redo failed');

    Shadow := TScreenLayoutShadowFilter.Create;
    Command := TScreenLayoutAddFilterCommand.Create(Document, Layer, 1,
      Shadow);
    Command.Execute;
    History.AddApplied(Command);
    Blur := TScreenLayoutBlurFilter.Create;
    Command := TScreenLayoutAddFilterCommand.Create(Document, Layer, 2,
      Blur);
    Command.Execute;
    History.AddApplied(Command);
    Check(Layer.FilterCount = 3, 'filter stack count is incorrect');

    Command := TScreenLayoutMoveFilterCommand.Create(Document, Layer, 2, 0);
    Command.Execute;
    History.AddApplied(Command);
    Check(Layer.Filters[0] = Blur, 'move did not preserve filter object');
    History.Undo;
    Check(Layer.Filters[2] = Blur, 'move undo failed');
    History.Redo;
    Check(Layer.Filters[0] = Blur, 'move redo failed');

    Command := TScreenLayoutRemoveFilterCommand.Create(Document, Layer, 1);
    Command.Execute;
    History.AddApplied(Command);
    Check(Layer.FilterCount = 2, 'remove did not change filter count');
    History.Undo;
    Check((Layer.FilterCount = 3) and (Layer.Filters[1] = Outline),
      'remove undo did not restore the same filter');
    History.Redo;
    Check(Layer.FilterCount = 2, 'remove redo failed');

    State.SelectFilter(Layer, Shadow);
    State.ValidateSelectedFilter(Document);
    Check(State.SelectedFilter = Shadow,
      'valid filter selection was cleared');
    RemovedFilter := Layer.ExtractFilter(1);
    try
      State.ValidateSelectedFilter(Document);
      Check((State.SelectedFilter = nil) and
        (State.SelectedFilterLayer = nil),
        'removed filter selection was not cleared');
    finally
      RemovedFilter.Free;
    end;
  finally
    State.Free;
    History.Free;
    Document.Free;
  end;
end;

begin
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
