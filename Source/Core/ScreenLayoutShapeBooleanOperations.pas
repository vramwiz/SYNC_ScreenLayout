// 選択Shapeの論理演算を組み立て、結果レイヤーへの置換と履歴登録を調整する。
unit ScreenLayoutShapeBooleanOperations;

interface

uses
  ScreenLayoutDocument, ScreenLayoutEditHistory;

type
  // ツールバーから選択する4種類のShape領域演算。
  TScreenLayoutShapeBooleanOperation = (slsboUnion, slsboSubtract,
    slsboIntersect, slsboXor);

// 未ロックのShapeが2個以上選択されている場合にTrueを返す。
function CanExecuteScreenLayoutShapeBoolean(
  Document: TVectArtDocument): Boolean;
// 減算はアクティブShape、それ以外は最背面Shapeを基準に選択Shapeを結果へ置換する。
// Skiaの演算に失敗した場合だけFalseを返し、空の演算結果は成功として全対象を除去する。
function ExecuteScreenLayoutShapeBoolean(Document: TVectArtDocument;
  EditHistory: TVectArtEditHistory;
  Operation: TScreenLayoutShapeBooleanOperation): Boolean;

implementation

uses
  System.Skia,
  ScreenLayoutShapeBooleanCommands, ScreenLayoutShapeBooleanGeometry,
  ScreenLayoutShapePath;

procedure SortIndicesAscending(var Values: TArray<Integer>);
var
  I: Integer;
  J: Integer;
  Temporary: Integer;
begin
  for I := 0 to High(Values) - 1 do
    for J := I + 1 to High(Values) do
      if Values[J] < Values[I] then
      begin
        Temporary := Values[I];
        Values[I] := Values[J];
        Values[J] := Temporary;
      end;
end;

function ShapeLayerData(ShapeLayer: TScreenLayoutShapeLayer):
  TScreenLayoutShapeData;
begin
  // 論理演算後も基準Shapeの見た目とレイヤー属性を引き継ぐ。
  Result.Contours := ShapeLayer.Contours;
  Result.FillColor := ShapeLayer.FillColor;
  Result.FillRule := ShapeLayer.FillRule;
  Result.Locked := ShapeLayer.Locked;
  Result.MifAntiAlias := ShapeLayer.MifAntiAlias;
  Result.Name := ShapeLayer.Name;
  Result.Opacity := ShapeLayer.Opacity;
  Result.StrokeColor := ShapeLayer.StrokeColor;
  Result.StrokeJoin := ShapeLayer.StrokeJoin;
  Result.StrokeStyle := ShapeLayer.StrokeStyle;
  Result.StrokeWidth := ShapeLayer.StrokeWidth;
  Result.Visible := ShapeLayer.Visible;
end;

function CanExecuteScreenLayoutShapeBoolean(
  Document: TVectArtDocument): Boolean;
var
  Index: Integer;
  SelectedIndices: TArray<Integer>;
begin
  Result := False;
  if (Document = nil) or (Document.SelectionCount < 2) then
    Exit;
  SelectedIndices := Document.GetSelectedLayerIndices;
  for Index in SelectedIndices do
    if (Index <= 0) or (Index >= Document.LayerCount) or
      not (Document[Index] is TScreenLayoutShapeLayer) or
      Document[Index].Locked then
      Exit;
  Result := True;
end;

function ExecuteScreenLayoutShapeBoolean(Document: TVectArtDocument;
  EditHistory: TVectArtEditHistory;
  Operation: TScreenLayoutShapeBooleanOperation): Boolean;
var
  BaseIndex: Integer;
  Command: TScreenLayoutShapeBooleanCommand;
  I: Integer;
  OperandPath: ISkPath;
  OriginalSelection: TArray<Integer>;
  ResultData: TScreenLayoutShapeData;
  ResultPath: ISkPath;
  SelectedIndices: TArray<Integer>;
  ShapeLayer: TScreenLayoutShapeLayer;
begin
  Result := False;
  if not CanExecuteScreenLayoutShapeBoolean(Document) then
    Exit;
  OriginalSelection := Document.GetSelectedLayerIndices;
  SelectedIndices := Copy(OriginalSelection);
  SortIndicesAscending(SelectedIndices);
  if Operation = slsboSubtract then
    BaseIndex := Document.SelectedIndex
  else
    BaseIndex := SelectedIndices[0];
  ShapeLayer := TScreenLayoutShapeLayer(Document[BaseIndex]);
  ResultData := ShapeLayerData(ShapeLayer);
  ResultPath := BuildScreenLayoutShapePath(ShapeLayer);
  for I := 0 to High(SelectedIndices) do
  begin
    if SelectedIndices[I] = BaseIndex then
      Continue;
    ShapeLayer := TScreenLayoutShapeLayer(Document[SelectedIndices[I]]);
    OperandPath := BuildScreenLayoutShapePath(ShapeLayer);
    case Operation of
      slsboUnion:
        ResultPath := ResultPath.Op(OperandPath, TSkPathOp.Union);
      slsboSubtract:
        ResultPath := ResultPath.Op(OperandPath, TSkPathOp.Difference);
      slsboIntersect:
        ResultPath := ResultPath.Op(OperandPath, TSkPathOp.Intersect);
      slsboXor:
        ResultPath := ResultPath.Op(OperandPath, TSkPathOp.&Xor);
    end;
    if ResultPath = nil then
      Exit;
  end;
  ResultData.Contours := ConvertSkPathToScreenLayoutShapeContours(ResultPath);
  // 演算結果は交差しない境界群なので、輪郭方向に依存しないEven-Oddで保持する。
  ResultData.FillRule := slfrEvenOdd;
  Command := TScreenLayoutShapeBooleanCommand.Create(Document,
    SelectedIndices, OriginalSelection, BaseIndex, ResultData,
    Length(ResultData.Contours) > 0);
  Command.Execute;
  if EditHistory <> nil then
    EditHistory.AddApplied(Command)
  else
    Command.Free;
  Result := True;
end;

end.
