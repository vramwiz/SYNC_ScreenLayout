// 編集キャンバス上の図形作成プレビューと操作補助アイコンを描画する。
unit ScreenLayoutCanvasPreview;

interface

uses
  System.Types, Vcl.Direct2D, Vcl.Graphics, ScreenLayoutDocument;

// 頂点種別を示す鋭角またはベジェ形状のアイコン座標を返す。
function BuildVertexKindIconPoints(const Bounds: TRect;
  Kind: TScreenLayoutVertexKind): TArray<TPoint>;
// 角丸半径ハンドルとして使用する菱形の4頂点を返す。
function BuildDiamondPoints(const Bounds: TRect): TArray<TPoint>;
// 回転ハンドル内へ収まる円弧と矢印の座標を返す。
procedure BuildRotationMarkPoints(const Bounds: TRect;
  out ArcPoints, ArrowPoints: TArray<TPoint>);
// GDIキャンバスへ線種と線端を反映した作成プレビューを描画する。
procedure DrawStyledPreviewLine(Target: TCanvas; const StartPoint,
  EndPoint: TPoint; Color: TColor; Width: Single;
  Style: TVectArtMifStrokeStyle; LineCap: TVectArtLineCap); overload;
// Direct2Dキャンバスへ線種と線端を反映した作成プレビューを描画する。
procedure DrawStyledPreviewLine(Target: TDirect2DCanvas;
  const StartPoint, EndPoint: TPoint; Color: TColor; Width: Single;
  Style: TVectArtMifStrokeStyle; LineCap: TVectArtLineCap); overload;

implementation

uses
  System.Math, Winapi.D2D1, ScreenLayoutRenderer;

type
  TPreviewLineSegment = record
    StartPoint: TPoint; // 画面座標での描画開始点。
    EndPoint: TPoint;   // 画面座標での描画終了点。
  end;

function BuildVertexKindIconPoints(const Bounds: TRect;
  Kind: TScreenLayoutVertexKind): TArray<TPoint>;
var
  CenterX: Integer;
begin
  CenterX := (Bounds.Left + Bounds.Right) div 2;
  if Kind = slvkSharp then
  begin
    SetLength(Result, 3);
    Result[0] := Point(Bounds.Left + 5, Bounds.Top + 5);
    Result[1] := Point(CenterX, Bounds.Bottom - 5);
    Result[2] := Point(Bounds.Right - 5, Bounds.Top + 5);
  end
  else
  begin
    SetLength(Result, 7);
    Result[0] := Point(Bounds.Left + 5, Bounds.Top + 5);
    Result[1] := Point(Bounds.Left + 5, Bounds.Bottom - 8);
    Result[2] := Point(Bounds.Left + 7, Bounds.Bottom - 5);
    Result[3] := Point(CenterX, Bounds.Bottom - 4);
    Result[4] := Point(Bounds.Right - 7, Bounds.Bottom - 5);
    Result[5] := Point(Bounds.Right - 5, Bounds.Bottom - 8);
    Result[6] := Point(Bounds.Right - 5, Bounds.Top + 5);
  end;
end;

function BuildDiamondPoints(const Bounds: TRect): TArray<TPoint>;
begin
  SetLength(Result, 4);
  Result[0] := Point((Bounds.Left + Bounds.Right) div 2, Bounds.Top);
  Result[1] := Point(Bounds.Right, (Bounds.Top + Bounds.Bottom) div 2);
  Result[2] := Point((Bounds.Left + Bounds.Right) div 2, Bounds.Bottom);
  Result[3] := Point(Bounds.Left, (Bounds.Top + Bounds.Bottom) div 2);
end;

procedure BuildRotationMarkPoints(const Bounds: TRect;
  out ArcPoints, ArrowPoints: TArray<TPoint>);
const
  ARC_POINT_COUNT = 10;
var
  Angle: Single;
  CenterX: Single;
  CenterY: Single;
  I: Integer;
  PerpendicularX: Single;
  PerpendicularY: Single;
  Radius: Single;
  TangentX: Single;
  TangentY: Single;
  Tip: TPoint;
