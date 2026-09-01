// Skiaの論理演算Pathを編集可能な直線・3次ベジェ輪郭へ変換する。
unit ScreenLayoutShapeBooleanGeometry;

interface

uses
  System.Skia, ScreenLayoutDocument;

// Skia Pathの閉輪郭をShapeデータへ変換する。空Pathは長さ0の配列を返す。
function ConvertSkPathToScreenLayoutShapeContours(
  const Path: ISkPath): TArray<TScreenLayoutContour>;

implementation

uses
  System.Generics.Collections, System.Math, System.Types;

const
  POINT_EPSILON           = 0.0001; // 閉点の浮動小数誤差を吸収する文書座標差。
  CONIC_SUBDIVISION_POWER = 3;      // 有理2次曲線を8本の2次曲線へ近似する分割指数。

function PointsEqual(const Left, Right: TPointF): Boolean;
begin
  Result := SameValue(Left.X, Right.X, POINT_EPSILON) and
    SameValue(Left.Y, Right.Y, POINT_EPSILON);
end;

procedure AppendVertex(var Contour: TScreenLayoutContour;
  const Vertex: TScreenLayoutVertex);
var
  Count: Integer;
begin
  Count := Length(Contour.Vertices);
  SetLength(Contour.Vertices, Count + 1);
  Contour.Vertices[Count] := Vertex;
end;

procedure AppendSegment(var Contour: TScreenLayoutContour;
  const EndPoint, StartControl, EndControl: TPointF;
  SegmentKind: TScreenLayoutSegmentKind);
var
  EndVertex: TScreenLayoutVertex;
  LastIndex: Integer;
  LastVertex: TScreenLayoutVertex;
begin
  if Length(Contour.Vertices) = 0 then
    Exit;
  LastIndex := High(Contour.Vertices);
  LastVertex := Contour.Vertices[LastIndex];
  LastVertex.OutgoingSegment := SegmentKind;
  if SegmentKind = slskCubicBezier then
    LastVertex.OutgoingControl := TPointF.Create(
      StartControl.X - LastVertex.Position.X,
      StartControl.Y - LastVertex.Position.Y)
  else
    LastVertex.OutgoingControl := TPointF.Zero;
  Contour.Vertices[LastIndex] := LastVertex;

  EndVertex := Default(TScreenLayoutVertex);
  EndVertex.Position := EndPoint;
  if SegmentKind = slskCubicBezier then
    EndVertex.IncomingControl := TPointF.Create(
      EndControl.X - EndPoint.X, EndControl.Y - EndPoint.Y);
  EndVertex.OutgoingSegment := slskLine;
  EndVertex.Kind := slvkSharp;
  AppendVertex(Contour, EndVertex);
end;

procedure AppendQuadraticSegment(var Contour: TScreenLayoutContour;
  const StartPoint, ControlPoint, EndPoint: TPointF);
var
  CubicControl1: TPointF;
  CubicControl2: TPointF;
begin
  // 2次ベジェは制御点を2/3位置へ写すことで、形状を変えずに3次へ変換できる。
  CubicControl1 := TPointF.Create(StartPoint.X +
    (ControlPoint.X - StartPoint.X) * 2 / 3,
    StartPoint.Y + (ControlPoint.Y - StartPoint.Y) * 2 / 3);
  CubicControl2 := TPointF.Create(EndPoint.X +
    (ControlPoint.X - EndPoint.X) * 2 / 3,
    EndPoint.Y + (ControlPoint.Y - EndPoint.Y) * 2 / 3);
  AppendSegment(Contour, EndPoint, CubicControl1, CubicControl2,
    slskCubicBezier);
end;

procedure FinalizeContour(var Contour: TScreenLayoutContour;
  Contours: TList<TScreenLayoutContour>);
var
  FirstVertex: TScreenLayoutVertex;
  I: Integer;
  LastIndex: Integer;
  PreviousIndex: Integer;
begin
  if Length(Contour.Vertices) < 3 then
  begin
    Contour.Vertices := nil;
    Exit;
  end;
  LastIndex := High(Contour.Vertices);
  if PointsEqual(Contour.Vertices[LastIndex].Position,
    Contour.Vertices[0].Position) then
  begin
    // Skiaが閉区間の終点として返す始点の複製を除き、入力側制御点だけを始点へ戻す。
    FirstVertex := Contour.Vertices[0];
    FirstVertex.IncomingControl := Contour.Vertices[LastIndex].IncomingControl;
    Contour.Vertices[0] := FirstVertex;
    SetLength(Contour.Vertices, LastIndex);
  end
  else
    Contour.Vertices[LastIndex].OutgoingSegment := slskLine;

  for I := 0 to High(Contour.Vertices) do
  begin
    PreviousIndex := (I + Length(Contour.Vertices) - 1) mod
      Length(Contour.Vertices);
    if (Contour.Vertices[I].OutgoingSegment = slskCubicBezier) or
      (Contour.Vertices[PreviousIndex].OutgoingSegment = slskCubicBezier) then
      Contour.Vertices[I].Kind := slvkBezier
    else
      Contour.Vertices[I].Kind := slvkSharp;
  end;
  Contours.Add(Contour);
  Contour.Vertices := nil;
end;

function ConvertSkPathToScreenLayoutShapeContours(
  const Path: ISkPath): TArray<TScreenLayoutContour>;
var
  ConicPoints: TArray<TPointF>;
  Contour: TScreenLayoutContour;
  Contours: TList<TScreenLayoutContour>;
  Element: TSkPathIteratorElem;
  I: Integer;
  StartVertex: TScreenLayoutVertex;
begin
  Result := nil;
  if (Path = nil) or Path.IsEmpty then
    Exit;
  Contours := TList<TScreenLayoutContour>.Create;
  try
    Contour.Vertices := nil;
    for Element in Path.GetIterator(False) do
      case Element.Verb of
        TSkPathVerb.Move:
          begin
            FinalizeContour(Contour, Contours);
            StartVertex := Default(TScreenLayoutVertex);
            StartVertex.Position := Element.Points[0];
            StartVertex.OutgoingSegment := slskLine;
            StartVertex.Kind := slvkSharp;
            AppendVertex(Contour, StartVertex);
          end;
        TSkPathVerb.Line:
          AppendSegment(Contour, Element.Points[1], TPointF.Zero,
            TPointF.Zero, slskLine);
        TSkPathVerb.Quad:
          AppendQuadraticSegment(Contour, Element.Points[0],
            Element.Points[1], Element.Points[2]);
        TSkPathVerb.Conic:
          begin
            ConicPoints := TSkPath.ConvertConicToQuads(Element.Points[0],
              Element.Points[1], Element.Points[2], Element.ConicWeight,
              CONIC_SUBDIVISION_POWER);
            I := 0;
            while I + 2 <= High(ConicPoints) do
            begin
              AppendQuadraticSegment(Contour, ConicPoints[I],
                ConicPoints[I + 1], ConicPoints[I + 2]);
              Inc(I, 2);
            end;
          end;
        TSkPathVerb.Cubic:
          AppendSegment(Contour, Element.Points[3], Element.Points[1],
            Element.Points[2], slskCubicBezier);
        TSkPathVerb.Close:
          FinalizeContour(Contour, Contours);
      end;
    FinalizeContour(Contour, Contours);
    Result := Contours.ToArray;
  finally
    Contours.Free;
  end;
end;

end.
