// 配置DocumentをAviUtl2の文字列項目へ保存できるJSONへ相互変換する。
unit VectArtDesignerDocumentJson;

interface

uses
  VectArtDesignerDocument;

// Documentを埋め込み用JSONへ変換する。既存キー名は内部のMif改名後も維持する。
function SerializeVectArtDocument(Document: TVectArtDocument): string;
// 既存キーを含むJSONをDocumentへ適用する。Documentを所有しない。
function TryDeserializeVectArtDocument(const Text: string;
  Document: TVectArtDocument; out ErrorMessage: string): Boolean;

implementation

uses
  System.Generics.Collections, System.JSON, System.Math, System.NetEncoding,
  System.SysUtils, System.Types,
  Vcl.Graphics;

const
  DOCUMENT_FORMAT_VERSION = 1;

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
  I: Integer;
  Image: TVectArtImageLayer;
  ImageJson: TJSONObject;
  Layer: TVectArtLayer;
  Line: TVectArtLineLayer;
  LineJson: TJSONObject;
  LayersJson: TJSONArray;
  Path: TVectArtPathLayer;
  PathJson: TJSONObject;
  PointIndex: Integer;
  PointJson: TJSONObject;
  PointsJson: TJSONArray;
  Rectangle: TVectArtRectangleLayer;
  RectangleJson: TJSONObject;
  Root: TJSONObject;
