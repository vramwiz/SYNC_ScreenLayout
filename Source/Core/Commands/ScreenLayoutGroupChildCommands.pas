// グループ直下の子に対する構造変更と所有権をUndo／Redo単位で管理する。
unit ScreenLayoutGroupChildCommands;

interface

uses
  ScreenLayoutDocument, ScreenLayoutEditCommands, ScreenLayoutEditorState;

type
  // グループ内部の子レイヤーの表示／ロック状態をポインターで管理する。
  TScreenLayoutGroupChildBooleanCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FLayer: TVectArtLayer;
    FNewValue: Boolean;
    FOldValue: Boolean;
    FPropertyKind: TVectArtLayerBooleanProperty;
    procedure ApplyValue(Value: Boolean);
  public
    constructor Create(ADocument: TVectArtDocument; ALayer: TVectArtLayer;
      PropertyKind: TVectArtLayerBooleanProperty; OldValue,
      NewValue: Boolean);
    procedure Execute; override;
    procedure Undo; override;
  end;

  // 選択された複数レイヤーを積層順のまま同一または別コンテナへ移す。
  TScreenLayoutReparentLayersCommand = class(TVectArtEditCommand)
  private
    FDestinationIndex: Integer;
    FDestinationParent: TScreenLayoutGroupLayer;
    FDocument: TVectArtDocument;
    FEditorState: TVectArtEditorState;
    FLayers: TArray<TVectArtLayer>;
    FSourceIndices: TArray<Integer>;
    FSourceParent: TScreenLayoutGroupLayer;
    function ExtractLayer(Parent: TScreenLayoutGroupLayer;
      Index: Integer): TVectArtLayer;
    function InsertLayer(Parent: TScreenLayoutGroupLayer; Index: Integer;
      Layer: TVectArtLayer): Integer;
    procedure SelectLayers(Parent: TScreenLayoutGroupLayer;
      const Indices: TArray<Integer>);
  public
    constructor Create(ADocument: TVectArtDocument;
      AEditorState: TVectArtEditorState;
      ASourceParent: TScreenLayoutGroupLayer;
      const SourceIndices: TArray<Integer>;
      ADestinationParent: TScreenLayoutGroupLayer; DestinationIndex: Integer);
    procedure Execute; override;
    procedure Undo; override;
  end;

  // 取り外した子の所有権を履歴内で保持し、Undo時に元の位置へ戻す。
  TScreenLayoutDeleteGroupChildCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FEditorState: TVectArtEditorState;
    FGroup: TScreenLayoutGroupLayer;
    FIndex: Integer;
    FLayer: TVectArtLayer;
    FLayerInGroup: Boolean;
  public
    constructor Create(ADocument: TVectArtDocument;
      AEditorState: TVectArtEditorState; AGroup: TScreenLayoutGroupLayer;
      Index: Integer);
    destructor Destroy; override;
    procedure Execute; override;
    procedure Undo; override;
  end;

  // 複製の所有権をグループと履歴の間で移し、選択状態も復元する。
  TScreenLayoutDuplicateGroupChildCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FDuplicate: TVectArtLayer;
    FDuplicateInGroup: Boolean;
    FEditorState: TVectArtEditorState;
    FGroup: TScreenLayoutGroupLayer;
    FIndex: Integer;
    FSource: TVectArtLayer;
  public
    constructor Create(ADocument: TVectArtDocument;
      AEditorState: TVectArtEditorState; AGroup: TScreenLayoutGroupLayer;
      Index: Integer; Duplicate: TVectArtLayer);
    destructor Destroy; override;
    procedure Execute; override;
    procedure Undo; override;
  end;

  // 同じ親グループ内の子を1件だけ並べ替える。
  TScreenLayoutMoveGroupChildCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FGroup: TScreenLayoutGroupLayer;
    FNewIndex: Integer;
    FOldIndex: Integer;
    procedure Move(FromIndex, ToIndex: Integer);
  public
    constructor Create(ADocument: TVectArtDocument;
      AGroup: TScreenLayoutGroupLayer; OldIndex, NewIndex: Integer);
    procedure Execute; override;
    procedure Undo; override;
  end;

  // 複数の子を積層順を保ったまま一括で取り外し、所有権を保持する。
  TScreenLayoutDeleteGroupChildrenCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FEditorState: TVectArtEditorState;
    FGroup: TScreenLayoutGroupLayer;
    FIndices: TArray<Integer>;
    FLayers: TArray<TVectArtLayer>;
    FLayersInGroup: Boolean;
  public
    constructor Create(ADocument: TVectArtDocument;
      AEditorState: TVectArtEditorState; AGroup: TScreenLayoutGroupLayer;
      const Indices: TArray<Integer>);
    destructor Destroy; override;
    procedure Execute; override;
    procedure Undo; override;
  end;

  // 複数の複製を積層順どおりに挿入し、Undo後は履歴が所有する。
  TScreenLayoutDuplicateGroupChildrenCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FDuplicates: TArray<TVectArtLayer>;
    FDuplicatesInGroup: Boolean;
    FEditorState: TVectArtEditorState;
    FGroup: TScreenLayoutGroupLayer;
    FIndices: TArray<Integer>;
    FSources: TArray<TVectArtLayer>;
  public
    constructor Create(ADocument: TVectArtDocument;
      AEditorState: TVectArtEditorState; AGroup: TScreenLayoutGroupLayer;
      const Indices: TArray<Integer>; const Sources,
      Duplicates: TArray<TVectArtLayer>);
    destructor Destroy; override;
    procedure Execute; override;
    procedure Undo; override;
  end;

  // 子オブジェクトの所有権を変えず、親内の順序だけを切り替える。
  TScreenLayoutReorderGroupChildrenCommand = class(TVectArtEditCommand)
  private
    FAfterOrder: TArray<TVectArtLayer>;
    FBeforeOrder: TArray<TVectArtLayer>;
    FDocument: TVectArtDocument;
    FGroup: TScreenLayoutGroupLayer;
    procedure ApplyOrder(const Order: TArray<TVectArtLayer>);
  public
    constructor Create(ADocument: TVectArtDocument;
      AGroup: TScreenLayoutGroupLayer; const BeforeOrder,
      AfterOrder: TArray<TVectArtLayer>);
    procedure Execute; override;
    procedure Undo; override;
  end;

  // 選択子を新しい内部グループへ移し、Undo時に元の位置へ展開する。
  TScreenLayoutGroupChildrenCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FEditorState: TVectArtEditorState;
    FGroup: TScreenLayoutGroupLayer;
    FGroupInParent: Boolean;
    FGroupIndex: Integer;
    FOriginalIndices: TArray<Integer>;
    FParent: TScreenLayoutGroupLayer;
  public
    constructor Create(ADocument: TVectArtDocument;
      AEditorState: TVectArtEditorState; AParent: TScreenLayoutGroupLayer;
      const OriginalIndices: TArray<Integer>; const GroupName: string);
    destructor Destroy; override;
    procedure Execute; override;
    procedure Undo; override;
  end;

  // 内部グループを取り外して子を親へ展開し、Undo用にコンテナを保持する。
  TScreenLayoutUngroupChildCommand = class(TVectArtEditCommand)
  private
    FChildCount: Integer;
    FDocument: TVectArtDocument;
    FEditorState: TVectArtEditorState;
    FGroup: TScreenLayoutGroupLayer;
    FGroupInParent: Boolean;
    FGroupIndex: Integer;
    FParent: TScreenLayoutGroupLayer;
  public
    constructor Create(ADocument: TVectArtDocument;
      AEditorState: TVectArtEditorState; AParent: TScreenLayoutGroupLayer;
      GroupIndex: Integer);
    destructor Destroy; override;
    procedure Execute; override;
    procedure Undo; override;
  end;

