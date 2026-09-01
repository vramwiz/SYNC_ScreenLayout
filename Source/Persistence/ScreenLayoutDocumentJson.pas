// 配置DocumentをAviUtl2の文字列項目へ保存できるJSONへ相互変換する。
unit ScreenLayoutDocumentJson;

interface

uses
  ScreenLayoutDocument;

// Documentを埋め込み用JSONへ変換する。既存キー名は内部のMif改名後も維持する。
function SerializeVectArtDocument(Document: TVectArtDocument): string;
// 専用JSONをDocumentへ適用する。旧形式との互換変換は行わない。
function TryDeserializeVectArtDocument(const Text: string;
  Document: TVectArtDocument; out ErrorMessage: string): Boolean;
// JSONファイルを読み込み、存在しない外部参照を持つレイヤーだけを除外してDocumentへ適用する。
function TryLoadVectArtDocumentFromJsonFile(const FileName: string;
  Document: TVectArtDocument; out SkippedReferenceCount: Integer;
  out ErrorMessage: string): Boolean;

implementation

uses
  System.Generics.Collections, System.IOUtils, System.JSON, System.Math,
  System.SysUtils, System.Types,
  Vcl.Graphics;

const
  DOCUMENT_FORMAT_VERSION = 7;

type
  TRequiredJSONValueClass = class of TJSONValue;

function RequireValue(Parent: TJSONObject; const Name: string;
  ValueClass: TRequiredJSONValueClass): TJSONValue;
begin
  Result := Parent.GetValue(Name);
  if (Result = nil) or not Result.InheritsFrom(ValueClass) then
    raise EConvertError.CreateFmt('JSON field "%s" has an invalid type',
      [Name]);
end;

function ReadBoolean(Parent: TJSONObject; const Name: string): Boolean;
begin
  Result := TJSONBool(RequireValue(Parent, Name, TJSONBool)).AsBoolean;
end;

function ReadInteger(Parent: TJSONObject; const Name: string): Integer;
begin
  if not TryStrToInt(RequireValue(Parent, Name, TJSONNumber).Value,
    Result) then
    raise EConvertError.CreateFmt('JSON field "%s" is not an integer',
      [Name]);
end;

function ReadSingle(Parent: TJSONObject; const Name: string): Single;
begin
  Result := TJSONNumber(RequireValue(Parent, Name,
    TJSONNumber)).AsDouble;
end;

function ReadString(Parent: TJSONObject; const Name: string): string;
begin
  Result := TJSONString(RequireValue(Parent, Name, TJSONString)).Value;
end;

function SerializeVectArtDocument(Document: TVectArtDocument): string;
var
  Canvas: TVectArtCanvasLayer;
  CanvasJson: TJSONObject;
  ContourIndex: Integer;
  ContourJson: TJSONObject;
  ContoursJson: TJSONArray;
  I: Integer;
  Image: TVectArtImageLayer;
  ImageJson: TJSONObject;
  Layer: TVectArtLayer;
  LayersJson: TJSONArray;
  Path: TVectArtPathLayer;
  PathJson: TJSONObject;
  PathVertices: TArray<TScreenLayoutVertex>;
  PointIndex: Integer;
  PointJson: TJSONObject;
  PointsJson: TJSONArray;
  Rectangle: TVectArtRectangleLayer;
  RectangleJson: TJSONObject;
  RoundedRectangle: TScreenLayoutRoundedRectangleLayer;
  RoundedRectangleJson: TJSONObject;
  Root: TJSONObject;
  SerializedSelectedIndex: Integer;
  Shape: TScreenLayoutShapeLayer;
  ShapeContours: TArray<TScreenLayoutContour>;
  ShapeJson: TJSONObject;
  VertexIndex: Integer;
  VertexJson: TJSONObject;
  VerticesJson: TJSONArray;
