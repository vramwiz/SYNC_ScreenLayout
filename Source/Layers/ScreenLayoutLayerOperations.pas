// レイヤー操作バーから実行する追加・複製・複数削除・複数積層移動を提供する。
unit ScreenLayoutLayerOperations;

interface

uses
  System.Types, ScreenLayoutDocument, ScreenLayoutEditHistory,
  ScreenLayoutEditorState;

type
  TVectArtLayerAction = (vlaAdd, vlaDuplicate, vlaDelete,
    vlaMoveForward, vlaMoveBackward);

  TVectArtLayerOperations = class
  private
    FDocument: TVectArtDocument;
    FEditHistory: TVectArtEditHistory;
    FEditorState: TVectArtEditorState;
    procedure AddRectangle;
    function CanMove(Delta: Integer): Boolean;
    procedure DeleteSelectedLayers;
    procedure MoveSelectedLayers(Delta: Integer);
    function NextRectangleName: string;
    function SelectedLayersEditable: Boolean;
  public
    function CanExecute(Action: TVectArtLayerAction): Boolean;
    procedure Execute(Action: TVectArtLayerAction);
    property Document: TVectArtDocument read FDocument write FDocument;
    property EditHistory: TVectArtEditHistory read FEditHistory
      write FEditHistory;
    property EditorState: TVectArtEditorState read FEditorState
      write FEditorState;
  end;

implementation

uses
  System.Math, System.SysUtils, Vcl.Graphics,
  ScreenLayoutEditCommands,
  ScreenLayoutGroupCommands,
  ScreenLayoutLayerDuplication,
  ScreenLayoutLayerStructureCommands, ScreenLayoutTextCommands;

const
  DEFAULT_RECTANGLE_WIDTH = 320;
  DEFAULT_RECTANGLE_HEIGHT = 240;
  DEFAULT_RECTANGLE_COLOR = TColor($00E2904A);

procedure TVectArtLayerOperations.AddRectangle;
var
  AfterSelection: TArray<Integer>;
  BeforeSelection: TArray<Integer>;
  Data: TVectArtRectangleData;
  Index: Integer;
  Left: Single;
  Top: Single;
begin
  Left := -DEFAULT_RECTANGLE_WIDTH / 2;
  Top := -DEFAULT_RECTANGLE_HEIGHT / 2;
  Data.Bounds := TRectF.Create(Left, Top, Left + DEFAULT_RECTANGLE_WIDTH,
    Top + DEFAULT_RECTANGLE_HEIGHT);
  if FEditorState <> nil then
    Data.FillColor := FEditorState.RectangleFillColor
  else
    Data.FillColor := DEFAULT_RECTANGLE_COLOR;
  Data.Locked := False;
  Data.Name := NextRectangleName;
  if FEditorState <> nil then
    Data.Opacity := FEditorState.RectangleOpacity
  else
    Data.Opacity := 1.0;
  Data.RotationDegrees := 0.0;
  Data.Visible := True;
  BeforeSelection := FDocument.GetSelectedLayerIndices;
  Index := FDocument.InsertRectangle(FDocument.LayerCount, Data);
  FDocument.SetSelectedLayers([Index]);
  AfterSelection := FDocument.GetSelectedLayerIndices;
  if FEditHistory <> nil then
    FEditHistory.AddApplied(TVectArtInsertRectangleCommand.Create(FDocument,
      Index, Data, BeforeSelection, AfterSelection));
end;

function TVectArtLayerOperations.CanExecute(
  Action: TVectArtLayerAction): Boolean;