begin
  if Document = nil then
    raise EArgumentNilException.Create('Document');
  Canvas := Document.CanvasLayer;
  if Canvas = nil then
    raise EInvalidOp.Create('Document canvas is missing');

  Root := TJSONObject.Create;
  try
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
        ImageJson := TJSONObject.Create;
        ImageJson.AddPair('type', 'image');
        ImageJson.AddPair('name', Image.Name);
        if Image.SourceKind = visLogo then
          ImageJson.AddPair('sourceKind', 'logo')
        else
          ImageJson.AddPair('sourceKind', 'image');
        ImageJson.AddPair('pngBase64',
          TNetEncoding.Base64.EncodeBytesToString(Image.PngData));
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
        Continue;
      end;
      if Layer is TVectArtLineLayer then
      begin
        Line := TVectArtLineLayer(Layer);
        LineJson := TJSONObject.Create;
        LineJson.AddPair('type', 'line');
        LineJson.AddPair('name', Line.Name);
        LineJson.AddPair('startX', TJSONNumber.Create(Line.StartPoint.X));
        LineJson.AddPair('startY', TJSONNumber.Create(Line.StartPoint.Y));
        LineJson.AddPair('endX', TJSONNumber.Create(Line.EndPoint.X));
        LineJson.AddPair('endY', TJSONNumber.Create(Line.EndPoint.Y));
        LineJson.AddPair('opacity', TJSONNumber.Create(Line.Opacity));
        LineJson.AddPair('strokeColor',
          TJSONNumber.Create(Integer(Line.StrokeColor)));
        LineJson.AddPair('strokeWidth',
          TJSONNumber.Create(Line.StrokeWidth));
        LineJson.AddPair('strokeStyle',
          TJSONNumber.Create(Ord(Line.MifStrokeStyle)));
        LineJson.AddPair('lineCap', TJSONNumber.Create(Ord(Line.LineCap)));
        LineJson.AddPair('lineJoin', TJSONNumber.Create(Ord(Line.LineJoin)));
        LineJson.AddPair('antiAlias', TJSONBool.Create(Line.MifAntiAlias));
        LineJson.AddPair('endMarker', TJSONNumber.Create(Ord(Line.MifEndMarker)));
        LineJson.AddPair('endMarkerSize', TJSONNumber.Create(Line.MifEndMarkerSize));
        LineJson.AddPair('startMarker',
          TJSONNumber.Create(Ord(Line.MifStartMarker)));
        LineJson.AddPair('startMarkerSize',
          TJSONNumber.Create(Line.MifStartMarkerSize));
        LineJson.AddPair('visible', TJSONBool.Create(Line.Visible));
        LineJson.AddPair('locked', TJSONBool.Create(Line.Locked));
        LayersJson.AddElement(LineJson);
        Continue;
      end;
      if Layer is TVectArtPathLayer then
      begin
        Path := TVectArtPathLayer(Layer);
        PathJson := TJSONObject.Create;
        PathJson.AddPair('type', 'path');
        PathJson.AddPair('name', Path.Name);
        PathJson.AddPair('closed', TJSONBool.Create(Path.Closed));
        PathJson.AddPair('filled', TJSONBool.Create(Path.Filled));
        PathJson.AddPair('fillColor',
          TJSONNumber.Create(Integer(Path.FillColor)));
        PathJson.AddPair('opacity', TJSONNumber.Create(Path.Opacity));
        PathJson.AddPair('strokeColor',
          TJSONNumber.Create(Integer(Path.StrokeColor)));
        PathJson.AddPair('strokeWidth',
          TJSONNumber.Create(Path.StrokeWidth));
        PathJson.AddPair('strokeStyle',
          TJSONNumber.Create(Ord(Path.MifStrokeStyle)));
        PathJson.AddPair('lineCap', TJSONNumber.Create(Ord(Path.LineCap)));
        PathJson.AddPair('lineJoin', TJSONNumber.Create(Ord(Path.LineJoin)));
        PathJson.AddPair('antiAlias', TJSONBool.Create(Path.MifAntiAlias));
        PathJson.AddPair('visible', TJSONBool.Create(Path.Visible));
        PathJson.AddPair('locked', TJSONBool.Create(Path.Locked));
        PointsJson := TJSONArray.Create;
        for PointIndex := 0 to High(Path.Points) do
        begin
          PointJson := TJSONObject.Create;
          PointJson.AddPair('x', TJSONNumber.Create(Path.Points[PointIndex].X));
          PointJson.AddPair('y', TJSONNumber.Create(Path.Points[PointIndex].Y));
          PointsJson.AddElement(PointJson);
        end;
        PathJson.AddPair('points', PointsJson);
        LayersJson.AddElement(PathJson);
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
      RectangleJson.AddPair('strokeColor',
        TJSONNumber.Create(Integer(Rectangle.StrokeColor)));
      RectangleJson.AddPair('strokeWidth',
        TJSONNumber.Create(Rectangle.StrokeWidth));
      RectangleJson.AddPair('strokeStyle',
        TJSONNumber.Create(Ord(Rectangle.MifStrokeStyle)));
      RectangleJson.AddPair('visible', TJSONBool.Create(Rectangle.Visible));
      RectangleJson.AddPair('locked', TJSONBool.Create(Rectangle.Locked));
      LayersJson.AddElement(RectangleJson);
    end;
    Root.AddPair('selectedIndex',
      TJSONNumber.Create(Document.SelectedIndex));
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

function TryDeserializeVectArtDocument(const Text: string;
  Document: TVectArtDocument; out ErrorMessage: string): Boolean;
var
  Canvas: TVectArtCanvasLayer;
  CanvasColor: Integer;
  CanvasHeight: Integer;
  CanvasJson: TJSONObject;
  CanvasTransparent: Boolean;
  CanvasWidth: Integer;
  Data: TVectArtRectangleData;
  Discarded: TVectArtRectangleData;
  DiscardedLine: TVectArtLineData;
  DiscardedPath: TVectArtPathData;
  DiscardedImage: TVectArtImageData;
  I: Integer;
  ImageData: TArray<TVectArtImageData>;
  ImageValue: TVectArtImageData;
  Json: TJSONValue;
  LayerJson: TJSONObject;
  LayerTypes: TArray<string>;
  LayersJson: TJSONArray;
  RectangleData: TArray<TVectArtRectangleData>;
  LineData: TArray<TVectArtLineData>;
  LineValue: TVectArtLineData;
  PathData: TArray<TVectArtPathData>;
  PathValue: TVectArtPathData;
  PointIndex: Integer;
  PointJson: TJSONObject;
  PointsJson: TJSONArray;
  Root: TJSONObject;
  SelectedIndex: Integer;
  SourceKind: string;
  LineCapValue: Integer;
  LineJoinValue: Integer;
  LineMarkerValue: Integer;
  MifStrokeStyleValue: Integer;
  Version: Integer;
