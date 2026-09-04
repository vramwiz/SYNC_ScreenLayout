// 文字パスを文字単位の配置セルへ展開し、描画と選択で共有する幾何情報を生成する。
unit ScreenLayoutTextPathGeometry;

interface

uses
  System.Skia, System.Types, ScreenLayoutDocument;

type
  TScreenLayoutTextPathQuad = array[0..3] of TPointF;

  TScreenLayoutTextPathPlacement = record
    CharacterIndex: Integer;                // 文字単位配列内の0基準位置。
    TextIndex: Integer;                     // 元文字列内のUTF-16開始位置。
    TextUnit: string;                       // サロゲートペアを分割しない描画単位。
    PathDistance: Single;                   // Path始点から文字セル下辺中央までの距離。
    Anchor: TPointF;                        // Path上に置く文字セル下辺中央。
    Tangent: TPointF;                       // Anchor位置でのPath進行方向の単位ベクトル。
    AngleDegrees: Single;                   // 文字描画へ適用する接線角度。
    AdvanceWidth: Single;                   // フォントが返した文字セルの送り幅。
    Scale: Single;                          // この文字セルへ適用した個別の均等倍率。
    CellHeight: Single;                     // ascentからdescentまでの文字セル高。
    BaselineOffset: Single;                 // セル下辺からベースラインまでの上向き距離。
    CollisionAdjusted: Boolean;             // 直前文字との重なりを自動間隔で解消した場合にTrue。
    CollidesWithPrevious: Boolean;          // 手動位置またはPath端により重なりが残る場合にTrue。
    Corners: TScreenLayoutTextPathQuad;     // 左上から時計回りの文書座標四隅。
  end;

// 文字セルの下辺中央をPath上へ置き、Pathに収まる文字の配置結果を返す。
function BuildScreenLayoutTextPathPlacements(
  Layer: TScreenLayoutTextPathLayer; const Font: ISkFont = nil):
  TArray<TScreenLayoutTextPathPlacement>;
// 配置済み文字セル全体の文書座標外接範囲を返す。
function TryGetScreenLayoutTextPathBounds(Layer: TScreenLayoutTextPathLayer;
  out Bounds: TRectF): Boolean;
// 配置済みのいずれかの文字セルに文書座標点が含まれるかを返す。
function PointInScreenLayoutTextPath(Layer: TScreenLayoutTextPathLayer;
  const Point: TPointF): Boolean;

implementation

uses
  System.Math, ScreenLayoutGeometry, ScreenLayoutPathOperations,
  ScreenLayoutTextGeometry;

function TextPathQuadsOverlap(const Left,
  Right: TScreenLayoutTextPathQuad): Boolean;
const
  MINIMUM_OVERLAP = 0.01;
var
  AxisX: Single;
  AxisY: Single;
  EdgeIndex: Integer;
  I: Integer;
  LeftMaximum: Single;
  LeftMinimum: Single;
  Projection: Single;
  QuadIndex: Integer;
  RightMaximum: Single;
  RightMinimum: Single;
begin
  for QuadIndex := 0 to 1 do
    for EdgeIndex := 0 to 3 do
    begin
      if QuadIndex = 0 then
      begin
        AxisX := -(Left[(EdgeIndex + 1) mod 4].Y - Left[EdgeIndex].Y);
        AxisY := Left[(EdgeIndex + 1) mod 4].X - Left[EdgeIndex].X;
      end
      else
      begin
        AxisX := -(Right[(EdgeIndex + 1) mod 4].Y - Right[EdgeIndex].Y);
        AxisY := Right[(EdgeIndex + 1) mod 4].X - Right[EdgeIndex].X;
      end;
      LeftMinimum := MaxSingle;
      LeftMaximum := -MaxSingle;
      RightMinimum := MaxSingle;
      RightMaximum := -MaxSingle;
      for I := 0 to 3 do
      begin
        Projection := Left[I].X * AxisX + Left[I].Y * AxisY;
        LeftMinimum := Min(LeftMinimum, Projection);
        LeftMaximum := Max(LeftMaximum, Projection);
        Projection := Right[I].X * AxisX + Right[I].Y * AxisY;
        RightMinimum := Min(RightMinimum, Projection);
        RightMaximum := Max(RightMaximum, Projection);
      end;
      if Min(LeftMaximum, RightMaximum) -
        Max(LeftMinimum, RightMinimum) <= MINIMUM_OVERLAP then
        Exit(False);
    end;
  Result := True;
end;

function BuildScreenLayoutTextPathPlacements(
  Layer: TScreenLayoutTextPathLayer; const Font: ISkFont):
  TArray<TScreenLayoutTextPathPlacement>;