implementation

uses
  System.Math;

procedure TScreenLayoutGroupChildBooleanCommand.ApplyValue(Value: Boolean);
begin
  case FPropertyKind of
    vlbpVisible: FLayer.Visible := Value;
    vlbpLocked: FLayer.Locked := Value;
  end;
  FDocument.Changed;
end;

constructor TScreenLayoutGroupChildBooleanCommand.Create(
  ADocument: TVectArtDocument; ALayer: TVectArtLayer;
  PropertyKind: TVectArtLayerBooleanProperty; OldValue,
  NewValue: Boolean);
begin
  inherited Create;
  FDocument := ADocument;
  FLayer := ALayer;
  FPropertyKind := PropertyKind;
  FOldValue := OldValue;
  FNewValue := NewValue;
end;

procedure TScreenLayoutGroupChildBooleanCommand.Execute;
begin
  ApplyValue(FNewValue);
end;

procedure TScreenLayoutGroupChildBooleanCommand.Undo;
begin
  ApplyValue(FOldValue);
end;

constructor TScreenLayoutReparentLayersCommand.Create(
  ADocument: TVectArtDocument; AEditorState: TVectArtEditorState;
  ASourceParent: TScreenLayoutGroupLayer;
  const SourceIndices: TArray<Integer>;
  ADestinationParent: TScreenLayoutGroupLayer; DestinationIndex: Integer);