begin
  if Document = nil then
    raise EArgumentNilException.Create('Document');
  Canvas := Document.CanvasLayer;
  if Canvas = nil then
    raise EInvalidOp.Create('Document canvas is missing');

  Root := TJSONObject.Create;
  try
    SerializedSelectedIndex := -1;
    Root.AddPair('version', TJSONNumber.Create(DOCUMENT_FORMAT_VERSION));
    CanvasJson := TJSONObject.Create;
    CanvasJson.AddPair('width', TJSONNumber.Create(Canvas.Width));
    CanvasJson.AddPair('height', TJSONNumber.Create(Canvas.Height));
    CanvasJson.AddPair('backgroundColor',
      TJSONNumber.Create(Integer(Canvas.BackgroundColor)));
    CanvasJson.AddPair('transparent', TJSONBool.Create(Canvas.Transparent));
    Root.AddPair('canvas', CanvasJson);

    LayersJson := TJSONArray.Create;
    Root.AddPair('layers', LayersJson);
    for I := 1 to Document.LayerCount - 1 do
    begin
      Layer := Document.Layers[I];
      if Layer is TVectArtImageLayer then
      begin
        Image := TVectArtImageLayer(Layer);
        if Image.SourceFileName = '' then
          Continue;
        ImageJson := TJSONObject.Create;
        ImageJson.AddPair('type', 'image');
        ImageJson.AddPair('name', Image.Name);
        if Image.SourceKind = visLogo then
          ImageJson.AddPair('sourceKind', 'logo')
        else
          ImageJson.AddPair('sourceKind', 'image');
        ImageJson.AddPair('sourceFile', Image.SourceFileName);
        ImageJson.AddPair('opacity', TJSONNumber.Create(Image.Opacity));
        ImageJson.AddPair('visible', TJSONBool.Create(Image.Visible));
        ImageJson.AddPair('locked', TJSONBool.Create(Image.Locked));
        PointsJson := TJSONArray.Create;
        for PointIndex := 0 to High(Image.Points) do
        begin
          PointJson := TJSONObject.Create;
          PointJson.AddPair('x', TJSONNumber.Create(
            Image.Points[PointIndex].X));
          PointJson.AddPair('y', TJSONNumber.Create(
            Image.Points[PointIndex].Y));
          PointsJson.AddElement(PointJson);
        end;
        ImageJson.AddPair('points', PointsJson);
        LayersJson.AddElement(ImageJson);
        if I = Document.SelectedIndex then
          SerializedSelectedIndex := LayersJson.Count;
        Continue;
      end;
      if Layer is TVectArtPathLayer then
      begin
        Path := TVectArtPathLayer(Layer);
        PathJson := TJSONObject.Create;
        PathJson.AddPair('type', 'path');
        PathJson.AddPair('name', Path.Name);
        PathJson.AddPair('closed', TJSONBool.Create(Path.Closed));
        PathJson.AddPair('opacity', TJSONNumber.Create(Path.Opacity));
        PathJson.AddPair('strokeColor',
          TJSONNumber.Create(Integer(Path.StrokeColor)));
        PathJson.AddPair('strokeWidth', TJSONNumber.Create(Path.StrokeWidth));
        PathJson.AddPair('strokeStyle',
          TJSONNumber.Create(Ord(Path.MifStrokeStyle)));
        PathJson.AddPair('lineCap', TJSONNumber.Create(Ord(Path.LineCap)));
        PathJson.AddPair('visible', TJSONBool.Create(Path.Visible));
        PathJson.AddPair('locked', TJSONBool.Create(Path.Locked));
        VerticesJson := TJSONArray.Create;
        PathVertices := Path.Vertices;
        for VertexIndex := 0 to High(PathVertices) do
        begin
          VertexJson := TJSONObject.Create;
          with PathVertices[VertexIndex] do
          begin
            VertexJson.AddPair('x', TJSONNumber.Create(Position.X));
            VertexJson.AddPair('y', TJSONNumber.Create(Position.Y));
            VertexJson.AddPair('incomingX',
              TJSONNumber.Create(IncomingControl.X));
            VertexJson.AddPair('incomingY',
              TJSONNumber.Create(IncomingControl.Y));
            VertexJson.AddPair('outgoingX',
              TJSONNumber.Create(OutgoingControl.X));
            VertexJson.AddPair('outgoingY',
              TJSONNumber.Create(OutgoingControl.Y));
            if Kind = slvkBezier then
              VertexJson.AddPair('kind', 'bezier')
            else
              VertexJson.AddPair('kind', 'sharp');
            if OutgoingSegment = slskCubicBezier then
              VertexJson.AddPair('outgoingSegment', 'cubicBezier')
            else
              VertexJson.AddPair('outgoingSegment', 'line');
          end;
          VerticesJson.AddElement(VertexJson);
        end;
        PathJson.AddPair('vertices', VerticesJson);
        LayersJson.AddElement(PathJson);
        if I = Document.SelectedIndex then
          SerializedSelectedIndex := LayersJson.Count;
        Continue;
      end;
      if Layer is TScreenLayoutShapeLayer then
      begin
        Shape := TScreenLayoutShapeLayer(Layer);
        ShapeJson := TJSONObject.Create;
        ShapeJson.AddPair('type', 'shape');
        ShapeJson.AddPair('name', Shape.Name);
        ShapeJson.AddPair('opacity', TJSONNumber.Create(Shape.Opacity));
        ShapeJson.AddPair('fillColor',
          TJSONNumber.Create(Integer(Shape.FillColor)));
        ShapeJson.AddPair('fillRule',
          TJSONNumber.Create(Ord(Shape.FillRule)));
        ShapeJson.AddPair('strokeColor',
          TJSONNumber.Create(Integer(Shape.StrokeColor)));
        ShapeJson.AddPair('strokeWidth',
          TJSONNumber.Create(Shape.StrokeWidth));
        ShapeJson.AddPair('strokeStyle',
          TJSONNumber.Create(Ord(Shape.StrokeStyle)));
        ShapeJson.AddPair('visible', TJSONBool.Create(Shape.Visible));
        ShapeJson.AddPair('locked', TJSONBool.Create(Shape.Locked));
        ContoursJson := TJSONArray.Create;
        ShapeContours := Shape.Contours;
        for ContourIndex := 0 to High(ShapeContours) do
        begin
          ContourJson := TJSONObject.Create;
          VerticesJson := TJSONArray.Create;
          for VertexIndex := 0 to
            High(ShapeContours[ContourIndex].Vertices) do
          begin
            VertexJson := TJSONObject.Create;
            with ShapeContours[ContourIndex].Vertices[VertexIndex] do
            begin
              VertexJson.AddPair('x', TJSONNumber.Create(Position.X));
              VertexJson.AddPair('y', TJSONNumber.Create(Position.Y));
              VertexJson.AddPair('incomingX',
                TJSONNumber.Create(IncomingControl.X));
              VertexJson.AddPair('incomingY',
                TJSONNumber.Create(IncomingControl.Y));
              VertexJson.AddPair('outgoingX',
                TJSONNumber.Create(OutgoingControl.X));
              VertexJson.AddPair('outgoingY',
                TJSONNumber.Create(OutgoingControl.Y));
              if Kind = slvkBezier then
                VertexJson.AddPair('kind', 'bezier')
              else
                VertexJson.AddPair('kind', 'sharp');
              if OutgoingSegment = slskCubicBezier then
                VertexJson.AddPair('outgoingSegment', 'cubicBezier')
              else
                VertexJson.AddPair('outgoingSegment', 'line');
            end;
            VerticesJson.AddElement(VertexJson);
          end;
          ContourJson.AddPair('vertices', VerticesJson);
          ContoursJson.AddElement(ContourJson);
        end;
        ShapeJson.AddPair('contours', ContoursJson);
        LayersJson.AddElement(ShapeJson);
        if I = Document.SelectedIndex then
          SerializedSelectedIndex := LayersJson.Count;
        Continue;
      end;
      if Layer is TScreenLayoutRoundedRectangleLayer then
      begin
        RoundedRectangle := TScreenLayoutRoundedRectangleLayer(Layer);
        RoundedRectangleJson := TJSONObject.Create;
        RoundedRectangleJson.AddPair('type', 'roundedRectangle');
        RoundedRectangleJson.AddPair('name', RoundedRectangle.Name);
        RoundedRectangleJson.AddPair('left',
          TJSONNumber.Create(RoundedRectangle.Bounds.Left));
        RoundedRectangleJson.AddPair('top',
          TJSONNumber.Create(RoundedRectangle.Bounds.Top));
        RoundedRectangleJson.AddPair('right',
          TJSONNumber.Create(RoundedRectangle.Bounds.Right));
        RoundedRectangleJson.AddPair('bottom',
          TJSONNumber.Create(RoundedRectangle.Bounds.Bottom));
        RoundedRectangleJson.AddPair('topLeftRadius',
          TJSONNumber.Create(RoundedRectangle.CornerRadii.TopLeft));
        RoundedRectangleJson.AddPair('topRightRadius',
          TJSONNumber.Create(RoundedRectangle.CornerRadii.TopRight));
        RoundedRectangleJson.AddPair('bottomRightRadius',
          TJSONNumber.Create(RoundedRectangle.CornerRadii.BottomRight));
        RoundedRectangleJson.AddPair('bottomLeftRadius',
          TJSONNumber.Create(RoundedRectangle.CornerRadii.BottomLeft));
        RoundedRectangleJson.AddPair('fillColor',
          TJSONNumber.Create(Integer(RoundedRectangle.FillColor)));
        RoundedRectangleJson.AddPair('opacity',
          TJSONNumber.Create(RoundedRectangle.Opacity));
        RoundedRectangleJson.AddPair('rotation',
          TJSONNumber.Create(RoundedRectangle.RotationDegrees));
        RoundedRectangleJson.AddPair('visible',
          TJSONBool.Create(RoundedRectangle.Visible));
        RoundedRectangleJson.AddPair('locked',
          TJSONBool.Create(RoundedRectangle.Locked));
        LayersJson.AddElement(RoundedRectangleJson);
        if I = Document.SelectedIndex then
          SerializedSelectedIndex := LayersJson.Count;
        Continue;
      end;
      if not (Layer is TVectArtRectangleLayer) then
        Continue;
      Rectangle := TVectArtRectangleLayer(Layer);
      RectangleJson := TJSONObject.Create;
      RectangleJson.AddPair('type', 'rectangle');
      RectangleJson.AddPair('name', Rectangle.Name);
      RectangleJson.AddPair('left',
        TJSONNumber.Create(Rectangle.Bounds.Left));
      RectangleJson.AddPair('top',
        TJSONNumber.Create(Rectangle.Bounds.Top));
      RectangleJson.AddPair('right',
        TJSONNumber.Create(Rectangle.Bounds.Right));
      RectangleJson.AddPair('bottom',
        TJSONNumber.Create(Rectangle.Bounds.Bottom));
      RectangleJson.AddPair('fillColor',
        TJSONNumber.Create(Integer(Rectangle.FillColor)));
      RectangleJson.AddPair('opacity', TJSONNumber.Create(Rectangle.Opacity));
      RectangleJson.AddPair('rotation',
        TJSONNumber.Create(Rectangle.RotationDegrees));
      RectangleJson.AddPair('visible', TJSONBool.Create(Rectangle.Visible));
      RectangleJson.AddPair('locked', TJSONBool.Create(Rectangle.Locked));
      LayersJson.AddElement(RectangleJson);
      if I = Document.SelectedIndex then
        SerializedSelectedIndex := LayersJson.Count;
    end;
    Root.AddPair('selectedIndex',
      TJSONNumber.Create(SerializedSelectedIndex));
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

