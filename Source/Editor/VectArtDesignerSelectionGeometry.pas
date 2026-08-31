// 選択枠、8個のリサイズマーカー、四隅外側の回転マーカーを計算する。
unit VectArtDesignerSelectionGeometry;

interface

uses
  System.Types, Vcl.Controls;

type
  TVectArtScreenQuad = array[0..3] of TPoint;

  TVectArtSelectionHandle = (vshNone, vshTopLeft, vshTop,
    vshTopRight, vshRight, vshBottomRight, vshBottom,
    vshBottomLeft, vshLeft);

  TVectArtSelectionGeometry = record
    DrawFrame: Boolean;
    FrameRect: TRect;
    FramePoints: array[0..4] of TPoint;
    Handles: array[vshTopLeft..vshLeft] of TRect;
    RotationHandles: array[0..3] of TRect;
  end;

function SelectionFrameOffset(StrokeWidth, Zoom: Single): Integer;
function BuildSelectionGeometry(const LayerRect: TRect;
  FrameOffset: Integer = 8): TVectArtSelectionGeometry;
function BuildRotatedSelectionGeometry(
  const Quad: TVectArtScreenQuad;
  FrameOffset: Integer = 8): TVectArtSelectionGeometry;
function BuildLineSelectionGeometry(const StartPoint,
  EndPoint: TPoint): TVectArtSelectionGeometry;
function BuildPathSelectionGeometry(const LayerRect: TRect;
  FrameOffset: Integer = 8): TVectArtSelectionGeometry;
function LineSelectionHandleDistance: Integer;
function HitTestSelectionHandle(const Point: TPoint;
  const Geometry: TVectArtSelectionGeometry): TVectArtSelectionHandle;
function HitTestRotationHandle(const Point: TPoint;
  const Geometry: TVectArtSelectionGeometry): Boolean;
// 回転操作を表す円弧矢印カーソルを返す。画像リソースは使用しない。
function RotationHandleCursor: TCursor;
function SelectionHandleCursor(Handle: TVectArtSelectionHandle): TCursor;

implementation

uses
  System.Math, Vcl.Forms, Winapi.Windows;

const
  SELECTION_FRAME_OFFSET = 8;
  SELECTION_HANDLE_SIZE = 8;
  ROTATION_HANDLE_OFFSET = 18;
  LINE_HANDLE_GAP = 6;
  CR_VECTART_ROTATE = 101;

var
  RotationCursorHandle: HCURSOR;

function CreateRotationCursor: HCURSOR;
var
  AndMask: array[0..127] of Byte;
  Angle: Integer;
  XorMask: array[0..127] of Byte;

  procedure SetPixel(X, Y: Integer);
  var
    ByteIndex: Integer;
  begin
    if (X < 0) or (X >= 32) or (Y < 0) or (Y >= 32) then
      Exit;
    ByteIndex := Y * 4 + X div 8;
    XorMask[ByteIndex] := XorMask[ByteIndex] or (Byte($80) shr (X mod 8));
  end;

  procedure DrawLine(X1, Y1, X2, Y2: Integer);
  var
    DX: Integer;
    DY: Integer;
    ErrorValue: Integer;
    StepX: Integer;
    StepY: Integer;
  begin
    DX := Abs(X2 - X1);
    DY := -Abs(Y2 - Y1);
    if X1 < X2 then
      StepX := 1
    else
      StepX := -1;
    if Y1 < Y2 then
      StepY := 1
    else
      StepY := -1;
    ErrorValue := DX + DY;
    while True do
    begin
      SetPixel(X1, Y1);
      SetPixel(X1 + 1, Y1);
      if (X1 = X2) and (Y1 = Y2) then
        Break;
      if ErrorValue * 2 >= DY then
      begin
        ErrorValue := ErrorValue + DY;
        X1 := X1 + StepX;
      end;
      if ErrorValue * 2 <= DX then
      begin
        ErrorValue := ErrorValue + DX;
        Y1 := Y1 + StepY;
      end;
    end;
  end;

begin
  FillChar(AndMask, SizeOf(AndMask), $FF);
  FillChar(XorMask, SizeOf(XorMask), 0);
  for Angle := 35 to 325 do
    if Angle mod 3 = 0 then
    begin
      SetPixel(Round(16 + 10 * Cos(DegToRad(Angle))),
        Round(16 - 10 * Sin(DegToRad(Angle))));
      SetPixel(Round(16 + 9 * Cos(DegToRad(Angle))),
        Round(16 - 9 * Sin(DegToRad(Angle))));
    end;
  DrawLine(24, 10, 19, 8);
  DrawLine(24, 10, 22, 15);
  Result := CreateCursor(HInstance, 16, 16, 32, 32, @AndMask[0],
    @XorMask[0]);