begin
  inherited Create;
  FDocument := ADocument;
  FEditorState := AEditorState;
  FSourceParent := ASourceParent;
  FSourceIndices := Copy(SourceIndices);
  FDestinationParent := ADestinationParent;
  FDestinationIndex := DestinationIndex;
  SetLength(FLayers, Length(FSourceIndices));
end;

procedure TScreenLayoutReparentLayersCommand.Execute;
var
  DestinationIndices: TArray<Integer>;
  I: Integer;
begin
  FDocument.BeginUpdate;
  try
    for I := High(FSourceIndices) downto 0 do
      FLayers[I] := ExtractLayer(FSourceParent, FSourceIndices[I]);
    SetLength(DestinationIndices, Length(FLayers));
    for I := 0 to High(FLayers) do
      DestinationIndices[I] := InsertLayer(FDestinationParent,
        FDestinationIndex + I, FLayers[I]);
    FDocument.Changed;
  finally
    FDocument.EndUpdate;
  end;
  SelectLayers(FDestinationParent, DestinationIndices);
end;

function TScreenLayoutReparentLayersCommand.ExtractLayer(
  Parent: TScreenLayoutGroupLayer; Index: Integer): TVectArtLayer;
begin
  if Parent <> nil then
    Result := Parent.ExtractChild(Index)
  else
    Result := FDocument.ExtractLayer(Index);
end;

function TScreenLayoutReparentLayersCommand.InsertLayer(
  Parent: TScreenLayoutGroupLayer; Index: Integer;
  Layer: TVectArtLayer): Integer;
begin
  if Parent <> nil then
  begin
    Result := EnsureRange(Index, 0, Parent.ChildCount);
    Parent.InsertChild(Result, Layer);
  end
  else
    Result := FDocument.InsertLayer(Index, Layer);
end;

procedure TScreenLayoutReparentLayersCommand.SelectLayers(
  Parent: TScreenLayoutGroupLayer; const Indices: TArray<Integer>);
begin
  if Parent <> nil then
  begin
    FEditorState.OpenGroupInDocument(FDocument, Parent);
    FEditorState.SetOpenGroupChildren(FLayers);
  end
  else
  begin
    FEditorState.OpenGroup := nil;
    FDocument.SetSelectedLayers(Indices);
  end;
end;

procedure TScreenLayoutReparentLayersCommand.Undo;
var
  I: Integer;
begin
  FDocument.BeginUpdate;
  try
    for I := High(FLayers) downto 0 do
      ExtractLayer(FDestinationParent, FDestinationIndex + I);
    for I := 0 to High(FLayers) do
      InsertLayer(FSourceParent, FSourceIndices[I], FLayers[I]);
    FDocument.Changed;
  finally
    FDocument.EndUpdate;
  end;
  SelectLayers(FSourceParent, FSourceIndices);
end;

constructor TScreenLayoutDeleteGroupChildCommand.Create(
  ADocument: TVectArtDocument; AEditorState: TVectArtEditorState;
  AGroup: TScreenLayoutGroupLayer; Index: Integer);
begin
  inherited Create;
  FDocument := ADocument;
  FEditorState := AEditorState;
  FGroup := AGroup;
  FIndex := Index;
  FLayerInGroup := True;
end;

destructor TScreenLayoutDeleteGroupChildCommand.Destroy;
begin
  if not FLayerInGroup then
    FLayer.Free;
  inherited Destroy;
end;

procedure TScreenLayoutDeleteGroupChildCommand.Execute;
begin
  FLayer := FGroup.ExtractChild(FIndex);
  FLayerInGroup := False;
  FEditorState.OpenGroupChild := nil;
  FDocument.Changed;
end;

procedure TScreenLayoutDeleteGroupChildCommand.Undo;
begin
  FGroup.InsertChild(FIndex, FLayer);
  FLayerInGroup := True;
  FEditorState.OpenGroupChild := FLayer;
  FDocument.Changed;
end;

constructor TScreenLayoutDuplicateGroupChildCommand.Create(
  ADocument: TVectArtDocument; AEditorState: TVectArtEditorState;
  AGroup: TScreenLayoutGroupLayer; Index: Integer; Duplicate: TVectArtLayer);
begin
  inherited Create;
  FDocument := ADocument;
  FEditorState := AEditorState;
  FGroup := AGroup;
  FIndex := Index;
  FDuplicate := Duplicate;
  FSource := AEditorState.OpenGroupChild;
end;

destructor TScreenLayoutDuplicateGroupChildCommand.Destroy;
begin
  if not FDuplicateInGroup then
    FDuplicate.Free;
  inherited Destroy;