function TryDeserializeVectArtDocumentCore(const Text, BaseDirectory: string;
  Document: TVectArtDocument; out SkippedReferenceCount: Integer;
  out ErrorMessage: string): Boolean;
var
  Canvas: TVectArtCanvasLayer;
  CanvasColor: Integer;
  CanvasHeight: Integer;
  CanvasJson: TJSONObject;
  CanvasTransparent: Boolean;
  CanvasWidth: Integer;
  ContourIndex: Integer;
  ContourJson: TJSONObject;
  ContoursJson: TJSONArray;
  Data: TVectArtRectangleData;
  Discarded: TVectArtRectangleData;
  DiscardedRoundedRectangle: TScreenLayoutRoundedRectangleData;
  DiscardedPath: TVectArtPathData;
  DiscardedImage: TVectArtImageData;
  DiscardedShape: TScreenLayoutShapeData;
  FillRuleValue: Integer;
  I: Integer;
  ImageData: TArray<TVectArtImageData>;
  ImageFileName: string;
  ImageValue: TVectArtImageData;
  Json: TJSONValue;
  LayerJson: TJSONObject;
  LayerTypes: TArray<string>;
  LayersJson: TJSONArray;
  RectangleData: TArray<TVectArtRectangleData>;
  RoundedRectangleData: TArray<TScreenLayoutRoundedRectangleData>;
  RoundedRectangleValue: TScreenLayoutRoundedRectangleData;
  PathData: TArray<TVectArtPathData>;
  PathValue: TVectArtPathData;
  PointIndex: Integer;
  PointJson: TJSONObject;
  PointsJson: TJSONArray;
  Root: TJSONObject;
  SelectedIndex: Integer;
  SegmentKind: string;
  ShapeData: TArray<TScreenLayoutShapeData>;
  ShapeValue: TScreenLayoutShapeData;
  LoadedSelectedIndex: Integer;
  SourceKind: string;
  VertexIndex: Integer;
  VertexJson: TJSONObject;
  VertexKind: string;
  VerticesJson: TJSONArray;
  LineCapValue: Integer;
  MifStrokeStyleValue: Integer;
  Version: Integer;
