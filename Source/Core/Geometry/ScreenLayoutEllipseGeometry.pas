// 楕円と楕円弧の中心、角度、端点、接線、外接範囲をUIへ依存せず計算する。
unit ScreenLayoutEllipseGeometry;

interface

uses
  System.Types;

// 楕円の媒介角を0度以上360度未満へ正規化する。
function NormalizeScreenLayoutEllipseAngleDegrees(Value: Single): Single;
// 回転前Boundsの中心を返す。Boundsの辺順が逆でも同じ中心となる。
function ScreenLayoutEllipseCenter(const Bounds: TRectF): TPointF;
// 回転前Boundsの幅と高さの半分を、常に非負の半径として返す。
function ScreenLayoutEllipseRadii(const Bounds: TRectF): TPointF;
// 右向き0度、時計回り正の媒介角に対応する回転楕円上の点を返す。
function ScreenLayoutEllipsePoint(const Bounds: TRectF;
  RotationDegrees, AngleDegrees: Single): TPointF;
// 指定角度の進行方向を示す長さ1の接線を返す。退化楕円ではゼロベクトルとなる。
function ScreenLayoutEllipseTangent(const Bounds: TRectF;
  RotationDegrees, AngleDegrees: Single): TPointF;
// ドキュメント座標を基礎楕円の媒介角へ変換する。
function ScreenLayoutEllipseAngleAtPoint(const Bounds: TRectF;
  RotationDegrees: Single; const Point: TPointF): Single;
// Pointが回転楕円の内部または輪郭上にあるかを返す。
function PointInScreenLayoutEllipse(const Point: TPointF;
  const Bounds: TRectF; RotationDegrees: Single): Boolean;
// 回転楕円全体のドキュメント座標上の外接範囲を返す。
function ScreenLayoutEllipseBounds(const Bounds: TRectF;
  RotationDegrees: Single): TRectF;
// 開始角から時計回りにSweepAngleDegreesだけ進む円弧の終点を返す。
function ScreenLayoutArcEndPoint(const Bounds: TRectF; RotationDegrees,
  StartAngleDegrees, SweepAngleDegrees: Single): TPointF;
// 線幅を含まない回転楕円弧のドキュメント座標上の外接範囲を返す。
function ScreenLayoutArcBounds(const Bounds: TRectF; RotationDegrees,
  StartAngleDegrees, SweepAngleDegrees: Single): TRectF;
// CandidateAngleDegreesが開始角から時計回りの掃引範囲に含まれるかを返す。
function ScreenLayoutAngleInArc(StartAngleDegrees, SweepAngleDegrees,
  CandidateAngleDegrees: Single): Boolean;

implementation

uses
  System.Math, ScreenLayoutGeometry;

function NormalizeScreenLayoutEllipseAngleDegrees(Value: Single): Single;
begin
  Result := Value - Floor(Value / 360.0) * 360.0;
  if Result < 0.0 then
    Result := Result + 360.0;
end;

function ScreenLayoutEllipseCenter(const Bounds: TRectF): TPointF;
begin
  Result := TPointF.Create((Bounds.Left + Bounds.Right) * 0.5,
    (Bounds.Top + Bounds.Bottom) * 0.5);
end;

function ScreenLayoutEllipseRadii(const Bounds: TRectF): TPointF;
begin
  Result := TPointF.Create(Abs(Bounds.Right - Bounds.Left) * 0.5,
    Abs(Bounds.Bottom - Bounds.Top) * 0.5);
end;

function ScreenLayoutEllipsePoint(const Bounds: TRectF;
  RotationDegrees, AngleDegrees: Single): TPointF;
var
  AngleRadians: Extended;
  Center: TPointF;
  LocalPoint: TPointF;
  Radii: TPointF;
begin
  Center := ScreenLayoutEllipseCenter(Bounds);
  Radii := ScreenLayoutEllipseRadii(Bounds);
  AngleRadians := DegToRad(AngleDegrees);
  LocalPoint := TPointF.Create(Center.X + Radii.X * Cos(AngleRadians),
    Center.Y + Radii.Y * Sin(AngleRadians));
  Result := RotatePointAround(LocalPoint, Center, RotationDegrees);
end;

function ScreenLayoutEllipseTangent(const Bounds: TRectF;
  RotationDegrees, AngleDegrees: Single): TPointF;
var
  AngleRadians: Extended;
  LengthValue: Single;
  RotatedPoint: TPointF;
  Tangent: TPointF;
begin
  AngleRadians := DegToRad(AngleDegrees);
  Tangent := TPointF.Create(-ScreenLayoutEllipseRadii(Bounds).X *
    Sin(AngleRadians), ScreenLayoutEllipseRadii(Bounds).Y *
    Cos(AngleRadians));
  RotatedPoint := RotatePointAround(Tangent, TPointF.Zero,
    RotationDegrees);
  LengthValue := Hypot(RotatedPoint.X, RotatedPoint.Y);
  if LengthValue <= 0.000001 then
    Exit(TPointF.Zero);
  Result := TPointF.Create(RotatedPoint.X / LengthValue,
    RotatedPoint.Y / LengthValue);
end;