var
  ActiveFont: ISkFont;
  AngleDegrees: Single;
  CellHeight: Single;
  CharacterIndex: Integer;
  CharacterPathOffsets: TArray<Single>;
  CharacterPositionManual: TArray<Boolean>;
  CharacterScales: TArray<Single>;
  CollisionHigh: Single;
  CollisionLow: Single;
  CollisionStep: Single;
  CollisionTest: Single;
  CollisionTrial: Integer;
  CursorDistance: Single;
  FontMetrics: TSkFontMetrics;
  I: Integer;
  LocalYAxis: TPointF;
  NaturalCursorDistance: Single;
  PathLength: Single;
  PathPoint: TPointF;
  PathPoints: TArray<TPointF>;
  Placement: TScreenLayoutTextPathPlacement;
  PlacementCursorDistance: Single;
  PreviousManual: Boolean;
  Tangent: TPointF;
  UnitLength: Integer;
  UnitManual: Boolean;
  UnitPathDistance: Single;
  UnitPathOffset: Single;
  UnitScale: Single;
  UnitText: string;
  UnitWidth: Single;

  function TransformCellPoint(LocalX, LocalY: Single): TPointF;
  begin
    Result := TPointF.Create(PathPoint.X + Tangent.X * LocalX +
      LocalYAxis.X * LocalY, PathPoint.Y + Tangent.Y * LocalX +
      LocalYAxis.Y * LocalY);
  end;

  procedure UpdatePlacementAtDistance(Distance: Single);
  begin
    ScreenLayoutPolylinePointAtDistance(PathPoints, Distance,
      PathPoint, Tangent);
    AngleDegrees := RadToDeg(ArcTan2(Tangent.Y, Tangent.X));
    LocalYAxis := TPointF.Create(-Tangent.Y, Tangent.X);
    Placement.PathDistance := Distance;
    Placement.Anchor := PathPoint;
    Placement.Tangent := Tangent;
    Placement.AngleDegrees := AngleDegrees;
    Placement.Corners[0] := TransformCellPoint(-UnitWidth * 0.5,
      -Placement.CellHeight);
    Placement.Corners[1] := TransformCellPoint(UnitWidth * 0.5,
      -Placement.CellHeight);
    Placement.Corners[2] := TransformCellPoint(UnitWidth * 0.5, 0);
    Placement.Corners[3] := TransformCellPoint(-UnitWidth * 0.5, 0);
  end;

