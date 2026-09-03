// フィルタースタックの構造と値を、所有権を保ちながらUndo／Redoする。
unit ScreenLayoutFilterCommands;

interface

uses
  ScreenLayoutDocument, ScreenLayoutEditCommands, ScreenLayoutFilters;

type
  // 新規フィルターを挿入し、Undo中だけコマンド側で所有する。
  TScreenLayoutAddFilterCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FFilter: TScreenLayoutFilter;
    FInLayer: Boolean; // FFilterの所有者がFLayerならTrue。
    FIndex: Integer;
    FLayer: TVectArtLayer;
  public
    constructor Create(Document: TVectArtDocument; Layer: TVectArtLayer;
      Index: Integer; Filter: TScreenLayoutFilter);
    destructor Destroy; override;
    procedure Execute; override;
    procedure Undo; override;
  end;

  // 既存フィルターを取り外し、削除状態の間だけコマンド側で所有する。
  TScreenLayoutRemoveFilterCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FFilter: TScreenLayoutFilter;
    FInLayer: Boolean; // FFilterの所有者がFLayerならTrue。
    FIndex: Integer;
    FLayer: TVectArtLayer;
  public
    constructor Create(Document: TVectArtDocument; Layer: TVectArtLayer;
      Index: Integer);
    destructor Destroy; override;
    procedure Execute; override;
    procedure Undo; override;
  end;

  // 同一レイヤー内の順序だけを変更し、フィルター本体は移動しない。
  TScreenLayoutMoveFilterCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FFromIndex: Integer;
    FLayer: TVectArtLayer;
    FToIndex: Integer;
  public
    constructor Create(Document: TVectArtDocument; Layer: TVectArtLayer;
      FromIndex, ToIndex: Integer);
    procedure Execute; override;
    procedure Undo; override;
  end;

  // 既存フィルターの有効状態を履歴化する。
  TScreenLayoutSetFilterEnabledCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FFilter: TScreenLayoutFilter;
    FNewValue: Boolean;
    FOldValue: Boolean;
    procedure Apply(Value: Boolean);
  public
    constructor Create(Document: TVectArtDocument;
      Filter: TScreenLayoutFilter; OldValue, NewValue: Boolean);
    procedure Execute; override;
    procedure Undo; override;
  end;

  // 同じフィルターへスナップショットを適用し、ドラッグ全体を1履歴にする。
  TScreenLayoutSetFilterParametersCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FFilter: TScreenLayoutFilter;
    FNewValue: TScreenLayoutFilter;
    FOldValue: TScreenLayoutFilter;
    procedure Apply(Source: TScreenLayoutFilter);
  public
    constructor Create(Document: TVectArtDocument;
      Filter, OldValue, NewValue: TScreenLayoutFilter);
    destructor Destroy; override;
    procedure Execute; override;
    procedure Undo; override;
  end;

implementation

uses
  System.SysUtils;

{ TScreenLayoutAddFilterCommand }

constructor TScreenLayoutAddFilterCommand.Create(Document: TVectArtDocument;
  Layer: TVectArtLayer; Index: Integer; Filter: TScreenLayoutFilter);
begin
  inherited Create;
  if Layer = nil then
    raise EArgumentNilException.Create('Layer');
  if Filter = nil then
    raise EArgumentNilException.Create('Filter');
  FDocument := Document;
  FLayer := Layer;
  FIndex := Index;
  FFilter := Filter;
  FInLayer := False;
end;

destructor TScreenLayoutAddFilterCommand.Destroy;
begin
  if not FInLayer then
    FFilter.Free;
  inherited Destroy;
end;

procedure TScreenLayoutAddFilterCommand.Execute;
begin
  if FInLayer then
    Exit;
  FLayer.InsertFilter(FIndex, FFilter);
  FInLayer := True;
  if FDocument <> nil then
    FDocument.Changed;
end;

procedure TScreenLayoutAddFilterCommand.Undo;
begin
  if not FInLayer then
    Exit;
  FFilter := FLayer.ExtractFilter(FIndex);
  FInLayer := False;
  if FDocument <> nil then
    FDocument.Changed;
end;

{ TScreenLayoutRemoveFilterCommand }

constructor TScreenLayoutRemoveFilterCommand.Create(
  Document: TVectArtDocument; Layer: TVectArtLayer; Index: Integer);