begin
  CenterX := (Bounds.Left + Bounds.Right) * 0.5;
  CenterY := (Bounds.Top + Bounds.Bottom) * 0.5;
  Radius := Max(Min(Bounds.Width, Bounds.Height) * 0.5 - 4, 2);
  SetLength(ArcPoints, ARC_POINT_COUNT);
  for I := 0 to High(ArcPoints) do
  begin
    Angle := DegToRad(45 + 270 * I / High(ArcPoints));
    ArcPoints[I] := Point(Round(CenterX + Cos(Angle) * Radius),
      Round(CenterY - Sin(Angle) * Radius));
  end;
  Tip := ArcPoints[High(ArcPoints)];
  Angle := DegToRad(315);
  TangentX := -Sin(Angle);
  TangentY := -Cos(Angle);
  PerpendicularX := -TangentY;
  PerpendicularY := TangentX;
  SetLength(ArrowPoints, 3);
  ArrowPoints[0] := Tip;
  ArrowPoints[1] := Point(Round(Tip.X - TangentX * 4 +
    PerpendicularX * 2), Round(Tip.Y - TangentY * 4 +
    PerpendicularY * 2));
  ArrowPoints[2] := Point(Round(Tip.X - TangentX * 4 -
    PerpendicularX * 2), Round(Tip.Y - TangentY * 4 -
    PerpendicularY * 2));
end;

function BuildStyledPreviewSegments(const StartPoint, EndPoint: TPoint;
  Width: Single; Style: TVectArtMifStrokeStyle): TArray<TPreviewLineSegment>;
var
  CurrentDistance: Single;
  DashIndex: Integer;
  DrawSegment: Boolean;
  DX: Single;
  DY: Single;
  EndDistance: Single;
  Intervals: TArray<Single>;
  LineLength: Single;
  SegmentLength: Single;
  UnitX: Single;
  UnitY: Single;
begin
  Result := nil;
  DX := EndPoint.X - StartPoint.X;
  DY := EndPoint.Y - StartPoint.Y;
  LineLength := Hypot(DX, DY);
  if LineLength <= 0 then
    Exit;
  Intervals := VectArtStrokeDashIntervals(Style, Max(Width, 1.0));
  if Length(Intervals) = 0 then
  begin
    SetLength(Result, 1);
    Result[0].StartPoint := StartPoint;
    Result[0].EndPoint := EndPoint;
    Exit;
  end;
  UnitX := DX / LineLength;
  UnitY := DY / LineLength;
  CurrentDistance := 0;
  DashIndex := 0;
  DrawSegment := True;
  while CurrentDistance < LineLength do
  begin
    SegmentLength := Max(Intervals[DashIndex], 1.0);
    EndDistance := Min(CurrentDistance + SegmentLength, LineLength);
    if DrawSegment then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)].StartPoint := Point(
        StartPoint.X + Round(UnitX * CurrentDistance),
        StartPoint.Y + Round(UnitY * CurrentDistance));
      Result[High(Result)].EndPoint := Point(
        StartPoint.X + Round(UnitX * EndDistance),
        StartPoint.Y + Round(UnitY * EndDistance));
    end;
    CurrentDistance := EndDistance;
    DashIndex := (DashIndex + 1) mod Length(Intervals);
    DrawSegment := not DrawSegment;
  end;
end;

procedure DrawStyledPreviewLine(Target: TCanvas; const StartPoint,
  EndPoint: TPoint; Color: TColor; Width: Single;
  Style: TVectArtMifStrokeStyle; LineCap: TVectArtLineCap);
var
  DX: Single;
  DY: Single;
  I: Integer;
  LengthValue: Single;
  P1: TPoint;
  P2: TPoint;
  Points: array[0..2] of TPoint;
  Radius: Integer;
  Segments: TArray<TPreviewLineSegment>;
begin
  Segments := BuildStyledPreviewSegments(StartPoint, EndPoint, Width, Style);
  Target.Pen.Color := Color;
  Target.Pen.Width := Max(Round(Width), 1);
  Target.Pen.Style := psSolid;
  for I := 0 to High(Segments) do
  begin
    P1 := Segments[I].StartPoint;
    P2 := Segments[I].EndPoint;
    if LineCap = vlcSquare then
    begin
      DX := P2.X - P1.X;
      DY := P2.Y - P1.Y;
      LengthValue := Hypot(DX, DY);
      if LengthValue > 0 then
      begin
        P1.Offset(-Round(DX / LengthValue * Width * 0.5),
          -Round(DY / LengthValue * Width * 0.5));
        P2.Offset(Round(DX / LengthValue * Width * 0.5),
          Round(DY / LengthValue * Width * 0.5));
      end;
    end;
    Target.MoveTo(P1.X, P1.Y);
    Target.LineTo(P2.X, P2.Y);
    if LineCap = vlcRound then
    begin
      Radius := Max(Round(Width * 0.5), 1);
      Target.Brush.Style := bsSolid;
      Target.Brush.Color := Color;
      Target.Ellipse(P1.X - Radius, P1.Y - Radius, P1.X + Radius + 1,
        P1.Y + Radius + 1);
      Target.Ellipse(P2.X - Radius, P2.Y - Radius, P2.X + Radius + 1,
        P2.Y + Radius + 1);
      Target.Brush.Style := bsClear;
    end
    else if LineCap = vlcTriangle then
    begin
      DX := P2.X - P1.X;
      DY := P2.Y - P1.Y;
      LengthValue := Hypot(DX, DY);
      if LengthValue > 0 then
      begin
        Radius := Max(Round(Width * 0.5), 1);
        DX := DX / LengthValue;
        DY := DY / LengthValue;
        Target.Brush.Style := bsSolid;
        Target.Brush.Color := Color;
        Points[0] := Point(P1.X - Round(DY * Radius),
          P1.Y + Round(DX * Radius));
        Points[1] := Point(P1.X - Round(DX * Radius),
          P1.Y - Round(DY * Radius));
        Points[2] := Point(P1.X + Round(DY * Radius),
          P1.Y - Round(DX * Radius));
        Target.Polygon(Points);
        Points[0] := Point(P2.X - Round(DY * Radius),
          P2.Y + Round(DX * Radius));
        Points[1] := Point(P2.X + Round(DX * Radius),
          P2.Y + Round(DY * Radius));
        Points[2] := Point(P2.X + Round(DY * Radius),
          P2.Y - Round(DX * Radius));
        Target.Polygon(Points);
        Target.Brush.Style := bsClear;
      end;
    end;
  end;
  Target.Pen.Width := 1;