begin
  Result := FDocument <> nil;
  if not Result or (Action = vlaAdd) then
    Exit;
  case Action of
    vlaDuplicate:
      if CanEditOpenGroupChild(FEditorState) then
        Result := True
      else
        Result := CanDuplicateSelectedGroups(FDocument) or
          CanDuplicateSelectedLayers(FDocument);
    vlaDelete:
      Result := CanEditOpenGroupChild(FEditorState) or SelectedLayersEditable;
    vlaMoveForward:
      if CanEditOpenGroupChild(FEditorState) then
        Result := CanMoveOpenGroupChild(FEditorState, 1)
      else
        Result := SelectedLayersEditable and CanMove(1);
    vlaMoveBackward:
      if CanEditOpenGroupChild(FEditorState) then
        Result := CanMoveOpenGroupChild(FEditorState, -1)
      else
        Result := SelectedLayersEditable and CanMove(-1);
  end;
end;

function TVectArtLayerOperations.CanMove(Delta: Integer): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to FDocument.LayerCount - 1 do
    if FDocument.IsLayerSelected(I) then
    begin
      if (Delta > 0) and (I < FDocument.LayerCount - 1) and
        not FDocument.IsLayerSelected(I + 1) then
        Exit(True);
      if (Delta < 0) and (I > 1) and
        not FDocument.IsLayerSelected(I - 1) then
        Exit(True);
    end;
end;

procedure TVectArtLayerOperations.DeleteSelectedLayers;
var
  AfterSelection: TArray<Integer>;
  BeforeSelection: TArray<Integer>;
  Command: TVectArtCompoundCommand;
  ArcData: TScreenLayoutArcData;
  Data: TVectArtRectangleData;
  EllipseData: TScreenLayoutEllipseData;
  EllipseLineData: TScreenLayoutEllipseLineData;
  EllipseArcShapeData: TScreenLayoutEllipseArcShapeData;
  RoundedRectangleData: TScreenLayoutRoundedRectangleData;
  RoundedRectangleLineData: TScreenLayoutRoundedRectangleLineData;
  ImageData: TVectArtImageData;
  PathData: TVectArtPathData;
  RectangleLineData: TScreenLayoutRectangleLineData;
  ShapeData: TScreenLayoutShapeData;
  TextData: TScreenLayoutTextData;
  I: Integer;
  SelectedIndices: TArray<Integer>;
  SelectionIndex: Integer;