begin
  inherited Create;
  if Layer = nil then
    raise EArgumentNilException.Create('Layer');
  if (Index < 0) or (Index >= Layer.FilterCount) then
    raise EArgumentOutOfRangeException.Create('Index');
  FDocument := Document;
  FLayer := Layer;
  FIndex := Index;
  FFilter := nil;
  FInLayer := True;
end;

destructor TScreenLayoutRemoveFilterCommand.Destroy;
begin
  if not FInLayer then
    FFilter.Free;
  inherited Destroy;
end;

procedure TScreenLayoutRemoveFilterCommand.Execute;
begin
  if not FInLayer then
    Exit;
  FFilter := FLayer.ExtractFilter(FIndex);
  FInLayer := False;
  if FDocument <> nil then
    FDocument.Changed;
end;

procedure TScreenLayoutRemoveFilterCommand.Undo;
begin
  if FInLayer then
    Exit;
  FLayer.InsertFilter(FIndex, FFilter);
  FInLayer := True;
  if FDocument <> nil then
    FDocument.Changed;
end;

{ TScreenLayoutMoveFilterCommand }

constructor TScreenLayoutMoveFilterCommand.Create(Document: TVectArtDocument;
  Layer: TVectArtLayer; FromIndex, ToIndex: Integer);
begin
  inherited Create;
  if Layer = nil then
    raise EArgumentNilException.Create('Layer');
  FDocument := Document;
  FLayer := Layer;
  FFromIndex := FromIndex;
  FToIndex := ToIndex;
end;

procedure TScreenLayoutMoveFilterCommand.Execute;
begin
  FLayer.MoveFilter(FFromIndex, FToIndex);
  if FDocument <> nil then
    FDocument.Changed;
end;

procedure TScreenLayoutMoveFilterCommand.Undo;
begin
  FLayer.MoveFilter(FToIndex, FFromIndex);
  if FDocument <> nil then
    FDocument.Changed;
end;

{ TScreenLayoutSetFilterEnabledCommand }

procedure TScreenLayoutSetFilterEnabledCommand.Apply(Value: Boolean);
begin
  if FFilter.Enabled = Value then
    Exit;
  FFilter.Enabled := Value;
  if FDocument <> nil then
    FDocument.Changed;
end;

constructor TScreenLayoutSetFilterEnabledCommand.Create(
  Document: TVectArtDocument; Filter: TScreenLayoutFilter; OldValue,
  NewValue: Boolean);
begin
  inherited Create;
  if Filter = nil then
    raise EArgumentNilException.Create('Filter');
  FDocument := Document;
  FFilter := Filter;
  FOldValue := OldValue;
  FNewValue := NewValue;
end;

procedure TScreenLayoutSetFilterEnabledCommand.Execute;
begin
  Apply(FNewValue);
end;

procedure TScreenLayoutSetFilterEnabledCommand.Undo;
begin
  Apply(FOldValue);
end;

{ TScreenLayoutSetFilterParametersCommand }

procedure TScreenLayoutSetFilterParametersCommand.Apply(
  Source: TScreenLayoutFilter);
begin
  AssignScreenLayoutFilter(FFilter, Source);
  if FDocument <> nil then
    FDocument.Changed;
end;

constructor TScreenLayoutSetFilterParametersCommand.Create(
  Document: TVectArtDocument; Filter, OldValue,
  NewValue: TScreenLayoutFilter);
begin
  inherited Create;
  if (Filter = nil) or (OldValue = nil) or (NewValue = nil) then
    raise EArgumentNilException.Create('Filter');
  if (Filter.Kind <> OldValue.Kind) or (Filter.Kind <> NewValue.Kind) then
    raise EArgumentException.Create('Filter kinds do not match');
  FDocument := Document;
  FFilter := Filter;
  FOldValue := OldValue.Clone;
  FNewValue := NewValue.Clone;
end;

destructor TScreenLayoutSetFilterParametersCommand.Destroy;
begin
  FNewValue.Free;
  FOldValue.Free;
  inherited Destroy;
end;

procedure TScreenLayoutSetFilterParametersCommand.Execute;
begin
  Apply(FNewValue);
end;

procedure TScreenLayoutSetFilterParametersCommand.Undo;
begin
  Apply(FOldValue);
end;

end.
