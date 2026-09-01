// Shape論理演算による複数レイヤーから結果レイヤーへの置換をUndo／Redo可能にする。
unit ScreenLayoutShapeBooleanCommands;

interface

uses
  ScreenLayoutDocument, ScreenLayoutEditCommands;

type
  TScreenLayoutShapeBooleanCommand = class(TVectArtEditCommand)
  private
    FAfterSelection: TArray<Integer>;              // 結果レイヤーだけを選択した状態。
    FBeforeSelection: TArray<Integer>;             // 操作前の順序を含む選択状態。
    FDocument: TVectArtDocument;
    FOriginalData: TArray<TScreenLayoutShapeData>; // Undoで戻す各Shapeの独立データ。
    FOriginalIndices: TArray<Integer>;             // 操作前の積層位置を昇順で保持する。
    FOriginalsCaptured: Boolean;
    FResultData: TScreenLayoutShapeData;
    FResultExists: Boolean;                        // 空演算では結果レイヤーを生成しない。
    FResultIndex: Integer;                         // 対象除去後の結果挿入位置。
    procedure RemoveOriginals;
  public
    // 選択Shape群と結果を独立して保持し、置換全体を1つの履歴項目にする。
    constructor Create(ADocument: TVectArtDocument;
      const SelectedIndices, BeforeSelection: TArray<Integer>;
      ResultOriginalIndex: Integer; const ResultData: TScreenLayoutShapeData;
      ResultExists: Boolean);
    // 元Shape群を結果Shapeへ置換し、空結果の場合は元Shape群の除去だけを行う。
    procedure Execute; override;
    // 結果Shapeを除去して元Shape群の積層位置と選択状態を復元する。
    procedure Undo; override;
  end;

implementation

uses
  ScreenLayoutShapeOperations;

procedure CopyShapeData(const Source: TScreenLayoutShapeData;
  out Target: TScreenLayoutShapeData);
begin
  Target := Source;
  Target.Contours := CloneScreenLayoutShapeContours(Source.Contours);
end;

constructor TScreenLayoutShapeBooleanCommand.Create(
  ADocument: TVectArtDocument; const SelectedIndices,
  BeforeSelection: TArray<Integer>; ResultOriginalIndex: Integer;
  const ResultData: TScreenLayoutShapeData; ResultExists: Boolean);
var
  I: Integer;
begin
  inherited Create;
  FDocument := ADocument;
  FBeforeSelection := Copy(BeforeSelection);
  FOriginalIndices := Copy(SelectedIndices);
  SetLength(FOriginalData, Length(SelectedIndices));
  FResultIndex := ResultOriginalIndex;
  for I := 0 to High(SelectedIndices) do
    if SelectedIndices[I] < ResultOriginalIndex then
      Dec(FResultIndex);
  CopyShapeData(ResultData, FResultData);
  FResultExists := ResultExists;
  if FResultExists then
    FAfterSelection := TArray<Integer>.Create(FResultIndex)
  else
    FAfterSelection := nil;
end;

procedure TScreenLayoutShapeBooleanCommand.Execute;
begin
  if FDocument = nil then
    Exit;
  FDocument.BeginUpdate;
  try
    RemoveOriginals;
    if FResultExists then
      FResultIndex := FDocument.InsertShape(FResultIndex, FResultData);
    FDocument.SetSelectedLayers(FAfterSelection);
  finally
    FDocument.EndUpdate;
  end;
end;

procedure TScreenLayoutShapeBooleanCommand.RemoveOriginals;
var
  I: Integer;
  RemovedData: TScreenLayoutShapeData;
begin
  // 後方から除去すれば、まだ除去していない元のレイヤー番号がずれない。
  for I := High(FOriginalIndices) downto 0 do
    if FDocument.RemoveShape(FOriginalIndices[I], RemovedData) and
      not FOriginalsCaptured then
      CopyShapeData(RemovedData, FOriginalData[I]);
  FOriginalsCaptured := True;
end;

procedure TScreenLayoutShapeBooleanCommand.Undo;
var
  I: Integer;
  RemovedData: TScreenLayoutShapeData;
begin
  if FDocument = nil then
    Exit;
  FDocument.BeginUpdate;
  try
    if FResultExists then
      FDocument.RemoveShape(FResultIndex, RemovedData);
    // 前方から元位置へ挿入すると、後続レイヤーも操作前の番号へ自然に戻る。
    for I := 0 to High(FOriginalIndices) do
      FOriginalIndices[I] := FDocument.InsertShape(FOriginalIndices[I],
        FOriginalData[I]);
    FDocument.SetSelectedLayers(FBeforeSelection);
  finally
    FDocument.EndUpdate;
  end;
end;

end.
