// Rectangle Documentを標準SVGへ可逆保存し、対応するSVGのキャンバスと四角形を復元する。
// 標準属性を描画情報の正本とし、SVGに表現できない編集情報だけをvad名前空間へ保持する。
// Rectangle、Line、Path、Imageを扱い、読込後は標準編集モードを選択する。
unit VectArtDesignerSvgDocument;

interface

uses
  VectArtDesignerDocument;

// DocumentをUTF-8で保存可能なSVG文字列へ変換する。Documentを所有しない。
function TryCreateVectArtSvg(Document: TVectArtDocument; out SvgText,
  ErrorMessage: string): Boolean;
// SVG文字列から対応内容をDocumentへ適用し、標準編集モードにする。Documentを所有しない。
function TryLoadVectArtDocumentFromSvg(const SvgText: string;
  Document: TVectArtDocument; out ErrorMessage: string): Boolean;
// SVGファイルを読み、対応内容をDocumentへ適用する。例外を呼び出し側へ漏らさない。
function TryLoadVectArtDocumentFromSvgFile(const FileName: string;
  Document: TVectArtDocument; out ErrorMessage: string): Boolean;
// 同じフォルダーの一時ファイルを置換してUTF-8 BOMなしのSVGを保存する。失敗時は既存ファイルを維持する。
function TrySaveVectArtDocumentToSvgFile(Document: TVectArtDocument;
  const FileName: string; out ErrorMessage: string): Boolean;

implementation

uses
  System.Classes, System.Generics.Collections, System.IOUtils, System.Math,
  System.NetEncoding, System.SysUtils, System.Types, System.Variants,
  Vcl.Graphics, Vcl.Imaging.pngimage, Winapi.Windows,
  VectArtDesignerGeometry, Xml.omnixmldom, Xml.XMLDoc, Xml.XMLIntf,
  Xml.xmldom;

const
  SVG_NAMESPACE = 'http://www.w3.org/2000/svg';
  VAD_NAMESPACE = 'urn:vectartdesigner:document:1';
  VAD_FORMAT_VERSION = 1;

type
  TSvgAffineMatrix = record
    A: Single;
    B: Single;
    C: Single;
    D: Single;
    E: Single;
    F: Single;
  end;
  TSvgInheritedStyles = TDictionary<string, string>;

const
  SVG_INHERITED_STYLE_NAMES: array[0..8] of string = (
    'fill', 'stroke', 'stroke-width', 'stroke-dasharray',
    'stroke-linecap', 'stroke-linejoin', 'fill-opacity',
    'stroke-opacity', 'shape-rendering');

function SvgIdentityMatrix: TSvgAffineMatrix;
begin
  Result.A := 1;
  Result.B := 0;
  Result.C := 0;
  Result.D := 1;
  Result.E := 0;
  Result.F := 0;
end;

function MultiplySvgMatrices(const Left, Right: TSvgAffineMatrix):
  TSvgAffineMatrix;
begin
  Result.A := Left.A * Right.A + Left.C * Right.B;
  Result.B := Left.B * Right.A + Left.D * Right.B;
  Result.C := Left.A * Right.C + Left.C * Right.D;
  Result.D := Left.B * Right.C + Left.D * Right.D;
  Result.E := Left.A * Right.E + Left.C * Right.F + Left.E;
  Result.F := Left.B * Right.E + Left.D * Right.F + Left.F;
end;

function SvgTransformPoint(const Matrix: TSvgAffineMatrix;
  const Point: TPointF): TPointF;
begin
  Result := PointF(Matrix.A * Point.X + Matrix.C * Point.Y + Matrix.E,
    Matrix.B * Point.X + Matrix.D * Point.Y + Matrix.F);
end;

function SvgStrokeScale(const Matrix: TSvgAffineMatrix): Single;
begin
  Result := (Hypot(Matrix.A, Matrix.B) +
    Hypot(Matrix.C, Matrix.D)) * 0.5;
end;