end;

procedure TScreenLayoutDuplicateGroupChildCommand.Execute;
begin
  FGroup.InsertChild(FIndex, FDuplicate);
  FDuplicateInGroup := True;
  FEditorState.OpenGroupChild := FDuplicate;
  FDocument.Changed;
end;

procedure TScreenLayoutDuplicateGroupChildCommand.Undo;
begin
  FGroup.ExtractChild(FIndex);
  FDuplicateInGroup := False;
  FEditorState.OpenGroupChild := FSource;
  FDocument.Changed;
end;

constructor TScreenLayoutMoveGroupChildCommand.Create(
  ADocument: TVectArtDocument; AGroup: TScreenLayoutGroupLayer;
  OldIndex, NewIndex: Integer);
begin
  inherited Create;
  FDocument := ADocument;
  FGroup := AGroup;
  FOldIndex := OldIndex;
  FNewIndex := NewIndex;
end;

procedure TScreenLayoutMoveGroupChildCommand.Execute;
begin
  Move(FOldIndex, FNewIndex);
end;

procedure TScreenLayoutMoveGroupChildCommand.Move(FromIndex, ToIndex: Integer);
var
  Layer: TVectArtLayer;
begin
  Layer := FGroup.ExtractChild(FromIndex);
  FGroup.InsertChild(ToIndex, Layer);
  FDocument.Changed;
end;

procedure TScreenLayoutMoveGroupChildCommand.Undo;
begin
  Move(FNewIndex, FOldIndex);
end;

constructor TScreenLayoutDeleteGroupChildrenCommand.Create(
  ADocument: TVectArtDocument; AEditorState: TVectArtEditorState;
  AGroup: TScreenLayoutGroupLayer; const Indices: TArray<Integer>);
begin
  inherited Create;
  FDocument := ADocument;
  FEditorState := AEditorState;
  FGroup := AGroup;
  FIndices := Copy(Indices);
  SetLength(FLayers, Length(Indices));
  FLayersInGroup := True;
end;

destructor TScreenLayoutDeleteGroupChildrenCommand.Destroy;
var
  Layer: TVectArtLayer;
begin
  if not FLayersInGroup then
    for Layer in FLayers do
      Layer.Free;
  inherited Destroy;
end;

procedure TScreenLayoutDeleteGroupChildrenCommand.Execute;
var
  I: Integer;
begin
  for I := High(FIndices) downto 0 do
    FLayers[I] := FGroup.ExtractChild(FIndices[I]);
  FLayersInGroup := False;
  FEditorState.SetOpenGroupChildren([]);
  FDocument.Changed;
end;

procedure TScreenLayoutDeleteGroupChildrenCommand.Undo;
var
  I: Integer;
begin
  for I := 0 to High(FIndices) do
    FGroup.InsertChild(FIndices[I], FLayers[I]);
  FLayersInGroup := True;
  FEditorState.SetOpenGroupChildren(FLayers);
  FDocument.Changed;
end;

constructor TScreenLayoutDuplicateGroupChildrenCommand.Create(
  ADocument: TVectArtDocument; AEditorState: TVectArtEditorState;
  AGroup: TScreenLayoutGroupLayer; const Indices: TArray<Integer>;
  const Sources, Duplicates: TArray<TVectArtLayer>);
begin
  inherited Create;
  FDocument := ADocument;
  FEditorState := AEditorState;
  FGroup := AGroup;
  FIndices := Copy(Indices);
  FSources := Copy(Sources);
  FDuplicates := Copy(Duplicates);
end;

destructor TScreenLayoutDuplicateGroupChildrenCommand.Destroy;
var
  Layer: TVectArtLayer;
begin
  if not FDuplicatesInGroup then
    for Layer in FDuplicates do
      Layer.Free;
  inherited Destroy;
end;

procedure TScreenLayoutDuplicateGroupChildrenCommand.Execute;
var
  I: Integer;
begin
  for I := 0 to High(FIndices) do
    FGroup.InsertChild(FIndices[I], FDuplicates[I]);
  FDuplicatesInGroup := True;
  FEditorState.SetOpenGroupChildren(FDuplicates);
  FDocument.Changed;
end;

procedure TScreenLayoutDuplicateGroupChildrenCommand.Undo;
var
  I: Integer;
begin
  for I := High(FIndices) downto 0 do
    FGroup.ExtractChild(FIndices[I]);
  FDuplicatesInGroup := False;
  FEditorState.SetOpenGroupChildren(FSources);
  FDocument.Changed;
end;

