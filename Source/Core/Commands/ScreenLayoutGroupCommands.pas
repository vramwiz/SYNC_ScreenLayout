// レイヤーのグループ化と解除を、所有権を保ったままUndo／Redo可能にする。
unit ScreenLayoutGroupCommands;

interface

uses
  ScreenLayoutDocument, ScreenLayoutEditHistory, ScreenLayoutEditorState;

// トップレベルの現在選択をグループ化できるかを返す。
function CanGroupSelectedLayers(Document: TVectArtDocument): Boolean;
// トップレベルの単一選択を解除できるグループかを返す。
function CanUngroupSelectedLayer(Document: TVectArtDocument): Boolean;
// 現在選択を1グループへ置き換え、操作を履歴へ追加する。
procedure GroupSelectedLayers(Document: TVectArtDocument;
  EditHistory: TVectArtEditHistory);
// 選択グループを子へ展開し、操作を履歴へ追加する。
procedure UngroupSelectedLayer(Document: TVectArtDocument;
  EditHistory: TVectArtEditHistory);
// 開いているグループの子選択へ編集操作を適用できるかを返す。
function CanEditOpenGroupChild(EditorState: TVectArtEditorState): Boolean;
// 選択中の直下子をグループから取り外し、操作を履歴へ追加する。
procedure DeleteOpenGroupChild(Document: TVectArtDocument;
  EditHistory: TVectArtEditHistory; EditorState: TVectArtEditorState);
// 選択中の直下子を再帰複製し、同じ親へ挿入する。
procedure DuplicateOpenGroupChild(Document: TVectArtDocument;
  EditHistory: TVectArtEditHistory; EditorState: TVectArtEditorState);
// 選択子を指定方向へ1段移動できるかを返す。
function CanMoveOpenGroupChild(EditorState: TVectArtEditorState;
  Delta: Integer): Boolean;
// 選択子を親グループ内で指定方向へ1段移動する。
procedure MoveOpenGroupChild(Document: TVectArtDocument;
  EditHistory: TVectArtEditHistory; EditorState: TVectArtEditorState;
  Delta: Integer);
// トップレベル選択がグループだけで構成され複製可能かを返す。
function CanDuplicateSelectedGroups(Document: TVectArtDocument): Boolean;
// 選択グループを入れ子構造ごと再帰複製する。
procedure DuplicateSelectedGroups(Document: TVectArtDocument;
  EditHistory: TVectArtEditHistory);
// レイヤーとそのフィルターを、所有権を共有せず再帰複製する。
function CloneScreenLayoutLayer(Source: TVectArtLayer;
  const NewName: string): TVectArtLayer;
// 開いているグループの子選択を内部グループ化できるかを返す。
function CanGroupOpenGroupChildren(EditorState: TVectArtEditorState): Boolean;
// 選択中の直下子が解除可能な内部グループかを返す。
function CanUngroupOpenGroupChild(EditorState: TVectArtEditorState): Boolean;
// 選択中の直下子を新しい内部グループへまとめる。
procedure GroupOpenGroupChildren(Document: TVectArtDocument;
  EditHistory: TVectArtEditHistory; EditorState: TVectArtEditorState);
// 選択中の内部グループを解除し、子を現在の親へ展開する。
procedure UngroupOpenGroupChild(Document: TVectArtDocument;
  EditHistory: TVectArtEditHistory; EditorState: TVectArtEditorState);

implementation

uses
  System.Classes, System.Generics.Collections, System.SysUtils, System.Types,
  ScreenLayoutEditCommands, ScreenLayoutGroupChildCommands,
  ScreenLayoutLayerGeometry, ScreenLayoutPathOperations,
  ScreenLayoutShapeOperations;

