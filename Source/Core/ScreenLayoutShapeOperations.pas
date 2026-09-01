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
// 指定頂点とその前後区間を、鋭角または滑らかなベジェ接続へ変更する。
procedure SetScreenLayoutShapeVertexKind(var Contour: TScreenLayoutContour;
  VertexIndex: Integer; Kind: TScreenLayoutVertexKind);
// 指定区間を分割し、輪郭の見た目を維持した新頂点の番号を返す。
function InsertScreenLayoutShapeVertex(var Contour: TScreenLayoutContour;
  SegmentIndex: Integer; Parameter: Single): Integer;
// 指定頂点を削除する。閉輪郭を維持できない場合はFalseを返す。
function DeleteScreenLayoutShapeVertex(var Contour: TScreenLayoutContour;
  VertexIndex: Integer): Boolean;
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

function LerpPoint(const StartPoint, EndPoint: TPointF;
  Parameter: Single): TPointF;
begin
  Result := TPointF.Create(StartPoint.X +
    (EndPoint.X - StartPoint.X) * Parameter,
    StartPoint.Y + (EndPoint.Y - StartPoint.Y) * Parameter);
end;

procedure RecalculateScreenLayoutSmoothVertex(var Contour: TScreenLayoutContour;
  VertexIndex: Integer);
var
  NextPosition: TPointF;
  PreviousPosition: TPointF;
begin
  if (VertexIndex < 0) or (VertexIndex > High(Contour.Vertices)) then
    Exit;
  if Contour.Vertices[VertexIndex].Kind = slvkSharp then
  begin
    Contour.Vertices[VertexIndex].IncomingControl := TPointF.Zero;
    Contour.Vertices[VertexIndex].OutgoingControl := TPointF.Zero;
    Exit;
  end;
  PreviousPosition := Contour.Vertices[
    (VertexIndex + Length(Contour.Vertices) - 1) mod
    Length(Contour.Vertices)].Position;
  NextPosition := Contour.Vertices[
    (VertexIndex + 1) mod Length(Contour.Vertices)].Position;
  Contour.Vertices[VertexIndex].IncomingControl := TPointF.Create(
    (PreviousPosition.X - NextPosition.X) / 6,
    (PreviousPosition.Y - NextPosition.Y) / 6);
  Contour.Vertices[VertexIndex].OutgoingControl := TPointF.Create(
    (NextPosition.X - PreviousPosition.X) / 6,
    (NextPosition.Y - PreviousPosition.Y) / 6);
end;

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
          Right[ContourIndex].Vertices[VertexIndex].OutgoingSegment) or
          (Kind <> Right[ContourIndex].Vertices[VertexIndex].Kind) then
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
    if Contour.Vertices[I].Kind = slvkSharp then
    begin
      Contour.Vertices[I].IncomingControl := TPointF.Zero;
      Contour.Vertices[I].OutgoingControl := TPointF.Zero;
      Continue;
    end;
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

procedure SetScreenLayoutShapeVertexKind(var Contour: TScreenLayoutContour;
  VertexIndex: Integer; Kind: TScreenLayoutVertexKind);
var
  NextIndex: Integer;
  NextPosition: TPointF;
  PreviousIndex: Integer;
  PreviousPosition: TPointF;
begin
  if (VertexIndex < 0) or (VertexIndex > High(Contour.Vertices)) then
    Exit;
  PreviousIndex := (VertexIndex + Length(Contour.Vertices) - 1) mod
    Length(Contour.Vertices);
  NextIndex := (VertexIndex + 1) mod Length(Contour.Vertices);
  Contour.Vertices[VertexIndex].Kind := Kind;
  if Kind = slvkSharp then
  begin
    Contour.Vertices[VertexIndex].IncomingControl := TPointF.Zero;
    Contour.Vertices[VertexIndex].OutgoingControl := TPointF.Zero;
  end
  else
  begin
    PreviousPosition := Contour.Vertices[PreviousIndex].Position;
    NextPosition := Contour.Vertices[NextIndex].Position;
    Contour.Vertices[VertexIndex].IncomingControl := TPointF.Create(
      (PreviousPosition.X - NextPosition.X) / 6,
      (PreviousPosition.Y - NextPosition.Y) / 6);
    Contour.Vertices[VertexIndex].OutgoingControl := TPointF.Create(
      (NextPosition.X - PreviousPosition.X) / 6,
      (NextPosition.Y - PreviousPosition.Y) / 6);
  end;
  if (Contour.Vertices[PreviousIndex].Kind = slvkBezier) or
    (Contour.Vertices[VertexIndex].Kind = slvkBezier) then
    Contour.Vertices[PreviousIndex].OutgoingSegment := slskCubicBezier
  else
    Contour.Vertices[PreviousIndex].OutgoingSegment := slskLine;
  if (Contour.Vertices[VertexIndex].Kind = slvkBezier) or
    (Contour.Vertices[NextIndex].Kind = slvkBezier) then
    Contour.Vertices[VertexIndex].OutgoingSegment := slskCubicBezier
  else
    Contour.Vertices[VertexIndex].OutgoingSegment := slskLine;
end;

function InsertScreenLayoutShapeVertex(var Contour: TScreenLayoutContour;
  SegmentIndex: Integer; Parameter: Single): Integer;