constructor TScreenLayoutReorderGroupChildrenCommand.Create(
  ADocument: TVectArtDocument; AGroup: TScreenLayoutGroupLayer;
  const BeforeOrder, AfterOrder: TArray<TVectArtLayer>);
begin
  inherited Create;
  FDocument := ADocument;
  FGroup := AGroup;
  FBeforeOrder := Copy(BeforeOrder);
  FAfterOrder := Copy(AfterOrder);
end;

procedure TScreenLayoutReorderGroupChildrenCommand.ApplyOrder(
  const Order: TArray<TVectArtLayer>);
var
  I: Integer;
begin
  for I := FGroup.ChildCount - 1 downto 0 do
    FGroup.ExtractChild(I);
  for I := 0 to High(Order) do
    FGroup.AddChild(Order[I]);
  FDocument.Changed;
end;

procedure TScreenLayoutReorderGroupChildrenCommand.Execute;
begin
  ApplyOrder(FAfterOrder);
end;

procedure TScreenLayoutReorderGroupChildrenCommand.Undo;
begin
  ApplyOrder(FBeforeOrder);
end;

constructor TScreenLayoutGroupChildrenCommand.Create(
  ADocument: TVectArtDocument; AEditorState: TVectArtEditorState;
  AParent: TScreenLayoutGroupLayer; const OriginalIndices: TArray<Integer>;
  const GroupName: string);
begin
  inherited Create;
  FDocument := ADocument;
  FEditorState := AEditorState;
  FParent := AParent;
  FOriginalIndices := Copy(OriginalIndices);
  FGroup := TScreenLayoutGroupLayer.Create(GroupName);
end;

destructor TScreenLayoutGroupChildrenCommand.Destroy;
begin
  if not FGroupInParent then
    FGroup.Free;
  inherited Destroy;
end;

procedure TScreenLayoutGroupChildrenCommand.Execute;
var
  I: Integer;
begin
  for I := High(FOriginalIndices) downto 0 do
    FGroup.InsertChild(0, FParent.ExtractChild(FOriginalIndices[I]));
  FGroupIndex := FOriginalIndices[0];
  FParent.InsertChild(FGroupIndex, FGroup);
  FGroupInParent := True;
  FEditorState.SetOpenGroupChildren([FGroup]);
  FDocument.Changed;
end;

procedure TScreenLayoutGroupChildrenCommand.Undo;
var
  I: Integer;
  Selection: TArray<TVectArtLayer>;
begin
  FParent.ExtractChild(FGroupIndex);
  FGroupInParent := False;
  SetLength(Selection, Length(FOriginalIndices));
  for I := 0 to High(FOriginalIndices) do
  begin
    Selection[I] := FGroup[0];
    FParent.InsertChild(FOriginalIndices[I], FGroup.ExtractChild(0));
  end;
  FEditorState.SetOpenGroupChildren(Selection);
  FDocument.Changed;
end;

constructor TScreenLayoutUngroupChildCommand.Create(
  ADocument: TVectArtDocument; AEditorState: TVectArtEditorState;
  AParent: TScreenLayoutGroupLayer; GroupIndex: Integer);
begin
  inherited Create;
  FDocument := ADocument;
  FEditorState := AEditorState;
  FParent := AParent;
  FGroupIndex := GroupIndex;
  FGroup := TScreenLayoutGroupLayer(AParent[GroupIndex]);
  FChildCount := FGroup.ChildCount;
  FGroupInParent := True;
end;

destructor TScreenLayoutUngroupChildCommand.Destroy;
begin
  if not FGroupInParent then
    FGroup.Free;
  inherited Destroy;
end;

procedure TScreenLayoutUngroupChildCommand.Execute;
var
  Child: TVectArtLayer;
  I: Integer;
  Selection: TArray<TVectArtLayer>;
begin
  FParent.ExtractChild(FGroupIndex);
  FGroupInParent := False;
  SetLength(Selection, FChildCount);
  for I := High(Selection) downto 0 do
  begin
    Child := FGroup.ExtractChild(FGroup.ChildCount - 1);
    FParent.InsertChild(FGroupIndex, Child);
    Selection[I] := Child;
  end;
  FEditorState.SetOpenGroupChildren(Selection);
  FDocument.Changed;
end;

procedure TScreenLayoutUngroupChildCommand.Undo;
var
  I: Integer;
begin
  for I := FGroupIndex + FChildCount - 1 downto FGroupIndex do
    FGroup.InsertChild(0, FParent.ExtractChild(I));
  FParent.InsertChild(FGroupIndex, FGroup);
  FGroupInParent := True;
  FEditorState.SetOpenGroupChildren([FGroup]);
  FDocument.Changed;
end;

end.
