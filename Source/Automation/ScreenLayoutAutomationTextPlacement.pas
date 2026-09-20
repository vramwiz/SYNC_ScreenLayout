// 通常文字の実表示倍率・行配置の計測と、未適用Document上での枠フィットを担当する。
unit ScreenLayoutAutomationTextPlacement;

interface

uses System.JSON, ScreenLayoutDocument;

// 枠、個別字間、反転、回転、射影変形を反映した行セル四隅を返す。効果は含まない。
function MeasureAutomationTextLayer(Document: TVectArtDocument; Request: TJSONObject): TJSONObject;
// 呼出側所有の一時Documentだけを変更する。文字サイズ・字間・行間は維持する。
function FitAutomationText(Document: TVectArtDocument; Request: TJSONObject): TJSONObject;

implementation

uses System.SysUtils, System.Types, System.Math, System.Skia,
  ScreenLayoutAutomationArguments, ScreenLayoutTextGeometry, ScreenLayoutGeometry;

function ResolveText(Document: TVectArtDocument; Request: TJSONObject;
  out Visible, Locked: Boolean): TScreenLayoutTextLayer;
var Layer: TVectArtLayer;
begin
  Layer := AutomationLayer(Document, AutomationString(Request, 'layer_path', ''), Visible, Locked);
  if not (Layer is TScreenLayoutTextLayer) or (Layer is TScreenLayoutTextPathLayer) then
    raise EArgumentException.Create('layer_path must identify normal horizontal text.');
  Result := TScreenLayoutTextLayer(Layer);
end;

function TextLayout(Layer: TScreenLayoutTextLayer): TScreenLayoutTextLayout;
begin
  Result := BuildScreenLayoutTextLayout(Layer.Text, Layer.FontFamily, Layer.FontSize,
    Layer.WrapWidth, Layer.FontStyle, Layer.LetterSpacingRatio, Layer.LineSpacingRatio,
    Layer.IndividualLetterSpacingRatios);
end;

function DisplayPoint(Layer: TScreenLayoutTextLayer; X, Y, SX, SY: Single): TJSONObject;
var P, Center: TPointF;
begin
  P := TPointF.Create(Layer.Bounds.Left + X * SX, Layer.Bounds.Top + Y * SY);
  Center := Layer.Bounds.CenterPoint;
  if Layer.FlipHorizontal then P.X := 2 * Center.X - P.X;
  if Layer.FlipVertical then P.Y := 2 * Center.Y - P.Y;
  P := Layer.Transform.Map(RotatePointAround(P, Center, Layer.RotationDegrees));
  Result := TJSONObject.Create;
  Result.AddPair('x', TJSONNumber.Create(P.X));
  Result.AddPair('y', TJSONNumber.Create(P.Y));
end;

function MeasureAutomationTextLayer(Document: TVectArtDocument; Request: TJSONObject): TJSONObject;
var
  Layer: TScreenLayoutTextLayer;
  Layout: TScreenLayoutTextLayout;
  Font: ISkFont;
  Visible, Locked: Boolean;
  SX, SY, X, Y, Width: Single;
  I: Integer;
  Lines, Quad: TJSONArray;
  Line: TJSONObject;
