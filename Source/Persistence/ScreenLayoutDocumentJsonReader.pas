// Document JSONの検証、読み込み、外部画像参照の解決を担当する。
unit ScreenLayoutDocumentJsonReader;

interface

uses
  ScreenLayoutDocument;

// 専用JSONをDocumentへ適用し、失敗時は理由を返す。
function TryDeserializeVectArtDocument(const Text: string;
  Document: TVectArtDocument; out ErrorMessage: string): Boolean;
// JSONファイルを読み込み、無効な外部参照の件数と失敗理由を返す。
function TryLoadVectArtDocumentFromJsonFile(const FileName: string;
  Document: TVectArtDocument; out SkippedReferenceCount: Integer;
  out ErrorMessage: string): Boolean;

implementation

uses
  System.Generics.Collections, System.IOUtils, System.JSON, System.Math,
  System.SysUtils, System.Types, Vcl.Graphics, ScreenLayoutFilters;

const
  DOCUMENT_FORMAT_VERSION = 15;
  DOCUMENT_COORDINATE_ORIGIN = 'center';

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

function ParseFilter(Value: TJSONValue): TScreenLayoutFilter;
var
  Blur: TScreenLayoutBlurFilter;
  FilterJson: TJSONObject;
  FilterType: string;
  Outline: TScreenLayoutOutlineFilter;
  Shadow: TScreenLayoutShadowFilter;
begin
  if not (Value is TJSONObject) then
    raise EConvertError.Create('Filter is not a JSON object');
  FilterJson := TJSONObject(Value);
  FilterType := ReadString(FilterJson, 'type');
  Result := nil;
  try
    if FilterType = 'outline' then
    begin
      Outline := TScreenLayoutOutlineFilter.Create;
      Result := Outline;
      Outline.Color := TColor(ReadInteger(FilterJson, 'color'));
      Outline.Width := ReadSingle(FilterJson, 'width');
      if Outline.Width < 0 then
        raise EConvertError.Create('Outline width must not be negative');
    end
    else if FilterType = 'shadow' then
    begin
      Shadow := TScreenLayoutShadowFilter.Create;
      Result := Shadow;
      Shadow.Color := TColor(ReadInteger(FilterJson, 'color'));
      Shadow.OffsetX := ReadSingle(FilterJson, 'offsetX');
      Shadow.OffsetY := ReadSingle(FilterJson, 'offsetY');
      Shadow.BlurRadius := ReadSingle(FilterJson, 'blurRadius');
      Shadow.Opacity := ReadSingle(FilterJson, 'opacity');
      if Shadow.BlurRadius < 0 then
        raise EConvertError.Create(
          'Shadow blur radius must not be negative');
      if (Shadow.Opacity < 0) or (Shadow.Opacity > 1) then
        raise EConvertError.Create('Shadow opacity must be between 0 and 1');
    end
    else if FilterType = 'blur' then
    begin
      Blur := TScreenLayoutBlurFilter.Create;
      Result := Blur;
      Blur.Radius := ReadSingle(FilterJson, 'radius');
      if Blur.Radius < 0 then
        raise EConvertError.Create('Blur radius must not be negative');
    end
    else
      raise EConvertError.CreateFmt('Unsupported filter type: %s',
        [FilterType]);
    Result.Enabled := ReadBoolean(FilterJson, 'enabled');
  except
    Result.Free;
    raise;
  end;
end;

procedure ValidateLayerFilters(LayerJson: TJSONObject);
var
  Filter: TScreenLayoutFilter;
  FiltersJson: TJSONArray;
  I: Integer;
begin
  FiltersJson := TJSONArray(RequireValue(LayerJson, 'filters', TJSONArray));
  for I := 0 to FiltersJson.Count - 1 do
  begin
    Filter := ParseFilter(FiltersJson.Items[I]);
    Filter.Free;
  end;
end;

procedure LoadLayerFilters(LayerJson: TJSONObject; Layer: TVectArtLayer);
var
  Filter: TScreenLayoutFilter;
  FiltersJson: TJSONArray;
  I: Integer;