begin
  Result := False;
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
      SetLength(LineData, LayersJson.Count);
      SetLength(PathData, LayersJson.Count);
      SetLength(ImageData, LayersJson.Count);
      SetLength(LayerTypes, LayersJson.Count);
      for I := 0 to LayersJson.Count - 1 do
      begin
        if not (LayersJson.Items[I] is TJSONObject) then
          raise EConvertError.CreateFmt('Layer %d is not a JSON object', [I]);
        LayerJson := TJSONObject(LayersJson.Items[I]);
        LayerTypes[I] := ReadString(LayerJson, 'type');
        if LayerTypes[I] = 'image' then
        begin
          ImageValue.Name := ReadString(LayerJson, 'name');
          SourceKind := ReadString(LayerJson, 'sourceKind');
          if SourceKind = 'logo' then
            ImageValue.SourceKind := visLogo
          else if SourceKind = 'image' then
            ImageValue.SourceKind := visImage
          else
            raise EConvertError.CreateFmt(
              'Image layer %d has an invalid source kind', [I]);
          ImageValue.PngData := TNetEncoding.Base64.DecodeStringToBytes(
            ReadString(LayerJson, 'pngBase64'));
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
        if LayerTypes[I] = 'line' then
        begin
          LineValue.Name := ReadString(LayerJson, 'name');
          LineValue.StartPoint := TPointF.Create(
            ReadSingle(LayerJson, 'startX'), ReadSingle(LayerJson, 'startY'));
          LineValue.EndPoint := TPointF.Create(ReadSingle(LayerJson, 'endX'),
            ReadSingle(LayerJson, 'endY'));
          LineValue.Opacity := ReadSingle(LayerJson, 'opacity');
          LineValue.StrokeColor := TColor(ReadInteger(LayerJson,
            'strokeColor'));
          LineValue.StrokeWidth := Max(ReadSingle(LayerJson,
            'strokeWidth'), 0.1);
          MifStrokeStyleValue := ReadInteger(LayerJson, 'strokeStyle');
          LineValue.MifStrokeStyle := vssSolid;
          if InRange(MifStrokeStyleValue, Ord(Low(TVectArtMifStrokeStyle)),
            Ord(High(TVectArtMifStrokeStyle))) then
            LineValue.MifStrokeStyle := TVectArtMifStrokeStyle(MifStrokeStyleValue);
          LineValue.LineCap := vlcButt;
          if LayerJson.GetValue('lineCap') is TJSONNumber then
          begin
            LineCapValue := TJSONNumber(
              LayerJson.GetValue('lineCap')).AsInt;
            if InRange(LineCapValue, Ord(Low(TVectArtLineCap)),
              Ord(High(TVectArtLineCap))) then
              LineValue.LineCap := TVectArtLineCap(LineCapValue);
          end;
          LineValue.LineJoin := vljMiter;
          if LayerJson.GetValue('lineJoin') is TJSONNumber then
          begin
            LineJoinValue := TJSONNumber(
              LayerJson.GetValue('lineJoin')).AsInt;
            if InRange(LineJoinValue, Ord(Low(TVectArtLineJoin)),
              Ord(High(TVectArtLineJoin))) then
              LineValue.LineJoin := TVectArtLineJoin(LineJoinValue);
          end;
          LineValue.MifAntiAlias := True;
          if LayerJson.GetValue('antiAlias') is TJSONBool then
            LineValue.MifAntiAlias := TJSONBool(
              LayerJson.GetValue('antiAlias')).AsBoolean;
          LineValue.MifEndMarker := vlmNone;
          LineValue.MifEndMarkerSize := 4.0;
          if LayerJson.GetValue('endMarker') is TJSONNumber then
          begin
            LineMarkerValue := TJSONNumber(
              LayerJson.GetValue('endMarker')).AsInt;
            if InRange(LineMarkerValue, Ord(Low(TVectArtMifLineMarker)),
              Ord(High(TVectArtMifLineMarker))) then
              LineValue.MifEndMarker := TVectArtMifLineMarker(LineMarkerValue);
          end;
          if LayerJson.GetValue('endMarkerSize') is TJSONNumber then
            LineValue.MifEndMarkerSize := Max(TJSONNumber(
              LayerJson.GetValue('endMarkerSize')).AsDouble, 1.0);
          LineValue.MifStartMarker := vlmNone;
          LineValue.MifStartMarkerSize := 4.0;
          if LayerJson.GetValue('startMarker') is TJSONNumber then
          begin
            LineMarkerValue := TJSONNumber(
              LayerJson.GetValue('startMarker')).AsInt;
            if InRange(LineMarkerValue, Ord(Low(TVectArtMifLineMarker)),
              Ord(High(TVectArtMifLineMarker))) then
              LineValue.MifStartMarker := TVectArtMifLineMarker(LineMarkerValue);
          end;
          if LayerJson.GetValue('startMarkerSize') is TJSONNumber then
            LineValue.MifStartMarkerSize := Max(TJSONNumber(
              LayerJson.GetValue('startMarkerSize')).AsDouble, 1.0);
          LineValue.Visible := ReadBoolean(LayerJson, 'visible');
          LineValue.Locked := ReadBoolean(LayerJson, 'locked');
          LineData[I] := LineValue;
          Continue;
        end;
        if LayerTypes[I] = 'path' then
        begin
          PathValue.Name := ReadString(LayerJson, 'name');
          PathValue.Closed := ReadBoolean(LayerJson, 'closed');
          PathValue.Filled := ReadBoolean(LayerJson, 'filled');
          PathValue.FillColor := TColor(ReadInteger(LayerJson, 'fillColor'));
          PathValue.Opacity := ReadSingle(LayerJson, 'opacity');
          PathValue.StrokeColor := TColor(ReadInteger(LayerJson,
            'strokeColor'));
          PathValue.StrokeWidth := Max(ReadSingle(LayerJson,
            'strokeWidth'), 0.0);
          MifStrokeStyleValue := ReadInteger(LayerJson, 'strokeStyle');
          PathValue.MifStrokeStyle := vssSolid;
          if InRange(MifStrokeStyleValue, Ord(Low(TVectArtMifStrokeStyle)),
            Ord(High(TVectArtMifStrokeStyle))) then
            PathValue.MifStrokeStyle := TVectArtMifStrokeStyle(MifStrokeStyleValue);
          PathValue.LineCap := vlcButt;
          if LayerJson.GetValue('lineCap') is TJSONNumber then
          begin
            LineCapValue := TJSONNumber(LayerJson.GetValue('lineCap')).AsInt;
            if InRange(LineCapValue, Ord(Low(TVectArtLineCap)),
              Ord(High(TVectArtLineCap))) then
              PathValue.LineCap := TVectArtLineCap(LineCapValue);
          end;
          PathValue.LineJoin := vljMiter;
          if LayerJson.GetValue('lineJoin') is TJSONNumber then
          begin
            LineJoinValue := TJSONNumber(LayerJson.GetValue('lineJoin')).AsInt;
            if InRange(LineJoinValue, Ord(Low(TVectArtLineJoin)),
              Ord(High(TVectArtLineJoin))) then
              PathValue.LineJoin := TVectArtLineJoin(LineJoinValue);
          end;
          PathValue.MifAntiAlias := True;
          if LayerJson.GetValue('antiAlias') is TJSONBool then
            PathValue.MifAntiAlias := TJSONBool(
              LayerJson.GetValue('antiAlias')).AsBoolean;
          PathValue.Visible := ReadBoolean(LayerJson, 'visible');
          PathValue.Locked := ReadBoolean(LayerJson, 'locked');
          PointsJson := TJSONArray(RequireValue(LayerJson, 'points',
            TJSONArray));
          if PointsJson.Count < 2 then
            raise EConvertError.CreateFmt('Path layer %d has too few points',
              [I]);
          SetLength(PathValue.Points, PointsJson.Count);
          for PointIndex := 0 to PointsJson.Count - 1 do
          begin
            if not (PointsJson.Items[PointIndex] is TJSONObject) then
              raise EConvertError.CreateFmt(
                'Path layer %d point %d is invalid', [I, PointIndex]);
            PointJson := TJSONObject(PointsJson.Items[PointIndex]);
            PathValue.Points[PointIndex] := TPointF.Create(
              ReadSingle(PointJson, 'x'), ReadSingle(PointJson, 'y'));
          end;
          PathData[I] := PathValue;
          Continue;
        end;
        if LayerTypes[I] <> 'rectangle' then
          raise EConvertError.CreateFmt('Layer %d has an unsupported type',
            [I]);
        Data.Name := ReadString(LayerJson, 'name');
        Data.Bounds := TRectF.Create(
          ReadSingle(LayerJson, 'left'),
          ReadSingle(LayerJson, 'top'),
          ReadSingle(LayerJson, 'right'),
          ReadSingle(LayerJson, 'bottom'));
        Data.FillColor := TColor(ReadInteger(LayerJson, 'fillColor'));
        Data.Opacity := ReadSingle(LayerJson, 'opacity');
        Data.RotationDegrees := 0.0;
        if LayerJson.GetValue('rotation') is TJSONNumber then
          Data.RotationDegrees := TJSONNumber(
            LayerJson.GetValue('rotation')).AsDouble;
        Data.StrokeColor := clBlack;
        if LayerJson.GetValue('strokeColor') is TJSONNumber then
          Data.StrokeColor := TColor(TJSONNumber(
            LayerJson.GetValue('strokeColor')).AsInt);
        Data.StrokeWidth := 0.0;
        if LayerJson.GetValue('strokeWidth') is TJSONNumber then
          Data.StrokeWidth := Max(TJSONNumber(
            LayerJson.GetValue('strokeWidth')).AsDouble, 0.0);
        Data.MifStrokeStyle := vssSolid;
        if LayerJson.GetValue('strokeStyle') is TJSONNumber then
        begin
          MifStrokeStyleValue := TJSONNumber(
            LayerJson.GetValue('strokeStyle')).AsInt;
          if InRange(MifStrokeStyleValue, Ord(Low(TVectArtMifStrokeStyle)),
            Ord(High(TVectArtMifStrokeStyle))) then
            Data.MifStrokeStyle := TVectArtMifStrokeStyle(MifStrokeStyleValue);
        end;
        Data.Visible := ReadBoolean(LayerJson, 'visible');
        Data.Locked := ReadBoolean(LayerJson, 'locked');
        RectangleData[I] := Data;
      end;
      SelectedIndex := ReadInteger(Root, 'selectedIndex');

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
      Canvas.BackgroundColor := TColor(CanvasColor);
      Canvas.Transparent := CanvasTransparent;
      for I := 0 to High(RectangleData) do
        if LayerTypes[I] = 'rectangle' then
          Document.InsertRectangle(Document.LayerCount, RectangleData[I])
        else if LayerTypes[I] = 'line' then
          Document.InsertLine(Document.LayerCount, LineData[I])
        else if LayerTypes[I] = 'image' then
          Document.InsertImage(Document.LayerCount, ImageData[I])
        else
          Document.InsertPath(Document.LayerCount, PathData[I]);
      Document.SelectedIndex := SelectedIndex;
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

end.