end;

procedure DrawStyledPreviewLine(Target: TDirect2DCanvas;
  const StartPoint, EndPoint: TPoint; Color: TColor; Width: Single;
  Style: TVectArtMifStrokeStyle; LineCap: TVectArtLineCap);
var
  DX: Single;
  DY: Single;
  I: Integer;
  LengthValue: Single;
  P1: TPoint;
  P2: TPoint;
  Points: array[0..2] of TPoint;
  Radius: Integer;
  Segments: TArray<TPreviewLineSegment>;
begin
  Target.RenderTarget.SetAntialiasMode(D2D1_ANTIALIAS_MODE_PER_PRIMITIVE);
  Segments := BuildStyledPreviewSegments(StartPoint, EndPoint, Width, Style);
  Target.Pen.Color := Color;
  Target.Pen.Width := Max(Round(Width), 1);
  Target.Pen.Style := psSolid;
  for I := 0 to High(Segments) do
  begin
    P1 := Segments[I].StartPoint;
    P2 := Segments[I].EndPoint;
    if LineCap = vlcSquare then
    begin
      DX := P2.X - P1.X;
      DY := P2.Y - P1.Y;
      LengthValue := Hypot(DX, DY);
      if LengthValue > 0 then
      begin
        P1.Offset(-Round(DX / LengthValue * Width * 0.5),
          -Round(DY / LengthValue * Width * 0.5));
        P2.Offset(Round(DX / LengthValue * Width * 0.5),
          Round(DY / LengthValue * Width * 0.5));
      end;
    end;
    Target.MoveTo(P1.X, P1.Y);
    Target.LineTo(P2.X, P2.Y);
    if LineCap = vlcRound then
    begin
      Radius := Max(Round(Width * 0.5), 1);
      Target.Brush.Style := bsSolid;
      Target.Brush.Color := Color;
      Target.Ellipse(P1.X - Radius, P1.Y - Radius, P1.X + Radius + 1,
        P1.Y + Radius + 1);
      Target.Ellipse(P2.X - Radius, P2.Y - Radius, P2.X + Radius + 1,
        P2.Y + Radius + 1);
      Target.Brush.Style := bsClear;
    end
    else if LineCap = vlcTriangle then
    begin
      DX := P2.X - P1.X;
      DY := P2.Y - P1.Y;
      LengthValue := Hypot(DX, DY);
      if LengthValue > 0 then
      begin
        Radius := Max(Round(Width * 0.5), 1);
        DX := DX / LengthValue;
        DY := DY / LengthValue;
        Target.Brush.Style := bsSolid;
        Target.Brush.Color := Color;
        Points[0] := Point(P1.X - Round(DY * Radius),
          P1.Y + Round(DX * Radius));
        Points[1] := Point(P1.X - Round(DX * Radius),
          P1.Y - Round(DY * Radius));
        Points[2] := Point(P1.X + Round(DY * Radius),
          P1.Y - Round(DX * Radius));
        Target.Polygon(Points);
        Points[0] := Point(P2.X - Round(DY * Radius),
          P2.Y + Round(DX * Radius));
        Points[1] := Point(P2.X + Round(DX * Radius),
          P2.Y + Round(DY * Radius));
        Points[2] := Point(P2.X + Round(DY * Radius),
          P2.Y - Round(DX * Radius));
        Target.Polygon(Points);
        Target.Brush.Style := bsClear;
      end;
    end;
  end;
  Target.Pen.Width := 1;
  Target.RenderTarget.SetAntialiasMode(D2D1_ANTIALIAS_MODE_PER_PRIMITIVE);
end;

end.