type
  TScreenLayoutGroupCommand = class(TVectArtEditCommand)
  private
    FBeforeSelection: TArray<Integer>;
    FDocument: TVectArtDocument;
    FGroup: TScreenLayoutGroupLayer;
    FGroupInDocument: Boolean;
    FGroupIndex: Integer;
    FOriginalIndices: TArray<Integer>;
  public
    constructor Create(ADocument: TVectArtDocument;
      const OriginalIndices: TArray<Integer>; const GroupName: string);
    destructor Destroy; override;
    procedure Execute; override;
    procedure Undo; override;
  end;

  TScreenLayoutUngroupCommand = class(TVectArtEditCommand)
  private
    FChildCount: Integer;
    FDocument: TVectArtDocument;
    FGroup: TScreenLayoutGroupLayer;
    FGroupInDocument: Boolean;
    FGroupIndex: Integer;
  public
    constructor Create(ADocument: TVectArtDocument; GroupIndex: Integer);
    destructor Destroy; override;
    procedure Execute; override;
    procedure Undo; override;
  end;

  TScreenLayoutDuplicateGroupsCommand = class(TVectArtEditCommand)
  private
    FAfterSelection: TArray<Integer>;
    FBeforeSelection: TArray<Integer>;
    FDocument: TVectArtDocument;
    FDuplicates: TArray<TVectArtLayer>;
    FDuplicatesInDocument: Boolean;
    FIndices: TArray<Integer>;
  public
    constructor Create(ADocument: TVectArtDocument;
      const BeforeSelection, Indices: TArray<Integer>;
      const Duplicates: TArray<TVectArtLayer>);
    destructor Destroy; override;
    procedure Execute; override;
    procedure Undo; override;
  end;

function OpenGroupChildIndex(EditorState: TVectArtEditorState): Integer;
var
  I: Integer;
begin
  Result := -1;
  if (EditorState = nil) or (EditorState.OpenGroup = nil) or
    (EditorState.OpenGroupChild = nil) then
    Exit;
  for I := 0 to EditorState.OpenGroup.ChildCount - 1 do
    if EditorState.OpenGroup[I] = EditorState.OpenGroupChild then
      Exit(I);
end;

function CanEditOpenGroupChild(EditorState: TVectArtEditorState): Boolean;
var
  Layer: TVectArtLayer;
  Layers: TArray<TVectArtLayer>;
begin
  Result := (EditorState <> nil) and
    (EditorState.OpenGroupChildCount > 0) and
    (OpenGroupChildIndex(EditorState) >= 0) and
    (EditorState.OpenGroup <> nil);
  if not Result then
    Exit;
  Layers := EditorState.GetOpenGroupChildren;
  for Layer in Layers do
    if Layer.Locked then
      Exit(False);
end;

function OpenGroupSelectedIndices(
  EditorState: TVectArtEditorState): TArray<Integer>;
var
  I: Integer;
  Indices: TList<Integer>;
begin
  Indices := TList<Integer>.Create;
  try
    if (EditorState <> nil) and (EditorState.OpenGroup <> nil) then
      for I := 0 to EditorState.OpenGroup.ChildCount - 1 do
        if EditorState.IsOpenGroupChildSelected(
          EditorState.OpenGroup[I]) then
          Indices.Add(I);
    Result := Indices.ToArray;
  finally
    Indices.Free;
  end;
end;

function CanGroupOpenGroupChildren(
  EditorState: TVectArtEditorState): Boolean;
begin
  Result := CanEditOpenGroupChild(EditorState) and
    (EditorState.OpenGroupChildCount >= 2) and
    (Length(OpenGroupSelectedIndices(EditorState)) =
      EditorState.OpenGroupChildCount);
end;

function CanUngroupOpenGroupChild(
  EditorState: TVectArtEditorState): Boolean;
begin
  Result := CanEditOpenGroupChild(EditorState) and
    (EditorState.OpenGroupChildCount = 1) and
    (EditorState.OpenGroupChild is TScreenLayoutGroupLayer);
end;

function NextChildGroupName(Parent: TScreenLayoutGroupLayer): string;
var
  Count: Integer;
  I: Integer;
begin
  Count := 0;
  for I := 0 to Parent.ChildCount - 1 do
    if Parent[I] is TScreenLayoutGroupLayer then
      Inc(Count);
  Result := Format('グループ %d', [Count + 1]);
end;

procedure GroupOpenGroupChildren(Document: TVectArtDocument;
  EditHistory: TVectArtEditHistory; EditorState: TVectArtEditorState);
var
  Command: TScreenLayoutGroupChildrenCommand;
begin
  if (Document = nil) or not CanGroupOpenGroupChildren(EditorState) then
    Exit;
  Command := TScreenLayoutGroupChildrenCommand.Create(Document, EditorState,
    EditorState.OpenGroup, OpenGroupSelectedIndices(EditorState),
    NextChildGroupName(EditorState.OpenGroup));
  Command.Execute;
  if EditHistory <> nil then
    EditHistory.AddApplied(Command)
  else
    Command.Free;
end;

procedure UngroupOpenGroupChild(Document: TVectArtDocument;
  EditHistory: TVectArtEditHistory; EditorState: TVectArtEditorState);
var
  Command: TScreenLayoutUngroupChildCommand;
