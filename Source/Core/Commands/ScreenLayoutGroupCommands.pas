// レイヤーのグループ化と解除を、所有権を保ったままUndo／Redo可能にする。
unit ScreenLayoutGroupCommands;

interface

uses
  ScreenLayoutDocument, ScreenLayoutEditCommands, ScreenLayoutEditHistory;

type
  TScreenLayoutTranslateGroupsCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FDX: Single;
    FDY: Single;
    FLayerIndices: TArray<Integer>;
    procedure Translate(DX, DY: Single);
  public
    constructor Create(ADocument: TVectArtDocument;
      const LayerIndices: TArray<Integer>; DX, DY: Single);
    procedure Execute; override;
    procedure Undo; override;
  end;

function CanGroupSelectedLayers(Document: TVectArtDocument): Boolean;
function CanUngroupSelectedLayer(Document: TVectArtDocument): Boolean;
procedure GroupSelectedLayers(Document: TVectArtDocument;
  EditHistory: TVectArtEditHistory);
procedure UngroupSelectedLayer(Document: TVectArtDocument;
  EditHistory: TVectArtEditHistory);

implementation

uses
  System.Generics.Collections, System.SysUtils, ScreenLayoutLayerGeometry;

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
    if Document[Indices[I]].Locked or
      (Document[Indices[I]] is TScreenLayoutGroupLayer) then
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

{ TScreenLayoutTranslateGroupsCommand }

constructor TScreenLayoutTranslateGroupsCommand.Create(
  ADocument: TVectArtDocument; const LayerIndices: TArray<Integer>;
  DX, DY: Single);
begin
  inherited Create;
  FDocument := ADocument;
  FLayerIndices := Copy(LayerIndices);
  FDX := DX;
  FDY := DY;
end;

procedure TScreenLayoutTranslateGroupsCommand.Execute;
begin
  Translate(FDX, FDY);
end;

procedure TScreenLayoutTranslateGroupsCommand.Translate(DX, DY: Single);
var
  I: Integer;
begin
  FDocument.BeginUpdate;
  try
    for I := 0 to High(FLayerIndices) do
      if (FLayerIndices[I] > 0) and
        (FLayerIndices[I] < FDocument.LayerCount) and
        (FDocument[FLayerIndices[I]] is TScreenLayoutGroupLayer) then
        TranslateScreenLayoutLayer(FDocument[FLayerIndices[I]], DX, DY);
    FDocument.Changed;
  finally
    FDocument.EndUpdate;
  end;
end;

procedure TScreenLayoutTranslateGroupsCommand.Undo;
begin
  Translate(-FDX, -FDY);
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
