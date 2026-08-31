// 同種の選択Rectangle、Path、画像一式の複製、挿入、選択更新を担当する。
unit ScreenLayoutLayerDuplication;

interface

uses
  ScreenLayoutDocument, ScreenLayoutEditHistory;

function CanDuplicateSelectedLayers(ADocument: TVectArtDocument): Boolean;
procedure DuplicateSelectedLayers(ADocument: TVectArtDocument;
  AEditHistory: TVectArtEditHistory);

implementation

uses
  System.Classes, System.Generics.Collections, System.SysUtils, System.Types,
  ScreenLayoutLayerBatchCommands;

const
  DUPLICATE_OFFSET = 24;

function CanDuplicateSelectedLayers(ADocument: TVectArtDocument): Boolean;
var
  HasImages: Boolean;
  HasPaths: Boolean;
  HasRectangles: Boolean;
  I: Integer;
begin
  Result := (ADocument <> nil) and (ADocument.SelectionCount > 0);
  if not Result then
    Exit;
  HasImages := False;
  HasPaths := False;
  HasRectangles := False;
  for I := 0 to ADocument.LayerCount - 1 do
    if ADocument.IsLayerSelected(I) and
      ((I = 0) or ADocument[I].Locked) then
      Exit(False)
    else if ADocument.IsLayerSelected(I) then
    begin
      if ADocument[I] is TVectArtRectangleLayer then
        HasRectangles := True
      else if ADocument[I] is TVectArtImageLayer then
        HasImages := True
      else if ADocument[I] is TVectArtPathLayer then
        HasPaths := True
      else
        Exit(False);
      if Ord(HasRectangles) + Ord(HasImages) + Ord(HasPaths) > 1 then
        Exit(False);
    end;
end;

function CopyName(const SourceName: string; UsedNames: TStrings): string;
var
  Number: Integer;
begin
  Result := SourceName + ' Copy';
  Number := 2;
  while UsedNames.IndexOf(Result) >= 0 do
  begin
    Result := SourceName + ' Copy ' + Number.ToString;
    Inc(Number);
  end;
  UsedNames.Add(Result);
end;

procedure DuplicateSelectedLayers(ADocument: TVectArtDocument;
  AEditHistory: TVectArtEditHistory);
var
  AfterSelection: TArray<Integer>;
  BeforeSelection: TArray<Integer>;
  Data: TArray<TVectArtRectangleData>;
  DataList: TList<TVectArtRectangleData>;
  I: Integer;
  ImageData: TArray<TVectArtImageData>;
  ImageDataList: TList<TVectArtImageData>;
  ImageLayer: TVectArtImageLayer;
  ImageValue: TVectArtImageData;
  Index: Integer;
  J: Integer;
  NewIndices: TList<Integer>;
  PathData: TArray<TVectArtPathData>;
  PathDataList: TList<TVectArtPathData>;
  PathLayer: TVectArtPathLayer;
  PathValue: TVectArtPathData;
  RectangleData: TVectArtRectangleData;
  RectangleLayer: TVectArtRectangleLayer;
  StartIndex: Integer;
  UsedNames: TStringList;