begin
  if (Document = nil) or not CanUngroupOpenGroupChild(EditorState) then
    Exit;
  Command := TScreenLayoutUngroupChildCommand.Create(Document, EditorState,
    EditorState.OpenGroup, OpenGroupChildIndex(EditorState));
  Command.Execute;
  if EditHistory <> nil then
    EditHistory.AddApplied(Command)
  else
    Command.Free;
end;

function CanMoveOpenGroupChild(EditorState: TVectArtEditorState;
  Delta: Integer): Boolean;
var
  Index: Integer;
begin
  Result := CanEditOpenGroupChild(EditorState);
  if not Result then
    Exit;
  for Index in OpenGroupSelectedIndices(EditorState) do
  begin
    if (Delta > 0) and
      (Index < EditorState.OpenGroup.ChildCount - 1) and
      not EditorState.IsOpenGroupChildSelected(
        EditorState.OpenGroup[Index + 1]) then
      Exit(True);
    if (Delta < 0) and (Index > 0) and
      not EditorState.IsOpenGroupChildSelected(
        EditorState.OpenGroup[Index - 1]) then
      Exit(True);
  end;
  Result := False;
end;

procedure CopyCommonLayerValues(Source, Target: TVectArtLayer);
var
  I: Integer;
begin
  Target.Locked := False;
  Target.Opacity := Source.Opacity;
  Target.Visible := Source.Visible;
  for I := 0 to Source.FilterCount - 1 do
    Target.AddFilter(Source.Filters[I].Clone);
end;

function CloneScreenLayoutLayer(Source: TVectArtLayer;
  const NewName: string): TVectArtLayer;
var
  Arc: TScreenLayoutArcLayer;
  ArcShape: TScreenLayoutEllipseArcShapeLayer;
  ChildClone: TVectArtLayer;
  Group: TScreenLayoutGroupLayer;
  I: Integer;
  Image: TVectArtImageLayer;
  Path: TVectArtPathLayer;
  Rectangle: TVectArtRectangleLayer;
  RectangleLine: TScreenLayoutRectangleLineLayer;
  Rounded: TScreenLayoutRoundedRectangleLayer;
  RoundedLine: TScreenLayoutRoundedRectangleLineLayer;
  Shape: TScreenLayoutShapeLayer;
  TextLayer: TScreenLayoutTextLayer;
