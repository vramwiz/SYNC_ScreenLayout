// 閉輪郭Shapeの複製、比較、外接範囲、平滑化、座標変換を提供する。
// DocumentやUIの状態を変更せず、受け取った輪郭データだけを扱う。
unit ScreenLayoutShapeOperations;

interface

uses
  System.Types, ScreenLayoutDocument;

// 動的配列を共有しない輪郭群の複製を返す。
function CloneScreenLayoutShapeContours(
  const Source: TArray<TScreenLayoutContour>): TArray<TScreenLayoutContour>;
// 頂点、相対制御点、区間種別がすべて等しい場合にTrueを返す。
function ScreenLayoutShapeContoursEqual(const Left,
  Right: TArray<TScreenLayoutContour>): Boolean;
// アンカーと相対制御点を含む輪郭群の外接範囲を返す。
function ScreenLayoutShapeContoursBounds(
  const Contours: TArray<TScreenLayoutContour>): TRectF;
// 各アンカーの前後頂点から、閉輪郭の自動平滑化制御点を再計算する。
procedure RecalculateScreenLayoutSmoothContour(
  var Contour: TScreenLayoutContour);
// 全アンカーを同じ量だけ移動した輪郭群の複製を返す。
function TranslateScreenLayoutShapeContours(
  const Source: TArray<TScreenLayoutContour>; DX,
  DY: Single): TArray<TScreenLayoutContour>;
// 元の外接範囲から新しい外接範囲へアンカーを写し、平滑化し直した複製を返す。
function ScaleScreenLayoutShapeContours(
  const Source: TArray<TScreenLayoutContour>; const SourceBounds,
  TargetBounds: TRectF): TArray<TScreenLayoutContour>;

implementation

uses
  System.Math;

procedure IncludeShapeBoundsPoint(var Bounds: TRectF; var Found: Boolean;
  const PointValue: TPointF);
begin
  if not Found then
  begin
    Bounds := TRectF.Create(PointValue, PointValue);
    Found := True;
  end
  else
  begin
    Bounds.Left := Min(Bounds.Left, PointValue.X);
    Bounds.Top := Min(Bounds.Top, PointValue.Y);
    Bounds.Right := Max(Bounds.Right, PointValue.X);
    Bounds.Bottom := Max(Bounds.Bottom, PointValue.Y);
  end;
end;

function CloneScreenLayoutShapeContours(
  const Source: TArray<TScreenLayoutContour>): TArray<TScreenLayoutContour>;
var
  I: Integer;
begin
  SetLength(Result, Length(Source));
  for I := 0 to High(Source) do
    Result[I].Vertices := Copy(Source[I].Vertices);
end;

function ScreenLayoutShapeContoursEqual(const Left,
  Right: TArray<TScreenLayoutContour>): Boolean;
var
  ContourIndex: Integer;
  VertexIndex: Integer;
begin
  if Length(Left) <> Length(Right) then
    Exit(False);
  for ContourIndex := 0 to High(Left) do
  begin
    if Length(Left[ContourIndex].Vertices) <>
      Length(Right[ContourIndex].Vertices) then
      Exit(False);
    for VertexIndex := 0 to High(Left[ContourIndex].Vertices) do
      with Left[ContourIndex].Vertices[VertexIndex] do
        if not SameValue(Position.X,
          Right[ContourIndex].Vertices[VertexIndex].Position.X) or
          not SameValue(Position.Y,
          Right[ContourIndex].Vertices[VertexIndex].Position.Y) or
          not SameValue(IncomingControl.X,
          Right[ContourIndex].Vertices[VertexIndex].IncomingControl.X) or
          not SameValue(IncomingControl.Y,
          Right[ContourIndex].Vertices[VertexIndex].IncomingControl.Y) or
          not SameValue(OutgoingControl.X,
          Right[ContourIndex].Vertices[VertexIndex].OutgoingControl.X) or
          not SameValue(OutgoingControl.Y,
          Right[ContourIndex].Vertices[VertexIndex].OutgoingControl.Y) or
          (OutgoingSegment <>
          Right[ContourIndex].Vertices[VertexIndex].OutgoingSegment) then
          Exit(False);
  end;
  Result := True;