end;

function SelectionFrameOffset(StrokeWidth, Zoom: Single): Integer;
begin
  Result := SELECTION_FRAME_OFFSET +
    Ceil(Max(0.0, StrokeWidth) * Max(0.0, Zoom) * 0.5);
end;

function LineSelectionHandleDistance: Integer;
begin
  Result := SELECTION_HANDLE_SIZE div 2 + LINE_HANDLE_GAP;
end;

function BuildSelectionGeometry(const LayerRect: TRect;
  FrameOffset: Integer): TVectArtSelectionGeometry;
var
  CenterX: Integer;
  CenterY: Integer;
  HalfHandle: Integer;

  function HandleRect(X, Y: Integer): TRect;
  begin
    Result := Rect(X - HalfHandle, Y - HalfHandle,
      X - HalfHandle + SELECTION_HANDLE_SIZE,
      Y - HalfHandle + SELECTION_HANDLE_SIZE);
  end;

begin
  Result.FrameRect := LayerRect;
  Result.DrawFrame := True;
  FrameOffset := Max(0, FrameOffset);
  InflateRect(Result.FrameRect, FrameOffset, FrameOffset);
  CenterX := (Result.FrameRect.Left + Result.FrameRect.Right) div 2;
  CenterY := (Result.FrameRect.Top + Result.FrameRect.Bottom) div 2;
  HalfHandle := SELECTION_HANDLE_SIZE div 2;
  Result.FramePoints[0] := Result.FrameRect.TopLeft;
  Result.FramePoints[1] := Point(Result.FrameRect.Right,
    Result.FrameRect.Top);
  Result.FramePoints[2] := Result.FrameRect.BottomRight;
  Result.FramePoints[3] := Point(Result.FrameRect.Left,
    Result.FrameRect.Bottom);
  Result.FramePoints[4] := Result.FramePoints[0];
  Result.Handles[vshTopLeft] := HandleRect(Result.FrameRect.Left,
    Result.FrameRect.Top);
  Result.Handles[vshTop] := HandleRect(CenterX, Result.FrameRect.Top);
  Result.Handles[vshTopRight] := HandleRect(Result.FrameRect.Right,
    Result.FrameRect.Top);
  Result.Handles[vshRight] := HandleRect(Result.FrameRect.Right, CenterY);
  Result.Handles[vshBottomRight] := HandleRect(Result.FrameRect.Right,
    Result.FrameRect.Bottom);
  Result.Handles[vshBottom] := HandleRect(CenterX, Result.FrameRect.Bottom);
  Result.Handles[vshBottomLeft] := HandleRect(Result.FrameRect.Left,
    Result.FrameRect.Bottom);
  Result.Handles[vshLeft] := HandleRect(Result.FrameRect.Left, CenterY);
  Result.RotationHandles[0] := HandleRect(Result.FrameRect.Left -
    ROTATION_HANDLE_OFFSET, Result.FrameRect.Top - ROTATION_HANDLE_OFFSET);
  Result.RotationHandles[1] := HandleRect(Result.FrameRect.Right +
    ROTATION_HANDLE_OFFSET, Result.FrameRect.Top - ROTATION_HANDLE_OFFSET);
  Result.RotationHandles[2] := HandleRect(Result.FrameRect.Right +
    ROTATION_HANDLE_OFFSET, Result.FrameRect.Bottom + ROTATION_HANDLE_OFFSET);
  Result.RotationHandles[3] := HandleRect(Result.FrameRect.Left -
    ROTATION_HANDLE_OFFSET, Result.FrameRect.Bottom + ROTATION_HANDLE_OFFSET);
end;

function BuildRotatedSelectionGeometry(
  const Quad: TVectArtScreenQuad;
  FrameOffset: Integer): TVectArtSelectionGeometry;
var
  Distance: Single;
  HalfHandle: Integer;
  I: Integer;
  Midpoint: TPoint;
  OutwardX: array[0..3] of Single;
  OutwardY: array[0..3] of Single;
  UnitX: Single;
  UnitY: Single;
  AxisUX: Single;
  AxisUY: Single;
  AxisVX: Single;
  AxisVY: Single;

  function HandleRect(X, Y: Integer): TRect;
  begin
    Result := Rect(X - HalfHandle, Y - HalfHandle,
      X - HalfHandle + SELECTION_HANDLE_SIZE,
      Y - HalfHandle + SELECTION_HANDLE_SIZE);
  end;