begin
  Command := nil;
  if FEditHistory <> nil then
    Command := TVectArtCompoundCommand.Create;
  // RemoveRectangle は選択が空になると隣接レイヤーを自動選択するため、
  // 削除中の現在選択ではなく、操作開始時の選択だけを対象にする。
  SelectedIndices := FDocument.GetSelectedLayerIndices;
  for SelectionIndex := High(SelectedIndices) downto 0 do
  begin
    I := SelectedIndices[SelectionIndex];
    if (I > 0) and (I < FDocument.LayerCount) then
    begin
      BeforeSelection := FDocument.GetSelectedLayerIndices;
      if FDocument[I] is TScreenLayoutEllipseArcShapeLayer then
      begin
        if FDocument.RemoveEllipseArcShape(I, EllipseArcShapeData) then
        begin
          AfterSelection := FDocument.GetSelectedLayerIndices;
          if Command <> nil then
            Command.Add(TScreenLayoutDeleteEllipseArcShapeCommand.Create(
              FDocument, I, EllipseArcShapeData, BeforeSelection,
              AfterSelection));
        end;
      end
      else if FDocument[I] is TScreenLayoutEllipseLineLayer then
      begin
        if FDocument.RemoveEllipseLine(I, EllipseLineData) then
        begin
          AfterSelection := FDocument.GetSelectedLayerIndices;
          if Command <> nil then
            Command.Add(TScreenLayoutDeleteEllipseLineCommand.Create(
              FDocument, I, EllipseLineData, BeforeSelection,
              AfterSelection));
        end;
      end
      else if FDocument[I] is TScreenLayoutRoundedRectangleLineLayer then
      begin
        if FDocument.RemoveRoundedRectangleLine(I,
          RoundedRectangleLineData) then
        begin
          AfterSelection := FDocument.GetSelectedLayerIndices;
          if Command <> nil then
            Command.Add(TScreenLayoutDeleteRoundedRectangleLineCommand.Create(
              FDocument, I, RoundedRectangleLineData, BeforeSelection,
              AfterSelection));
        end;
      end
      else if FDocument[I] is TScreenLayoutRectangleLineLayer then
      begin
        if FDocument.RemoveRectangleLine(I, RectangleLineData) then
        begin
          AfterSelection := FDocument.GetSelectedLayerIndices;
          if Command <> nil then
            Command.Add(TScreenLayoutDeleteRectangleLineCommand.Create(
              FDocument, I, RectangleLineData, BeforeSelection,
              AfterSelection));
        end;
      end
      else if FDocument[I] is TScreenLayoutArcLayer then
      begin
        if FDocument.RemoveArc(I, ArcData) then
        begin
          AfterSelection := FDocument.GetSelectedLayerIndices;
          if Command <> nil then
            Command.Add(TScreenLayoutDeleteArcCommand.Create(FDocument, I,
              ArcData, BeforeSelection, AfterSelection));
        end;
      end
      else if FDocument[I] is TScreenLayoutEllipseLayer then
      begin
        if FDocument.RemoveEllipse(I, EllipseData) then
        begin
          AfterSelection := FDocument.GetSelectedLayerIndices;
          if Command <> nil then
            Command.Add(TScreenLayoutDeleteEllipseCommand.Create(FDocument,
              I, EllipseData, BeforeSelection, AfterSelection));
        end;
      end
      else if FDocument[I] is TScreenLayoutRoundedRectangleLayer then
      begin
        if FDocument.RemoveRoundedRectangle(I, RoundedRectangleData) then
        begin
          AfterSelection := FDocument.GetSelectedLayerIndices;
          if Command <> nil then
            Command.Add(TScreenLayoutDeleteRoundedRectangleCommand.Create(
              FDocument, I, RoundedRectangleData, BeforeSelection,
              AfterSelection));
        end;
      end
      else if FDocument[I] is TScreenLayoutTextLayer then
      begin
        if FDocument.RemoveText(I, TextData) then
        begin
          AfterSelection := FDocument.GetSelectedLayerIndices;
          if Command <> nil then
            Command.Add(TScreenLayoutDeleteTextCommand.Create(FDocument, I,
              TextData, BeforeSelection, AfterSelection));
        end;
      end
      else if FDocument[I] is TVectArtRectangleLayer then
      begin
        if FDocument.RemoveRectangle(I, Data) then
        begin
          AfterSelection := FDocument.GetSelectedLayerIndices;
          if Command <> nil then
            Command.Add(TVectArtDeleteRectangleCommand.Create(FDocument, I,
              Data, BeforeSelection, AfterSelection));
        end;
      end
      else if FDocument[I] is TVectArtPathLayer then
      begin
        if FDocument.RemovePath(I, PathData) then
        begin
          AfterSelection := FDocument.GetSelectedLayerIndices;
          if Command <> nil then
            Command.Add(TVectArtDeletePathCommand.Create(FDocument, I,
              PathData, BeforeSelection, AfterSelection));
        end;
      end
      else if FDocument[I] is TVectArtImageLayer then
      begin
        if FDocument.RemoveImage(I, ImageData) then
        begin
          AfterSelection := FDocument.GetSelectedLayerIndices;
          if Command <> nil then
            Command.Add(TVectArtDeleteImageCommand.Create(FDocument, I,
              ImageData, BeforeSelection, AfterSelection));
        end;
      end
      else if FDocument[I] is TScreenLayoutShapeLayer then
      begin
        if FDocument.RemoveShape(I, ShapeData) then
        begin
          AfterSelection := FDocument.GetSelectedLayerIndices;
          if Command <> nil then
            Command.Add(TScreenLayoutDeleteShapeCommand.Create(FDocument, I,
              ShapeData, BeforeSelection, AfterSelection));
        end;
      end;
    end;
  end;
  if (Command <> nil) and (Command.Count > 0) then
    FEditHistory.AddApplied(Command)
  else
    Command.Free;
end;

