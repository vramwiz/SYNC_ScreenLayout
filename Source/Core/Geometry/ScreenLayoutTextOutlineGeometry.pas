// Skiaの字形アウトラインを文字レイヤーの表示座標へ変換し、編集可能なShapeデータを生成する。
unit ScreenLayoutTextOutlineGeometry;

interface

uses
  ScreenLayoutDocument;

// 表示行、配置、字間、枠内スケール、回転を反映した字形ごとの閉じたShapeデータを返す。
function BuildScreenLayoutTextOutlineShapes(
  Source: TScreenLayoutTextLayer): TArray<TScreenLayoutShapeData>;

implementation

uses
  System.Generics.Collections, System.Math, System.Skia, System.SysUtils,
  System.Types, ScreenLayoutGeometry, ScreenLayoutShapeBooleanGeometry,
  ScreenLayoutTextGeometry;

function HorizontalAlignmentOffset(Alignment: TScreenLayoutTextAlignment;
  LayoutWidth, TextWidth: Single): Single;
begin
  case Ord(Alignment) mod 3 of
    1: Result := (LayoutWidth - TextWidth) * 0.5;
    2: Result := LayoutWidth - TextWidth;
  else
    Result := 0;
  end;
end;

function TransformTextPoint(Source: TScreenLayoutTextLayer;
  const Layout: TScreenLayoutTextLayout; const Point: TPointF): TPointF;
var
  Center: TPointF;
begin
  Result := TPointF.Create(Source.Bounds.Left +
    Point.X * Source.Bounds.Width / Layout.Width, Source.Bounds.Top +
    Point.Y * Source.Bounds.Height / Layout.Height);
  Center := TPointF.Create(
    (Source.Bounds.Left + Source.Bounds.Right) * 0.5,
    (Source.Bounds.Top + Source.Bounds.Bottom) * 0.5);
  Result := RotatePointAround(Result, Center, Source.RotationDegrees);
end;

procedure TransformContourVertices(Source: TScreenLayoutTextLayer;
  const Layout: TScreenLayoutTextLayout; OffsetX, OffsetY: Single;
  var Contours: TArray<TScreenLayoutContour>);
var
  IncomingPoint: TPointF;
  I: Integer;
  J: Integer;
  OldPosition: TPointF;
  OutgoingPoint: TPointF;
  Position: TPointF;
begin
  for I := 0 to High(Contours) do
    for J := 0 to High(Contours[I].Vertices) do
    begin
      OldPosition := Contours[I].Vertices[J].Position;
      IncomingPoint := TPointF.Create(OldPosition.X +
        Contours[I].Vertices[J].IncomingControl.X + OffsetX,
        OldPosition.Y + Contours[I].Vertices[J].IncomingControl.Y + OffsetY);
      OutgoingPoint := TPointF.Create(OldPosition.X +
        Contours[I].Vertices[J].OutgoingControl.X + OffsetX,
        OldPosition.Y + Contours[I].Vertices[J].OutgoingControl.Y + OffsetY);
      Position := TransformTextPoint(Source, Layout, TPointF.Create(
        OldPosition.X + OffsetX, OldPosition.Y + OffsetY));
      IncomingPoint := TransformTextPoint(Source, Layout, IncomingPoint);
      OutgoingPoint := TransformTextPoint(Source, Layout, OutgoingPoint);
      Contours[I].Vertices[J].Position := Position;
      Contours[I].Vertices[J].IncomingControl := TPointF.Create(
        IncomingPoint.X - Position.X, IncomingPoint.Y - Position.Y);
      Contours[I].Vertices[J].OutgoingControl := TPointF.Create(
        OutgoingPoint.X - Position.X, OutgoingPoint.Y - Position.Y);
    end;
end;

function AppendGlyphShape(Shapes: TList<TScreenLayoutShapeData>;
  Source: TScreenLayoutTextLayer; const Layout: TScreenLayoutTextLayout;
  const Font: ISkFont; Glyph: Word; X, BaselineY: Single;
  AllowMissingOutline: Boolean): Boolean;
var
  Contours: TArray<TScreenLayoutContour>;
  Data: TScreenLayoutShapeData;
  Path: ISkPath;