end;

function ScreenLayoutShapeContoursBounds(
  const Contours: TArray<TScreenLayoutContour>): TRectF;
var
  ContourIndex: Integer;
  ControlPoint: TPointF;
  Found: Boolean;
  Vertex: TScreenLayoutVertex;
  VertexIndex: Integer;
begin
  Result := TRectF.Empty;
  Found := False;
  for ContourIndex := 0 to High(Contours) do
    for VertexIndex := 0 to High(Contours[ContourIndex].Vertices) do
    begin
      Vertex := Contours[ContourIndex].Vertices[VertexIndex];
      IncludeShapeBoundsPoint(Result, Found, Vertex.Position);
      ControlPoint := TPointF.Create(
        Vertex.Position.X + Vertex.IncomingControl.X,
        Vertex.Position.Y + Vertex.IncomingControl.Y);
      IncludeShapeBoundsPoint(Result, Found, ControlPoint);
      ControlPoint := TPointF.Create(
        Vertex.Position.X + Vertex.OutgoingControl.X,
        Vertex.Position.Y + Vertex.OutgoingControl.Y);
      IncludeShapeBoundsPoint(Result, Found, ControlPoint);
    end;
end;

procedure RecalculateScreenLayoutSmoothContour(
  var Contour: TScreenLayoutContour);
var
  I: Integer;
  NextPosition: TPointF;
  PreviousPosition: TPointF;
begin
  if Length(Contour.Vertices) < 3 then
    Exit;
  for I := 0 to High(Contour.Vertices) do
  begin
    PreviousPosition := Contour.Vertices[
      (I + Length(Contour.Vertices) - 1) mod Length(Contour.Vertices)].Position;
    NextPosition := Contour.Vertices[
      (I + 1) mod Length(Contour.Vertices)].Position;
    Contour.Vertices[I].IncomingControl := TPointF.Create(
      (PreviousPosition.X - NextPosition.X) / 6,
      (PreviousPosition.Y - NextPosition.Y) / 6);
    Contour.Vertices[I].OutgoingControl := TPointF.Create(
      (NextPosition.X - PreviousPosition.X) / 6,
      (NextPosition.Y - PreviousPosition.Y) / 6);
  end;
end;

function TranslateScreenLayoutShapeContours(
  const Source: TArray<TScreenLayoutContour>; DX,
  DY: Single): TArray<TScreenLayoutContour>;
var
  ContourIndex: Integer;
  VertexIndex: Integer;
begin
  Result := CloneScreenLayoutShapeContours(Source);
  for ContourIndex := 0 to High(Result) do
    for VertexIndex := 0 to High(Result[ContourIndex].Vertices) do
      with Result[ContourIndex].Vertices[VertexIndex] do
        Position := TPointF.Create(Position.X + DX, Position.Y + DY);
end;

function ScaleScreenLayoutShapeContours(
  const Source: TArray<TScreenLayoutContour>; const SourceBounds,
  TargetBounds: TRectF): TArray<TScreenLayoutContour>;
var
  ContourIndex: Integer;
  ScaleX: Single;
  ScaleY: Single;
  VertexIndex: Integer;
begin
  Result := CloneScreenLayoutShapeContours(Source);
  if SameValue(SourceBounds.Width, 0.0) or
    SameValue(SourceBounds.Height, 0.0) then
    Exit;
  ScaleX := TargetBounds.Width / SourceBounds.Width;
  ScaleY := TargetBounds.Height / SourceBounds.Height;
  for ContourIndex := 0 to High(Result) do
  begin
    for VertexIndex := 0 to High(Result[ContourIndex].Vertices) do
      with Result[ContourIndex].Vertices[VertexIndex] do
        Position := TPointF.Create(TargetBounds.Left +
          (Position.X - SourceBounds.Left) * ScaleX,
          TargetBounds.Top + (Position.Y - SourceBounds.Top) * ScaleY);
    RecalculateScreenLayoutSmoothContour(Result[ContourIndex]);
  end;
end;

end.