begin
  if not CanDuplicateSelectedLayers(ADocument) then
    Exit;
  BeforeSelection := ADocument.GetSelectedLayerIndices;
  DataList := TList<TVectArtRectangleData>.Create;
  ImageDataList := TList<TVectArtImageData>.Create;
  PathDataList := TList<TVectArtPathData>.Create;
  NewIndices := TList<Integer>.Create;
  UsedNames := TStringList.Create;
  try
    UsedNames.CaseSensitive := False;
    for I := 0 to ADocument.LayerCount - 1 do
      UsedNames.Add(ADocument[I].Name);
    for I := 1 to ADocument.LayerCount - 1 do
      if ADocument.IsLayerSelected(I) then
      begin
        if ADocument[I] is TVectArtImageLayer then
        begin
          ImageLayer := TVectArtImageLayer(ADocument[I]);
          ImageValue.Name := CopyName(ImageLayer.Name, UsedNames);
          ImageValue.Locked := False;
          ImageValue.Opacity := ImageLayer.Opacity;
          ImageValue.PngData := Copy(ImageLayer.PngData);
          ImageValue.SourceFileName := ImageLayer.SourceFileName;
          ImageValue.SourceKind := ImageLayer.SourceKind;
          ImageValue.Visible := ImageLayer.Visible;
          for J := 0 to High(ImageLayer.Points) do
            ImageValue.Points[J] :=
              TPointF.Create(ImageLayer.Points[J].X + DUPLICATE_OFFSET,
                ImageLayer.Points[J].Y + DUPLICATE_OFFSET);
          ImageDataList.Add(ImageValue);
        end
        else if ADocument[I] is TVectArtPathLayer then
        begin
          PathLayer := TVectArtPathLayer(ADocument[I]);
          PathValue.Closed := PathLayer.Closed;
          PathValue.FillColor := PathLayer.FillColor;
          PathValue.LineCap := PathLayer.LineCap;
          PathValue.LineJoin := PathLayer.LineJoin;
          PathValue.Locked := False;
          PathValue.MifAntiAlias := PathLayer.MifAntiAlias;
          PathValue.MifStrokeStyle := PathLayer.MifStrokeStyle;
          PathValue.Name := CopyName(PathLayer.Name, UsedNames);
          PathValue.Opacity := PathLayer.Opacity;
          SetLength(PathValue.Points, Length(PathLayer.Points));
          for J := 0 to High(PathLayer.Points) do
            PathValue.Points[J] := TPointF.Create(
              PathLayer.Points[J].X + DUPLICATE_OFFSET,
              PathLayer.Points[J].Y + DUPLICATE_OFFSET);
          PathValue.StrokeColor := PathLayer.StrokeColor;
          PathValue.StrokeWidth := PathLayer.StrokeWidth;
          PathValue.Visible := PathLayer.Visible;
          PathDataList.Add(PathValue);
        end
        else
        begin
          RectangleLayer := TVectArtRectangleLayer(ADocument[I]);
          RectangleData.Bounds := RectangleLayer.Bounds;
          RectangleData.Bounds.Offset(DUPLICATE_OFFSET, DUPLICATE_OFFSET);
          RectangleData.FillColor := RectangleLayer.FillColor;
          RectangleData.Locked := False;
          RectangleData.Name := CopyName(RectangleLayer.Name, UsedNames);
          RectangleData.Opacity := RectangleLayer.Opacity;
          RectangleData.RotationDegrees := RectangleLayer.RotationDegrees;
          RectangleData.Visible := RectangleLayer.Visible;
          DataList.Add(RectangleData);
        end;
      end;

    StartIndex := ADocument.LayerCount;
    if PathDataList.Count > 0 then
    begin
      PathData := PathDataList.ToArray;
      for I := 0 to High(PathData) do
      begin
        Index := ADocument.InsertPath(ADocument.LayerCount, PathData[I]);
        NewIndices.Add(Index);
      end;
    end
    else if ImageDataList.Count > 0 then
    begin
      ImageData := ImageDataList.ToArray;
      for I := 0 to High(ImageData) do
      begin
        Index := ADocument.InsertImage(ADocument.LayerCount, ImageData[I]);
        NewIndices.Add(Index);
      end;
    end
    else
    begin
      Data := DataList.ToArray;
      for I := 0 to High(Data) do
      begin
        Index := ADocument.InsertRectangle(ADocument.LayerCount, Data[I]);
        NewIndices.Add(Index);
      end;
    end;
    ADocument.SetSelectedLayers(NewIndices.ToArray);
    AfterSelection := ADocument.GetSelectedLayerIndices;
    if AEditHistory <> nil then
      if PathDataList.Count > 0 then
        AEditHistory.AddApplied(TVectArtInsertPathsCommand.Create(
          ADocument, StartIndex, PathData, BeforeSelection, AfterSelection))
      else if ImageDataList.Count > 0 then
        AEditHistory.AddApplied(TVectArtInsertImagesCommand.Create(
          ADocument, StartIndex, ImageData, BeforeSelection, AfterSelection))
      else
        AEditHistory.AddApplied(TVectArtInsertRectanglesCommand.Create(
          ADocument, StartIndex, Data, BeforeSelection, AfterSelection));
  finally
    UsedNames.Free;
    NewIndices.Free;
    PathDataList.Free;
    ImageDataList.Free;
    DataList.Free;
  end;
end;

end.