begin
  if Source is TScreenLayoutGroupLayer then
  begin
    Group := TScreenLayoutGroupLayer.Create(NewName);
    for I := 0 to TScreenLayoutGroupLayer(Source).ChildCount - 1 do
    begin
      ChildClone := CloneScreenLayoutLayer(
        TScreenLayoutGroupLayer(Source)[I],
        TScreenLayoutGroupLayer(Source)[I].Name);
      ChildClone.Locked := TScreenLayoutGroupLayer(Source)[I].Locked;
      Group.AddChild(ChildClone);
    end;
    Result := Group;
  end
  else if Source is TScreenLayoutRoundedRectangleLineLayer then
  begin
    RoundedLine := TScreenLayoutRoundedRectangleLineLayer(Source);
    Result := TScreenLayoutRoundedRectangleLineLayer.Create(NewName,
      RoundedLine.Bounds, RoundedLine.CornerRadii);
    TScreenLayoutRoundedRectangleLineLayer(Result).RotationDegrees :=
      RoundedLine.RotationDegrees;
    TScreenLayoutRoundedRectangleLineLayer(Result).StrokeColor :=
      RoundedLine.StrokeColor;
    TScreenLayoutRoundedRectangleLineLayer(Result).StrokeStyle :=
      RoundedLine.StrokeStyle;
    TScreenLayoutRoundedRectangleLineLayer(Result).StrokeWidth :=
      RoundedLine.StrokeWidth;
  end
  else if Source is TScreenLayoutEllipseLineLayer then
  begin
    RectangleLine := TScreenLayoutRectangleLineLayer(Source);
    Result := TScreenLayoutEllipseLineLayer.Create(NewName,
      RectangleLine.Bounds);
    TScreenLayoutEllipseLineLayer(Result).RotationDegrees :=
      RectangleLine.RotationDegrees;
    TScreenLayoutEllipseLineLayer(Result).StrokeColor :=
      RectangleLine.StrokeColor;
    TScreenLayoutEllipseLineLayer(Result).StrokeStyle :=
      RectangleLine.StrokeStyle;
    TScreenLayoutEllipseLineLayer(Result).StrokeWidth :=
      RectangleLine.StrokeWidth;
  end
  else if Source is TScreenLayoutRectangleLineLayer then
  begin
    RectangleLine := TScreenLayoutRectangleLineLayer(Source);
    Result := TScreenLayoutRectangleLineLayer.Create(NewName,
      RectangleLine.Bounds);
    TScreenLayoutRectangleLineLayer(Result).RotationDegrees :=
      RectangleLine.RotationDegrees;
    TScreenLayoutRectangleLineLayer(Result).StrokeColor :=
      RectangleLine.StrokeColor;
    TScreenLayoutRectangleLineLayer(Result).StrokeStyle :=
      RectangleLine.StrokeStyle;
    TScreenLayoutRectangleLineLayer(Result).StrokeWidth :=
      RectangleLine.StrokeWidth;
  end
  else if Source is TScreenLayoutArcLayer then
  begin
    Arc := TScreenLayoutArcLayer(Source);
    Result := TScreenLayoutArcLayer.Create(NewName, Arc.Bounds);
    TScreenLayoutArcLayer(Result).LineCap := Arc.LineCap;
    TScreenLayoutArcLayer(Result).RotationDegrees := Arc.RotationDegrees;
    TScreenLayoutArcLayer(Result).StartAngleDegrees := Arc.StartAngleDegrees;
    TScreenLayoutArcLayer(Result).StrokeColor := Arc.StrokeColor;
    TScreenLayoutArcLayer(Result).StrokeStyle := Arc.StrokeStyle;
    TScreenLayoutArcLayer(Result).StrokeWidth := Arc.StrokeWidth;
    TScreenLayoutArcLayer(Result).SweepAngleDegrees := Arc.SweepAngleDegrees;
  end
  else if Source is TScreenLayoutEllipseArcShapeLayer then
  begin
    ArcShape := TScreenLayoutEllipseArcShapeLayer(Source);
    Result := TScreenLayoutEllipseArcShapeLayer.Create(NewName,
      ArcShape.Bounds, ArcShape.FillColor);
    TScreenLayoutEllipseArcShapeLayer(Result).RotationDegrees :=
      ArcShape.RotationDegrees;
    TScreenLayoutEllipseArcShapeLayer(Result).StartAngleDegrees :=
      ArcShape.StartAngleDegrees;
    TScreenLayoutEllipseArcShapeLayer(Result).SweepAngleDegrees :=
      ArcShape.SweepAngleDegrees;
  end
  else if Source is TScreenLayoutRoundedRectangleLayer then
  begin
    Rounded := TScreenLayoutRoundedRectangleLayer(Source);
    Result := TScreenLayoutRoundedRectangleLayer.Create(NewName,
      Rounded.Bounds, Rounded.FillColor, Rounded.CornerRadii);
    TScreenLayoutRoundedRectangleLayer(Result).RotationDegrees :=
      Rounded.RotationDegrees;
  end
  else if Source is TScreenLayoutTextLayer then
  begin
    TextLayer := TScreenLayoutTextLayer(Source);
    Result := TScreenLayoutTextLayer.Create(NewName, TextLayer.Bounds,
      TextLayer.Text, TextLayer.FontFamily, TextLayer.FontSize,
      TextLayer.WrapWidth, TextLayer.FillColor);
    TScreenLayoutTextLayer(Result).Alignment := TextLayer.Alignment;
    TScreenLayoutTextLayer(Result).FontStyle := TextLayer.FontStyle;
    TScreenLayoutTextLayer(Result).LetterSpacingRatio :=
      TextLayer.LetterSpacingRatio;
    TScreenLayoutTextLayer(Result).IndividualLetterSpacingRatios :=
      TextLayer.IndividualLetterSpacingRatios;
    TScreenLayoutTextLayer(Result).LineSpacingRatio :=
      TextLayer.LineSpacingRatio;
    TScreenLayoutTextLayer(Result).RotationDegrees :=
      TextLayer.RotationDegrees;
    TScreenLayoutTextLayer(Result).TransformMode :=
      TextLayer.TransformMode;
  end
  else if Source is TScreenLayoutEllipseLayer then
  begin
    Rectangle := TVectArtRectangleLayer(Source);
    Result := TScreenLayoutEllipseLayer.Create(NewName, Rectangle.Bounds,
      Rectangle.FillColor);
    TScreenLayoutEllipseLayer(Result).RotationDegrees :=
      Rectangle.RotationDegrees;
  end
  else if Source is TVectArtRectangleLayer then
  begin
    Rectangle := TVectArtRectangleLayer(Source);
    Result := TVectArtRectangleLayer.Create(NewName, Rectangle.Bounds,
      Rectangle.FillColor);
    TVectArtRectangleLayer(Result).RotationDegrees :=
      Rectangle.RotationDegrees;
  end
  else if Source is TVectArtImageLayer then
  begin
    Image := TVectArtImageLayer(Source);
    Result := TVectArtImageLayer.Create(NewName, Copy(Image.PngData),
      Image.Points, Image.SourceKind, Image.SourceFileName);
  end
  else if Source is TScreenLayoutShapeLayer then
  begin
    Shape := TScreenLayoutShapeLayer(Source);
    Result := TScreenLayoutShapeLayer.Create(NewName,
      CloneScreenLayoutShapeContours(Shape.Contours));
    TScreenLayoutShapeLayer(Result).FillColor := Shape.FillColor;
    TScreenLayoutShapeLayer(Result).FillRule := Shape.FillRule;
    TScreenLayoutShapeLayer(Result).StrokeColor := Shape.StrokeColor;
    TScreenLayoutShapeLayer(Result).StrokeStyle := Shape.StrokeStyle;
    TScreenLayoutShapeLayer(Result).StrokeWidth := Shape.StrokeWidth;
  end
  else if Source is TVectArtPathLayer then
  begin
    Path := TVectArtPathLayer(Source);
    Result := TVectArtPathLayer.Create(NewName,
      CloneScreenLayoutPathVertices(Path.Vertices), Path.Closed);
    TVectArtPathLayer(Result).LineCap := Path.LineCap;
    TVectArtPathLayer(Result).MifStrokeStyle := Path.MifStrokeStyle;
    TVectArtPathLayer(Result).StrokeColor := Path.StrokeColor;
    TVectArtPathLayer(Result).StrokeWidth := Path.StrokeWidth;
  end
  else
    raise EArgumentException.Create('Unsupported group child layer type');
  CopyCommonLayerValues(Source, Result);