begin
  Layer := ResolveText(Document, Request, Visible, Locked);
  Layout := TextLayout(Layer);
  Font := CreateScreenLayoutTextFont(Layer.FontFamily, Layer.FontSize, Layer.FontStyle);
  SX := 0;
  SY := 0;
  if Layout.Width > 0 then SX := Layer.Bounds.Width / Layout.Width;
  if Layout.Height > 0 then SY := Layer.Bounds.Height / Layout.Height;
  Result := TJSONObject.Create;
  try
    Result.AddPair('measurement_kind', 'transformed_line_cells');
    Result.AddPair('effects_included', TJSONBool.Create(False));
    Result.AddPair('visible', TJSONBool.Create(Visible));
    Result.AddPair('locked', TJSONBool.Create(Locked));
    Result.AddPair('font_family_requested', Layer.FontFamily);
    Result.AddPair('font_family_resolved', Font.Typeface.FamilyName);
    Result.AddPair('layout_width', TJSONNumber.Create(Layout.Width));
    Result.AddPair('layout_height', TJSONNumber.Create(Layout.Height));
    Result.AddPair('scale_x', TJSONNumber.Create(SX));
    Result.AddPair('scale_y', TJSONNumber.Create(SY));
    Result.AddPair('frame', AutomationRectJson(Layer.Bounds));
    Result.AddPair('line_count', TJSONNumber.Create(Length(Layout.Lines)));
    Lines := TJSONArray.Create;
    Result.AddPair('lines', Lines);
    for I := 0 to High(Layout.Lines) do
    begin
      Width := MeasureScreenLayoutText(Layout.Lines[I], Font,
        Layer.FontSize * Layer.LetterSpacingRatio, Layer.FontSize,
        Layer.IndividualLetterSpacingRatios, Layout.LineGapOffsets[I]);
      X := 0;
      case Ord(Layer.Alignment) mod 3 of
        1: X := (Layout.Width - Width) * 0.5;
        2: X := Layout.Width - Width;
      end;
      Y := I * Layout.LineHeight;
      Line := TJSONObject.Create;
      Lines.AddElement(Line);
      Line.AddPair('text', Layout.Lines[I]);
      Line.AddPair('layout_width', TJSONNumber.Create(Width));
      Line.AddPair('baseline_start', DisplayPoint(Layer, X, Layout.Ascent + Y, SX, SY));
      Quad := TJSONArray.Create;
      Line.AddPair('cell_quad', Quad);
      Quad.AddElement(DisplayPoint(Layer, X, Y, SX, SY));
      Quad.AddElement(DisplayPoint(Layer, X + Width, Y, SX, SY));
      Quad.AddElement(DisplayPoint(Layer, X + Width, Y + Layout.LineHeight, SX, SY));
      Quad.AddElement(DisplayPoint(Layer, X, Y + Layout.LineHeight, SX, SY));
    end;
  except
    Result.Free;
    raise;
  end;
end;

function FitAutomationText(Document: TVectArtDocument; Request: TJSONObject): TJSONObject;
const
  ALIGNMENTS: array[0..8] of string = ('topLeft', 'topCenter', 'topRight',
    'middleLeft', 'middleCenter', 'middleRight', 'bottomLeft', 'bottomCenter', 'bottomRight');
var
  Layer: TScreenLayoutTextLayer;
  Layout: TScreenLayoutTextLayout;
  Target: TRectF;
  Visible, Locked: Boolean;
  Margin, Scale, W, H, X, Y: Single;
  Mode, Alignment: string;
  I, AlignIndex: Integer;
begin
  Layer := ResolveText(Document, Request, Visible, Locked);
  if Locked then raise EArgumentException.Create('Cannot fit locked text or a locked group child.');
  if not Layer.Transform.IsIdentity or not SameValue(Layer.RotationDegrees, 0) then
    raise EArgumentException.Create('fit_text requires unrotated text with identity transform.');
  Target := AutomationRect(Request.GetValue('target_bounds'));
  Margin := AutomationNumber(Request, 'margin', 0, 0, 10000);
  Target.Inflate(-Margin, -Margin);
  if (Target.Width <= 0) or (Target.Height <= 0) then
    raise EArgumentException.Create('margin consumes the target rectangle.');
  Mode := AutomationString(Request, 'fit_mode', 'uniform');
  if (Mode <> 'uniform') and (Mode <> 'frame') then
    raise EArgumentException.Create('fit_mode must be uniform or frame.');
  Alignment := AutomationString(Request, 'alignment', ALIGNMENTS[Ord(Layer.Alignment)]);
  AlignIndex := -1;
  for I := 0 to 8 do
    if Alignment = ALIGNMENTS[I] then AlignIndex := I;
  if AlignIndex < 0 then raise EArgumentException.Create('Unknown alignment.');
  Layer.WrapWidth := AutomationNumber(Request, 'wrap_width', Layer.WrapWidth, 0, 100000);
  Layout := TextLayout(Layer);
  if (Layout.Width <= 0) or (Layout.Height <= 0) then
    raise EArgumentException.Create('Cannot fit empty or zero-width text.');
  W := Target.Width;
  H := Target.Height;
  if Mode = 'uniform' then
  begin
    Scale := Min(W / Layout.Width, H / Layout.Height);
    W := Layout.Width * Scale;
    H := Layout.Height * Scale;
    Layer.TransformMode := slttmUniformScale;
  end
  else
    Layer.TransformMode := slttmFrameFit;
  X := Target.Left + (Target.Width - W) * (AlignIndex mod 3) / 2;
  Y := Target.Top + (Target.Height - H) * (AlignIndex div 3) / 2;
  Layer.Alignment := TScreenLayoutTextAlignment(AlignIndex);
  Layer.Bounds := TRectF.Create(X, Y, X + W, Y + H);
  Result := MeasureAutomationTextLayer(Document, Request);
  Result.AddPair('fit_mode', Mode);
  Result.AddPair('effects_fitted', TJSONBool.Create(False));
  Result.AddPair('target_bounds', AutomationRectJson(Target));
end;

end.
