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
  DOCUMENT_FORMAT_VERSION = 4;

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
  LayersJson: TJSONArray;
  Path: TVectArtPathLayer;
  PathJson: TJSONObject;
  PointIndex: Integer;
  PointJson: TJSONObject;
  PointsJson: TJSONArray;
  Rectangle: TVectArtRectangleLayer;
  RectangleJson: TJSONObject;
  Root: TJSONObject;
  SerializedSelectedIndex: Integer;
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
        if Path.Closed then
          PathJson.AddPair('fillColor',
            TJSONNumber.Create(Integer(Path.FillColor)))
        else
        begin
          PathJson.AddPair('strokeColor',
            TJSONNumber.Create(Integer(Path.StrokeColor)));
          PathJson.AddPair('strokeWidth',
            TJSONNumber.Create(Path.StrokeWidth));
          PathJson.AddPair('strokeStyle',
            TJSONNumber.Create(Ord(Path.MifStrokeStyle)));
          PathJson.AddPair('lineCap', TJSONNumber.Create(Ord(Path.LineCap)));
          PathJson.AddPair('lineJoin', TJSONNumber.Create(Ord(Path.LineJoin)));
          PathJson.AddPair('antiAlias', TJSONBool.Create(Path.MifAntiAlias));
        end;
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
  Data: TVectArtRectangleData;
  Discarded: TVectArtRectangleData;
  DiscardedPath: TVectArtPathData;
  DiscardedImage: TVectArtImageData;
  I: Integer;
  ImageData: TArray<TVectArtImageData>;
  ImageFileName: string;
  ImageValue: TVectArtImageData;
  Json: TJSONValue;
  LayerJson: TJSONObject;
  LayerTypes: TArray<string>;
  LayersJson: TJSONArray;
  RectangleData: TArray<TVectArtRectangleData>;
  PathData: TArray<TVectArtPathData>;
  PathValue: TVectArtPathData;
  PointIndex: Integer;
  PointJson: TJSONObject;
  PointsJson: TJSONArray;
  Root: TJSONObject;
  SelectedIndex: Integer;
  LoadedSelectedIndex: Integer;
  SourceKind: string;
  LineCapValue: Integer;
  LineJoinValue: Integer;
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
          PathValue.FillColor := clWhite;
          PathValue.StrokeColor := clBlack;
          PathValue.StrokeWidth := 1.0;
          PathValue.MifStrokeStyle := vssSolid;
          PathValue.LineCap := vlcButt;
          PathValue.LineJoin := vljMiter;
          PathValue.MifAntiAlias := True;
          if PathValue.Closed then
            PathValue.FillColor := TColor(ReadInteger(LayerJson, 'fillColor'))
          else
          begin
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
            LineJoinValue := ReadInteger(LayerJson, 'lineJoin');
            if InRange(LineJoinValue, Ord(Low(TVectArtLineJoin)),
              Ord(High(TVectArtLineJoin))) then
              PathValue.LineJoin := TVectArtLineJoin(LineJoinValue);
            PathValue.MifAntiAlias := TJSONBool(
              RequireValue(LayerJson, 'antiAlias', TJSONBool)).AsBoolean;
          end;
          PathValue.Visible := ReadBoolean(LayerJson, 'visible');
          PathValue.Locked := ReadBoolean(LayerJson, 'locked');
          PointsJson := TJSONArray(RequireValue(LayerJson, 'points',
            TJSONArray));
          if PointsJson.Count < 2 then
            raise EConvertError.CreateFmt('Path layer %d has too few points',
              [I]);
          if PathValue.Closed and (PointsJson.Count < 3) then
            raise EConvertError.CreateFmt(
              'Closed path layer %d must contain at least three points', [I]);
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
        if Document[Document.LayerCount - 1] is TVectArtRectangleLayer then
          Document.RemoveRectangle(Document.LayerCount - 1, Discarded)
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
      LoadedSelectedIndex := -1;
      for I := 0 to High(RectangleData) do
      begin
        if LayerTypes[I] = 'rectangle' then
          Document.InsertRectangle(Document.LayerCount, RectangleData[I])
        else if LayerTypes[I] = 'image' then
          Document.InsertImage(Document.LayerCount, ImageData[I])
        else if LayerTypes[I] = 'path' then
          Document.InsertPath(Document.LayerCount, PathData[I]);
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