end;

function GroupChildCopyName(Group: TScreenLayoutGroupLayer;
  const SourceName: string): string;
var
  Found: Boolean;
  I: Integer;
  Number: Integer;
begin
  Result := SourceName + ' Copy';
  Number := 2;
  while True do
  begin
    Found := False;
    for I := 0 to Group.ChildCount - 1 do
      if SameText(Group[I].Name, Result) then
      begin
        Found := True;
        Break;
      end;
    if not Found then
      Exit;
    Result := SourceName + ' Copy ' + Number.ToString;
    Inc(Number);
  end;
end;

function CanDuplicateSelectedGroups(Document: TVectArtDocument): Boolean;
var
  I: Integer;
begin
  Result := (Document <> nil) and (Document.SelectionCount > 0);
  if not Result then
    Exit;
  for I := 1 to Document.LayerCount - 1 do
    if Document.IsLayerSelected(I) and
      (Document[I].Locked or
       not (Document[I] is TScreenLayoutGroupLayer)) then
      Exit(False);
end;

function DocumentCopyName(UsedNames: TStrings;
  const SourceName: string): string;
var
  Number: Integer;
begin
  Result := SourceName + ' Copy';
  Number := 2;
  while UsedNames.IndexOf(Result) >= 0 do
  begin
    Result := SourceName + ' Copy ' + Number.ToString;
    Inc(Number);
  end;
  UsedNames.Add(Result);
end;

procedure DuplicateSelectedGroups(Document: TVectArtDocument;
  EditHistory: TVectArtEditHistory);
var
  BeforeSelection: TArray<Integer>;
  Command: TScreenLayoutDuplicateGroupsCommand;
  Duplicates: TArray<TVectArtLayer>;
  I: Integer;
  Indices: TArray<Integer>;
  UsedNames: TStringList;
begin
  if not CanDuplicateSelectedGroups(Document) then
    Exit;
  BeforeSelection := Document.GetSelectedLayerIndices;
  Indices := Copy(BeforeSelection);
  SetLength(Duplicates, Length(Indices));
  UsedNames := TStringList.Create;
  try
    UsedNames.CaseSensitive := False;
    for I := 0 to Document.LayerCount - 1 do
      UsedNames.Add(Document[I].Name);
    for I := 0 to High(Indices) do
    begin
      Duplicates[I] := CloneScreenLayoutLayer(Document[Indices[I]],
        DocumentCopyName(UsedNames, Document[Indices[I]].Name));
      TranslateScreenLayoutLayer(Duplicates[I], 24, 24);
      Indices[I] := Indices[I] + I + 1;
    end;
  finally
    UsedNames.Free;
  end;
  Command := TScreenLayoutDuplicateGroupsCommand.Create(Document,
    BeforeSelection, Indices, Duplicates);
  Command.Execute;
  if EditHistory <> nil then
    EditHistory.AddApplied(Command)
  else
    Command.Free;