begin
  FiltersJson := TJSONArray(RequireValue(LayerJson, 'filters', TJSONArray));
  Layer.ClearFilters;
  for I := 0 to FiltersJson.Count - 1 do
  begin
    Filter := ParseFilter(FiltersJson.Items[I]);
    try
      Layer.AddFilter(Filter);
    except
      Filter.Free;
      raise;
    end;
  end;
end;

function TryDeserializeVectArtDocumentCore(const Text, BaseDirectory: string;
  Document: TVectArtDocument; out SkippedReferenceCount: Integer;
  out ErrorMessage: string): Boolean;
var
  ArcData: TArray<TScreenLayoutArcData>;
  ArcValue: TScreenLayoutArcData;
  ArcShapeData: TArray<TScreenLayoutEllipseArcShapeData>;
  ArcShapeValue: TScreenLayoutEllipseArcShapeData;
  Canvas: TVectArtCanvasLayer;
  CanvasColor: Integer;
  CanvasHeight: Integer;
  CanvasJson: TJSONObject;
  CanvasOrigin: string;
  CanvasTransparent: Boolean;
  CanvasWidth: Integer;
  ContourIndex: Integer;
  ContourJson: TJSONObject;
  ContoursJson: TJSONArray;
  Data: TVectArtRectangleData;
  Discarded: TVectArtRectangleData;
  DiscardedArc: TScreenLayoutArcData;
  DiscardedArcShape: TScreenLayoutEllipseArcShapeData;
  DiscardedEllipse: TScreenLayoutEllipseData;
  DiscardedEllipseLine: TScreenLayoutEllipseLineData;
  DiscardedRoundedRectangle: TScreenLayoutRoundedRectangleData;
  DiscardedRoundedRectangleLine: TScreenLayoutRoundedRectangleLineData;
  DiscardedPath: TVectArtPathData;
  DiscardedRectangleLine: TScreenLayoutRectangleLineData;
  DiscardedImage: TVectArtImageData;
  DiscardedShape: TScreenLayoutShapeData;
  DiscardedText: TScreenLayoutTextData;
  FillRuleValue: Integer;
  GroupData: TArray<TScreenLayoutGroupLayer>;
  GroupJson: TJSONObject;
  GroupLayersJson: TJSONArray;
  GroupValue: TScreenLayoutGroupLayer;
  ChildDocument: TVectArtDocument;
  ChildIndex: Integer;
  ChildRoot: TJSONObject;
  ChildLayers: TJSONArray;
  ChildSkippedReferenceCount: Integer;
  ChildErrorMessage: string;
  ChildText: string;
  ExtractedLayer: TVectArtLayer;
  I: Integer;
  ImageData: TArray<TVectArtImageData>;
  ImageFileName: string;
  ImageValue: TVectArtImageData;
  Json: TJSONValue;
  LayerJson: TJSONObject;
  LayerTypes: TArray<string>;
  LayersJson: TJSONArray;
  EllipseData: TArray<TScreenLayoutEllipseData>;
  EllipseValue: TScreenLayoutEllipseData;
  EllipseLineData: TArray<TScreenLayoutEllipseLineData>;
  EllipseLineValue: TScreenLayoutEllipseLineData;
  RectangleData: TArray<TVectArtRectangleData>;
  RectangleLineData: TArray<TScreenLayoutRectangleLineData>;
  RectangleLineValue: TScreenLayoutRectangleLineData;
  RoundedRectangleData: TArray<TScreenLayoutRoundedRectangleData>;
  RoundedRectangleValue: TScreenLayoutRoundedRectangleData;
  RoundedRectangleLineData: TArray<TScreenLayoutRoundedRectangleLineData>;
  RoundedRectangleLineValue: TScreenLayoutRoundedRectangleLineData;
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
  TextData: TArray<TScreenLayoutTextData>;
  TextValue: TScreenLayoutTextData;
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
      CanvasOrigin := ReadString(CanvasJson, 'origin');
      CanvasColor := ReadInteger(CanvasJson, 'backgroundColor');
      CanvasTransparent := ReadBoolean(CanvasJson, 'transparent');
      if (CanvasWidth <= 0) or (CanvasHeight <= 0) then
        raise EConvertError.Create('Canvas size must be positive');
      if CanvasOrigin <> DOCUMENT_COORDINATE_ORIGIN then
        raise EConvertError.CreateFmt('Unsupported coordinate origin: %s',
          [CanvasOrigin]);
      LayersJson := TJSONArray(RequireValue(Root, 'layers', TJSONArray));
      SetLength(RectangleData, LayersJson.Count);
      SetLength(RectangleLineData, LayersJson.Count);
      SetLength(RoundedRectangleData, LayersJson.Count);
      SetLength(RoundedRectangleLineData, LayersJson.Count);
      SetLength(EllipseData, LayersJson.Count);
      SetLength(EllipseLineData, LayersJson.Count);
      SetLength(ArcData, LayersJson.Count);
      SetLength(ArcShapeData, LayersJson.Count);
      SetLength(PathData, LayersJson.Count);
      SetLength(ImageData, LayersJson.Count);
      SetLength(ShapeData, LayersJson.Count);
      SetLength(TextData, LayersJson.Count);
      SetLength(GroupData, LayersJson.Count);
      SetLength(LayerTypes, LayersJson.Count);
      for I := 0 to LayersJson.Count - 1 do
      begin
        if not (LayersJson.Items[I] is TJSONObject) then
          raise EConvertError.CreateFmt('Layer %d is not a JSON object', [I]);
        LayerJson := TJSONObject(LayersJson.Items[I]);
        ValidateLayerFilters(LayerJson);
        LayerTypes[I] := ReadString(LayerJson, 'type');
        if LayerTypes[I] = 'group' then
        begin
          GroupJson := LayerJson;
          GroupValue := TScreenLayoutGroupLayer.Create(
            ReadString(GroupJson, 'name'));
          try
            GroupValue.Opacity := ReadSingle(GroupJson, 'opacity');
            GroupValue.Visible := ReadBoolean(GroupJson, 'visible');
            GroupValue.Locked := ReadBoolean(GroupJson, 'locked');
            GroupLayersJson := TJSONArray(RequireValue(GroupJson, 'layers',
              TJSONArray));
            for ChildIndex := 0 to GroupLayersJson.Count - 1 do
            begin
              if not (GroupLayersJson.Items[ChildIndex] is TJSONObject) then
                raise EConvertError.CreateFmt(
                  'Group child %d is not a JSON object', [ChildIndex]);
              ChildRoot := TJSONObject.Create;
              try
                ChildRoot.AddPair('version',
                  TJSONNumber.Create(DOCUMENT_FORMAT_VERSION));
                ChildRoot.AddPair('canvas', TJSONObject.ParseJSONValue(
                  CanvasJson.ToJSON));
                ChildLayers := TJSONArray.Create;
                ChildLayers.AddElement(TJSONObject.ParseJSONValue(
                  GroupLayersJson.Items[ChildIndex].ToJSON));
                ChildRoot.AddPair('layers', ChildLayers);
                ChildRoot.AddPair('selectedIndex', TJSONNumber.Create(-1));
                ChildText := ChildRoot.ToJSON;
              finally
                ChildRoot.Free;
              end;
              ChildDocument := TVectArtDocument.Create;
              try
                if not TryDeserializeVectArtDocumentCore(ChildText,
                  BaseDirectory, ChildDocument, ChildSkippedReferenceCount,
                  ChildErrorMessage) then
                  raise EConvertError.CreateFmt(
                    'Cannot load group child %d: %s',
                    [ChildIndex, ChildErrorMessage]);
                Inc(SkippedReferenceCount, ChildSkippedReferenceCount);
                if ChildDocument.LayerCount > 1 then
                begin
                  ExtractedLayer := ChildDocument.ExtractLayer(1);
                  GroupValue.AddChild(ExtractedLayer);
                end;
              finally
                ChildDocument.Free;
              end;
            end;
            GroupData[I] := GroupValue;
            GroupValue := nil;
          finally
            GroupValue.Free;
          end;
          Continue;
        end;
        if LayerTypes[I] = 'text' then
        begin
          TextValue.Name := ReadString(LayerJson, 'name');
          TextValue.Text := ReadString(LayerJson, 'text');
          TextValue.FontFamily := ReadString(LayerJson, 'fontFamily');
          TextValue.FontSize := Max(ReadSingle(LayerJson, 'fontSize'), 1.0);
          TextValue.WrapWidth := Max(ReadSingle(LayerJson, 'wrapWidth'), 1.0);
          TextValue.Bounds := TRectF.Create(
            ReadSingle(LayerJson, 'left'), ReadSingle(LayerJson, 'top'),
            ReadSingle(LayerJson, 'right'), ReadSingle(LayerJson, 'bottom'));
          TextValue.RotationDegrees := ReadSingle(LayerJson, 'rotation');
          TextValue.TextColor := TColor(ReadInteger(LayerJson, 'textColor'));
          TextValue.Opacity := ReadSingle(LayerJson, 'opacity');
          TextValue.Visible := ReadBoolean(LayerJson, 'visible');
          TextValue.Locked := ReadBoolean(LayerJson, 'locked');
          TextData[I] := TextValue;
          Continue;
        end;
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
        if LayerTypes[I] = 'ellipse' then
        begin
          EllipseValue.Name := ReadString(LayerJson, 'name');
          EllipseValue.Bounds := TRectF.Create(
            ReadSingle(LayerJson, 'left'), ReadSingle(LayerJson, 'top'),
            ReadSingle(LayerJson, 'right'), ReadSingle(LayerJson, 'bottom'));
          EllipseValue.FillColor := TColor(ReadInteger(LayerJson,
            'fillColor'));
          EllipseValue.Opacity := ReadSingle(LayerJson, 'opacity');
          EllipseValue.RotationDegrees := ReadSingle(LayerJson, 'rotation');
          EllipseValue.Visible := ReadBoolean(LayerJson, 'visible');
          EllipseValue.Locked := ReadBoolean(LayerJson, 'locked');
          EllipseData[I] := EllipseValue;
          Continue;
        end;
        if LayerTypes[I] = 'ellipseArcShape' then
        begin
          ArcShapeValue.Name := ReadString(LayerJson, 'name');
          ArcShapeValue.Bounds := TRectF.Create(
            ReadSingle(LayerJson, 'left'), ReadSingle(LayerJson, 'top'),
            ReadSingle(LayerJson, 'right'), ReadSingle(LayerJson, 'bottom'));
          ArcShapeValue.RotationDegrees := ReadSingle(LayerJson, 'rotation');
          ArcShapeValue.StartAngleDegrees :=
            ReadSingle(LayerJson, 'startAngle');
          ArcShapeValue.SweepAngleDegrees :=
            ReadSingle(LayerJson, 'sweepAngle');
          if (ArcShapeValue.SweepAngleDegrees < 0.0) or
            (ArcShapeValue.SweepAngleDegrees > 360.0) then
            raise EConvertError.CreateFmt(
              'Ellipse arc shape layer %d has an invalid sweep angle', [I]);
          ArcShapeValue.FillColor := TColor(ReadInteger(LayerJson,
            'fillColor'));
          ArcShapeValue.Opacity := ReadSingle(LayerJson, 'opacity');
          ArcShapeValue.Visible := ReadBoolean(LayerJson, 'visible');
          ArcShapeValue.Locked := ReadBoolean(LayerJson, 'locked');
          ArcShapeData[I] := ArcShapeValue;
          Continue;
        end;
        if LayerTypes[I] = 'ellipseLine' then
        begin
          EllipseLineValue.Name := ReadString(LayerJson, 'name');
          EllipseLineValue.Bounds := TRectF.Create(
            ReadSingle(LayerJson, 'left'), ReadSingle(LayerJson, 'top'),
            ReadSingle(LayerJson, 'right'), ReadSingle(LayerJson, 'bottom'));
          EllipseLineValue.RotationDegrees :=
            ReadSingle(LayerJson, 'rotation');
          EllipseLineValue.StrokeColor := TColor(ReadInteger(LayerJson,
            'strokeColor'));
          EllipseLineValue.StrokeWidth :=
            ReadSingle(LayerJson, 'strokeWidth');
          if EllipseLineValue.StrokeWidth < 0.1 then
            raise EConvertError.CreateFmt(
              'Ellipse line layer %d has an invalid stroke width', [I]);
          MifStrokeStyleValue := ReadInteger(LayerJson, 'strokeStyle');
          if not InRange(MifStrokeStyleValue,
            Ord(Low(TVectArtMifStrokeStyle)),
            Ord(High(TVectArtMifStrokeStyle))) then
            raise EConvertError.CreateFmt(
              'Ellipse line layer %d has an invalid stroke style', [I]);
          EllipseLineValue.StrokeStyle :=
            TVectArtMifStrokeStyle(MifStrokeStyleValue);
          EllipseLineValue.Opacity := ReadSingle(LayerJson, 'opacity');
          EllipseLineValue.Visible := ReadBoolean(LayerJson, 'visible');
          EllipseLineValue.Locked := ReadBoolean(LayerJson, 'locked');
          EllipseLineData[I] := EllipseLineValue;
          Continue;
        end;
        if LayerTypes[I] = 'roundedRectangleLine' then
        begin
          RoundedRectangleLineValue.Name := ReadString(LayerJson, 'name');
          RoundedRectangleLineValue.Bounds := TRectF.Create(
            ReadSingle(LayerJson, 'left'), ReadSingle(LayerJson, 'top'),
            ReadSingle(LayerJson, 'right'), ReadSingle(LayerJson, 'bottom'));
          RoundedRectangleLineValue.RotationDegrees :=
            ReadSingle(LayerJson, 'rotation');
          RoundedRectangleLineValue.CornerRadii.TopLeft :=
            ReadSingle(LayerJson, 'topLeftRadius');
          RoundedRectangleLineValue.CornerRadii.TopRight :=
            ReadSingle(LayerJson, 'topRightRadius');
          RoundedRectangleLineValue.CornerRadii.BottomRight :=
            ReadSingle(LayerJson, 'bottomRightRadius');
          RoundedRectangleLineValue.CornerRadii.BottomLeft :=
            ReadSingle(LayerJson, 'bottomLeftRadius');
          RoundedRectangleLineValue.StrokeColor := TColor(
            ReadInteger(LayerJson, 'strokeColor'));
          RoundedRectangleLineValue.StrokeWidth :=
            ReadSingle(LayerJson, 'strokeWidth');
          if RoundedRectangleLineValue.StrokeWidth < 0.1 then
            raise EConvertError.CreateFmt(
              'Rounded rectangle line layer %d has an invalid stroke width',
              [I]);
          MifStrokeStyleValue := ReadInteger(LayerJson, 'strokeStyle');
          if not InRange(MifStrokeStyleValue,
            Ord(Low(TVectArtMifStrokeStyle)),
            Ord(High(TVectArtMifStrokeStyle))) then
            raise EConvertError.CreateFmt(
              'Rounded rectangle line layer %d has an invalid stroke style',
              [I]);
          RoundedRectangleLineValue.StrokeStyle :=
            TVectArtMifStrokeStyle(MifStrokeStyleValue);
          RoundedRectangleLineValue.Opacity := ReadSingle(LayerJson,
            'opacity');
          RoundedRectangleLineValue.Visible := ReadBoolean(LayerJson,
            'visible');
          RoundedRectangleLineValue.Locked := ReadBoolean(LayerJson,
            'locked');
          RoundedRectangleLineData[I] := RoundedRectangleLineValue;
          Continue;
        end;
        if LayerTypes[I] = 'rectangleLine' then
        begin
          RectangleLineValue.Name := ReadString(LayerJson, 'name');
          RectangleLineValue.Bounds := TRectF.Create(
            ReadSingle(LayerJson, 'left'), ReadSingle(LayerJson, 'top'),
            ReadSingle(LayerJson, 'right'), ReadSingle(LayerJson, 'bottom'));
          RectangleLineValue.RotationDegrees :=
            ReadSingle(LayerJson, 'rotation');
          RectangleLineValue.StrokeColor := TColor(ReadInteger(LayerJson,
            'strokeColor'));
          RectangleLineValue.StrokeWidth :=
            ReadSingle(LayerJson, 'strokeWidth');
          if RectangleLineValue.StrokeWidth < 0.1 then
            raise EConvertError.CreateFmt(
              'Rectangle line layer %d has an invalid stroke width', [I]);
          MifStrokeStyleValue := ReadInteger(LayerJson, 'strokeStyle');
          if not InRange(MifStrokeStyleValue,
            Ord(Low(TVectArtMifStrokeStyle)),
            Ord(High(TVectArtMifStrokeStyle))) then
            raise EConvertError.CreateFmt(
              'Rectangle line layer %d has an invalid stroke style', [I]);
          RectangleLineValue.StrokeStyle :=
            TVectArtMifStrokeStyle(MifStrokeStyleValue);
          RectangleLineValue.Opacity := ReadSingle(LayerJson, 'opacity');
          RectangleLineValue.Visible := ReadBoolean(LayerJson, 'visible');
          RectangleLineValue.Locked := ReadBoolean(LayerJson, 'locked');
          RectangleLineData[I] := RectangleLineValue;
          Continue;
        end;
        if LayerTypes[I] = 'arc' then
        begin
          ArcValue.Name := ReadString(LayerJson, 'name');
          ArcValue.Bounds := TRectF.Create(
            ReadSingle(LayerJson, 'left'), ReadSingle(LayerJson, 'top'),
            ReadSingle(LayerJson, 'right'), ReadSingle(LayerJson, 'bottom'));
          ArcValue.RotationDegrees := ReadSingle(LayerJson, 'rotation');
          ArcValue.StartAngleDegrees := ReadSingle(LayerJson, 'startAngle');
          ArcValue.SweepAngleDegrees := ReadSingle(LayerJson, 'sweepAngle');
          if (ArcValue.SweepAngleDegrees < 0.0) or
            (ArcValue.SweepAngleDegrees > 360.0) then
            raise EConvertError.CreateFmt(
              'Arc layer %d has an invalid sweep angle', [I]);
          ArcValue.StrokeColor := TColor(ReadInteger(LayerJson,
            'strokeColor'));
          ArcValue.StrokeWidth := ReadSingle(LayerJson, 'strokeWidth');
          if ArcValue.StrokeWidth < 0.1 then
            raise EConvertError.CreateFmt(
              'Arc layer %d has an invalid stroke width', [I]);
          MifStrokeStyleValue := ReadInteger(LayerJson, 'strokeStyle');
          if not InRange(MifStrokeStyleValue,
            Ord(Low(TVectArtMifStrokeStyle)),
            Ord(High(TVectArtMifStrokeStyle))) then
            raise EConvertError.CreateFmt(
              'Arc layer %d has an invalid stroke style', [I]);
          ArcValue.StrokeStyle :=
            TVectArtMifStrokeStyle(MifStrokeStyleValue);
          LineCapValue := ReadInteger(LayerJson, 'lineCap');
          if not InRange(LineCapValue, Ord(Low(TVectArtLineCap)),
            Ord(High(TVectArtLineCap))) then
            raise EConvertError.CreateFmt(
              'Arc layer %d has an invalid line cap', [I]);
          ArcValue.LineCap := TVectArtLineCap(LineCapValue);
          ArcValue.Opacity := ReadSingle(LayerJson, 'opacity');
          ArcValue.Visible := ReadBoolean(LayerJson, 'visible');
          ArcValue.Locked := ReadBoolean(LayerJson, 'locked');
          ArcData[I] := ArcValue;
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
        if Document[Document.LayerCount - 1] is TScreenLayoutGroupLayer then
        begin
          ExtractedLayer := Document.ExtractLayer(Document.LayerCount - 1);
          ExtractedLayer.Free;
        end
        else if Document[Document.LayerCount - 1] is
          TScreenLayoutEllipseArcShapeLayer then
          Document.RemoveEllipseArcShape(Document.LayerCount - 1,
            DiscardedArcShape)
        else if Document[Document.LayerCount - 1] is TScreenLayoutEllipseLineLayer then
          Document.RemoveEllipseLine(Document.LayerCount - 1,
            DiscardedEllipseLine)
        else if Document[Document.LayerCount - 1] is
          TScreenLayoutRoundedRectangleLineLayer then
          Document.RemoveRoundedRectangleLine(Document.LayerCount - 1,
            DiscardedRoundedRectangleLine)
        else if Document[Document.LayerCount - 1] is
          TScreenLayoutRectangleLineLayer then
          Document.RemoveRectangleLine(Document.LayerCount - 1,
            DiscardedRectangleLine)
        else if Document[Document.LayerCount - 1] is TScreenLayoutEllipseLayer then
          Document.RemoveEllipse(Document.LayerCount - 1,
            DiscardedEllipse)
        else if Document[Document.LayerCount - 1] is TScreenLayoutArcLayer then
          Document.RemoveArc(Document.LayerCount - 1, DiscardedArc)
        else if Document[Document.LayerCount - 1] is
          TScreenLayoutRoundedRectangleLayer then
          Document.RemoveRoundedRectangle(Document.LayerCount - 1,
            DiscardedRoundedRectangle)
        else if Document[Document.LayerCount - 1] is TScreenLayoutTextLayer then
          Document.RemoveText(Document.LayerCount - 1, DiscardedText)
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
        if LayerTypes[I] = 'ellipseArcShape' then
          Document.InsertEllipseArcShape(Document.LayerCount, ArcShapeData[I])
        else if LayerTypes[I] = 'group' then
        begin
          Document.InsertLayer(Document.LayerCount, GroupData[I]);
          GroupData[I] := nil;
        end
        else if LayerTypes[I] = 'ellipseLine' then
          Document.InsertEllipseLine(Document.LayerCount, EllipseLineData[I])
        else if LayerTypes[I] = 'roundedRectangleLine' then
          Document.InsertRoundedRectangleLine(Document.LayerCount,
            RoundedRectangleLineData[I])
        else if LayerTypes[I] = 'rectangleLine' then
          Document.InsertRectangleLine(Document.LayerCount,
            RectangleLineData[I])
        else if LayerTypes[I] = 'rectangle' then
          Document.InsertRectangle(Document.LayerCount, RectangleData[I])
        else if LayerTypes[I] = 'roundedRectangle' then
          Document.InsertRoundedRectangle(Document.LayerCount,
            RoundedRectangleData[I])
        else if LayerTypes[I] = 'ellipse' then
          Document.InsertEllipse(Document.LayerCount, EllipseData[I])
        else if LayerTypes[I] = 'arc' then
          Document.InsertArc(Document.LayerCount, ArcData[I])
        else if LayerTypes[I] = 'image' then
          Document.InsertImage(Document.LayerCount, ImageData[I])
        else if LayerTypes[I] = 'text' then
          Document.InsertText(Document.LayerCount, TextData[I])
        else if LayerTypes[I] = 'path' then
          Document.InsertPath(Document.LayerCount, PathData[I])
        else if LayerTypes[I] = 'shape' then
          Document.InsertShape(Document.LayerCount, ShapeData[I]);
        if LayerTypes[I] <> '' then
          LoadLayerFilters(TJSONObject(LayersJson.Items[I]),
            Document[Document.LayerCount - 1]);
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
    for I := 0 to High(GroupData) do
      GroupData[I].Free;
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