function ScreenLayoutEllipseAngleAtPoint(const Bounds: TRectF;
  RotationDegrees: Single; const Point: TPointF): Single;
var
  Center: TPointF;
  LocalPoint: TPointF;
  Radii: TPointF;
begin
  Center := ScreenLayoutEllipseCenter(Bounds);
  Radii := ScreenLayoutEllipseRadii(Bounds);
  if (Radii.X <= 0.000001) or (Radii.Y <= 0.000001) then
    Exit(0.0);
  LocalPoint := RotatePointAround(Point, Center, -RotationDegrees);
  Result := NormalizeScreenLayoutEllipseAngleDegrees(RadToDeg(ArcTan2(
    (LocalPoint.Y - Center.Y) / Radii.Y,
    (LocalPoint.X - Center.X) / Radii.X)));
end;

function PointInScreenLayoutEllipse(const Point: TPointF;
  const Bounds: TRectF; RotationDegrees: Single): Boolean;
var
  Center: TPointF;
  LocalPoint: TPointF;
  NormalizedX: Single;
  NormalizedY: Single;
  Radii: TPointF;
begin
  Center := ScreenLayoutEllipseCenter(Bounds);
  Radii := ScreenLayoutEllipseRadii(Bounds);
  if (Radii.X <= 0.000001) or (Radii.Y <= 0.000001) then
    Exit(False);
  LocalPoint := RotatePointAround(Point, Center, -RotationDegrees);
  NormalizedX := (LocalPoint.X - Center.X) / Radii.X;
  NormalizedY := (LocalPoint.Y - Center.Y) / Radii.Y;
  Result := NormalizedX * NormalizedX +
    NormalizedY * NormalizedY <= 1.0 + 0.000001;
end;

function ScreenLayoutAngleInArc(StartAngleDegrees, SweepAngleDegrees,
  CandidateAngleDegrees: Single): Boolean;
var
  Offset: Single;
begin
  SweepAngleDegrees := EnsureRange(SweepAngleDegrees, 0.0, 360.0);
  if SweepAngleDegrees >= 360.0 - 0.0001 then
    Exit(True);
  Offset := NormalizeScreenLayoutEllipseAngleDegrees(
    CandidateAngleDegrees - StartAngleDegrees);
  Result := Offset <= SweepAngleDegrees + 0.0001;
end;

procedure IncludeEllipsePoint(var Bounds: TRectF; var HasPoint: Boolean;
  const Point: TPointF);
begin
  if not HasPoint then
  begin
    Bounds := TRectF.Create(Point, Point);
    HasPoint := True;
    Exit;
  end;
  Bounds.Left := Min(Bounds.Left, Point.X);
  Bounds.Top := Min(Bounds.Top, Point.Y);
  Bounds.Right := Max(Bounds.Right, Point.X);
  Bounds.Bottom := Max(Bounds.Bottom, Point.Y);
end;

function ScreenLayoutArcBounds(const Bounds: TRectF; RotationDegrees,
  StartAngleDegrees, SweepAngleDegrees: Single): TRectF;
var
  CandidateAngles: array[0..5] of Single;
  Cosine: Extended;
  HasPoint: Boolean;
  I: Integer;
  Radii: TPointF;
  RotationRadians: Extended;
  Sine: Extended;
begin
  SweepAngleDegrees := EnsureRange(SweepAngleDegrees, 0.0, 360.0);
  Radii := ScreenLayoutEllipseRadii(Bounds);
  RotationRadians := DegToRad(RotationDegrees);
  SinCos(RotationRadians, Sine, Cosine);
  CandidateAngles[0] := StartAngleDegrees;
  CandidateAngles[1] := StartAngleDegrees + SweepAngleDegrees;
  CandidateAngles[2] := RadToDeg(ArcTan2(-Radii.Y * Sine,
    Radii.X * Cosine));
  CandidateAngles[3] := CandidateAngles[2] + 180.0;
  CandidateAngles[4] := RadToDeg(ArcTan2(Radii.Y * Cosine,
    Radii.X * Sine));
  CandidateAngles[5] := CandidateAngles[4] + 180.0;
  HasPoint := False;
  Result := TRectF.Empty;
  for I := Low(CandidateAngles) to High(CandidateAngles) do
    if (I < 2) or ScreenLayoutAngleInArc(StartAngleDegrees,
      SweepAngleDegrees, CandidateAngles[I]) then
      IncludeEllipsePoint(Result, HasPoint, ScreenLayoutEllipsePoint(Bounds,
        RotationDegrees, CandidateAngles[I]));
end;

function ScreenLayoutEllipseBounds(const Bounds: TRectF;
  RotationDegrees: Single): TRectF;
begin
  Result := ScreenLayoutArcBounds(Bounds, RotationDegrees, 0.0, 360.0);
end;

function ScreenLayoutArcEndPoint(const Bounds: TRectF; RotationDegrees,
  StartAngleDegrees, SweepAngleDegrees: Single): TPointF;
begin
  Result := ScreenLayoutEllipsePoint(Bounds, RotationDegrees,
    StartAngleDegrees + EnsureRange(SweepAngleDegrees, 0.0, 360.0));
end;

end.