end;

procedure DeleteOpenGroupChild(Document: TVectArtDocument;
  EditHistory: TVectArtEditHistory; EditorState: TVectArtEditorState);
var
  BatchCommand: TScreenLayoutDeleteGroupChildrenCommand;
  Command: TScreenLayoutDeleteGroupChildCommand;
  Indices: TArray<Integer>;
begin
  if (Document = nil) or not CanEditOpenGroupChild(EditorState) then
    Exit;
  Indices := OpenGroupSelectedIndices(EditorState);
  if Length(Indices) > 1 then
  begin
    BatchCommand := TScreenLayoutDeleteGroupChildrenCommand.Create(Document,
      EditorState, EditorState.OpenGroup, Indices);
    BatchCommand.Execute;
    if EditHistory <> nil then
      EditHistory.AddApplied(BatchCommand)
    else
      BatchCommand.Free;
    Exit;
  end;
  Command := TScreenLayoutDeleteGroupChildCommand.Create(Document,
    EditorState, EditorState.OpenGroup, Indices[0]);
  Command.Execute;
  if EditHistory <> nil then
    EditHistory.AddApplied(Command)
  else
    Command.Free;
end;

procedure DuplicateOpenGroupChild(Document: TVectArtDocument;
  EditHistory: TVectArtEditHistory; EditorState: TVectArtEditorState);
var
  BatchCommand: TScreenLayoutDuplicateGroupChildrenCommand;
  Command: TScreenLayoutDuplicateGroupChildCommand;
  Duplicate: TVectArtLayer;
  Duplicates: TArray<TVectArtLayer>;
  I: Integer;
  Index: Integer;
  Indices: TArray<Integer>;
  Sources: TArray<TVectArtLayer>;
begin
  if (Document = nil) or not CanEditOpenGroupChild(EditorState) then
    Exit;
  Indices := OpenGroupSelectedIndices(EditorState);
  if Length(Indices) > 1 then
  begin
    SetLength(Sources, Length(Indices));
    SetLength(Duplicates, Length(Indices));
    for I := 0 to High(Indices) do
    begin
      Sources[I] := EditorState.OpenGroup[Indices[I]];
      Duplicates[I] := CloneScreenLayoutLayer(Sources[I],
        GroupChildCopyName(EditorState.OpenGroup, Sources[I].Name));
      TranslateScreenLayoutLayer(Duplicates[I], 24, 24);
      Indices[I] := Indices[I] + I + 1;
    end;
    BatchCommand := TScreenLayoutDuplicateGroupChildrenCommand.Create(
      Document, EditorState, EditorState.OpenGroup, Indices, Sources,
      Duplicates);
    BatchCommand.Execute;
    if EditHistory <> nil then
      EditHistory.AddApplied(BatchCommand)
    else
      BatchCommand.Free;
    Exit;
  end;
  Index := Indices[0];
  Duplicate := CloneScreenLayoutLayer(EditorState.OpenGroupChild,
    GroupChildCopyName(EditorState.OpenGroup,
      EditorState.OpenGroupChild.Name));
  TranslateScreenLayoutLayer(Duplicate, 24, 24);
  Command := TScreenLayoutDuplicateGroupChildCommand.Create(Document,
    EditorState, EditorState.OpenGroup, Index + 1, Duplicate);
  Command.Execute;
  if EditHistory <> nil then
    EditHistory.AddApplied(Command)
  else
    Command.Free;
end;

procedure MoveOpenGroupChild(Document: TVectArtDocument;
  EditHistory: TVectArtEditHistory; EditorState: TVectArtEditorState;
  Delta: Integer);
var
  AfterOrder: TArray<TVectArtLayer>;
  BeforeOrder: TArray<TVectArtLayer>;
  Command: TScreenLayoutMoveGroupChildCommand;
  I: Integer;
  Index: Integer;
  J: Integer;
  ReorderCommand: TScreenLayoutReorderGroupChildrenCommand;
  Temp: TVectArtLayer;