function XmlEscape(const Value: string): string;
begin
  Result := StringReplace(Value, '&', '&amp;', [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '&quot;', [rfReplaceAll]);
  Result := StringReplace(Result, '''', '&apos;', [rfReplaceAll]);
end;

function SvgNumber(Value: Single): string;
var
  FormatSettings: TFormatSettings;
begin
  FormatSettings := TFormatSettings.Create;
  FormatSettings.DecimalSeparator := '.';
  FormatSettings.ThousandSeparator := #0;
  Result := FloatToStrF(Value, ffGeneral, 9, 0, FormatSettings);
end;

function SvgColor(Value: TColor): string;
var
  RgbColor: TColor;
begin
  RgbColor := ColorToRGB(Value);
  Result := Format('#%.2x%.2x%.2x', [GetRValue(RgbColor),
    GetGValue(RgbColor), GetBValue(RgbColor)]);
end;

function BooleanText(Value: Boolean): string;
begin
  if Value then
    Result := 'true'
  else
    Result := 'false';
end;

function IsDecodablePng(const Data: TBytes): Boolean;
var
  Image: TPngImage;
  Stream: TBytesStream;
begin
  Result := False;
  if Length(Data) = 0 then
    Exit;
  Image := TPngImage.Create;
  Stream := TBytesStream.Create(Data);
  try
    try
      Image.LoadFromStream(Stream);
      Result := (Image.Width > 0) and (Image.Height > 0);
    except
      on Exception do
        Result := False;
    end;
  finally
    Stream.Free;
    Image.Free;
  end;
end;

function SvgLineCap(Value: TVectArtLineCap): string;
begin
  case Value of
    vlcSquare: Result := 'square';
    vlcRound: Result := 'round';
  else
    Result := 'butt';
  end;
end;

function SvgLineJoin(Value: TVectArtLineJoin): string;
begin
  case Value of
    vljBevel: Result := 'bevel';
    vljRound: Result := 'round';
  else
    Result := 'miter';
  end;
end;

function MifLineMarkerName(Value: TVectArtMifLineMarker): string;
begin
  case Value of
    vlmArrow: Result := 'arrow';
    vlmOpenArrow: Result := 'open-arrow';
    vlmWideArrow: Result := 'wide-arrow';
    vlmCircle: Result := 'circle';
    vlmDiamond: Result := 'diamond';
    vlmConcaveArrow: Result := 'concave-arrow';
    vlmSmallArrow: Result := 'small-arrow';
    vlmSlash: Result := 'slash';
    vlmStar: Result := 'star';
  else
    Result := 'none';
  end;
end;

function TryParseMifLineMarkerName(const Value: string;
  out Marker: TVectArtMifLineMarker): Boolean;
var
  Candidate: TVectArtMifLineMarker;
begin
  for Candidate := Low(TVectArtMifLineMarker) to High(TVectArtMifLineMarker) do
    if SameText(Trim(Value), MifLineMarkerName(Candidate)) then
    begin
      Marker := Candidate;
      Exit(True);
    end;
  Result := False;
end;

function SvgMifMarkerBody(Value: TVectArtMifLineMarker; MarkerSize: Single): string;
var
  OutlineWidth: string;
begin
  OutlineWidth := SvgNumber(6.0 / Max(MarkerSize, 1.0));
  case Value of
    vlmOpenArrow:
      Result := '<path d="M 0 0 L 4 2 L 0 4" fill="none" stroke="context-stroke" stroke-width="' +
        OutlineWidth + '"/>';
    vlmArrow:
      Result := '<path d="M 0 0 L 4 2 L 0 4 z" fill="context-stroke"/>';
    vlmWideArrow:
      Result := '<path d="M 0 -0.5 L 4 2 L 0 4.5 z" fill="context-stroke"/>';
    vlmCircle:
      Result := '<circle cx="2" cy="2" r="2" fill="context-stroke"/>';
    vlmDiamond:
      Result := '<path d="M 0 2 L 2 0 L 4 2 L 2 4 z" fill="context-stroke"/>';
    vlmConcaveArrow:
      Result := '<path d="M 0 0 L 4 2 L 0 4 L 1.4 2 z" fill="context-stroke"/>';
    vlmSmallArrow:
      Result := '<path d="M 1 1 L 4 2 L 1 3 z" fill="context-stroke"/>';
    vlmSlash:
      Result := '<path d="M 2 0 L 2 4" fill="none" stroke="context-stroke" stroke-width="' +
        OutlineWidth + '"/>';
    vlmStar:
      Result := '<path d="M 4 2 L 2.65 2.47 L 2.62 3.9 L 1.75 2.76 L 0.38 3.18 L 1.2 2 L 0.38 0.82 L 1.75 1.24 L 2.62 0.1 L 2.65 1.53 z" fill="context-stroke"/>';
  else
    Result := '';
  end;
end;

procedure AppendSvgStroke(Builder: TStringBuilder; Color: TColor;
  Width: Single; Style: TVectArtMifStrokeStyle);
var
  DashIndex: Integer;
  DashIntervals: TArray<Single>;
begin
  if Width <= 0 then
  begin
    Builder.Append(' stroke="none"');
    Exit;
  end;
  Builder.Append(' stroke="').Append(SvgColor(Color))
    .Append('" stroke-width="').Append(SvgNumber(Width))
    .Append('" vad:stroke-color="').Append(Integer(Color))
    .Append('" vad:stroke-style="').Append(Ord(Style)).Append('"');
  DashIntervals := VectArtStrokeDashIntervals(Style, Width);
  if Length(DashIntervals) = 0 then
    Exit;
  Builder.Append(' stroke-dasharray="');
  for DashIndex := 0 to High(DashIntervals) do
  begin
    if DashIndex > 0 then
      Builder.Append(' ');
    Builder.Append(SvgNumber(DashIntervals[DashIndex]));
  end;
  Builder.Append('"');
end;

function TryCreateVectArtSvg(Document: TVectArtDocument; out SvgText,
  ErrorMessage: string): Boolean;
var
  Builder: TStringBuilder;
  Canvas: TVectArtCanvasLayer;
  I: Integer;
  Image: TVectArtImageLayer;
  Layer: TVectArtLayer;
  Line: TVectArtLineLayer;
  Path: TVectArtPathLayer;
  PointIndex: Integer;
  Rectangle: TVectArtRectangleLayer;
begin
  Result := False;
  SvgText := '';
  ErrorMessage := '';
  Builder := nil;
  try
    try
      if Document = nil then
        raise EArgumentNilException.Create('Document');
      Canvas := Document.CanvasLayer;
      if Canvas = nil then
        raise EInvalidOp.Create('Document canvas is missing');
      Builder := TStringBuilder.Create;
      Builder.AppendLine('<?xml version="1.0" encoding="UTF-8"?>');
      Builder.Append('<svg xmlns="').Append(SVG_NAMESPACE)
        .Append('" xmlns:vad="').Append(VAD_NAMESPACE).Append('"')
        .Append(' width="').Append(Canvas.Width).Append('"')
        .Append(' height="').Append(Canvas.Height).Append('"')
        .Append(' viewBox="0 0 ').Append(Canvas.Width).Append(' ')
        .Append(Canvas.Height).Append('"')
        .Append(' vad:version="').Append(VAD_FORMAT_VERSION).Append('"')
        .Append(' vad:background-color="')
        .Append(Integer(Canvas.BackgroundColor)).Append('"')
        .Append(' vad:transparent="').Append(BooleanText(Canvas.Transparent))
        .Append('" vad:selected-index="').Append(Document.SelectedIndex)
        .Append('"');
      if not Canvas.Transparent then
        Builder.Append(' style="background-color:')
          .Append(SvgColor(Canvas.BackgroundColor)).Append('"');
      Builder.AppendLine('>');
      Builder.AppendLine('  <defs>');
      for I := 1 to Document.LayerCount - 1 do
        if Document[I] is TVectArtLineLayer then
        begin
          Line := TVectArtLineLayer(Document[I]);
          if Line.MifEndMarker <> vlmNone then
            Builder.Append('    <marker id="vad-end-marker-').Append(I)
              .Append('" markerWidth="').Append(SvgNumber(Line.MifEndMarkerSize))
              .Append('" markerHeight="').Append(SvgNumber(Line.MifEndMarkerSize))
              .Append('" refX="4" refY="2" viewBox="-1 -1 6 6" orient="auto" markerUnits="strokeWidth">')
              .Append(SvgMifMarkerBody(Line.MifEndMarker, Line.MifEndMarkerSize))
              .AppendLine('</marker>');
          if Line.MifStartMarker <> vlmNone then
            Builder.Append('    <marker id="vad-start-marker-').Append(I)
              .Append('" markerWidth="').Append(SvgNumber(Line.MifStartMarkerSize))
              .Append('" markerHeight="').Append(SvgNumber(Line.MifStartMarkerSize))
              .Append('" refX="4" refY="2" viewBox="-1 -1 6 6" orient="auto-start-reverse" markerUnits="strokeWidth">')
              .Append(SvgMifMarkerBody(Line.MifStartMarker, Line.MifStartMarkerSize))
              .AppendLine('</marker>');
        end;
      Builder.AppendLine('  </defs>');
      for I := 1 to Document.LayerCount - 1 do
      begin
        Layer := Document[I];
        if Layer is TVectArtImageLayer then
        begin
          Image := TVectArtImageLayer(Layer);
          if not IsDecodablePng(Image.PngData) then
            raise EConvertError.CreateFmt(
              'Image layer "%s" does not contain a valid PNG',
              [Image.Name]);
          Builder.Append('  <image x="0" y="0" width="1" height="1"')
            .Append(' preserveAspectRatio="none" href="data:image/png;base64,')
            .Append(TNetEncoding.Base64.EncodeBytesToString(Image.PngData))
            .Append('" transform="matrix(')
            .Append(SvgNumber(Image.Points[1].X - Image.Points[0].X))
            .Append(' ')
            .Append(SvgNumber(Image.Points[1].Y - Image.Points[0].Y))
            .Append(' ')
            .Append(SvgNumber(Image.Points[3].X - Image.Points[0].X))
            .Append(' ')
            .Append(SvgNumber(Image.Points[3].Y - Image.Points[0].Y))
            .Append(' ').Append(SvgNumber(Image.Points[0].X))
            .Append(' ').Append(SvgNumber(Image.Points[0].Y))
            .Append(')" opacity="').Append(SvgNumber(Image.Opacity))
            .Append('" vad:name="').Append(XmlEscape(Image.Name))
            .Append('" vad:locked="').Append(BooleanText(Image.Locked))
            .Append('" vad:source-kind="');
          if Image.SourceKind = visLogo then
            Builder.Append('logo')
          else
            Builder.Append('image');
          Builder.Append('"');
          if not Image.Visible then
            Builder.Append(' display="none"');
          Builder.Append('><title>').Append(XmlEscape(Image.Name))
            .AppendLine('</title></image>');
          Continue;
        end;
        if Layer is TVectArtLineLayer then
        begin
          Line := TVectArtLineLayer(Layer);
          Builder.Append('  <line x1="').Append(SvgNumber(Line.StartPoint.X))
            .Append('" y1="').Append(SvgNumber(Line.StartPoint.Y))
            .Append('" x2="').Append(SvgNumber(Line.EndPoint.X))
            .Append('" y2="').Append(SvgNumber(Line.EndPoint.Y))
            .Append('" fill="none"');
          AppendSvgStroke(Builder, Line.StrokeColor, Line.StrokeWidth,
            Line.MifStrokeStyle);
          Builder.Append(' opacity="').Append(SvgNumber(Line.Opacity))
            .Append('" stroke-linecap="')
            .Append(SvgLineCap(Line.LineCap)).Append('" stroke-linejoin="')
            .Append(SvgLineJoin(Line.LineJoin)).Append('" vad:name="')
            .Append(XmlEscape(Line.Name)).Append('" vad:locked="')
            .Append(BooleanText(Line.Locked)).Append('"');
          if not Line.MifAntiAlias then
            Builder.Append(' shape-rendering="crispEdges"');
          if Line.MifEndMarker <> vlmNone then
            Builder.Append(' marker-end="url(#vad-end-marker-').Append(I)
              .Append(')" vad:end-marker="').Append(MifLineMarkerName(Line.MifEndMarker))
              .Append('" vad:end-marker-size="')
              .Append(SvgNumber(Line.MifEndMarkerSize)).Append('"');
          if Line.MifStartMarker <> vlmNone then
            Builder.Append(' marker-start="url(#vad-start-marker-').Append(I)
              .Append(')" vad:start-marker="').Append(MifLineMarkerName(Line.MifStartMarker))
              .Append('" vad:start-marker-size="')
              .Append(SvgNumber(Line.MifStartMarkerSize)).Append('"');
          if not Line.Visible then
            Builder.Append(' display="none"');
          Builder.Append('><title>').Append(XmlEscape(Line.Name))
            .AppendLine('</title></line>');
          Continue;
        end;
        if Layer is TVectArtPathLayer then
        begin
          Path := TVectArtPathLayer(Layer);
          if Path.Closed then
            Builder.Append('  <polygon points="')
          else
            Builder.Append('  <polyline points="');
          for PointIndex := 0 to High(Path.Points) do
          begin
            if PointIndex > 0 then
              Builder.Append(' ');
            Builder.Append(SvgNumber(Path.Points[PointIndex].X)).Append(',')
              .Append(SvgNumber(Path.Points[PointIndex].Y));
          end;
          Builder.Append('" fill="');
          if Path.Filled and Path.Closed then
            Builder.Append(SvgColor(Path.FillColor))
          else
            Builder.Append('none');
          Builder.Append('"');
          AppendSvgStroke(Builder, Path.StrokeColor, Path.StrokeWidth,
            Path.MifStrokeStyle);
          Builder.Append(' stroke-linecap="').Append(SvgLineCap(Path.LineCap))
            .Append('" stroke-linejoin="').Append(SvgLineJoin(Path.LineJoin))
            .Append('"');
          if not Path.MifAntiAlias then
            Builder.Append(' shape-rendering="crispEdges"');
          Builder.Append(' opacity="').Append(SvgNumber(Path.Opacity))
            .Append('" vad:fill-color="').Append(Integer(Path.FillColor))
            .Append('" vad:name="').Append(XmlEscape(Path.Name))
            .Append('" vad:locked="').Append(BooleanText(Path.Locked))
            .Append('"');
          if not Path.Visible then
            Builder.Append(' display="none"');
          if Path.Closed then
            Builder.Append('><title>').Append(XmlEscape(Path.Name))
              .AppendLine('</title></polygon>')
          else
            Builder.Append('><title>').Append(XmlEscape(Path.Name))
              .AppendLine('</title></polyline>');
          Continue;
        end;
        if not (Layer is TVectArtRectangleLayer) then
          Continue;
        Rectangle := TVectArtRectangleLayer(Layer);
        Builder.Append('  <rect x="').Append(SvgNumber(Rectangle.Bounds.Left))
          .Append('" y="').Append(SvgNumber(Rectangle.Bounds.Top))
          .Append('" width="').Append(SvgNumber(Rectangle.Bounds.Width))
          .Append('" height="').Append(SvgNumber(Rectangle.Bounds.Height))
          .Append('" fill="').Append(SvgColor(Rectangle.FillColor))
          .Append('" opacity="').Append(SvgNumber(Rectangle.Opacity))
          .Append('" vad:fill-color="')
          .Append(Integer(Rectangle.FillColor))
          .Append('"');
        AppendSvgStroke(Builder, Rectangle.StrokeColor,
          Rectangle.StrokeWidth, Rectangle.MifStrokeStyle);
        Builder
          .Append(' vad:name="').Append(XmlEscape(Rectangle.Name))
          .Append('" vad:locked="').Append(BooleanText(Rectangle.Locked))
          .Append('"');
        if not SameValue(Rectangle.RotationDegrees, 0.0) then
          Builder.Append(' transform="rotate(')
            .Append(SvgNumber(Rectangle.RotationDegrees)).Append(' ')
            .Append(SvgNumber((Rectangle.Bounds.Left +
              Rectangle.Bounds.Right) * 0.5)).Append(' ')
            .Append(SvgNumber((Rectangle.Bounds.Top +
              Rectangle.Bounds.Bottom) * 0.5)).Append(')"');
        if not Rectangle.Visible then
          Builder.Append(' display="none"');
        Builder.Append('><title>').Append(XmlEscape(Rectangle.Name))
          .AppendLine('</title></rect>');
      end;
      Builder.AppendLine('</svg>');
      SvgText := Builder.ToString;
      Result := True;
    except
      on E: Exception do
        ErrorMessage := E.Message;
    end;
  finally
    Builder.Free;
  end;
end;

function LocalNodeName(const Node: IXMLNode): string;
var
  SeparatorIndex: Integer;
begin
  Result := Node.NodeName;
  SeparatorIndex := Result.IndexOf(':');
  if SeparatorIndex >= 0 then
    Result := Result.Substring(SeparatorIndex + 1);
end;

function TryGetAttribute(const Node: IXMLNode; const Name: string;
  out Value: string): Boolean;
begin
  Result := (Node <> nil) and Node.HasAttribute(Name);
  if Result then
    Value := VarToStr(Node.Attributes[Name])
  else
    Value := '';
end;

function TryGetStyleValue(const Node: IXMLNode; const RequiredName: string;
  out Value: string): Boolean;
var
  I: Integer;
  Name: string;
  Pair: string;
  SeparatorIndex: Integer;
  Style: string;
  Values: TStringList;
begin
  Result := False;
  Value := '';
  if not TryGetAttribute(Node, 'style', Style) then
    Exit;
  Values := TStringList.Create;
  try
    Values.StrictDelimiter := True;
    Values.Delimiter := ';';
    Values.DelimitedText := Style;
    for I := 0 to Values.Count - 1 do
    begin
      Pair := Values[I];
      SeparatorIndex := Pair.IndexOf(':');
      if SeparatorIndex < 0 then
        Continue;
      Name := Trim(Pair.Substring(0, SeparatorIndex));
      if SameText(Name, RequiredName) then
      begin
        Value := Trim(Pair.Substring(SeparatorIndex + 1));
        Exit(True);
      end;
    end;
  finally
    Values.Free;
  end;
end;

function TryGetPresentationValue(const Node: IXMLNode; const Name: string;
  var Value: string): Boolean;
var
  Candidate: string;
begin
  Result := TryGetStyleValue(Node, Name, Candidate);
  if not Result then
    Result := TryGetAttribute(Node, Name, Candidate);
  if Result then
    Value := Candidate;
end;

function TryGetPresentationValueOrInherited(const Node: IXMLNode;
  InheritedStyles: TSvgInheritedStyles; const Name: string;
  var Value: string): Boolean;
var
  InheritedValue: string;
begin
  Result := TryGetPresentationValue(Node, Name, Value);
  if not Result and (InheritedStyles <> nil) and
    InheritedStyles.TryGetValue(LowerCase(Name), InheritedValue) then
  begin
    Value := InheritedValue;
    Result := True;
  end;
end;

function CreateInheritedStyles(ParentStyles: TSvgInheritedStyles;
  const Node: IXMLNode): TSvgInheritedStyles;
var
  Name: string;
  Pair: TPair<string, string>;
  Value: string;
begin
  Result := TSvgInheritedStyles.Create;
  if ParentStyles <> nil then
    for Pair in ParentStyles do
      Result.AddOrSetValue(Pair.Key, Pair.Value);
  for Name in SVG_INHERITED_STYLE_NAMES do
    if TryGetPresentationValue(Node, Name, Value) then
      Result.AddOrSetValue(Name, Value);
end;

function TryParseSvgNumber(const Text: string; out Value: Single): Boolean;
var
  FormatSettings: TFormatSettings;
  NumberText: string;
begin
  NumberText := Trim(Text);
  if NumberText.EndsWith('px', True) then
    Delete(NumberText, Length(NumberText) - 1, 2);
  FormatSettings := TFormatSettings.Create;
  FormatSettings.DecimalSeparator := '.';
  FormatSettings.ThousandSeparator := #0;
  Result := TryStrToFloat(Trim(NumberText), Value, FormatSettings) and
    not IsNan(Value) and not IsInfinite(Value);
end;

function TryParseBoolean(const Text: string; out Value: Boolean): Boolean;
begin
  Result := SameText(Trim(Text), 'true') or (Trim(Text) = '1') or
    SameText(Trim(Text), 'false') or (Trim(Text) = '0');
  if Result then
    Value := SameText(Trim(Text), 'true') or (Trim(Text) = '1')
  else
    Value := False;
end;

function TryParseHexByte(const Text: string; out Value: Byte): Boolean;
var
  IntegerValue: Integer;
begin
  Result := TryStrToInt('$' + Text, IntegerValue) and
    InRange(IntegerValue, 0, 255);
  if Result then
    Value := Byte(IntegerValue)
  else
    Value := 0;
end;

function TryParseSvgColor(const Text: string; out Value: TColor): Boolean;
var
  B: Byte;
  ColorText: string;
  G: Byte;
  R: Byte;
begin
  ColorText := Trim(Text);
  if SameText(ColorText, 'black') then
  begin
    Value := clBlack;
    Exit(True);
  end;
  if SameText(ColorText, 'white') then
  begin
    Value := clWhite;
    Exit(True);
  end;
  if SameText(ColorText, 'red') then
  begin
    Value := clRed;
    Exit(True);
  end;
  if SameText(ColorText, 'green') then
  begin
    Value := clGreen;
    Exit(True);
  end;
  if SameText(ColorText, 'blue') then
  begin
    Value := clBlue;
    Exit(True);
  end;
  if (Length(ColorText) = 4) and (ColorText[1] = '#') then
    ColorText := '#' + ColorText[2] + ColorText[2] + ColorText[3] +
      ColorText[3] + ColorText[4] + ColorText[4];
  Result := (Length(ColorText) = 7) and (ColorText[1] = '#') and
    TryParseHexByte(Copy(ColorText, 2, 2), R) and
    TryParseHexByte(Copy(ColorText, 4, 2), G) and
    TryParseHexByte(Copy(ColorText, 6, 2), B);
  if Result then
    Value := TColor(RGB(R, G, B))
  else
    Value := clBlack;
end;

function LayerName(const Node: IXMLNode; const KindName: string;
  Index: Integer): string;
var
  Child: IXMLNode;
  I: Integer;
begin
  for I := 0 to Node.ChildNodes.Count - 1 do
  begin
    Child := Node.ChildNodes[I];
    if SameText(LocalNodeName(Child), 'title') and (Trim(Child.Text) <> '') then
      Exit(Child.Text);
  end;
  if TryGetAttribute(Node, 'vad:name', Result) and (Result <> '') then
    Exit;
  if TryGetAttribute(Node, 'id', Result) and (Result <> '') then
    Exit;
  Result := Format('%s %d', [KindName, Index]);
end;

function ImageName(const Node: IXMLNode; Index: Integer): string;
var
  Child: IXMLNode;
  I: Integer;
begin
  for I := 0 to Node.ChildNodes.Count - 1 do
  begin
    Child := Node.ChildNodes[I];
    if SameText(LocalNodeName(Child), 'title') and (Trim(Child.Text) <> '') then
      Exit(Child.Text);
  end;
  if TryGetAttribute(Node, 'vad:name', Result) and (Result <> '') then
    Exit;
  if TryGetAttribute(Node, 'id', Result) and (Result <> '') then
    Exit;
  Result := Format('Image %d', [Index]);
end;

function TryParseSvgMatrix(const Text: string; out A, B, C, D, E,
  F: Single): Boolean;
var
  CloseIndex: Integer;
  I: Integer;
  OpenIndex: Integer;
  Parts: TStringList;
  ValueText: string;
begin
  Result := False;
  ValueText := Trim(Text);
  OpenIndex := ValueText.IndexOf('(');
  CloseIndex := ValueText.LastIndexOf(')');
  if (OpenIndex < 0) or (CloseIndex <= OpenIndex) or
    (Trim(ValueText.Substring(CloseIndex + 1)) <> '') or
    not SameText(Trim(ValueText.Substring(0, OpenIndex)), 'matrix') then
    Exit;
  ValueText := ValueText.Substring(OpenIndex + 1,
    CloseIndex - OpenIndex - 1).Replace(',', ' ');
  Parts := TStringList.Create;
  try
    Parts.StrictDelimiter := True;
    Parts.Delimiter := ' ';
    Parts.DelimitedText := ValueText;
    for I := Parts.Count - 1 downto 0 do
      if Trim(Parts[I]) = '' then
        Parts.Delete(I);
    Result := (Parts.Count = 6) and
      TryParseSvgNumber(Parts[0], A) and
      TryParseSvgNumber(Parts[1], B) and
      TryParseSvgNumber(Parts[2], C) and
      TryParseSvgNumber(Parts[3], D) and
      TryParseSvgNumber(Parts[4], E) and
      TryParseSvgNumber(Parts[5], F);
  finally
    Parts.Free;
  end;
end;

function TransformSvgPoint(const Point: TPointF; A, B, C, D, E,
  F: Single): TPointF;
begin
  Result := TPointF.Create(A * Point.X + C * Point.Y + E,
    B * Point.X + D * Point.Y + F);
end;

function TryDecodePngDataUri(const Uri: string; out Data: TBytes): Boolean;
const
  PNG_DATA_HEADER = 'data:image/png;base64';
var
  CommaIndex: Integer;
  EncodedData: string;
  Header: string;
begin
  Result := False;
  Data := nil;
  CommaIndex := Uri.IndexOf(',');
  if CommaIndex < 0 then
    Exit;
  Header := Trim(Uri.Substring(0, CommaIndex));
  if not SameText(Header, PNG_DATA_HEADER) then
    Exit;
  EncodedData := Uri.Substring(CommaIndex + 1);
  EncodedData := StringReplace(EncodedData, ' ', '', [rfReplaceAll]);
  EncodedData := StringReplace(EncodedData, #9, '', [rfReplaceAll]);
  EncodedData := StringReplace(EncodedData, #10, '', [rfReplaceAll]);
  EncodedData := StringReplace(EncodedData, #13, '', [rfReplaceAll]);
  if EncodedData = '' then
    Exit;
  try
    Data := TNetEncoding.Base64.DecodeStringToBytes(EncodedData);
    Result := IsDecodablePng(Data);
    if not Result then
      Data := nil;
  except
    on EConvertError do
      Data := nil;
    on EEncodingError do
      Data := nil;
  end;
end;

function TryParseImage(const Node: IXMLNode; Index: Integer;
  out Data: TVectArtImageData): Boolean;
var
  A: Single;
  B: Single;
  C: Single;
  D: Single;
  DisplayValue: string;
  E: Single;
  F: Single;
  Height: Single;
  Href: string;
  LockedText: string;
  OpacityText: string;
  SourceKindText: string;
  TransformText: string;
  ValueText: string;
  VisibilityValue: string;
  Width: Single;
  X: Single;
  Y: Single;
begin
  Result := False;
  if not TryGetAttribute(Node, 'href', Href) then
    if not TryGetAttribute(Node, 'xlink:href', Href) then
      Exit;
  if not TryDecodePngDataUri(Trim(Href), Data.PngData) then
    Exit;
  if not TryGetAttribute(Node, 'x', ValueText) then
    ValueText := '0';
  if not TryParseSvgNumber(ValueText, X) then
    Exit;
  if not TryGetAttribute(Node, 'y', ValueText) then
    ValueText := '0';
  if not TryParseSvgNumber(ValueText, Y) then
    Exit;
  if not TryGetAttribute(Node, 'width', ValueText) or
    not TryParseSvgNumber(ValueText, Width) or (Width <= 0) then
    Exit;
  if not TryGetAttribute(Node, 'height', ValueText) or
    not TryParseSvgNumber(ValueText, Height) or (Height <= 0) then
    Exit;
  A := 1;
  B := 0;
  C := 0;
  D := 1;
  E := 0;
  F := 0;
  if TryGetAttribute(Node, 'transform', TransformText) and
    not TryParseSvgMatrix(TransformText, A, B, C, D, E, F) then
    Exit;
  Data.Points[0] := TransformSvgPoint(PointF(X, Y), A, B, C, D, E, F);
  Data.Points[1] := TransformSvgPoint(PointF(X + Width, Y),
    A, B, C, D, E, F);
  Data.Points[2] := TransformSvgPoint(PointF(X + Width, Y + Height),
    A, B, C, D, E, F);
  Data.Points[3] := TransformSvgPoint(PointF(X, Y + Height),
    A, B, C, D, E, F);
  Data.Name := ImageName(Node, Index);
  Data.SourceKind := visImage;
  if TryGetAttribute(Node, 'vad:source-kind', SourceKindText) and
    SameText(Trim(SourceKindText), 'logo') then
    Data.SourceKind := visLogo;
  Data.Opacity := 1.0;
  if TryGetPresentationValue(Node, 'opacity', OpacityText) and
    not TryParseSvgNumber(OpacityText, Data.Opacity) then
    Exit;
  Data.Opacity := EnsureRange(Data.Opacity, 0.0, 1.0);
  Data.Visible := True;
  if TryGetPresentationValue(Node, 'display', DisplayValue) then
    Data.Visible := not SameText(Trim(DisplayValue), 'none');
  if TryGetPresentationValue(Node, 'visibility', VisibilityValue) then
    Data.Visible := Data.Visible and
      not SameText(Trim(VisibilityValue), 'hidden') and
      not SameText(Trim(VisibilityValue), 'collapse');
  Data.Locked := False;
  if TryGetAttribute(Node, 'vad:locked', LockedText) then
    TryParseBoolean(LockedText, Data.Locked);
  Result := True;
end;

function TryParseRectangle(const Node: IXMLNode;
  InheritedStyles: TSvgInheritedStyles; Index: Integer;
  out Data: TVectArtRectangleData): Boolean;
var
  DisplayValue: string;
  FillOpacity: Single;
  FillInteger: Integer;
  FillText: string;
  Height: Single;
  LockedText: string;
  Opacity: Single;
  OpacityText: string;
  StrokeInteger: Integer;
  MifStrokeStyleInteger: Integer;
  StrokeText: string;
  StrokeWidth: Single;
  ValueText: string;
  VisibilityValue: string;
  Width: Single;
  X: Single;
  Y: Single;
begin
  Result := False;
  if not TryGetAttribute(Node, 'x', ValueText) then
    ValueText := '0';
  if not TryParseSvgNumber(ValueText, X) then
    Exit;
  if not TryGetAttribute(Node, 'y', ValueText) then
    ValueText := '0';
  if not TryParseSvgNumber(ValueText, Y) then
    Exit;
  if not TryGetAttribute(Node, 'width', ValueText) or
    not TryParseSvgNumber(ValueText, Width) or (Width < 0) then
    Exit;
  if not TryGetAttribute(Node, 'height', ValueText) or
    not TryParseSvgNumber(ValueText, Height) or (Height < 0) then
    Exit;
  FillText := 'black';
  TryGetPresentationValueOrInherited(Node, InheritedStyles, 'fill',
    FillText);
  if SameText(Trim(FillText), 'none') or
    not TryParseSvgColor(FillText, Data.FillColor) then
    Exit;
  if TryGetAttribute(Node, 'vad:fill-color', ValueText) and
    TryStrToInt(ValueText, FillInteger) and
    (ColorToRGB(TColor(FillInteger)) = ColorToRGB(Data.FillColor)) then
    Data.FillColor := TColor(FillInteger);
  Data.StrokeColor := clBlack;
  Data.MifStrokeStyle := vssSolid;
  Data.StrokeWidth := 0.0;
  StrokeText := 'none';
  if TryGetPresentationValueOrInherited(Node, InheritedStyles, 'stroke',
    StrokeText) and
    not SameText(Trim(StrokeText), 'none') then
  begin
    if not TryParseSvgColor(StrokeText, Data.StrokeColor) then
      Exit;
    if TryGetAttribute(Node, 'vad:stroke-color', ValueText) and
      TryStrToInt(ValueText, StrokeInteger) and
      (ColorToRGB(TColor(StrokeInteger)) =
       ColorToRGB(Data.StrokeColor)) then
      Data.StrokeColor := TColor(StrokeInteger);
    StrokeWidth := 1.0;
    if TryGetPresentationValueOrInherited(Node, InheritedStyles,
      'stroke-width', ValueText) and
      (not TryParseSvgNumber(ValueText, StrokeWidth) or (StrokeWidth < 0)) then
      Exit;
    Data.StrokeWidth := StrokeWidth;
    if TryGetAttribute(Node, 'vad:stroke-style', ValueText) and
      TryStrToInt(ValueText, MifStrokeStyleInteger) and
      InRange(MifStrokeStyleInteger, Ord(Low(TVectArtMifStrokeStyle)),
        Ord(High(TVectArtMifStrokeStyle))) then
      Data.MifStrokeStyle := TVectArtMifStrokeStyle(MifStrokeStyleInteger)
    else if TryGetPresentationValueOrInherited(Node, InheritedStyles,
      'stroke-dasharray', ValueText) and
      (Trim(ValueText) <> '') and not SameText(Trim(ValueText), 'none') then
      Data.MifStrokeStyle := vssDashed;
  end;
  Opacity := 1.0;
  if TryGetPresentationValue(Node, 'opacity', OpacityText) and
    not TryParseSvgNumber(OpacityText, Opacity) then
    Exit;
  FillOpacity := 1.0;
  if TryGetPresentationValueOrInherited(Node, InheritedStyles,
    'fill-opacity', OpacityText) and
    not TryParseSvgNumber(OpacityText, FillOpacity) then
    Exit;
  Data.Bounds := TRectF.Create(X, Y, X + Width, Y + Height);
  Data.Name := LayerName(Node, 'Rectangle', Index);
  Data.Opacity := EnsureRange(Opacity * FillOpacity, 0.0, 1.0);
  Data.RotationDegrees := 0.0;
  Data.Visible := True;
  if TryGetPresentationValue(Node, 'display', DisplayValue) then
    Data.Visible := not SameText(Trim(DisplayValue), 'none');
  if TryGetPresentationValue(Node, 'visibility', VisibilityValue) then
    Data.Visible := Data.Visible and
      not SameText(Trim(VisibilityValue), 'hidden') and
      not SameText(Trim(VisibilityValue), 'collapse');
  Data.Locked := False;
  if TryGetAttribute(Node, 'vad:locked', LockedText) then
    TryParseBoolean(LockedText, Data.Locked);
  Result := True;
end;

function TryParseLine(const Node: IXMLNode;
  InheritedStyles: TSvgInheritedStyles; Index: Integer;
  out Data: TVectArtLineData): Boolean;
var
  DisplayValue: string;
  LineCapText: string;
  LineJoinText: string;
  LockedText: string;
  OpacityText: string;
  StrokeInteger: Integer;
  StrokeOpacity: Single;
  MifStrokeStyleInteger: Integer;
  StrokeText: string;
  ValueText: string;
  VisibilityValue: string;
begin
  Result := TryGetAttribute(Node, 'x1', ValueText) and
    TryParseSvgNumber(ValueText, Data.StartPoint.X) and
    TryGetAttribute(Node, 'y1', ValueText) and
    TryParseSvgNumber(ValueText, Data.StartPoint.Y) and
    TryGetAttribute(Node, 'x2', ValueText) and
    TryParseSvgNumber(ValueText, Data.EndPoint.X) and
    TryGetAttribute(Node, 'y2', ValueText) and
    TryParseSvgNumber(ValueText, Data.EndPoint.Y);
  if not Result then
    Exit;
  StrokeText := 'none';
  TryGetPresentationValueOrInherited(Node, InheritedStyles, 'stroke',
    StrokeText);
  if SameText(Trim(StrokeText), 'none') or
    not TryParseSvgColor(StrokeText, Data.StrokeColor) then
    Exit(False);
  if TryGetAttribute(Node, 'vad:stroke-color', ValueText) and
    TryStrToInt(ValueText, StrokeInteger) and
    (ColorToRGB(TColor(StrokeInteger)) =
     ColorToRGB(Data.StrokeColor)) then
    Data.StrokeColor := TColor(StrokeInteger);
  Data.StrokeWidth := 1.0;
  if TryGetPresentationValueOrInherited(Node, InheritedStyles,
    'stroke-width', ValueText) and
    (not TryParseSvgNumber(ValueText, Data.StrokeWidth) or
     (Data.StrokeWidth <= 0)) then
    Exit(False);
  Data.MifStrokeStyle := vssSolid;
  if TryGetAttribute(Node, 'vad:stroke-style', ValueText) and
    TryStrToInt(ValueText, MifStrokeStyleInteger) and
    InRange(MifStrokeStyleInteger, Ord(Low(TVectArtMifStrokeStyle)),
      Ord(High(TVectArtMifStrokeStyle))) then
    Data.MifStrokeStyle := TVectArtMifStrokeStyle(MifStrokeStyleInteger)
  else if TryGetPresentationValueOrInherited(Node, InheritedStyles,
    'stroke-dasharray', ValueText) and
    (Trim(ValueText) <> '') and not SameText(Trim(ValueText), 'none') then
    Data.MifStrokeStyle := vssDashed;
  Data.LineCap := vlcButt;
  if TryGetPresentationValueOrInherited(Node, InheritedStyles,
    'stroke-linecap', LineCapText) then
    if SameText(Trim(LineCapText), 'square') then
      Data.LineCap := vlcSquare
    else if SameText(Trim(LineCapText), 'round') then
      Data.LineCap := vlcRound;
  Data.LineJoin := vljMiter;
  if TryGetPresentationValueOrInherited(Node, InheritedStyles,
    'stroke-linejoin', LineJoinText) then
    if SameText(Trim(LineJoinText), 'bevel') then
      Data.LineJoin := vljBevel
    else if SameText(Trim(LineJoinText), 'round') then
      Data.LineJoin := vljRound;
  Data.MifAntiAlias := True;
  if TryGetPresentationValueOrInherited(Node, InheritedStyles,
    'shape-rendering', ValueText) and
    SameText(Trim(ValueText), 'crispEdges') then
    Data.MifAntiAlias := False;
  Data.MifEndMarker := vlmNone;
  Data.MifEndMarkerSize := 4.0;
  if TryGetAttribute(Node, 'vad:end-marker', ValueText) then
    TryParseMifLineMarkerName(ValueText, Data.MifEndMarker);
  if TryGetAttribute(Node, 'vad:end-marker-size', ValueText) then
    if not TryParseSvgNumber(ValueText, Data.MifEndMarkerSize) or
      (Data.MifEndMarkerSize < 1.0) then Data.MifEndMarkerSize := 4.0;
  Data.MifStartMarker := vlmNone;
  Data.MifStartMarkerSize := 4.0;
  if TryGetAttribute(Node, 'vad:start-marker', ValueText) then
    TryParseMifLineMarkerName(ValueText, Data.MifStartMarker);
  if TryGetAttribute(Node, 'vad:start-marker-size', ValueText) then
    if not TryParseSvgNumber(ValueText, Data.MifStartMarkerSize) or
      (Data.MifStartMarkerSize < 1.0) then Data.MifStartMarkerSize := 4.0;
  Data.Opacity := 1.0;
  if TryGetPresentationValue(Node, 'opacity', OpacityText) and
    not TryParseSvgNumber(OpacityText, Data.Opacity) then
    Exit(False);
  StrokeOpacity := 1.0;
  if TryGetPresentationValueOrInherited(Node, InheritedStyles,
    'stroke-opacity', OpacityText) and
    not TryParseSvgNumber(OpacityText, StrokeOpacity) then
    Exit(False);
  Data.Opacity := EnsureRange(Data.Opacity * StrokeOpacity, 0.0, 1.0);
  Data.Name := LayerName(Node, 'Line', Index);
  Data.Visible := True;
  if TryGetPresentationValue(Node, 'display', DisplayValue) then
    Data.Visible := not SameText(Trim(DisplayValue), 'none');
  if TryGetPresentationValue(Node, 'visibility', VisibilityValue) then
    Data.Visible := Data.Visible and
      not SameText(Trim(VisibilityValue), 'hidden') and
      not SameText(Trim(VisibilityValue), 'collapse');
  Data.Locked := False;
  if TryGetAttribute(Node, 'vad:locked', LockedText) then
    TryParseBoolean(LockedText, Data.Locked);
  Result := True;
end;

function IsSvgPathCommand(Value: Char): Boolean;
begin
  Result := CharInSet(Value, ['M', 'm', 'L', 'l', 'H', 'h', 'V', 'v',
    'Z', 'z']);
end;

procedure SkipSvgPathSeparators(const Text: string; var Index: Integer);
begin
  while (Index <= Length(Text)) and
    CharInSet(Text[Index], [' ', #9, #10, #13, ',']) do
    Inc(Index);
end;

function TryReadSvgPathNumber(const Text: string; var Index: Integer;
  out Value: Single): Boolean;
var
  DigitFound: Boolean;
  ExponentDigits: Boolean;
  StartIndex: Integer;
begin
  Result := False;
  SkipSvgPathSeparators(Text, Index);
  StartIndex := Index;
  if (Index <= Length(Text)) and CharInSet(Text[Index], ['+', '-']) then
    Inc(Index);
  DigitFound := False;
  while (Index <= Length(Text)) and CharInSet(Text[Index], ['0'..'9']) do
  begin
    DigitFound := True;
    Inc(Index);
  end;
  if (Index <= Length(Text)) and (Text[Index] = '.') then
  begin
    Inc(Index);
    while (Index <= Length(Text)) and CharInSet(Text[Index], ['0'..'9']) do
    begin
      DigitFound := True;
      Inc(Index);
    end;
  end;
  if not DigitFound then
  begin
    Index := StartIndex;
    Exit;
  end;
  if (Index <= Length(Text)) and CharInSet(Text[Index], ['E', 'e']) then
  begin
    Inc(Index);
    if (Index <= Length(Text)) and CharInSet(Text[Index], ['+', '-']) then
      Inc(Index);
    ExponentDigits := False;
    while (Index <= Length(Text)) and CharInSet(Text[Index], ['0'..'9']) do
    begin
      ExponentDigits := True;
      Inc(Index);
    end;
    if not ExponentDigits then
    begin
      Index := StartIndex;
      Exit;
    end;
  end;
  Result := TryParseSvgNumber(Copy(Text, StartIndex, Index - StartIndex),
    Value);
  if not Result then
    Index := StartIndex;
end;

function TryParseSvgTransformArguments(const Text: string;
  out Values: TArray<Single>): Boolean;
var
  Index: Integer;
  ParsedValues: TList<Single>;
  Value: Single;
begin
  Result := False;
  Values := nil;
  Index := 1;
  ParsedValues := TList<Single>.Create;
  try
    SkipSvgPathSeparators(Text, Index);
    while Index <= Length(Text) do
    begin
      if not TryReadSvgPathNumber(Text, Index, Value) then
        Exit;
      ParsedValues.Add(Value);
      SkipSvgPathSeparators(Text, Index);
    end;
    Values := ParsedValues.ToArray;
    Result := True;
  finally
    ParsedValues.Free;
  end;
end;

function TryParseSvgTransform(const Text: string;
  out Matrix: TSvgAffineMatrix): Boolean;
var
  Angle: Single;
  ArgumentStart: Integer;
  Arguments: TArray<Single>;
  CloseIndex: Integer;
  Cosine: Single;
  Index: Integer;
  Name: string;
  NameStart: Integer;
  Operation: TSvgAffineMatrix;
  Rotation: TSvgAffineMatrix;
  Sine: Single;
  TranslateBack: TSvgAffineMatrix;
  TranslateToOrigin: TSvgAffineMatrix;
  Value: Single;
begin
  Result := False;
  Matrix := SvgIdentityMatrix;
  Index := 1;
  while True do
  begin
    SkipSvgPathSeparators(Text, Index);
    if Index > Length(Text) then
      Break;
    NameStart := Index;
    while (Index <= Length(Text)) and
      CharInSet(Text[Index], ['A'..'Z', 'a'..'z']) do
      Inc(Index);
    if NameStart = Index then
      Exit;
    Name := Copy(Text, NameStart, Index - NameStart);
    while (Index <= Length(Text)) and
      CharInSet(Text[Index], [' ', #9, #10, #13]) do
      Inc(Index);
    if (Index > Length(Text)) or (Text[Index] <> '(') then
      Exit;
    ArgumentStart := Index + 1;
    CloseIndex := ArgumentStart;
    while (CloseIndex <= Length(Text)) and (Text[CloseIndex] <> ')') do
      Inc(CloseIndex);
    if CloseIndex > Length(Text) then
      Exit;
    if not TryParseSvgTransformArguments(Copy(Text, ArgumentStart,
      CloseIndex - ArgumentStart), Arguments) then
      Exit;
    Operation := SvgIdentityMatrix;
    if SameText(Name, 'matrix') then
    begin
      if Length(Arguments) <> 6 then
        Exit;
      Operation.A := Arguments[0];
      Operation.B := Arguments[1];
      Operation.C := Arguments[2];
      Operation.D := Arguments[3];
      Operation.E := Arguments[4];
      Operation.F := Arguments[5];
    end
    else if SameText(Name, 'translate') then
    begin
      if not (Length(Arguments) in [1, 2]) then
        Exit;
      Operation.E := Arguments[0];
      if Length(Arguments) = 2 then
        Operation.F := Arguments[1];
    end
    else if SameText(Name, 'scale') then
    begin
      if not (Length(Arguments) in [1, 2]) then
        Exit;
      Operation.A := Arguments[0];
      if Length(Arguments) = 2 then
        Operation.D := Arguments[1]
      else
        Operation.D := Arguments[0];
    end
    else if SameText(Name, 'rotate') then
    begin
      if not (Length(Arguments) in [1, 3]) then
        Exit;
      Angle := DegToRad(Arguments[0]);
      Sine := Sin(Angle);
      Cosine := Cos(Angle);
      Rotation := SvgIdentityMatrix;
      Rotation.A := Cosine;
      Rotation.B := Sine;
      Rotation.C := -Sine;
      Rotation.D := Cosine;
      if Length(Arguments) = 1 then
        Operation := Rotation
      else
      begin
        TranslateBack := SvgIdentityMatrix;
        TranslateBack.E := Arguments[1];
        TranslateBack.F := Arguments[2];
        TranslateToOrigin := SvgIdentityMatrix;
        TranslateToOrigin.E := -Arguments[1];
        TranslateToOrigin.F := -Arguments[2];
        Operation := MultiplySvgMatrices(TranslateBack,
          MultiplySvgMatrices(Rotation, TranslateToOrigin));
      end;
    end
    else if SameText(Name, 'skewX') then
    begin
      if Length(Arguments) <> 1 then
        Exit;
      Angle := DegToRad(Arguments[0]);
      if Abs(Cos(Angle)) < 0.000001 then
        Exit;
      Value := Tan(Angle);
      if IsNan(Value) or IsInfinite(Value) then
        Exit;
      Operation.C := Value;
    end
    else if SameText(Name, 'skewY') then
    begin
      if Length(Arguments) <> 1 then
        Exit;
      Angle := DegToRad(Arguments[0]);
      if Abs(Cos(Angle)) < 0.000001 then
        Exit;
      Value := Tan(Angle);
      if IsNan(Value) or IsInfinite(Value) then
        Exit;
      Operation.B := Value;
    end
    else
      Exit;
    Matrix := MultiplySvgMatrices(Matrix, Operation);
    Index := CloseIndex + 1;
  end;
  Result := True;
end;

function TryCombineSvgTransform(const Node: IXMLNode;
  const ParentMatrix: TSvgAffineMatrix;
  out CombinedMatrix: TSvgAffineMatrix): Boolean;
var
  LocalMatrix: TSvgAffineMatrix;
  TransformText: string;
begin
  CombinedMatrix := ParentMatrix;
  if not TryGetAttribute(Node, 'transform', TransformText) or
    (Trim(TransformText) = '') then
    Exit(True);
  Result := TryParseSvgTransform(TransformText, LocalMatrix);
  if Result then
    CombinedMatrix := MultiplySvgMatrices(ParentMatrix, LocalMatrix);
end;

function TryParseSvgPathPoints(const PathText: string;
  out Points: TArray<TPointF>; out Closed: Boolean): Boolean;
var
  Command: Char;
  CurrentPoint: TPointF;
  Index: Integer;
  IsRelative: Boolean;
  NewPoint: TPointF;
  ParsedPoints: TList<TPointF>;
  Value: Single;
begin
  // Documentは単一点列なので、曲線と複数サブパスを推測で平坦化しない。
  Result := False;
  Points := nil;
  Closed := False;
  Command := #0;
  CurrentPoint := PointF(0, 0);
  Index := 1;
  ParsedPoints := TList<TPointF>.Create;
  try
    while True do
    begin
      SkipSvgPathSeparators(PathText, Index);
      if Index > Length(PathText) then
        Break;
      if CharInSet(PathText[Index], ['A'..'Z', 'a'..'z']) then
      begin
        if not IsSvgPathCommand(PathText[Index]) then
          Exit;
        Command := PathText[Index];
        Inc(Index);
      end
      else if Command = #0 then
        Exit;
      IsRelative := CharInSet(Command, ['m', 'l', 'h', 'v']);
      case UpCase(Command) of
        'M', 'L':
          begin
            if (UpCase(Command) = 'M') and (ParsedPoints.Count > 0) then
              Exit;
            if not TryReadSvgPathNumber(PathText, Index, NewPoint.X) or
              not TryReadSvgPathNumber(PathText, Index, NewPoint.Y) then
              Exit;
            if IsRelative then
            begin
              NewPoint.X := NewPoint.X + CurrentPoint.X;
              NewPoint.Y := NewPoint.Y + CurrentPoint.Y;
            end;
            CurrentPoint := NewPoint;
            ParsedPoints.Add(CurrentPoint);
            if UpCase(Command) = 'M' then
              if Command = 'm' then
                Command := 'l'
              else
                Command := 'L';
          end;
        'H':
          begin
            if ParsedPoints.Count = 0 then
              Exit;
            if not TryReadSvgPathNumber(PathText, Index, Value) then
              Exit;
            if IsRelative then
              CurrentPoint.X := CurrentPoint.X + Value
            else
              CurrentPoint.X := Value;
            ParsedPoints.Add(CurrentPoint);
          end;
        'V':
          begin
            if ParsedPoints.Count = 0 then
              Exit;
            if not TryReadSvgPathNumber(PathText, Index, Value) then
              Exit;
            if IsRelative then
              CurrentPoint.Y := CurrentPoint.Y + Value
            else
              CurrentPoint.Y := Value;
            ParsedPoints.Add(CurrentPoint);
          end;
        'Z':
          begin
            if ParsedPoints.Count < 2 then
              Exit;
            Closed := True;
            Command := #0;
            SkipSvgPathSeparators(PathText, Index);
            if Index <= Length(PathText) then
              Exit;
          end;
      else
        Exit;
      end;
    end;
    if ParsedPoints.Count < 2 then
      Exit;
    if Closed and (ParsedPoints.Count > 2) and
      SameValue(ParsedPoints[0].X, ParsedPoints[ParsedPoints.Count - 1].X) and
      SameValue(ParsedPoints[0].Y, ParsedPoints[ParsedPoints.Count - 1].Y) then
      ParsedPoints.Delete(ParsedPoints.Count - 1);
    Points := ParsedPoints.ToArray;
    Result := True;
  finally
    ParsedPoints.Free;
  end;
end;

function TryParsePath(const Node: IXMLNode;
  InheritedStyles: TSvgInheritedStyles; Index: Integer; Closed: Boolean;
  out Data: TVectArtPathData): Boolean;
var
  ColorInteger: Integer;
  DisplayValue: string;
  FillOpacity: Single;
  I: Integer;
  LineCapText: string;
  LineJoinText: string;
  LockedText: string;
  Opacity: Single;
  OpacityText: string;
  Parts: TStringList;
  PointsText: string;
  StrokeOpacity: Single;
  MifStrokeStyleInteger: Integer;
  ValueText: string;
  VisibilityValue: string;
begin
  Result := False;
  if SameText(LocalNodeName(Node), 'path') then
  begin
    if not TryGetAttribute(Node, 'd', PointsText) or
      not TryParseSvgPathPoints(PointsText, Data.Points, Closed) then
      Exit;
  end
  else
  begin
    if not TryGetAttribute(Node, 'points', PointsText) then
      Exit;
    PointsText := StringReplace(Trim(PointsText), ',', ' ', [rfReplaceAll]);
    PointsText := StringReplace(PointsText, #9, ' ', [rfReplaceAll]);
    PointsText := StringReplace(PointsText, #10, ' ', [rfReplaceAll]);
    PointsText := StringReplace(PointsText, #13, ' ', [rfReplaceAll]);
    Parts := TStringList.Create;
    try
      Parts.StrictDelimiter := True;
      Parts.Delimiter := ' ';
      Parts.DelimitedText := PointsText;
      for I := Parts.Count - 1 downto 0 do
        if Trim(Parts[I]) = '' then
          Parts.Delete(I);
      if (Parts.Count < 4) or Odd(Parts.Count) then
        Exit;
      SetLength(Data.Points, Parts.Count div 2);
      for I := 0 to High(Data.Points) do
        if not TryParseSvgNumber(Parts[I * 2], Data.Points[I].X) or
          not TryParseSvgNumber(Parts[I * 2 + 1], Data.Points[I].Y) then
          Exit;
    finally
      Parts.Free;
    end;
  end;
  Data.Closed := Closed;
  if Closed then
    ValueText := 'black'
  else
    ValueText := 'none';
  TryGetPresentationValueOrInherited(Node, InheritedStyles, 'fill',
    ValueText);
  Data.Filled := Closed and not SameText(Trim(ValueText), 'none');
  Data.FillColor := clWhite;
  if Data.Filled and not TryParseSvgColor(ValueText, Data.FillColor) then
    Exit;
  if TryGetAttribute(Node, 'vad:fill-color', ValueText) and
    TryStrToInt(ValueText, ColorInteger) and
    (not Data.Filled or (ColorToRGB(TColor(ColorInteger)) =
    ColorToRGB(Data.FillColor))) then
    Data.FillColor := TColor(ColorInteger);
  ValueText := 'none';
  TryGetPresentationValueOrInherited(Node, InheritedStyles, 'stroke',
    ValueText);
  Data.StrokeWidth := 0.0;
  Data.StrokeColor := clBlack;
  if not SameText(Trim(ValueText), 'none') then
  begin
    if not TryParseSvgColor(ValueText, Data.StrokeColor) then
      Exit;
    Data.StrokeWidth := 1.0;
    if TryGetPresentationValueOrInherited(Node, InheritedStyles,
      'stroke-width', ValueText) and
      (not TryParseSvgNumber(ValueText, Data.StrokeWidth) or
      (Data.StrokeWidth < 0)) then
      Exit;
  end;
  if TryGetAttribute(Node, 'vad:stroke-color', ValueText) and
    TryStrToInt(ValueText, ColorInteger) and
    (ColorToRGB(TColor(ColorInteger)) = ColorToRGB(Data.StrokeColor)) then
    Data.StrokeColor := TColor(ColorInteger);
  Data.MifStrokeStyle := vssSolid;
  if TryGetAttribute(Node, 'vad:stroke-style', ValueText) and
    TryStrToInt(ValueText, MifStrokeStyleInteger) and
    InRange(MifStrokeStyleInteger, Ord(Low(TVectArtMifStrokeStyle)),
      Ord(High(TVectArtMifStrokeStyle))) then
    Data.MifStrokeStyle := TVectArtMifStrokeStyle(MifStrokeStyleInteger)
  else if TryGetPresentationValueOrInherited(Node, InheritedStyles,
    'stroke-dasharray', ValueText) and
    (Trim(ValueText) <> '') and not SameText(Trim(ValueText), 'none') then
    Data.MifStrokeStyle := vssDashed;
  Data.LineCap := vlcButt;
  if TryGetPresentationValueOrInherited(Node, InheritedStyles,
    'stroke-linecap', LineCapText) then
    if SameText(Trim(LineCapText), 'square') then
      Data.LineCap := vlcSquare
    else if SameText(Trim(LineCapText), 'round') then
      Data.LineCap := vlcRound;
  Data.LineJoin := vljMiter;
  if TryGetPresentationValueOrInherited(Node, InheritedStyles,
    'stroke-linejoin', LineJoinText) then
    if SameText(Trim(LineJoinText), 'bevel') then
      Data.LineJoin := vljBevel
    else if SameText(Trim(LineJoinText), 'round') then
      Data.LineJoin := vljRound;
  Data.MifAntiAlias := True;
  if TryGetPresentationValueOrInherited(Node, InheritedStyles,
    'shape-rendering', ValueText) and
    SameText(Trim(ValueText), 'crispEdges') then
    Data.MifAntiAlias := False;
  if not Data.Filled and (Data.StrokeWidth <= 0) then
    Exit(False);
  Opacity := 1.0;
  if TryGetPresentationValue(Node, 'opacity', OpacityText) and
    not TryParseSvgNumber(OpacityText, Opacity) then
    Exit;
  FillOpacity := 1.0;
  if TryGetPresentationValueOrInherited(Node, InheritedStyles,
    'fill-opacity', OpacityText) and
    not TryParseSvgNumber(OpacityText, FillOpacity) then
    Exit;
  StrokeOpacity := 1.0;
  if TryGetPresentationValueOrInherited(Node, InheritedStyles,
    'stroke-opacity', OpacityText) and
    not TryParseSvgNumber(OpacityText, StrokeOpacity) then
    Exit;
  if Data.Filled then
    Data.Opacity := EnsureRange(Opacity * FillOpacity, 0.0, 1.0)
  else
    Data.Opacity := EnsureRange(Opacity * StrokeOpacity, 0.0, 1.0);
  Data.Name := LayerName(Node, 'Path', Index);
  Data.Visible := True;
  if TryGetPresentationValue(Node, 'display', DisplayValue) then
    Data.Visible := not SameText(Trim(DisplayValue), 'none');
  if TryGetPresentationValue(Node, 'visibility', VisibilityValue) then
    Data.Visible := Data.Visible and
      not SameText(Trim(VisibilityValue), 'hidden') and
      not SameText(Trim(VisibilityValue), 'collapse');
  Data.Locked := False;
  if TryGetAttribute(Node, 'vad:locked', LockedText) then
    TryParseBoolean(LockedText, Data.Locked);
  Result := True;
end;

function TryReadCanvasSize(const Root: IXMLNode; out Width,
  Height: Integer): Boolean;
var
  HeightValue: Single;
  I: Integer;
  Part: string;
  Parts: TStringList;
  ValueText: string;
  ViewBox: string;
  WidthValue: Single;
begin
  Result := TryGetAttribute(Root, 'width', ValueText) and
    TryParseSvgNumber(ValueText, WidthValue) and
    TryGetAttribute(Root, 'height', ValueText) and
    TryParseSvgNumber(ValueText, HeightValue) and
    (WidthValue > 0) and (HeightValue > 0);
  if not Result and TryGetAttribute(Root, 'viewBox', ViewBox) then
  begin
    ViewBox := StringReplace(Trim(ViewBox), ',', ' ', [rfReplaceAll]);
    Parts := TStringList.Create;
    try
      Parts.StrictDelimiter := True;
      Parts.Delimiter := ' ';
      Parts.DelimitedText := ViewBox;
      for I := Parts.Count - 1 downto 0 do
      begin
        Part := Trim(Parts[I]);
        if Part = '' then
          Parts.Delete(I);
      end;
      Result := (Parts.Count = 4) and TryParseSvgNumber(Parts[2], WidthValue)
        and TryParseSvgNumber(Parts[3], HeightValue) and
        (WidthValue > 0) and (HeightValue > 0);
    finally
      Parts.Free;
    end;
  end;
  if Result then
  begin
    Width := Max(Round(WidthValue), 1);
    Height := Max(Round(HeightValue), 1);
  end
  else
  begin
    Width := 0;
    Height := 0;
  end;
end;

function TransformSvgRectangle(const Matrix: TSvgAffineMatrix;
  var Data: TVectArtRectangleData; out Corners: TVectArtQuad): Boolean;
const
  ORTHOGONAL_TOLERANCE = 0.0001;
var
  Angle: Single;
  Center: TPointF;
  DotProduct: Single;
  EdgeDown: TPointF;
  EdgeHeight: Single;
  EdgeRight: TPointF;
  EdgeWidth: Single;
  I: Integer;
  OriginalCorners: TVectArtQuad;
begin
  OriginalCorners := RectangleCorners(Data.Bounds, Data.RotationDegrees);
  for I := Low(Corners) to High(Corners) do
    Corners[I] := SvgTransformPoint(Matrix, OriginalCorners[I]);
  EdgeRight := Corners[1] - Corners[0];
  EdgeDown := Corners[3] - Corners[0];
  EdgeWidth := Hypot(EdgeRight.X, EdgeRight.Y);
  EdgeHeight := Hypot(EdgeDown.X, EdgeDown.Y);
  DotProduct := EdgeRight.X * EdgeDown.X + EdgeRight.Y * EdgeDown.Y;
  Result := (EdgeWidth <= ORTHOGONAL_TOLERANCE) or
    (EdgeHeight <= ORTHOGONAL_TOLERANCE) or
    (Abs(DotProduct) <= EdgeWidth * EdgeHeight * ORTHOGONAL_TOLERANCE);
  if not Result then
    Exit;
  Center := PointF((Corners[0].X + Corners[2].X) * 0.5,
    (Corners[0].Y + Corners[2].Y) * 0.5);
  if EdgeWidth > ORTHOGONAL_TOLERANCE then
    Angle := RadToDeg(ArcTan2(EdgeRight.Y, EdgeRight.X))
  else if EdgeHeight > ORTHOGONAL_TOLERANCE then
    Angle := RadToDeg(ArcTan2(EdgeDown.Y, EdgeDown.X)) - 90.0
  else
    Angle := 0.0;
  Data.Bounds := RectF(Center.X - EdgeWidth * 0.5,
    Center.Y - EdgeHeight * 0.5, Center.X + EdgeWidth * 0.5,
    Center.Y + EdgeHeight * 0.5);
  Data.RotationDegrees := NormalizeAngleDegrees(Angle);
  Data.StrokeWidth := Data.StrokeWidth * SvgStrokeScale(Matrix);
end;

function PathDataFromTransformedRectangle(
  const RectangleData: TVectArtRectangleData;
  const Corners: TVectArtQuad; StrokeScale: Single): TVectArtPathData;
var
  I: Integer;
begin
  Result.Closed := True;
  Result.FillColor := RectangleData.FillColor;
  Result.Filled := True;
  Result.Locked := RectangleData.Locked;
  Result.Name := RectangleData.Name;
  Result.Opacity := RectangleData.Opacity;
  SetLength(Result.Points, Length(Corners));
  for I := Low(Corners) to High(Corners) do
    Result.Points[I] := Corners[I];
  Result.StrokeColor := RectangleData.StrokeColor;
  Result.MifStrokeStyle := RectangleData.MifStrokeStyle;
  Result.LineCap := vlcButt;
  Result.LineJoin := vljMiter;
  Result.MifAntiAlias := True;
  Result.StrokeWidth := RectangleData.StrokeWidth * StrokeScale;
  Result.Visible := RectangleData.Visible;
end;

procedure CollectSvgLayers(const Parent: IXMLNode;
  const ParentMatrix: TSvgAffineMatrix; ParentOpacity: Single;
  ParentVisible: Boolean; InheritedStyles: TSvgInheritedStyles;
  Rectangles: TList<TVectArtRectangleData>;
  Lines: TList<TVectArtLineData>; Paths: TList<TVectArtPathData>;
  Images: TList<TVectArtImageData>; LayerOrder: TList<Integer>);
var
  Child: IXMLNode;
  ChildMatrix: TSvgAffineMatrix;
  Corners: TVectArtQuad;
  ChildOpacity: Single;
  ChildStyles: TSvgInheritedStyles;
  ChildVisible: Boolean;
  Data: TVectArtRectangleData;
  DisplayText: string;
  I: Integer;
  ImageData: TVectArtImageData;
  J: Integer;
  LineData: TVectArtLineData;
  NodeName: string;
  OpacityText: string;
  PathData: TVectArtPathData;
  VisibilityText: string;
begin
  for I := 0 to Parent.ChildNodes.Count - 1 do
  begin
    Child := Parent.ChildNodes[I];
    if Child.NodeType <> ntElement then
      Continue;
    NodeName := LocalNodeName(Child);
    if SameText(NodeName, 'g') then
    begin
      if not TryCombineSvgTransform(Child, ParentMatrix, ChildMatrix) then
        Continue;
      ChildOpacity := 1.0;
      if TryGetPresentationValue(Child, 'opacity', OpacityText) and
        not TryParseSvgNumber(OpacityText, ChildOpacity) then
        Continue;
      ChildOpacity := ParentOpacity * EnsureRange(ChildOpacity, 0.0, 1.0);
      ChildVisible := ParentVisible;
      if TryGetPresentationValue(Child, 'display', DisplayText) then
        ChildVisible := ChildVisible and
          not SameText(Trim(DisplayText), 'none');
      if TryGetPresentationValue(Child, 'visibility', VisibilityText) then
        ChildVisible := ChildVisible and
          not SameText(Trim(VisibilityText), 'hidden') and
          not SameText(Trim(VisibilityText), 'collapse');
      ChildStyles := CreateInheritedStyles(InheritedStyles, Child);
      try
        CollectSvgLayers(Child, ChildMatrix, ChildOpacity, ChildVisible,
          ChildStyles, Rectangles, Lines, Paths, Images, LayerOrder);
      finally
        ChildStyles.Free;
      end;
      Continue;
    end;
    if SameText(NodeName, 'rect') and
      TryParseRectangle(Child, InheritedStyles, Rectangles.Count + 1,
        Data) then
    begin
      if not TryCombineSvgTransform(Child, ParentMatrix, ChildMatrix) then
        Continue;
      Data.Opacity := Data.Opacity * ParentOpacity;
      Data.Visible := Data.Visible and ParentVisible;
      if TransformSvgRectangle(ChildMatrix, Data, Corners) then
      begin
        Rectangles.Add(Data);
        LayerOrder.Add(Rectangles.Count);
      end
      else
      begin
        PathData := PathDataFromTransformedRectangle(Data, Corners,
          SvgStrokeScale(ChildMatrix));
        Paths.Add(PathData);
        LayerOrder.Add(-(1000000 + Paths.Count));
      end;
    end
    else if SameText(NodeName, 'line') and
      TryParseLine(Child, InheritedStyles, Lines.Count + 1, LineData) then
    begin
      if not TryCombineSvgTransform(Child, ParentMatrix, ChildMatrix) then
        Continue;
      LineData.StartPoint := SvgTransformPoint(ChildMatrix,
        LineData.StartPoint);
      LineData.EndPoint := SvgTransformPoint(ChildMatrix,
        LineData.EndPoint);
      LineData.StrokeWidth := LineData.StrokeWidth *
        SvgStrokeScale(ChildMatrix);
      LineData.Opacity := LineData.Opacity * ParentOpacity;
      LineData.Visible := LineData.Visible and ParentVisible;
      Lines.Add(LineData);
      LayerOrder.Add(-Lines.Count);
    end
    else if (SameText(NodeName, 'polyline') or
      SameText(NodeName, 'polygon')) and
      TryParsePath(Child, InheritedStyles, Paths.Count + 1,
        SameText(NodeName, 'polygon'), PathData) then
    begin
      if not TryCombineSvgTransform(Child, ParentMatrix, ChildMatrix) then
        Continue;
      for J := 0 to High(PathData.Points) do
        PathData.Points[J] := SvgTransformPoint(ChildMatrix,
          PathData.Points[J]);
      PathData.StrokeWidth := PathData.StrokeWidth *
        SvgStrokeScale(ChildMatrix);
      PathData.Opacity := PathData.Opacity * ParentOpacity;
      PathData.Visible := PathData.Visible and ParentVisible;
      Paths.Add(PathData);
      LayerOrder.Add(-(1000000 + Paths.Count));
    end
    else if SameText(NodeName, 'path') and
      TryParsePath(Child, InheritedStyles, Paths.Count + 1, False,
        PathData) then
    begin
      if not TryCombineSvgTransform(Child, ParentMatrix, ChildMatrix) then
        Continue;
      for J := 0 to High(PathData.Points) do
        PathData.Points[J] := SvgTransformPoint(ChildMatrix,
          PathData.Points[J]);
      PathData.StrokeWidth := PathData.StrokeWidth *
        SvgStrokeScale(ChildMatrix);
      PathData.Opacity := PathData.Opacity * ParentOpacity;
      PathData.Visible := PathData.Visible and ParentVisible;
      Paths.Add(PathData);
      LayerOrder.Add(-(1000000 + Paths.Count));
    end
    else if SameText(NodeName, 'image') and
      TryParseImage(Child, Images.Count + 1, ImageData) then
    begin
      for J := Low(ImageData.Points) to High(ImageData.Points) do
        ImageData.Points[J] := SvgTransformPoint(ParentMatrix,
          ImageData.Points[J]);
      ImageData.Opacity := ImageData.Opacity * ParentOpacity;
      ImageData.Visible := ImageData.Visible and ParentVisible;
      Images.Add(ImageData);
      LayerOrder.Add(-(2000000 + Images.Count));
    end;
  end;
end;

function TryLoadVectArtDocumentFromSvg(const SvgText: string;
  Document: TVectArtDocument; out ErrorMessage: string): Boolean;
var
  BackgroundColor: TColor;
  BackgroundInteger: Integer;
  BackgroundText: string;
  Canvas: TVectArtCanvasLayer;
  CanvasHeight: Integer;
  CanvasWidth: Integer;
  Discarded: TVectArtRectangleData;
  DiscardedImage: TVectArtImageData;
  DiscardedLine: TVectArtLineData;
  DiscardedPath: TVectArtPathData;
  I: Integer;
  Images: TList<TVectArtImageData>;
  LayerOrder: TList<Integer>;
  Lines: TList<TVectArtLineData>;
  Paths: TList<TVectArtPathData>;
  RectangleData: TList<TVectArtRectangleData>;
  Root: IXMLNode;
  RootStyles: TSvgInheritedStyles;
  SelectedIndex: Integer;
  StyleBackground: string;
  SvgDocument: IXMLDocument;
  SvgDocumentObject: TXMLDocument;
  Transparent: Boolean;
  TransparentText: string;
begin
  Result := False;
  ErrorMessage := '';
  RectangleData := TList<TVectArtRectangleData>.Create;
  Lines := TList<TVectArtLineData>.Create;
  Paths := TList<TVectArtPathData>.Create;
  Images := TList<TVectArtImageData>.Create;
  LayerOrder := TList<Integer>.Create;
  try
    try
      if Document = nil then
        raise EArgumentNilException.Create('Document');
      SvgDocumentObject := TXMLDocument.Create(nil);
      SvgDocumentObject.DOMVendor := GetDOMVendor(sOmniXmlVendor);
      SvgDocument := SvgDocumentObject;
      SvgDocument.LoadFromXML(SvgText);
      SvgDocument.Active := True;
      Root := SvgDocument.DocumentElement;
      if (Root = nil) or not SameText(LocalNodeName(Root), 'svg') then
        raise EConvertError.Create('SVG root element was not found');
      if not TryReadCanvasSize(Root, CanvasWidth, CanvasHeight) then
        raise EConvertError.Create('SVG canvas size is missing or unsupported');

      BackgroundColor := clWhite;
      if TryGetStyleValue(Root, 'background-color', StyleBackground) then
        TryParseSvgColor(StyleBackground, BackgroundColor);
      if TryGetAttribute(Root, 'vad:background-color', BackgroundText) and
        TryStrToInt(BackgroundText, BackgroundInteger) and
        (not TryGetStyleValue(Root, 'background-color', StyleBackground) or
        (ColorToRGB(TColor(BackgroundInteger)) =
        ColorToRGB(BackgroundColor))) then
        BackgroundColor := TColor(BackgroundInteger);
      Transparent := not TryGetStyleValue(Root, 'background-color',
        StyleBackground);
      if TryGetAttribute(Root, 'vad:transparent', TransparentText) then
        TryParseBoolean(TransparentText, Transparent);
      SelectedIndex := -1;
      if TryGetAttribute(Root, 'vad:selected-index', BackgroundText) then
        TryStrToInt(BackgroundText, SelectedIndex);

      RootStyles := CreateInheritedStyles(nil, Root);
      try
        CollectSvgLayers(Root, SvgIdentityMatrix, 1.0, True, RootStyles,
          RectangleData, Lines, Paths, Images, LayerOrder);
      finally
        RootStyles.Free;
      end;

      Canvas := Document.CanvasLayer;
      if Canvas = nil then
        raise EInvalidOp.Create('Document canvas is missing');
      while Document.LayerCount > 1 do
        if Document[Document.LayerCount - 1] is TVectArtRectangleLayer then
          Document.RemoveRectangle(Document.LayerCount - 1, Discarded)
        else if Document[Document.LayerCount - 1] is TVectArtLineLayer then
          Document.RemoveLine(Document.LayerCount - 1, DiscardedLine)
        else if Document[Document.LayerCount - 1] is TVectArtPathLayer then
          Document.RemovePath(Document.LayerCount - 1, DiscardedPath)
        else if Document[Document.LayerCount - 1] is TVectArtImageLayer then
          Document.RemoveImage(Document.LayerCount - 1, DiscardedImage)
        else
          raise EInvalidOp.Create('Document contains an unsupported layer');
      Canvas.Width := CanvasWidth;
      Canvas.Height := CanvasHeight;
      Canvas.BackgroundColor := BackgroundColor;
      Canvas.Transparent := Transparent;
      for I in LayerOrder do
        if I > 0 then
          Document.InsertRectangle(Document.LayerCount,
            RectangleData[I - 1])
        else if I <= -2000000 then
          Document.InsertImage(Document.LayerCount,
            Images[-I - 2000001])
        else if I <= -1000000 then
          Document.InsertPath(Document.LayerCount,
            Paths[-I - 1000001])
        else
          Document.InsertLine(Document.LayerCount, Lines[-I - 1]);
      Document.EditingMode := vemStandard;
      Document.SelectedIndex := SelectedIndex;
      Document.Changed;
      Result := True;
    except
      on E: Exception do
        ErrorMessage := E.Message;
    end;
  finally
    LayerOrder.Free;
    Images.Free;
    Lines.Free;
    Paths.Free;
    RectangleData.Free;
  end;
end;

function TryLoadVectArtDocumentFromSvgFile(const FileName: string;
  Document: TVectArtDocument; out ErrorMessage: string): Boolean;
var
  SvgText: string;
begin
  Result := False;
  ErrorMessage := '';
  try
    SvgText := TFile.ReadAllText(FileName, TEncoding.UTF8);
    Result := TryLoadVectArtDocumentFromSvg(SvgText, Document, ErrorMessage);
  except
    on E: Exception do
      ErrorMessage := E.Message;
  end;
end;

function TrySaveVectArtDocumentToSvgFile(Document: TVectArtDocument;
  const FileName: string; out ErrorMessage: string): Boolean;
var
  Encoding: TUTF8Encoding;
  FullFileName: string;
  SvgText: string;
  TempFileName: string;
begin
  Result := TryCreateVectArtSvg(Document, SvgText, ErrorMessage);
  if not Result then
    Exit;
  FullFileName := ExpandFileName(FileName);
  TempFileName := TPath.Combine(ExtractFilePath(FullFileName),
    ExtractFileName(FullFileName) + '.' + TPath.GetRandomFileName + '.tmp');
  Encoding := TUTF8Encoding.Create(False);
  try
    try
      TFile.WriteAllText(TempFileName, SvgText, Encoding);
      if not MoveFileEx(PChar(TempFileName), PChar(FullFileName),
        MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH) then
        RaiseLastOSError;
      TempFileName := '';
      Result := True;
    except
      on E: Exception do
      begin
        ErrorMessage := E.Message;
        Result := False;
      end;
    end;
  finally
    Encoding.Free;
    if (TempFileName <> '') and TFile.Exists(TempFileName) then
      try
        TFile.Delete(TempFileName);
      except
        // 元ファイルの保存結果を、一時ファイルの後始末失敗で上書きしない。
      end;
  end;
end;

end.
