// Shape論理演算による複数レイヤーから結果レイヤーへの置換をUndo／Redo可能にする。
unit ScreenLayoutShapeBooleanCommands;

interface

uses
  ScreenLayoutDocument, ScreenLayoutEditCommands;

type
  TScreenLayoutShapeBooleanOriginalKind = (slsbokRectangle,
    slsbokRoundedRectangle, slsbokShape);

  TScreenLayoutShapeBooleanOriginal = record
    Kind: TScreenLayoutShapeBooleanOriginalKind;             // Undoで復元するレイヤー型。
    RectangleData: TVectArtRectangleData;                    // 四角だった場合の全属性。
    RoundedRectangleData: TScreenLayoutRoundedRectangleData; // 角丸四角だった場合の全属性。
    ShapeData: TScreenLayoutShapeData;                        // Shapeだった場合の全属性と輪郭群。
  end;

  TScreenLayoutShapeBooleanCommand = class(TVectArtEditCommand)
  private
    FAfterSelection: TArray<Integer>;              // 結果レイヤーだけを選択した状態。
    FBeforeSelection: TArray<Integer>;             // 操作前の順序を含む選択状態。
    FDocument: TVectArtDocument;
    FOriginalData: TArray<TScreenLayoutShapeBooleanOriginal>; // Undoで元型を復元するデータ。
    FOriginalIndices: TArray<Integer>;             // 操作前の積層位置を昇順で保持する。
    FResultData: TScreenLayoutShapeData;
    FResultExists: Boolean;                        // 空演算では結果レイヤーを生成しない。
    FResultIndex: Integer;                         // 対象除去後の結果挿入位置。
    procedure CaptureOriginal(Index: Integer;
      out Original: TScreenLayoutShapeBooleanOriginal);
    procedure RemoveOriginals;
  public
    // 選択したShape／四角群と結果を独立して保持し、置換全体を1つの履歴項目にする。
    constructor Create(ADocument: TVectArtDocument;
      const SelectedIndices, BeforeSelection: TArray<Integer>;
      ResultOriginalIndex: Integer; const ResultData: TScreenLayoutShapeData;
      ResultExists: Boolean);
    // 元レイヤー群を結果Shapeへ置換し、空結果の場合は元レイヤー群の除去だけを行う。
    procedure Execute; override;
    // 結果Shapeを除去して元レイヤー群の型、積層位置、選択状態を復元する。
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

procedure TScreenLayoutShapeBooleanCommand.CaptureOriginal(Index: Integer;
  out Original: TScreenLayoutShapeBooleanOriginal);
var
  RectangleLayer: TVectArtRectangleLayer;
  RoundedLayer: TScreenLayoutRoundedRectangleLayer;
  ShapeLayer: TScreenLayoutShapeLayer;
begin
  Original := Default(TScreenLayoutShapeBooleanOriginal);
  if FDocument[Index] is TScreenLayoutRoundedRectangleLayer then
  begin
    Original.Kind := slsbokRoundedRectangle;
    RoundedLayer := TScreenLayoutRoundedRectangleLayer(FDocument[Index]);
    Original.RoundedRectangleData.Bounds := RoundedLayer.Bounds;
    Original.RoundedRectangleData.CornerRadii := RoundedLayer.CornerRadii;
    Original.RoundedRectangleData.FillColor := RoundedLayer.FillColor;
    Original.RoundedRectangleData.Locked := RoundedLayer.Locked;
    Original.RoundedRectangleData.Name := RoundedLayer.Name;
    Original.RoundedRectangleData.Opacity := RoundedLayer.Opacity;
    Original.RoundedRectangleData.RotationDegrees :=
      RoundedLayer.RotationDegrees;
    Original.RoundedRectangleData.Visible := RoundedLayer.Visible;
    Exit;
  end;
  if FDocument[Index] is TVectArtRectangleLayer then
  begin
    Original.Kind := slsbokRectangle;
    RectangleLayer := TVectArtRectangleLayer(FDocument[Index]);
    Original.RectangleData.Bounds := RectangleLayer.Bounds;
    Original.RectangleData.FillColor := RectangleLayer.FillColor;
    Original.RectangleData.Locked := RectangleLayer.Locked;
    Original.RectangleData.Name := RectangleLayer.Name;
    Original.RectangleData.Opacity := RectangleLayer.Opacity;
    Original.RectangleData.RotationDegrees :=
      RectangleLayer.RotationDegrees;
    Original.RectangleData.Visible := RectangleLayer.Visible;
    Exit;
  end;
  Original.Kind := slsbokShape;
  ShapeLayer := TScreenLayoutShapeLayer(FDocument[Index]);
  Original.ShapeData.Contours := ShapeLayer.Contours;
  Original.ShapeData.FillColor := ShapeLayer.FillColor;
  Original.ShapeData.FillRule := ShapeLayer.FillRule;
  Original.ShapeData.Locked := ShapeLayer.Locked;
  Original.ShapeData.Name := ShapeLayer.Name;
  Original.ShapeData.Opacity := ShapeLayer.Opacity;
  Original.ShapeData.StrokeColor := ShapeLayer.StrokeColor;
  Original.ShapeData.StrokeStyle := ShapeLayer.StrokeStyle;
  Original.ShapeData.StrokeWidth := ShapeLayer.StrokeWidth;
  Original.ShapeData.Visible := ShapeLayer.Visible;
  Original.ShapeData.Contours := CloneScreenLayoutShapeContours(
    Original.ShapeData.Contours);
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
  begin
    CaptureOriginal(SelectedIndices[I], FOriginalData[I]);
    if SelectedIndices[I] < ResultOriginalIndex then
      Dec(FResultIndex);
  end;
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
  RectangleData: TVectArtRectangleData;
  RemovedData: TScreenLayoutShapeData;
  RoundedRectangleData: TScreenLayoutRoundedRectangleData;
begin
  // 後方から除去すれば、まだ除去していない元のレイヤー番号がずれない。
  for I := High(FOriginalIndices) downto 0 do
    case FOriginalData[I].Kind of
      slsbokRectangle:
        FDocument.RemoveRectangle(FOriginalIndices[I], RectangleData);
      slsbokRoundedRectangle:
        FDocument.RemoveRoundedRectangle(FOriginalIndices[I],
          RoundedRectangleData);
      slsbokShape:
        FDocument.RemoveShape(FOriginalIndices[I], RemovedData);
    end;
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
      case FOriginalData[I].Kind of
        slsbokRectangle:
          FOriginalIndices[I] := FDocument.InsertRectangle(
            FOriginalIndices[I], FOriginalData[I].RectangleData);
        slsbokRoundedRectangle:
          FOriginalIndices[I] := FDocument.InsertRoundedRectangle(
            FOriginalIndices[I], FOriginalData[I].RoundedRectangleData);
        slsbokShape:
          FOriginalIndices[I] := FDocument.InsertShape(
            FOriginalIndices[I], FOriginalData[I].ShapeData);
      end;
    FDocument.SetSelectedLayers(FBeforeSelection);
  finally
    FDocument.EndUpdate;
  end;
end;

end.