begin
  if (Document = nil) or not CanMoveOpenGroupChild(EditorState, Delta) then
    Exit;
  if EditorState.OpenGroupChildCount > 1 then
  begin
    SetLength(BeforeOrder, EditorState.OpenGroup.ChildCount);
    for I := 0 to High(BeforeOrder) do
      BeforeOrder[I] := EditorState.OpenGroup[I];
    AfterOrder := Copy(BeforeOrder);
    if Delta > 0 then
      for I := High(AfterOrder) - 1 downto 0 do
        if EditorState.IsOpenGroupChildSelected(AfterOrder[I]) and
          not EditorState.IsOpenGroupChildSelected(AfterOrder[I + 1]) then
        begin
          Temp := AfterOrder[I];
          AfterOrder[I] := AfterOrder[I + 1];
          AfterOrder[I + 1] := Temp;
        end
    else
      for J := 1 to High(AfterOrder) do
        if EditorState.IsOpenGroupChildSelected(AfterOrder[J]) and
          not EditorState.IsOpenGroupChildSelected(AfterOrder[J - 1]) then
        begin
          Temp := AfterOrder[J];
          AfterOrder[J] := AfterOrder[J - 1];
          AfterOrder[J - 1] := Temp;
        end;
    ReorderCommand := TScreenLayoutReorderGroupChildrenCommand.Create(
      Document, EditorState.OpenGroup, BeforeOrder, AfterOrder);
    ReorderCommand.Execute;
    if EditHistory <> nil then
      EditHistory.AddApplied(ReorderCommand)
    else
      ReorderCommand.Free;
    Exit;
  end;
  Index := OpenGroupChildIndex(EditorState);
  Command := TScreenLayoutMoveGroupChildCommand.Create(Document,
    EditorState.OpenGroup, Index, Index + Delta);
  Command.Execute;
  if EditHistory <> nil then
    EditHistory.AddApplied(Command)
  else
    Command.Free;
end;

{ TScreenLayoutDuplicateGroupsCommand }

constructor TScreenLayoutDuplicateGroupsCommand.Create(
  ADocument: TVectArtDocument; const BeforeSelection,
  Indices: TArray<Integer>; const Duplicates: TArray<TVectArtLayer>);
begin
  inherited Create;
  FDocument := ADocument;
  FBeforeSelection := Copy(BeforeSelection);
  FIndices := Copy(Indices);
  FAfterSelection := Copy(Indices);
  FDuplicates := Copy(Duplicates);
end;

destructor TScreenLayoutDuplicateGroupsCommand.Destroy;
var
  Layer: TVectArtLayer;
begin
  if not FDuplicatesInDocument then
    for Layer in FDuplicates do
      Layer.Free;
  inherited Destroy;
end;

procedure TScreenLayoutDuplicateGroupsCommand.Execute;
var
  I: Integer;
begin
  FDocument.BeginUpdate;
  try
    for I := 0 to High(FIndices) do
      FDocument.InsertLayer(FIndices[I], FDuplicates[I]);
    FDuplicatesInDocument := True;
    FDocument.SetSelectedLayers(FAfterSelection);
  finally
    FDocument.EndUpdate;
  end;
end;

procedure TScreenLayoutDuplicateGroupsCommand.Undo;
var
  I: Integer;
begin
  FDocument.BeginUpdate;
  try
    for I := High(FIndices) downto 0 do
      FDocument.ExtractLayer(FIndices[I]);
    FDuplicatesInDocument := False;
    FDocument.SetSelectedLayers(FBeforeSelection);
  finally
    FDocument.EndUpdate;
  end;
end;

function NextGroupName(Document: TVectArtDocument): string;
var
  Count: Integer;
  I: Integer;
begin
  Count := 0;
  for I := 1 to Document.LayerCount - 1 do
    if Document[I] is TScreenLayoutGroupLayer then
      Inc(Count);
  Result := Format('グループ %d', [Count + 1]);
end;

function CanGroupSelectedLayers(Document: TVectArtDocument): Boolean;
var
  I: Integer;
  Indices: TArray<Integer>;
begin
  Result := (Document <> nil) and (Document.SelectionCount >= 2);
  if not Result then
    Exit;
  Indices := Document.GetSelectedLayerIndices;
  for I := 0 to High(Indices) do
    if Document[Indices[I]].Locked then
      Exit(False);
end;

function CanUngroupSelectedLayer(Document: TVectArtDocument): Boolean;
begin
  Result := (Document <> nil) and (Document.SelectionCount = 1) and
    (Document.SelectedIndex > 0) and
    (Document[Document.SelectedIndex] is TScreenLayoutGroupLayer) and
    not Document[Document.SelectedIndex].Locked;
end;

procedure GroupSelectedLayers(Document: TVectArtDocument;
  EditHistory: TVectArtEditHistory);