begin
  Result := AllowMissingOutline;
  Path := Font.GetPath(Glyph);
  if (Path = nil) or Path.IsEmpty then
    Exit;
  Contours := ConvertSkPathToScreenLayoutShapeContours(Path);
  if Length(Contours) = 0 then
    Exit;
  TransformContourVertices(Source, Layout, X, BaselineY, Contours);
  Data := Default(TScreenLayoutShapeData);
  Data.Contours := Contours;
  Data.FillColor := Source.FillColor;
  Data.FillRule := slfrEvenOdd;
  Data.Locked := Source.Locked;
  Data.Name := Format('%s %d', [Source.Name, Shapes.Count + 1]);
  Data.Opacity := Source.Opacity;
  Data.StrokeColor := Source.FillColor;
  Data.StrokeStyle := vssSolid;
  Data.StrokeWidth := 0;
  Data.Visible := Source.Visible;
  Shapes.Add(Data);
  Result := True;
end;

function AppendGlyphRun(Shapes: TList<TScreenLayoutShapeData>;
  Source: TScreenLayoutTextLayer; const Layout: TScreenLayoutTextLayout;
  const Font: ISkFont; const Text: string; X, BaselineY: Single;
  AllowMissingOutline: Boolean): Boolean;
var
  Glyphs: TArray<Word>;
  I: Integer;
  Positions: TArray<TPointF>;
begin
  Result := AllowMissingOutline;
  Glyphs := Font.GetGlyphs(Text);
  Positions := Font.GetPositions(Glyphs);
  for I := 0 to Min(High(Glyphs), High(Positions)) do
    if not AppendGlyphShape(Shapes, Source, Layout, Font, Glyphs[I],
      X + Positions[I].X, BaselineY + Positions[I].Y,
      AllowMissingOutline) then
      Exit(False);
  if Length(Glyphs) > 0 then
    Result := True;
end;

function BuildScreenLayoutTextOutlineShapes(
  Source: TScreenLayoutTextLayer): TArray<TScreenLayoutShapeData>;
var
  BaselineY: Single;
  CharacterIndex: Integer;
  CharacterLength: Integer;
  Font: ISkFont;
  GapIndex: Integer;
  I: Integer;
  IndividualLetterSpacingRatios: TArray<Single>;
  Layout: TScreenLayoutTextLayout;
  LetterSpacing: Single;
  LineText: string;
  Shapes: TList<TScreenLayoutShapeData>;
  TextWidth: Single;
  UnitText: string;
  X: Single;
begin
  Result := nil;
  if (Source = nil) or (Source.Text = '') then
    Exit;
  Layout := BuildScreenLayoutTextLayout(Source.Text, Source.FontFamily,
    Source.FontSize, Source.WrapWidth, Source.FontStyle,
    Source.LetterSpacingRatio, Source.LineSpacingRatio,
    Source.IndividualLetterSpacingRatios);
  if (Layout.Width <= 0) or (Layout.Height <= 0) then
    Exit;
  Font := CreateScreenLayoutTextFont(Source.FontFamily, Source.FontSize,
    Source.FontStyle);
  LetterSpacing := Source.FontSize * Source.LetterSpacingRatio;
  IndividualLetterSpacingRatios := Source.IndividualLetterSpacingRatios;
  Shapes := TList<TScreenLayoutShapeData>.Create;
  try
    for I := 0 to High(Layout.Lines) do
    begin
      LineText := Layout.Lines[I];
      GapIndex := Layout.LineGapOffsets[I];
      TextWidth := MeasureScreenLayoutText(LineText, Font, LetterSpacing,
        Source.FontSize, IndividualLetterSpacingRatios, GapIndex);
      X := HorizontalAlignmentOffset(Source.Alignment, Layout.Width,
        TextWidth);
      BaselineY := Layout.Ascent + I * Layout.LineHeight;
      CharacterIndex := 1;
      while CharacterIndex <= Length(LineText) do
      begin
        CharacterLength := ScreenLayoutTextUnitLengthAt(LineText,
          CharacterIndex);
        UnitText := Copy(LineText, CharacterIndex, CharacterLength);
        if not AppendGlyphRun(Shapes, Source, Layout, Font, UnitText, X,
          BaselineY, Trim(UnitText) = '') then
        begin
          Shapes.Clear;
          Exit(nil);
        end;
        X := X + Font.MeasureText(UnitText);
        Inc(CharacterIndex, CharacterLength);
        if CharacterIndex <= Length(LineText) then
        begin
          X := X + LetterSpacing;
          if (GapIndex >= 0) and
            (GapIndex < Length(IndividualLetterSpacingRatios)) then
            X := X + Source.FontSize *
              IndividualLetterSpacingRatios[GapIndex];
          Inc(GapIndex);
        end;
      end;
    end;
    Result := Shapes.ToArray;
  finally
    Shapes.Free;
  end;
end;

end.