var
  ControlA: TPointF;
  ControlB: TPointF;
  I: Integer;
  NewVertex: TScreenLayoutVertex;
  NewVertices: TArray<TScreenLayoutVertex>;
  NextIndex: Integer;
  PointA: TPointF;
  PointB: TPointF;
  PointC: TPointF;
  PointD: TPointF;
  SplitA: TPointF;
  SplitB: TPointF;
  SplitPoint: TPointF;
begin
  Result := -1;
  if (SegmentIndex < 0) or (SegmentIndex > High(Contour.Vertices)) then
    Exit;
  Parameter := EnsureRange(Parameter, 0.001, 0.999);
  NextIndex := (SegmentIndex + 1) mod Length(Contour.Vertices);
  PointA := Contour.Vertices[SegmentIndex].Position;
  PointD := Contour.Vertices[NextIndex].Position;
  NewVertex := Default(TScreenLayoutVertex);
  if Contour.Vertices[SegmentIndex].OutgoingSegment = slskCubicBezier then
  begin
    PointB := TPointF.Create(PointA.X +
      Contour.Vertices[SegmentIndex].OutgoingControl.X, PointA.Y +
      Contour.Vertices[SegmentIndex].OutgoingControl.Y);
    PointC := TPointF.Create(PointD.X +
      Contour.Vertices[NextIndex].IncomingControl.X, PointD.Y +
      Contour.Vertices[NextIndex].IncomingControl.Y);
    ControlA := LerpPoint(PointA, PointB, Parameter);
    SplitA := LerpPoint(PointB, PointC, Parameter);
    ControlB := LerpPoint(PointC, PointD, Parameter);
    SplitB := LerpPoint(ControlA, SplitA, Parameter);
    SplitA := LerpPoint(SplitA, ControlB, Parameter);
    SplitPoint := LerpPoint(SplitB, SplitA, Parameter);
    Contour.Vertices[SegmentIndex].OutgoingControl := TPointF.Create(
      ControlA.X - PointA.X, ControlA.Y - PointA.Y);
    Contour.Vertices[NextIndex].IncomingControl := TPointF.Create(
      ControlB.X - PointD.X, ControlB.Y - PointD.Y);
    NewVertex.Position := SplitPoint;
    NewVertex.IncomingControl := TPointF.Create(SplitB.X - SplitPoint.X,
      SplitB.Y - SplitPoint.Y);
    NewVertex.OutgoingControl := TPointF.Create(SplitA.X - SplitPoint.X,
      SplitA.Y - SplitPoint.Y);
    NewVertex.OutgoingSegment := slskCubicBezier;
    NewVertex.Kind := slvkBezier;
  end
  else
  begin
    NewVertex.Position := LerpPoint(PointA, PointD, Parameter);
    NewVertex.OutgoingSegment := slskLine;
    NewVertex.Kind := slvkSharp;
  end;
  Result := SegmentIndex + 1;
  SetLength(NewVertices, Length(Contour.Vertices) + 1);
  for I := 0 to Result - 1 do
    NewVertices[I] := Contour.Vertices[I];
  NewVertices[Result] := NewVertex;
  for I := Result to High(Contour.Vertices) do
    NewVertices[I + 1] := Contour.Vertices[I];
  Contour.Vertices := NewVertices;
end;

function DeleteScreenLayoutShapeVertex(var Contour: TScreenLayoutContour;
  VertexIndex: Integer): Boolean;
var
  I: Integer;
  NewVertices: TArray<TScreenLayoutVertex>;
  NextIndex: Integer;
  PreviousIndex: Integer;
begin
  Result := False;
  if (Length(Contour.Vertices) <= 3) or (VertexIndex < 0) or
    (VertexIndex > High(Contour.Vertices)) then
    Exit;
  SetLength(NewVertices, Length(Contour.Vertices) - 1);
  for I := 0 to VertexIndex - 1 do
    NewVertices[I] := Contour.Vertices[I];
  for I := VertexIndex + 1 to High(Contour.Vertices) do
    NewVertices[I - 1] := Contour.Vertices[I];
  Contour.Vertices := NewVertices;
  NextIndex := VertexIndex mod Length(Contour.Vertices);
  PreviousIndex := (NextIndex + Length(Contour.Vertices) - 1) mod
    Length(Contour.Vertices);
  if (Contour.Vertices[PreviousIndex].Kind = slvkBezier) or
    (Contour.Vertices[NextIndex].Kind = slvkBezier) then
    Contour.Vertices[PreviousIndex].OutgoingSegment := slskCubicBezier
  else
    Contour.Vertices[PreviousIndex].OutgoingSegment := slskLine;
  RecalculateScreenLayoutSmoothVertex(Contour, PreviousIndex);
  RecalculateScreenLayoutSmoothVertex(Contour, NextIndex);
  Result := True;
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
      begin
        Position := TPointF.Create(TargetBounds.Left +
          (Position.X - SourceBounds.Left) * ScaleX,
          TargetBounds.Top + (Position.Y - SourceBounds.Top) * ScaleY);
        IncomingControl := TPointF.Create(IncomingControl.X * ScaleX,
          IncomingControl.Y * ScaleY);
        OutgoingControl := TPointF.Create(OutgoingControl.X * ScaleX,
          OutgoingControl.Y * ScaleY);
      end;
  end;
end;

end.