begin
  Result := nil;
  if (Layer = nil) or (Layer.Text = '') then
    Exit;
  ActiveFont := Font;
  if ActiveFont = nil then
    ActiveFont := CreateScreenLayoutTextFont(Layer.FontFamily,
      Layer.FontSize, Layer.FontStyle);
  if ActiveFont = nil then
    Exit;
  PathPoints := FlattenScreenLayoutPathVertices(
    Layer.EditablePathVertices, 32);
  PathLength := ScreenLayoutPolylineLength(PathPoints);
  if PathLength <= 0 then
    Exit;
  ActiveFont.GetMetrics(FontMetrics);
  CellHeight := Max(FontMetrics.Descent - FontMetrics.Ascent, 1.0);
  CharacterPathOffsets := Layer.CharacterPathOffsets;
  CharacterPositionManual := Layer.CharacterPositionManual;
  CharacterScales := Layer.CharacterScales;
  CursorDistance := 0;
  NaturalCursorDistance := 0;
  CharacterIndex := 0;
  PreviousManual := False;
  I := 1;
  while I <= Length(Layer.Text) do
  begin
    UnitLength := ScreenLayoutTextUnitLengthAt(Layer.Text, I);
    UnitText := Copy(Layer.Text, I, UnitLength);
    if CharacterIndex < Length(CharacterScales) then
      UnitScale := CharacterScales[CharacterIndex]
    else
      UnitScale := 1.0;
    if CharacterIndex < Length(CharacterPathOffsets) then
      UnitPathOffset := CharacterPathOffsets[CharacterIndex]
    else
      UnitPathOffset := 0;
    UnitManual := (CharacterIndex < Length(CharacterPositionManual)) and
      CharacterPositionManual[CharacterIndex];
    UnitWidth := ActiveFont.MeasureText(UnitText) * UnitScale;
    if UnitWidth <= 0 then
    begin
      Inc(I, UnitLength);
      Inc(CharacterIndex);
      Continue;
    end;
    if UnitManual then
      PlacementCursorDistance := NaturalCursorDistance
    else
      PlacementCursorDistance := CursorDistance;
    if PlacementCursorDistance + UnitWidth > PathLength then
      Break;
    UnitPathDistance := EnsureRange(
      PlacementCursorDistance + UnitWidth * 0.5 + UnitPathOffset,
      UnitWidth * 0.5, PathLength - UnitWidth * 0.5);
    Placement := Default(TScreenLayoutTextPathPlacement);
    Placement.CharacterIndex := CharacterIndex;
    Placement.TextIndex := I;
    Placement.TextUnit := UnitText;
    Placement.AdvanceWidth := UnitWidth;
    Placement.Scale := UnitScale;
    Placement.CellHeight := CellHeight * UnitScale;
    Placement.BaselineOffset := FontMetrics.Descent * UnitScale;
    UpdatePlacementAtDistance(UnitPathDistance);
    if Length(Result) > 0 then
    begin
      Placement.CollidesWithPrevious := TextPathQuadsOverlap(
        Result[High(Result)].Corners, Placement.Corners);
      if Placement.CollidesWithPrevious and
        not PreviousManual and not UnitManual then
      begin
        CollisionLow := UnitPathDistance;
        CollisionHigh := UnitPathDistance;
        CollisionStep := Max(UnitWidth * 0.1, 0.5);
        while Placement.CollidesWithPrevious and
          (CollisionHigh < PathLength - UnitWidth * 0.5) do
        begin
          CollisionHigh := Min(CollisionHigh + CollisionStep,
            PathLength - UnitWidth * 0.5);
          UpdatePlacementAtDistance(CollisionHigh);
          Placement.CollidesWithPrevious := TextPathQuadsOverlap(
            Result[High(Result)].Corners, Placement.Corners);
        end;
        if not Placement.CollidesWithPrevious then
        begin
          for CollisionTrial := 1 to 12 do
          begin
            CollisionTest := (CollisionLow + CollisionHigh) * 0.5;
            UpdatePlacementAtDistance(CollisionTest);
            if TextPathQuadsOverlap(Result[High(Result)].Corners,
              Placement.Corners) then
              CollisionLow := CollisionTest
            else
              CollisionHigh := CollisionTest;
          end;
          UpdatePlacementAtDistance(CollisionHigh);
          Placement.CollisionAdjusted := True;
        end;
      end;
    end;
    Result := Result + [Placement];
    NaturalCursorDistance := NaturalCursorDistance + UnitWidth;
    if UnitManual then
      CursorDistance := NaturalCursorDistance
    else if Placement.CollisionAdjusted then
      CursorDistance := Max(CursorDistance + UnitWidth,
        Placement.PathDistance + UnitWidth * 0.5)
    else
      CursorDistance := CursorDistance + UnitWidth;
    PreviousManual := UnitManual;
    Inc(I, UnitLength);
    Inc(CharacterIndex);
  end;
end;

function TryGetScreenLayoutTextPathBounds(Layer: TScreenLayoutTextPathLayer;
  out Bounds: TRectF): Boolean;
var
  I: Integer;
  J: Integer;
  Placements: TArray<TScreenLayoutTextPathPlacement>;
begin
  Result := False;
  Bounds := TRectF.Empty;
  Placements := BuildScreenLayoutTextPathPlacements(Layer);
  for I := 0 to High(Placements) do
    for J := 0 to High(Placements[I].Corners) do
    begin
      if not Result then
      begin
        Bounds := TRectF.Create(Placements[I].Corners[J],
          Placements[I].Corners[J]);
        Result := True;
      end
      else
      begin
        Bounds.Left := Min(Bounds.Left, Placements[I].Corners[J].X);
        Bounds.Top := Min(Bounds.Top, Placements[I].Corners[J].Y);
        Bounds.Right := Max(Bounds.Right, Placements[I].Corners[J].X);
        Bounds.Bottom := Max(Bounds.Bottom, Placements[I].Corners[J].Y);
      end;
    end;
end;

function PointInScreenLayoutTextPath(Layer: TScreenLayoutTextPathLayer;
  const Point: TPointF): Boolean;
var
  I: Integer;
  Polygon: TArray<TPointF>;
  Placements: TArray<TScreenLayoutTextPathPlacement>;
begin
  Result := False;
  Placements := BuildScreenLayoutTextPathPlacements(Layer);
  SetLength(Polygon, 4);
  for I := 0 to High(Placements) do
  begin
    Polygon[0] := Placements[I].Corners[0];
    Polygon[1] := Placements[I].Corners[1];
    Polygon[2] := Placements[I].Corners[2];
    Polygon[3] := Placements[I].Corners[3];
    if PointInPolygon(Point, Polygon) then
      Exit(True);
  end;
end;

end.