begin
  Result.DrawFrame := True;
  FrameOffset := Max(0, FrameOffset);
  AxisUX := 0;
  AxisUY := 0;
  AxisVX := 0;
  AxisVY := 0;
  Distance := Hypot(Quad[1].X - Quad[0].X, Quad[1].Y - Quad[0].Y);
  if Distance > 0 then
  begin
    AxisUX := (Quad[1].X - Quad[0].X) / Distance;
    AxisUY := (Quad[1].Y - Quad[0].Y) / Distance;
  end;
  Distance := Hypot(Quad[3].X - Quad[0].X, Quad[3].Y - Quad[0].Y);
  if Distance > 0 then
  begin
    AxisVX := (Quad[3].X - Quad[0].X) / Distance;
    AxisVY := (Quad[3].Y - Quad[0].Y) / Distance;
  end;
  OutwardX[0] := -AxisUX - AxisVX;
  OutwardY[0] := -AxisUY - AxisVY;
  OutwardX[1] := AxisUX - AxisVX;
  OutwardY[1] := AxisUY - AxisVY;
  OutwardX[2] := AxisUX + AxisVX;
  OutwardY[2] := AxisUY + AxisVY;
  OutwardX[3] := -AxisUX + AxisVX;
  OutwardY[3] := -AxisUY + AxisVY;
  HalfHandle := SELECTION_HANDLE_SIZE div 2;
  Result.FrameRect := TRect.Empty;
  for I := 0 to High(Quad) do
  begin
    Result.FramePoints[I] := Point(
      Round(Quad[I].X + OutwardX[I] * FrameOffset),
      Round(Quad[I].Y + OutwardY[I] * FrameOffset));
    Distance := Hypot(OutwardX[I], OutwardY[I]);
    if Distance > 0 then
    begin
      UnitX := OutwardX[I] / Distance;
      UnitY := OutwardY[I] / Distance;
    end
    else
    begin
      UnitX := 0;
      UnitY := 0;
    end;
    Result.RotationHandles[I] := HandleRect(
      Round(Result.FramePoints[I].X + UnitX * ROTATION_HANDLE_OFFSET),
      Round(Result.FramePoints[I].Y + UnitY * ROTATION_HANDLE_OFFSET));
    if I = 0 then
      Result.FrameRect := Rect(Result.FramePoints[I].X,
        Result.FramePoints[I].Y, Result.FramePoints[I].X,
        Result.FramePoints[I].Y)
    else
    begin
      Result.FrameRect.Left := Min(Result.FrameRect.Left,
        Result.FramePoints[I].X);
      Result.FrameRect.Top := Min(Result.FrameRect.Top,
        Result.FramePoints[I].Y);
      Result.FrameRect.Right := Max(Result.FrameRect.Right,
        Result.FramePoints[I].X);
      Result.FrameRect.Bottom := Max(Result.FrameRect.Bottom,
        Result.FramePoints[I].Y);
    end;
  end;
  Result.FramePoints[4] := Result.FramePoints[0];
  Result.Handles[vshTopLeft] := HandleRect(Result.FramePoints[0].X,
    Result.FramePoints[0].Y);
  Midpoint := Point((Result.FramePoints[0].X + Result.FramePoints[1].X) div 2,
    (Result.FramePoints[0].Y + Result.FramePoints[1].Y) div 2);
  Result.Handles[vshTop] := HandleRect(Midpoint.X, Midpoint.Y);
  Result.Handles[vshTopRight] := HandleRect(Result.FramePoints[1].X,
    Result.FramePoints[1].Y);
  Midpoint := Point((Result.FramePoints[1].X + Result.FramePoints[2].X) div 2,
    (Result.FramePoints[1].Y + Result.FramePoints[2].Y) div 2);
  Result.Handles[vshRight] := HandleRect(Midpoint.X, Midpoint.Y);
  Result.Handles[vshBottomRight] := HandleRect(Result.FramePoints[2].X,
    Result.FramePoints[2].Y);
  Midpoint := Point((Result.FramePoints[2].X + Result.FramePoints[3].X) div 2,
    (Result.FramePoints[2].Y + Result.FramePoints[3].Y) div 2);
  Result.Handles[vshBottom] := HandleRect(Midpoint.X, Midpoint.Y);
  Result.Handles[vshBottomLeft] := HandleRect(Result.FramePoints[3].X,
    Result.FramePoints[3].Y);
  Midpoint := Point((Result.FramePoints[3].X + Result.FramePoints[0].X) div 2,
    (Result.FramePoints[3].Y + Result.FramePoints[0].Y) div 2);
  Result.Handles[vshLeft] := HandleRect(Midpoint.X, Midpoint.Y);