var
  Command: TScreenLayoutGroupCommand;
begin
  if not CanGroupSelectedLayers(Document) then
    Exit;
  Command := TScreenLayoutGroupCommand.Create(Document,
    Document.GetSelectedLayerIndices, NextGroupName(Document));
  Command.Execute;
  if EditHistory <> nil then
    EditHistory.AddApplied(Command)
  else
    Command.Free;
end;

procedure UngroupSelectedLayer(Document: TVectArtDocument;
  EditHistory: TVectArtEditHistory);
var
  Command: TScreenLayoutUngroupCommand;
begin
  if not CanUngroupSelectedLayer(Document) then
    Exit;
  Command := TScreenLayoutUngroupCommand.Create(Document,
    Document.SelectedIndex);
  Command.Execute;
  if EditHistory <> nil then
    EditHistory.AddApplied(Command)
  else
    Command.Free;
end;

{ TScreenLayoutGroupCommand }

constructor TScreenLayoutGroupCommand.Create(ADocument: TVectArtDocument;
  const OriginalIndices: TArray<Integer>; const GroupName: string);
begin
  inherited Create;
  FDocument := ADocument;
  FOriginalIndices := Copy(OriginalIndices);
  FBeforeSelection := Copy(OriginalIndices);
  FGroup := TScreenLayoutGroupLayer.Create(GroupName);
end;

destructor TScreenLayoutGroupCommand.Destroy;
begin
  if not FGroupInDocument then
    FGroup.Free;
  inherited Destroy;
end;

procedure TScreenLayoutGroupCommand.Execute;
var
  I: Integer;
begin
  FDocument.BeginUpdate;
  try
    for I := High(FOriginalIndices) downto 0 do
      FGroup.InsertChild(0, FDocument.ExtractLayer(FOriginalIndices[I]));
    FGroupIndex := FOriginalIndices[High(FOriginalIndices)] -
      High(FOriginalIndices);
    FGroupIndex := FDocument.InsertLayer(FGroupIndex, FGroup);
    FGroupInDocument := True;
    FDocument.SetSelectedLayers([FGroupIndex]);
  finally
    FDocument.EndUpdate;
  end;
end;

procedure TScreenLayoutGroupCommand.Undo;
var
  I: Integer;
begin
  FDocument.BeginUpdate;
  try
    FDocument.ExtractLayer(FGroupIndex);
    FGroupInDocument := False;
    for I := 0 to High(FOriginalIndices) do
      FDocument.InsertLayer(FOriginalIndices[I], FGroup.ExtractChild(0));
    FDocument.SetSelectedLayers(FBeforeSelection);
  finally
    FDocument.EndUpdate;
  end;
end;

{ TScreenLayoutUngroupCommand }

constructor TScreenLayoutUngroupCommand.Create(ADocument: TVectArtDocument;
  GroupIndex: Integer);
begin
  inherited Create;
  FDocument := ADocument;
  FGroupIndex := GroupIndex;
  FGroup := TScreenLayoutGroupLayer(ADocument[GroupIndex]);
  FChildCount := FGroup.ChildCount;
  FGroupInDocument := True;
end;

destructor TScreenLayoutUngroupCommand.Destroy;
begin
  if not FGroupInDocument then
    FGroup.Free;
  inherited Destroy;
end;

procedure TScreenLayoutUngroupCommand.Execute;
var
  Child: TVectArtLayer;
  I: Integer;
  Selection: TArray<Integer>;
begin
  FDocument.BeginUpdate;
  try
    FDocument.ExtractLayer(FGroupIndex);
    FGroupInDocument := False;
    SetLength(Selection, FChildCount);
    for I := High(Selection) downto 0 do
    begin
      Child := FGroup.ExtractChild(FGroup.ChildCount - 1);
      FDocument.InsertLayer(FGroupIndex, Child);
      Selection[I] := FGroupIndex + I;
    end;
    FDocument.SetSelectedLayers(Selection);
  finally
    FDocument.EndUpdate;
  end;
end;

procedure TScreenLayoutUngroupCommand.Undo;
var
  I: Integer;
begin
  FDocument.BeginUpdate;
  try
    for I := FGroupIndex + FChildCount - 1 downto FGroupIndex do
      FGroup.InsertChild(0, FDocument.ExtractLayer(I));
    FGroupIndex := FDocument.InsertLayer(FGroupIndex, FGroup);
    FGroupInDocument := True;
    FDocument.SetSelectedLayers([FGroupIndex]);
  finally
    FDocument.EndUpdate;
  end;
end;

end.