begin
  Result := False;
  SkippedReferenceCount := 0;
  ErrorMessage := '';
  if Document = nil then
  begin
    ErrorMessage := 'Document is not assigned';
    Exit;
  end;
  Json := nil;
  try
    try
      Json := TJSONObject.ParseJSONValue(Text);
      if not (Json is TJSONObject) then
        raise EConvertError.Create('Serialized layout is not a JSON object');
      Root := TJSONObject(Json);
      Version := ReadInteger(Root, 'version');
      if Version <> DOCUMENT_FORMAT_VERSION then
        raise EConvertError.CreateFmt('Unsupported layout version: %d',
          [Version]);

      CanvasJson := TJSONObject(RequireValue(Root, 'canvas', TJSONObject));
      CanvasWidth := ReadInteger(CanvasJson, 'width');
      CanvasHeight := ReadInteger(CanvasJson, 'height');
      CanvasColor := ReadInteger(CanvasJson, 'backgroundColor');
      CanvasTransparent := ReadBoolean(CanvasJson, 'transparent');
      if (CanvasWidth <= 0) or (CanvasHeight <= 0) then
        raise EConvertError.Create('Canvas size must be positive');
      LayersJson := TJSONArray(RequireValue(Root, 'layers', TJSONArray));
      SetLength(RectangleData, LayersJson.Count);
      SetLength(RoundedRectangleData, LayersJson.Count);
      SetLength(PathData, LayersJson.Count);
      SetLength(ImageData, LayersJson.Count);
      SetLength(ShapeData, LayersJson.Count);
      SetLength(LayerTypes, LayersJson.Count);
      for I := 0 to LayersJson.Count - 1 do
      begin
        if not (LayersJson.Items[I] is TJSONObject) then
          raise EConvertError.CreateFmt('Layer %d is not a JSON object', [I]);
        LayerJson := TJSONObject(LayersJson.Items[I]);
        LayerTypes[I] := ReadString(LayerJson, 'type');
        if LayerTypes[I] = 'image' then
        begin
          ImageValue.SourceFileName := '';
          ImageValue.Name := ReadString(LayerJson, 'name');
          SourceKind := ReadString(LayerJson, 'sourceKind');
          if SourceKind = 'logo' then
            ImageValue.SourceKind := visLogo
          else if SourceKind = 'image' then
            ImageValue.SourceKind := visImage
          else
            raise EConvertError.CreateFmt(
              'Image layer %d has an invalid source kind', [I]);
          ImageValue.SourceFileName := ReadString(LayerJson, 'sourceFile');
          ImageFileName := ImageValue.SourceFileName;
          if (ImageFileName <> '') and not TPath.IsPathRooted(ImageFileName)
            and (BaseDirectory <> '') then
            ImageFileName := TPath.Combine(BaseDirectory, ImageFileName);
          if (ImageFileName = '') or not TFile.Exists(ImageFileName) then
          begin
            LayerTypes[I] := '';
            Inc(SkippedReferenceCount);
            Continue;
          end;
          ImageFileName := ExpandFileName(ImageFileName);
          ImageValue.SourceFileName := ImageFileName;
          ImageValue.PngData := TFile.ReadAllBytes(ImageFileName);
          ImageValue.Opacity := ReadSingle(LayerJson, 'opacity');
          ImageValue.Visible := ReadBoolean(LayerJson, 'visible');
          ImageValue.Locked := ReadBoolean(LayerJson, 'locked');
          PointsJson := TJSONArray(RequireValue(LayerJson, 'points',
            TJSONArray));
          if PointsJson.Count <> Length(ImageValue.Points) then
            raise EConvertError.CreateFmt(
              'Image layer %d must contain four points', [I]);
          for PointIndex := 0 to PointsJson.Count - 1 do
          begin
            if not (PointsJson.Items[PointIndex] is TJSONObject) then
              raise EConvertError.CreateFmt(
                'Image layer %d point %d is invalid', [I, PointIndex]);
            PointJson := TJSONObject(PointsJson.Items[PointIndex]);
            ImageValue.Points[PointIndex] := TPointF.Create(
              ReadSingle(PointJson, 'x'), ReadSingle(PointJson, 'y'));
          end;
          ImageData[I] := ImageValue;
          Continue;
        end;
        if LayerTypes[I] = 'path' then
        begin
          PathValue.Name := ReadString(LayerJson, 'name');
          PathValue.Closed := ReadBoolean(LayerJson, 'closed');
          PathValue.Opacity := ReadSingle(LayerJson, 'opacity');
          PathValue.StrokeColor := clBlack;
          PathValue.StrokeWidth := 1.0;
          PathValue.MifStrokeStyle := vssSolid;
          PathValue.LineCap := vlcSquare;
          PathValue.StrokeColor := TColor(ReadInteger(LayerJson,
            'strokeColor'));
          PathValue.StrokeWidth := Max(ReadSingle(LayerJson,
            'strokeWidth'), 0.1);
          MifStrokeStyleValue := ReadInteger(LayerJson, 'strokeStyle');
          if InRange(MifStrokeStyleValue,
            Ord(Low(TVectArtMifStrokeStyle)),
            Ord(High(TVectArtMifStrokeStyle))) then
            PathValue.MifStrokeStyle :=
              TVectArtMifStrokeStyle(MifStrokeStyleValue);
          LineCapValue := ReadInteger(LayerJson, 'lineCap');
          if InRange(LineCapValue, Ord(Low(TVectArtLineCap)),
            Ord(High(TVectArtLineCap))) then
            PathValue.LineCap := TVectArtLineCap(LineCapValue);
          PathValue.Visible := ReadBoolean(LayerJson, 'visible');
          PathValue.Locked := ReadBoolean(LayerJson, 'locked');
          VerticesJson := TJSONArray(RequireValue(LayerJson, 'vertices',
            TJSONArray));
          if VerticesJson.Count < 2 then
            raise EConvertError.CreateFmt('Path layer %d has too few points',
              [I]);
          if PathValue.Closed and (VerticesJson.Count < 3) then
            raise EConvertError.CreateFmt(
              'Closed path layer %d must contain at least three points', [I]);
          SetLength(PathValue.Vertices, VerticesJson.Count);
          for VertexIndex := 0 to VerticesJson.Count - 1 do
          begin
            if not (VerticesJson.Items[VertexIndex] is TJSONObject) then
              raise EConvertError.CreateFmt(
                'Path layer %d vertex %d is invalid', [I, VertexIndex]);
            VertexJson := TJSONObject(VerticesJson.Items[VertexIndex]);
            with PathValue.Vertices[VertexIndex] do
            begin
              Position := TPointF.Create(ReadSingle(VertexJson, 'x'),
                ReadSingle(VertexJson, 'y'));
              IncomingControl := TPointF.Create(
                ReadSingle(VertexJson, 'incomingX'),
                ReadSingle(VertexJson, 'incomingY'));
              OutgoingControl := TPointF.Create(
                ReadSingle(VertexJson, 'outgoingX'),
                ReadSingle(VertexJson, 'outgoingY'));
              VertexKind := ReadString(VertexJson, 'kind');
              if VertexKind = 'sharp' then
                Kind := slvkSharp
              else if VertexKind = 'bezier' then
                Kind := slvkBezier
              else
                raise EConvertError.CreateFmt(
                  'Path layer %d vertex %d has an invalid kind',
                  [I, VertexIndex]);
              SegmentKind := ReadString(VertexJson, 'outgoingSegment');
              if SegmentKind = 'line' then
                OutgoingSegment := slskLine
              else if SegmentKind = 'cubicBezier' then
                OutgoingSegment := slskCubicBezier
              else
                raise EConvertError.CreateFmt(
                  'Path layer %d vertex %d has an invalid outgoing segment',
                  [I, VertexIndex]);
            end;
          end;
          PathData[I] := PathValue;
          Continue;
        end;
        if LayerTypes[I] = 'shape' then
        begin
          ShapeValue.Name := ReadString(LayerJson, 'name');
          ShapeValue.Opacity := ReadSingle(LayerJson, 'opacity');
          ShapeValue.FillColor := TColor(ReadInteger(LayerJson,
            'fillColor'));
          FillRuleValue := ReadInteger(LayerJson, 'fillRule');
          if not InRange(FillRuleValue, Ord(Low(TScreenLayoutFillRule)),
            Ord(High(TScreenLayoutFillRule))) then
            raise EConvertError.CreateFmt(
              'Shape layer %d has an invalid fill rule', [I]);
          ShapeValue.FillRule := TScreenLayoutFillRule(FillRuleValue);
          ShapeValue.StrokeColor := TColor(ReadInteger(LayerJson,
            'strokeColor'));
          ShapeValue.StrokeWidth := Max(ReadSingle(LayerJson,
            'strokeWidth'), 0.0);
          MifStrokeStyleValue := ReadInteger(LayerJson, 'strokeStyle');
          if not InRange(MifStrokeStyleValue,
            Ord(Low(TVectArtMifStrokeStyle)),
            Ord(High(TVectArtMifStrokeStyle))) then
            raise EConvertError.CreateFmt(
              'Shape layer %d has an invalid stroke style', [I]);
          ShapeValue.StrokeStyle :=
            TVectArtMifStrokeStyle(MifStrokeStyleValue);
          ShapeValue.Visible := ReadBoolean(LayerJson, 'visible');
          ShapeValue.Locked := ReadBoolean(LayerJson, 'locked');
          ContoursJson := TJSONArray(RequireValue(LayerJson, 'contours',
            TJSONArray));
          if ContoursJson.Count = 0 then
            raise EConvertError.CreateFmt(
              'Shape layer %d must contain at least one contour', [I]);
          SetLength(ShapeValue.Contours, ContoursJson.Count);
          for ContourIndex := 0 to ContoursJson.Count - 1 do
          begin
            if not (ContoursJson.Items[ContourIndex] is TJSONObject) then
              raise EConvertError.CreateFmt(
                'Shape layer %d contour %d is invalid', [I, ContourIndex]);
            ContourJson := TJSONObject(ContoursJson.Items[ContourIndex]);
            VerticesJson := TJSONArray(RequireValue(ContourJson, 'vertices',
              TJSONArray));
            if VerticesJson.Count < 3 then
              raise EConvertError.CreateFmt(
                'Shape layer %d contour %d has too few vertices',
                [I, ContourIndex]);
            SetLength(ShapeValue.Contours[ContourIndex].Vertices,
              VerticesJson.Count);
            for VertexIndex := 0 to VerticesJson.Count - 1 do
            begin
              if not (VerticesJson.Items[VertexIndex] is TJSONObject) then
                raise EConvertError.CreateFmt(
                  'Shape layer %d contour %d vertex %d is invalid',
                  [I, ContourIndex, VertexIndex]);
              VertexJson := TJSONObject(VerticesJson.Items[VertexIndex]);
              with ShapeValue.Contours[ContourIndex].Vertices[
                VertexIndex] do
              begin
                Position := TPointF.Create(ReadSingle(VertexJson, 'x'),
                  ReadSingle(VertexJson, 'y'));
                IncomingControl := TPointF.Create(
                  ReadSingle(VertexJson, 'incomingX'),
                  ReadSingle(VertexJson, 'incomingY'));
                OutgoingControl := TPointF.Create(
                  ReadSingle(VertexJson, 'outgoingX'),
                  ReadSingle(VertexJson, 'outgoingY'));
                VertexKind := ReadString(VertexJson, 'kind');
                if VertexKind = 'sharp' then
                  Kind := slvkSharp
                else if VertexKind = 'bezier' then
                  Kind := slvkBezier
                else
                  raise EConvertError.CreateFmt(
                    'Shape layer %d contour %d vertex %d has an invalid kind',
                    [I, ContourIndex, VertexIndex]);
                SegmentKind := ReadString(VertexJson, 'outgoingSegment');
                if SegmentKind = 'line' then
                  OutgoingSegment := slskLine
                else if SegmentKind = 'cubicBezier' then
                  OutgoingSegment := slskCubicBezier
                else
                  raise EConvertError.CreateFmt(
                    'Shape layer %d contour %d vertex %d has an invalid ' +
                    'outgoing segment', [I, ContourIndex, VertexIndex]);
              end;
            end;
          end;
          ShapeData[I] := ShapeValue;
          Continue;
        end;
        if LayerTypes[I] = 'roundedRectangle' then
        begin
          RoundedRectangleValue.Name := ReadString(LayerJson, 'name');
          RoundedRectangleValue.Bounds := TRectF.Create(
            ReadSingle(LayerJson, 'left'), ReadSingle(LayerJson, 'top'),
            ReadSingle(LayerJson, 'right'), ReadSingle(LayerJson, 'bottom'));
          RoundedRectangleValue.CornerRadii.TopLeft :=
            ReadSingle(LayerJson, 'topLeftRadius');
          RoundedRectangleValue.CornerRadii.TopRight :=
            ReadSingle(LayerJson, 'topRightRadius');
          RoundedRectangleValue.CornerRadii.BottomRight :=
            ReadSingle(LayerJson, 'bottomRightRadius');
          RoundedRectangleValue.CornerRadii.BottomLeft :=
            ReadSingle(LayerJson, 'bottomLeftRadius');
          RoundedRectangleValue.CornerRadii := ClampScreenLayoutCornerRadii(
            RoundedRectangleValue.Bounds,
            RoundedRectangleValue.CornerRadii);
          RoundedRectangleValue.FillColor := TColor(
            ReadInteger(LayerJson, 'fillColor'));
          RoundedRectangleValue.Opacity := ReadSingle(LayerJson, 'opacity');
          RoundedRectangleValue.RotationDegrees :=
            ReadSingle(LayerJson, 'rotation');
          RoundedRectangleValue.Visible := ReadBoolean(LayerJson, 'visible');
          RoundedRectangleValue.Locked := ReadBoolean(LayerJson, 'locked');
          RoundedRectangleData[I] := RoundedRectangleValue;
          Continue;
        end;
        if LayerTypes[I] <> 'rectangle' then
          raise EConvertError.CreateFmt('Layer %d has an unsupported type',
            [I]);
        Data.Name := ReadString(LayerJson, 'name');
        Data.Bounds := TRectF.Create(
          ReadSingle(LayerJson, 'left'), ReadSingle(LayerJson, 'top'),
          ReadSingle(LayerJson, 'right'), ReadSingle(LayerJson, 'bottom'));
        Data.FillColor := TColor(ReadInteger(LayerJson, 'fillColor'));
        Data.Opacity := ReadSingle(LayerJson, 'opacity');
        Data.RotationDegrees := 0.0;
        if LayerJson.GetValue('rotation') is TJSONNumber then
          Data.RotationDegrees := TJSONNumber(
            LayerJson.GetValue('rotation')).AsDouble;
        Data.Visible := ReadBoolean(LayerJson, 'visible');
        Data.Locked := ReadBoolean(LayerJson, 'locked');
        RectangleData[I] := Data;
      end;
      SelectedIndex := ReadInteger(Root, 'selectedIndex');

      Canvas := Document.CanvasLayer;
      if Canvas = nil then
        raise EInvalidOp.Create('Document canvas is missing');
      while Document.LayerCount > 1 do
        if Document[Document.LayerCount - 1] is
          TScreenLayoutRoundedRectangleLayer then
          Document.RemoveRoundedRectangle(Document.LayerCount - 1,
            DiscardedRoundedRectangle)
        else if Document[Document.LayerCount - 1] is TVectArtRectangleLayer then
          Document.RemoveRectangle(Document.LayerCount - 1, Discarded)
        else if Document[Document.LayerCount - 1] is TVectArtPathLayer then
          Document.RemovePath(Document.LayerCount - 1, DiscardedPath)
        else if Document[Document.LayerCount - 1] is TVectArtImageLayer then
          Document.RemoveImage(Document.LayerCount - 1, DiscardedImage)
        else if Document[Document.LayerCount - 1] is
          TScreenLayoutShapeLayer then
          Document.RemoveShape(Document.LayerCount - 1, DiscardedShape)
        else
          raise EInvalidOp.Create('Document contains an unsupported layer');
      Canvas.Width := CanvasWidth;
      Canvas.Height := CanvasHeight;
      Canvas.BackgroundColor := TColor(CanvasColor);
      Canvas.Transparent := CanvasTransparent;
      LoadedSelectedIndex := -1;
      for I := 0 to High(RectangleData) do
      begin
        if LayerTypes[I] = 'rectangle' then
          Document.InsertRectangle(Document.LayerCount, RectangleData[I])
        else if LayerTypes[I] = 'roundedRectangle' then
          Document.InsertRoundedRectangle(Document.LayerCount,
            RoundedRectangleData[I])
        else if LayerTypes[I] = 'image' then
          Document.InsertImage(Document.LayerCount, ImageData[I])
        else if LayerTypes[I] = 'path' then
          Document.InsertPath(Document.LayerCount, PathData[I])
        else if LayerTypes[I] = 'shape' then
          Document.InsertShape(Document.LayerCount, ShapeData[I]);
        if (LayerTypes[I] <> '') and (SelectedIndex = I + 1) then
          LoadedSelectedIndex := Document.LayerCount - 1;
      end;
      Document.SelectedIndex := LoadedSelectedIndex;
      Document.Changed;
      Result := True;
    except
      on E: Exception do
        ErrorMessage := E.Message;
    end;
  finally
    Json.Free;
  end;
end;

function TryDeserializeVectArtDocument(const Text: string;
  Document: TVectArtDocument; out ErrorMessage: string): Boolean;
var
  SkippedReferenceCount: Integer;
begin
  Result := TryDeserializeVectArtDocumentCore(Text, '', Document,
    SkippedReferenceCount, ErrorMessage);
end;

function TryLoadVectArtDocumentFromJsonFile(const FileName: string;
  Document: TVectArtDocument; out SkippedReferenceCount: Integer;
  out ErrorMessage: string): Boolean;
var
  JsonText: string;
begin
  Result := False;
  SkippedReferenceCount := 0;
  ErrorMessage := '';
  try
    JsonText := TFile.ReadAllText(FileName, TEncoding.UTF8);
    Result := TryDeserializeVectArtDocumentCore(JsonText,
      ExtractFilePath(ExpandFileName(FileName)), Document,
      SkippedReferenceCount, ErrorMessage);
  except
    on E: Exception do
      ErrorMessage := E.Message;
  end;
end;

end.
