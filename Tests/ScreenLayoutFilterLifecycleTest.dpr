program ScreenLayoutFilterLifecycleTest;

{$APPTYPE CONSOLE}

uses
  System.Math,
  System.SysUtils,
  System.Types,
  Vcl.Graphics,
  ScreenLayoutDocument in '..\Source\Core\Model\ScreenLayoutDocument.pas',
  ScreenLayoutFilters in '..\Source\Core\Model\ScreenLayoutFilters.pas',
  ScreenLayoutEditorState in
    '..\Source\Core\Model\ScreenLayoutEditorState.pas',
  ScreenLayoutEditCommands in
    '..\Source\Core\Commands\ScreenLayoutEditCommands.pas',
  ScreenLayoutEditHistory in
    '..\Source\Core\Model\ScreenLayoutEditHistory.pas',
  ScreenLayoutGroupCommands in
    '..\Source\Core\Commands\Layer\ScreenLayoutGroupCommands.pas',
  ScreenLayoutLayerOperations in
    '..\Source\Layers\ScreenLayoutLayerOperations.pas';

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
    raise Exception.Create(MessageText);
end;

procedure Run;
var
  Data: TVectArtRectangleData;
  Document: TVectArtDocument;
  Duplicate: TVectArtLayer;
  Group: TScreenLayoutGroupLayer;
  History: TVectArtEditHistory;
  Operations: TVectArtLayerOperations;
  Original: TVectArtLayer;
  Outline: TScreenLayoutOutlineFilter;
  Shadow: TScreenLayoutShadowFilter;
begin
  Document := TVectArtDocument.Create;
  History := TVectArtEditHistory.Create;
  Operations := TVectArtLayerOperations.Create;
  try
    Operations.Document := Document;
    Operations.EditHistory := History;
    Data.Bounds := TRectF.Create(10, 20, 110, 80);
    Data.FillColor := clWhite;
    Data.Locked := False;
    Data.Name := 'Filtered rectangle';
    Data.Opacity := 0.75;
    Data.RotationDegrees := 12;
    Data.Visible := True;
    Document.InsertRectangle(1, Data);
    Original := Document[1];

    Outline := TScreenLayoutOutlineFilter.Create;
    Outline.Width := 9;
    Outline.Color := clRed;
    Outline.Enabled := False;
    Original.AddFilter(Outline);
    Shadow := TScreenLayoutShadowFilter.Create;
    Shadow.BlurRadius := 17;
    Shadow.OffsetX := -8;
    Shadow.OffsetY := 13;
    Shadow.Opacity := 0.42;
    Original.AddFilter(Shadow);

    Document.SetSelectedLayers([1]);
    Operations.Execute(vlaDuplicate);
    Check(Document.LayerCount = 3, 'duplicate was not inserted');
    Duplicate := Document[2];
    Check(Duplicate.FilterCount = 2, 'duplicate lost filter stack');
    Check(Duplicate.Filters[0] <> Original.Filters[0],
      'duplicate shares filter ownership');
    Check((not Duplicate.Filters[0].Enabled) and
      (TScreenLayoutOutlineFilter(Duplicate.Filters[0]).Width = 9),
      'outline parameters were not copied');
    Check(SameValue(TScreenLayoutShadowFilter(
      Duplicate.Filters[1]).OffsetX, -8.0) and
      SameValue(TScreenLayoutShadowFilter(
      Duplicate.Filters[1]).Opacity, 0.42, 0.0001),
      'shadow parameters were not copied');
    TScreenLayoutOutlineFilter(Duplicate.Filters[0]).Width := 3;
    Check(TScreenLayoutOutlineFilter(Original.Filters[0]).Width = 9,
      'editing duplicate changed original filter');

    History.Undo;
    Check(Document.LayerCount = 2, 'duplicate undo failed');
    History.Redo;
    Check((Document[2] = Duplicate) and (Duplicate.FilterCount = 2),
      'duplicate redo did not preserve layer and filters');

    Operations.Execute(vlaDelete);
    Check(Document.LayerCount = 2, 'delete failed');
    History.Undo;
    Check((Document[2] = Duplicate) and (Duplicate.FilterCount = 2),
      'delete undo did not restore the same filtered layer');
    History.Redo;
    Check(Document.LayerCount = 2, 'delete redo failed');
    History.Undo;

    Document.SetSelectedLayers([1, 2]);
    GroupSelectedLayers(Document, History);
    Check(Document[1] is TScreenLayoutGroupLayer, 'group was not created');
    Group := TScreenLayoutGroupLayer(Document[1]);
    Check((Group.ChildCount = 2) and (Group[0] = Original) and
      (Group[1] = Duplicate), 'group changed layer identity');
    Check((Group[0].FilterCount = 2) and (Group[1].FilterCount = 2),
      'grouping lost filters');
    History.Undo;
    Check((Document[1] = Original) and (Document[2] = Duplicate),
      'group undo changed layer identity');
    Check((Original.FilterCount = 2) and (Duplicate.FilterCount = 2),
      'group undo lost filters');
    History.Redo;
    UngroupSelectedLayer(Document, History);
    Check((Document[1] = Original) and (Document[2] = Duplicate),
      'ungroup changed layer identity');
    Check((Original.FilterCount = 2) and (Duplicate.FilterCount = 2),
      'ungroup lost filters');
    History.Undo;
    Check((Document[1] is TScreenLayoutGroupLayer) and
      (TScreenLayoutGroupLayer(Document[1])[0] = Original),
      'ungroup undo failed');
  finally
    Operations.Free;
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