end;

function BuildLineSelectionGeometry(const StartPoint,
  EndPoint: TPoint): TVectArtSelectionGeometry;
var
  Distance: Single;
  HalfHandle: Integer;
  UnitX: Single;
  UnitY: Single;
  EndHandlePoint: TPoint;
  StartHandlePoint: TPoint;

  function HandleRect(const PointValue: TPoint): TRect;
  begin
    Result := Rect(PointValue.X - HalfHandle, PointValue.Y - HalfHandle,
      PointValue.X - HalfHandle + SELECTION_HANDLE_SIZE,
      PointValue.Y - HalfHandle + SELECTION_HANDLE_SIZE);
  end;

begin
  FillChar(Result, SizeOf(Result), 0);
  Result.DrawFrame := False;
  HalfHandle := SELECTION_HANDLE_SIZE div 2;
  Distance := Hypot(EndPoint.X - StartPoint.X, EndPoint.Y - StartPoint.Y);
  if Distance > 0 then
  begin
    UnitX := (EndPoint.X - StartPoint.X) / Distance;
    UnitY := (EndPoint.Y - StartPoint.Y) / Distance;
  end
  else
  begin
    UnitX := 1;
    UnitY := 0;
  end;
  StartHandlePoint := Point(
    Round(StartPoint.X - UnitX * LineSelectionHandleDistance),
    Round(StartPoint.Y - UnitY * LineSelectionHandleDistance));
  EndHandlePoint := Point(
    Round(EndPoint.X + UnitX * LineSelectionHandleDistance),
    Round(EndPoint.Y + UnitY * LineSelectionHandleDistance));
  Result.FrameRect := Rect(Min(StartPoint.X, EndPoint.X),
    Min(StartPoint.Y, EndPoint.Y), Max(StartPoint.X, EndPoint.X),
    Max(StartPoint.Y, EndPoint.Y));
  Result.FramePoints[0] := StartPoint;
  Result.FramePoints[1] := EndPoint;
  Result.FramePoints[2] := EndPoint;
  Result.FramePoints[3] := StartPoint;
  Result.FramePoints[4] := StartPoint;
  Result.Handles[vshTopLeft] := HandleRect(StartHandlePoint);
  Result.Handles[vshBottomRight] := HandleRect(EndHandlePoint);
end;

function BuildPathSelectionGeometry(const LayerRect: TRect;
  FrameOffset: Integer): TVectArtSelectionGeometry;
begin
  Result := BuildSelectionGeometry(LayerRect, FrameOffset);
  FillChar(Result.Handles, SizeOf(Result.Handles), 0);
  FillChar(Result.RotationHandles, SizeOf(Result.RotationHandles), 0);
end;

function HitTestSelectionHandle(const Point: TPoint;
  const Geometry: TVectArtSelectionGeometry): TVectArtSelectionHandle;
var
  Handle: TVectArtSelectionHandle;
begin
  for Handle := vshTopLeft to vshLeft do
    if PtInRect(Geometry.Handles[Handle], Point) then
      Exit(Handle);
  Result := vshNone;
end;

function HitTestRotationHandle(const Point: TPoint;
  const Geometry: TVectArtSelectionGeometry): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(Geometry.RotationHandles) do
    if PtInRect(Geometry.RotationHandles[I], Point) then
      Exit(True);
  Result := False;
end;

function RotationHandleCursor: TCursor;
begin
  if RotationCursorHandle = 0 then
  begin
    RotationCursorHandle := CreateRotationCursor;
    if RotationCursorHandle <> 0 then
      Screen.Cursors[CR_VECTART_ROTATE] := RotationCursorHandle;
  end;
  if RotationCursorHandle <> 0 then
    Result := CR_VECTART_ROTATE
  else
    Result := crCross;
end;

function SelectionHandleCursor(Handle: TVectArtSelectionHandle): TCursor;
begin
  case Handle of
    vshTopLeft, vshBottomRight:
      Result := crSizeNWSE;
    vshTopRight, vshBottomLeft:
      Result := crSizeNESW;
    vshTop, vshBottom:
      Result := crSizeNS;
    vshLeft, vshRight:
      Result := crSizeWE;
  else
    Result := crDefault;
  end;
end;

end.