procedure TVectArtLayerOperations.Execute(Action: TVectArtLayerAction);
begin
  if not CanExecute(Action) then
    Exit;
  case Action of
    vlaAdd: AddRectangle;
    vlaDuplicate:
      if CanEditOpenGroupChild(FEditorState) then
        DuplicateOpenGroupChild(FDocument, FEditHistory, FEditorState)
      else if CanDuplicateSelectedGroups(FDocument) then
        DuplicateSelectedGroups(FDocument, FEditHistory)
      else
        DuplicateSelectedLayers(FDocument, FEditHistory);
    vlaDelete:
      if CanEditOpenGroupChild(FEditorState) then
        DeleteOpenGroupChild(FDocument, FEditHistory, FEditorState)
      else
        DeleteSelectedLayers;
    vlaMoveForward:
      if CanEditOpenGroupChild(FEditorState) then
        MoveOpenGroupChild(FDocument, FEditHistory, FEditorState, 1)
      else
        MoveSelectedLayers(1);
    vlaMoveBackward:
      if CanEditOpenGroupChild(FEditorState) then
        MoveOpenGroupChild(FDocument, FEditHistory, FEditorState, -1)
      else
        MoveSelectedLayers(-1);
  end;
end;

procedure TVectArtLayerOperations.MoveSelectedLayers(Delta: Integer);
var
  AfterSelection: TArray<Integer>;
  BeforeSelection: TArray<Integer>;
  Command: TVectArtCompoundCommand;
  I: Integer;
begin
  Command := nil;
  if FEditHistory <> nil then
    Command := TVectArtCompoundCommand.Create;
  if Delta > 0 then
  begin
    for I := FDocument.LayerCount - 2 downto 1 do
      if FDocument.IsLayerSelected(I) and
        not FDocument.IsLayerSelected(I + 1) then
      begin
        BeforeSelection := FDocument.GetSelectedLayerIndices;
        FDocument.MoveLayer(I, I + 1);
        AfterSelection := FDocument.GetSelectedLayerIndices;
        if Command <> nil then
          Command.Add(TVectArtMoveLayerCommand.Create(FDocument, I, I + 1,
            BeforeSelection, AfterSelection));
      end;
  end
  else
  begin
    for I := 2 to FDocument.LayerCount - 1 do
      if FDocument.IsLayerSelected(I) and
        not FDocument.IsLayerSelected(I - 1) then
      begin
        BeforeSelection := FDocument.GetSelectedLayerIndices;
        FDocument.MoveLayer(I, I - 1);
        AfterSelection := FDocument.GetSelectedLayerIndices;
        if Command <> nil then
          Command.Add(TVectArtMoveLayerCommand.Create(FDocument, I, I - 1,
            BeforeSelection, AfterSelection));
      end;
  end;
  if (Command <> nil) and (Command.Count > 0) then
    FEditHistory.AddApplied(Command)
  else
    Command.Free;
end;

function TVectArtLayerOperations.NextRectangleName: string;
var
  Candidate: string;
  Found: Boolean;
  I: Integer;
  Number: Integer;
begin
  Number := 1;
  repeat
    Candidate := 'Rectangle ' + Number.ToString;
    Found := False;
    for I := 1 to FDocument.LayerCount - 1 do
      if SameText(FDocument[I].Name, Candidate) then
      begin
        Found := True;
        Break;
      end;
    Inc(Number);
  until not Found;
  Result := Candidate;
end;

function TVectArtLayerOperations.SelectedLayersEditable: Boolean;
var
  I: Integer;
begin
  Result := FDocument.SelectionCount > 0;
  if not Result then
    Exit;
  for I := 0 to FDocument.LayerCount - 1 do
    if FDocument.IsLayerSelected(I) and
      ((I = 0) or FDocument[I].Locked or
       not ((FDocument[I] is TVectArtRectangleLayer) or
         (FDocument[I] is TVectArtPathLayer) or
         (FDocument[I] is TScreenLayoutShapeLayer) or
         (FDocument[I] is TVectArtImageLayer))) then
      Exit(False);
end;

end.
