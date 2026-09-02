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
  ScreenLayoutEditCommands, ScreenLayoutLayerBatchCommands,
  ScreenLayoutLayerStructureCommands, ScreenLayoutTextCommands;

const
  DUPLICATE_OFFSET = 24;

function CanDuplicateSelectedLayers(ADocument: TVectArtDocument): Boolean;
var
  HasArcs: Boolean;
  HasImages: Boolean;
  HasEllipses: Boolean;
  HasEllipseLines: Boolean;
  HasArcShapes: Boolean;
  HasPaths: Boolean;
  HasRectangles: Boolean;
  HasRectangleLines: Boolean;
  HasRoundedRectangles: Boolean;
  HasRoundedRectangleLines: Boolean;
  HasTexts: Boolean;
  I: Integer;
begin
  Result := (ADocument <> nil) and (ADocument.SelectionCount > 0);
  if not Result then
    Exit;
  HasArcs := False;
  HasImages := False;
  HasEllipses := False;
  HasEllipseLines := False;
  HasArcShapes := False;
  HasPaths := False;
  HasRectangles := False;
  HasRectangleLines := False;
  HasRoundedRectangles := False;
  HasRoundedRectangleLines := False;
  HasTexts := False;
  for I := 0 to ADocument.LayerCount - 1 do
    if ADocument.IsLayerSelected(I) and
      ((I = 0) or ADocument[I].Locked) then
      Exit(False)
    else if ADocument.IsLayerSelected(I) then
    begin
      if ADocument[I] is TScreenLayoutEllipseArcShapeLayer then
        HasArcShapes := True
      else if ADocument[I] is TScreenLayoutEllipseLineLayer then
        HasEllipseLines := True
      else if ADocument[I] is TScreenLayoutRoundedRectangleLineLayer then
        HasRoundedRectangleLines := True
      else if ADocument[I] is TScreenLayoutRectangleLineLayer then
        HasRectangleLines := True
      else if ADocument[I] is TScreenLayoutArcLayer then
        HasArcs := True
      else if ADocument[I] is TScreenLayoutEllipseLayer then
        HasEllipses := True
      else if ADocument[I] is TScreenLayoutRoundedRectangleLayer then
        HasRoundedRectangles := True
      else if ADocument[I] is TScreenLayoutTextLayer then
        HasTexts := True
      else if ADocument[I] is TVectArtRectangleLayer then
        HasRectangles := True
      else if ADocument[I] is TVectArtImageLayer then
        HasImages := True
      else if ADocument[I] is TVectArtPathLayer then
        HasPaths := True
      else
        Exit(False);
      if Ord(HasArcShapes) + Ord(HasEllipseLines) +
        Ord(HasRoundedRectangleLines) +
        Ord(HasRectangleLines) + Ord(HasRectangles) +
        Ord(HasRoundedRectangles) + Ord(HasEllipses) +
        Ord(HasArcs) + Ord(HasImages) + Ord(HasPaths) + Ord(HasTexts) > 1 then
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
  ArcData: TArray<TScreenLayoutArcData>;
  ArcDataList: TList<TScreenLayoutArcData>;
  ArcLayer: TScreenLayoutArcLayer;
  ArcValue: TScreenLayoutArcData;
  ArcShapeData: TArray<TScreenLayoutEllipseArcShapeData>;
  ArcShapeDataList: TList<TScreenLayoutEllipseArcShapeData>;
  ArcShapeLayer: TScreenLayoutEllipseArcShapeLayer;
  ArcShapeValue: TScreenLayoutEllipseArcShapeData;
  BeforeSelection: TArray<Integer>;
  CompoundCommand: TVectArtCompoundCommand;
  Data: TArray<TVectArtRectangleData>;
  DataList: TList<TVectArtRectangleData>;
  EllipseData: TArray<TScreenLayoutEllipseData>;
  EllipseDataList: TList<TScreenLayoutEllipseData>;
  EllipseLayer: TScreenLayoutEllipseLayer;
  EllipseValue: TScreenLayoutEllipseData;
  EllipseLineData: TArray<TScreenLayoutEllipseLineData>;
  EllipseLineDataList: TList<TScreenLayoutEllipseLineData>;
  EllipseLineLayer: TScreenLayoutEllipseLineLayer;
  EllipseLineValue: TScreenLayoutEllipseLineData;
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
  RectangleLineData: TArray<TScreenLayoutRectangleLineData>;
  RectangleLineDataList: TList<TScreenLayoutRectangleLineData>;
  RectangleLine: TScreenLayoutRectangleLineLayer;
  RectangleLineValue: TScreenLayoutRectangleLineData;
  RectangleLayer: TVectArtRectangleLayer;
  RoundedData: TArray<TScreenLayoutRoundedRectangleData>;
  RoundedDataList: TList<TScreenLayoutRoundedRectangleData>;
  RoundedLayer: TScreenLayoutRoundedRectangleLayer;
  RoundedValue: TScreenLayoutRoundedRectangleData;
  RoundedLineData: TArray<TScreenLayoutRoundedRectangleLineData>;
  RoundedLineDataList: TList<TScreenLayoutRoundedRectangleLineData>;
  RoundedLineLayer: TScreenLayoutRoundedRectangleLineLayer;
  RoundedLineValue: TScreenLayoutRoundedRectangleLineData;
  StartIndex: Integer;
  TextData: TArray<TScreenLayoutTextData>;
  TextDataList: TList<TScreenLayoutTextData>;
  TextLayer: TScreenLayoutTextLayer;
  TextValue: TScreenLayoutTextData;
  UsedNames: TStringList;
begin
  if not CanDuplicateSelectedLayers(ADocument) then
    Exit;
  BeforeSelection := ADocument.GetSelectedLayerIndices;
  ArcDataList := TList<TScreenLayoutArcData>.Create;
  ArcShapeDataList := TList<TScreenLayoutEllipseArcShapeData>.Create;
  DataList := TList<TVectArtRectangleData>.Create;
  EllipseDataList := TList<TScreenLayoutEllipseData>.Create;
  EllipseLineDataList := TList<TScreenLayoutEllipseLineData>.Create;
  ImageDataList := TList<TVectArtImageData>.Create;
  PathDataList := TList<TVectArtPathData>.Create;
  RoundedDataList := TList<TScreenLayoutRoundedRectangleData>.Create;
  RectangleLineDataList := TList<TScreenLayoutRectangleLineData>.Create;
  RoundedLineDataList := TList<TScreenLayoutRoundedRectangleLineData>.Create;
  TextDataList := TList<TScreenLayoutTextData>.Create;
  NewIndices := TList<Integer>.Create;
  UsedNames := TStringList.Create;
  try
    UsedNames.CaseSensitive := False;
    for I := 0 to ADocument.LayerCount - 1 do
      UsedNames.Add(ADocument[I].Name);
    for I := 1 to ADocument.LayerCount - 1 do
      if ADocument.IsLayerSelected(I) then
      begin
        if ADocument[I] is TScreenLayoutEllipseArcShapeLayer then
        begin
          ArcShapeLayer := TScreenLayoutEllipseArcShapeLayer(ADocument[I]);
          ArcShapeValue.Bounds := ArcShapeLayer.Bounds;
          ArcShapeValue.Bounds.Offset(DUPLICATE_OFFSET, DUPLICATE_OFFSET);
          ArcShapeValue.FillColor := ArcShapeLayer.FillColor;
          ArcShapeValue.Locked := False;
          ArcShapeValue.Name := CopyName(ArcShapeLayer.Name, UsedNames);
          ArcShapeValue.Opacity := ArcShapeLayer.Opacity;
          ArcShapeValue.RotationDegrees := ArcShapeLayer.RotationDegrees;
          ArcShapeValue.StartAngleDegrees := ArcShapeLayer.StartAngleDegrees;
          ArcShapeValue.SweepAngleDegrees := ArcShapeLayer.SweepAngleDegrees;
          ArcShapeValue.Visible := ArcShapeLayer.Visible;
          ArcShapeDataList.Add(ArcShapeValue);
        end
        else if ADocument[I] is TScreenLayoutEllipseLineLayer then
        begin
          EllipseLineLayer := TScreenLayoutEllipseLineLayer(ADocument[I]);
          EllipseLineValue.Bounds := EllipseLineLayer.Bounds;
          EllipseLineValue.Bounds.Offset(DUPLICATE_OFFSET, DUPLICATE_OFFSET);
          EllipseLineValue.Locked := False;
          EllipseLineValue.Name := CopyName(EllipseLineLayer.Name, UsedNames);
          EllipseLineValue.Opacity := EllipseLineLayer.Opacity;
          EllipseLineValue.RotationDegrees := EllipseLineLayer.RotationDegrees;
          EllipseLineValue.StrokeColor := EllipseLineLayer.StrokeColor;
          EllipseLineValue.StrokeStyle := EllipseLineLayer.StrokeStyle;
          EllipseLineValue.StrokeWidth := EllipseLineLayer.StrokeWidth;
          EllipseLineValue.Visible := EllipseLineLayer.Visible;
          EllipseLineDataList.Add(EllipseLineValue);
        end
        else if ADocument[I] is TScreenLayoutRoundedRectangleLineLayer then
        begin
          RoundedLineLayer := TScreenLayoutRoundedRectangleLineLayer(
            ADocument[I]);
          RoundedLineValue.Bounds := RoundedLineLayer.Bounds;
          RoundedLineValue.Bounds.Offset(DUPLICATE_OFFSET, DUPLICATE_OFFSET);
          RoundedLineValue.CornerRadii := RoundedLineLayer.CornerRadii;
          RoundedLineValue.Locked := False;
          RoundedLineValue.Name := CopyName(RoundedLineLayer.Name, UsedNames);
          RoundedLineValue.Opacity := RoundedLineLayer.Opacity;
          RoundedLineValue.RotationDegrees :=
            RoundedLineLayer.RotationDegrees;
          RoundedLineValue.StrokeColor := RoundedLineLayer.StrokeColor;
          RoundedLineValue.StrokeStyle := RoundedLineLayer.StrokeStyle;
          RoundedLineValue.StrokeWidth := RoundedLineLayer.StrokeWidth;
          RoundedLineValue.Visible := RoundedLineLayer.Visible;
          RoundedLineDataList.Add(RoundedLineValue);
        end
        else if ADocument[I] is TScreenLayoutRectangleLineLayer then
        begin
          RectangleLine := TScreenLayoutRectangleLineLayer(ADocument[I]);
          RectangleLineValue.Bounds := RectangleLine.Bounds;
          RectangleLineValue.Bounds.Offset(DUPLICATE_OFFSET,
            DUPLICATE_OFFSET);
          RectangleLineValue.Locked := False;
          RectangleLineValue.Name := CopyName(RectangleLine.Name, UsedNames);
          RectangleLineValue.Opacity := RectangleLine.Opacity;
          RectangleLineValue.RotationDegrees := RectangleLine.RotationDegrees;
          RectangleLineValue.StrokeColor := RectangleLine.StrokeColor;
          RectangleLineValue.StrokeStyle := RectangleLine.StrokeStyle;
          RectangleLineValue.StrokeWidth := RectangleLine.StrokeWidth;
          RectangleLineValue.Visible := RectangleLine.Visible;
          RectangleLineDataList.Add(RectangleLineValue);
        end
        else if ADocument[I] is TScreenLayoutArcLayer then
        begin
          ArcLayer := TScreenLayoutArcLayer(ADocument[I]);
          ArcValue.Bounds := ArcLayer.Bounds;
          ArcValue.Bounds.Offset(DUPLICATE_OFFSET, DUPLICATE_OFFSET);
          ArcValue.LineCap := ArcLayer.LineCap;
          ArcValue.Locked := False;
          ArcValue.Name := CopyName(ArcLayer.Name, UsedNames);
          ArcValue.Opacity := ArcLayer.Opacity;
          ArcValue.RotationDegrees := ArcLayer.RotationDegrees;
          ArcValue.StartAngleDegrees := ArcLayer.StartAngleDegrees;
          ArcValue.StrokeColor := ArcLayer.StrokeColor;
          ArcValue.StrokeStyle := ArcLayer.StrokeStyle;
          ArcValue.StrokeWidth := ArcLayer.StrokeWidth;
          ArcValue.SweepAngleDegrees := ArcLayer.SweepAngleDegrees;
          ArcValue.Visible := ArcLayer.Visible;
          ArcDataList.Add(ArcValue);
        end
        else if ADocument[I] is TScreenLayoutEllipseLayer then
        begin
          EllipseLayer := TScreenLayoutEllipseLayer(ADocument[I]);
          EllipseValue.Bounds := EllipseLayer.Bounds;
          EllipseValue.Bounds.Offset(DUPLICATE_OFFSET, DUPLICATE_OFFSET);
          EllipseValue.FillColor := EllipseLayer.FillColor;
          EllipseValue.Locked := False;
          EllipseValue.Name := CopyName(EllipseLayer.Name, UsedNames);
          EllipseValue.Opacity := EllipseLayer.Opacity;
          EllipseValue.RotationDegrees := EllipseLayer.RotationDegrees;
          EllipseValue.Visible := EllipseLayer.Visible;
          EllipseDataList.Add(EllipseValue);
        end
        else if ADocument[I] is TScreenLayoutRoundedRectangleLayer then
        begin
          RoundedLayer := TScreenLayoutRoundedRectangleLayer(ADocument[I]);
          RoundedValue.Bounds := RoundedLayer.Bounds;
          RoundedValue.Bounds.Offset(DUPLICATE_OFFSET, DUPLICATE_OFFSET);
          RoundedValue.CornerRadii := RoundedLayer.CornerRadii;
          RoundedValue.FillColor := RoundedLayer.FillColor;
          RoundedValue.Locked := False;
          RoundedValue.Name := CopyName(RoundedLayer.Name, UsedNames);
          RoundedValue.Opacity := RoundedLayer.Opacity;
          RoundedValue.RotationDegrees := RoundedLayer.RotationDegrees;
          RoundedValue.Visible := RoundedLayer.Visible;
          RoundedDataList.Add(RoundedValue);
        end
        else if ADocument[I] is TScreenLayoutTextLayer then
        begin
          TextLayer := TScreenLayoutTextLayer(ADocument[I]);
          TextValue := CaptureScreenLayoutTextData(TextLayer);
          TextValue.Bounds.Offset(DUPLICATE_OFFSET, DUPLICATE_OFFSET);
          TextValue.Locked := False;
          TextValue.Name := CopyName(TextLayer.Name, UsedNames);
          TextDataList.Add(TextValue);
        end
        else if ADocument[I] is TVectArtImageLayer then
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
          PathValue.LineCap := PathLayer.LineCap;
          PathValue.Locked := False;
          PathValue.MifStrokeStyle := PathLayer.MifStrokeStyle;
          PathValue.Name := CopyName(PathLayer.Name, UsedNames);
          PathValue.Opacity := PathLayer.Opacity;
          PathValue.Vertices := PathLayer.Vertices;
          for J := 0 to High(PathValue.Vertices) do
            PathValue.Vertices[J].Position := TPointF.Create(
              PathValue.Vertices[J].Position.X + DUPLICATE_OFFSET,
              PathValue.Vertices[J].Position.Y + DUPLICATE_OFFSET);
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
    if ArcShapeDataList.Count > 0 then
    begin
      ArcShapeData := ArcShapeDataList.ToArray;
      for I := 0 to High(ArcShapeData) do
      begin
        Index := ADocument.InsertEllipseArcShape(ADocument.LayerCount,
          ArcShapeData[I]);
        NewIndices.Add(Index);
      end;
    end
    else if EllipseLineDataList.Count > 0 then
    begin
      EllipseLineData := EllipseLineDataList.ToArray;
      for I := 0 to High(EllipseLineData) do
      begin
        Index := ADocument.InsertEllipseLine(ADocument.LayerCount,
          EllipseLineData[I]);
        NewIndices.Add(Index);
      end;
    end
    else if RoundedLineDataList.Count > 0 then
    begin
      RoundedLineData := RoundedLineDataList.ToArray;
      for I := 0 to High(RoundedLineData) do
      begin
        Index := ADocument.InsertRoundedRectangleLine(ADocument.LayerCount,
          RoundedLineData[I]);
        NewIndices.Add(Index);
      end;
    end
    else if RectangleLineDataList.Count > 0 then
    begin
      RectangleLineData := RectangleLineDataList.ToArray;
      for I := 0 to High(RectangleLineData) do
      begin
        Index := ADocument.InsertRectangleLine(ADocument.LayerCount,
          RectangleLineData[I]);
        NewIndices.Add(Index);
      end;
    end
    else if ArcDataList.Count > 0 then
    begin
      ArcData := ArcDataList.ToArray;
      for I := 0 to High(ArcData) do
      begin
        Index := ADocument.InsertArc(ADocument.LayerCount, ArcData[I]);
        NewIndices.Add(Index);
      end;
    end
    else if EllipseDataList.Count > 0 then
    begin
      EllipseData := EllipseDataList.ToArray;
      for I := 0 to High(EllipseData) do
      begin
        Index := ADocument.InsertEllipse(ADocument.LayerCount,
          EllipseData[I]);
        NewIndices.Add(Index);
      end;
    end
    else if RoundedDataList.Count > 0 then
    begin
      RoundedData := RoundedDataList.ToArray;
      for I := 0 to High(RoundedData) do
      begin
        Index := ADocument.InsertRoundedRectangle(ADocument.LayerCount,
          RoundedData[I]);
        NewIndices.Add(Index);
      end;
    end
    else if PathDataList.Count > 0 then
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
    else if TextDataList.Count > 0 then
    begin
      TextData := TextDataList.ToArray;
      for I := 0 to High(TextData) do
      begin
        Index := ADocument.InsertText(ADocument.LayerCount, TextData[I]);
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
      if ArcShapeDataList.Count > 0 then
      begin
        CompoundCommand := TVectArtCompoundCommand.Create;
        for I := 0 to High(ArcShapeData) do
          CompoundCommand.Add(
            TScreenLayoutInsertEllipseArcShapeCommand.Create(ADocument,
              StartIndex + I, ArcShapeData[I], BeforeSelection,
              AfterSelection));
        AEditHistory.AddApplied(CompoundCommand);
      end
      else if EllipseLineDataList.Count > 0 then
      begin
        CompoundCommand := TVectArtCompoundCommand.Create;
        for I := 0 to High(EllipseLineData) do
          CompoundCommand.Add(TScreenLayoutInsertEllipseLineCommand.Create(
            ADocument, StartIndex + I, EllipseLineData[I], BeforeSelection,
            AfterSelection));
        AEditHistory.AddApplied(CompoundCommand);
      end
      else if RoundedLineDataList.Count > 0 then
      begin
        CompoundCommand := TVectArtCompoundCommand.Create;
        for I := 0 to High(RoundedLineData) do
          CompoundCommand.Add(
            TScreenLayoutInsertRoundedRectangleLineCommand.Create(ADocument,
              StartIndex + I, RoundedLineData[I], BeforeSelection,
              AfterSelection));
        AEditHistory.AddApplied(CompoundCommand);
      end
      else if RectangleLineDataList.Count > 0 then
      begin
        CompoundCommand := TVectArtCompoundCommand.Create;
        for I := 0 to High(RectangleLineData) do
          CompoundCommand.Add(TScreenLayoutInsertRectangleLineCommand.Create(
            ADocument, StartIndex + I, RectangleLineData[I], BeforeSelection,
            AfterSelection));
        AEditHistory.AddApplied(CompoundCommand);
      end
      else if ArcDataList.Count > 0 then
      begin
        CompoundCommand := TVectArtCompoundCommand.Create;
        for I := 0 to High(ArcData) do
          CompoundCommand.Add(TScreenLayoutInsertArcCommand.Create(
            ADocument, StartIndex + I, ArcData[I], BeforeSelection,
            AfterSelection));
        AEditHistory.AddApplied(CompoundCommand);
      end
      else if EllipseDataList.Count > 0 then
      begin
        CompoundCommand := TVectArtCompoundCommand.Create;
        for I := 0 to High(EllipseData) do
          CompoundCommand.Add(TScreenLayoutInsertEllipseCommand.Create(
            ADocument, StartIndex + I, EllipseData[I], BeforeSelection,
            AfterSelection));
        AEditHistory.AddApplied(CompoundCommand);
      end
      else if RoundedDataList.Count > 0 then
      begin
        CompoundCommand := TVectArtCompoundCommand.Create;
        for I := 0 to High(RoundedData) do
          CompoundCommand.Add(TScreenLayoutInsertRoundedRectangleCommand.Create(
            ADocument, StartIndex + I, RoundedData[I], BeforeSelection,
            AfterSelection));
        AEditHistory.AddApplied(CompoundCommand);
      end
      else if PathDataList.Count > 0 then
        AEditHistory.AddApplied(TVectArtInsertPathsCommand.Create(
          ADocument, StartIndex, PathData, BeforeSelection, AfterSelection))
      else if ImageDataList.Count > 0 then
        AEditHistory.AddApplied(TVectArtInsertImagesCommand.Create(
          ADocument, StartIndex, ImageData, BeforeSelection, AfterSelection))
      else if TextDataList.Count > 0 then
      begin
        CompoundCommand := TVectArtCompoundCommand.Create;
        for I := 0 to High(TextData) do
          CompoundCommand.Add(TScreenLayoutInsertTextCommand.Create(
            ADocument, StartIndex + I, TextData[I], BeforeSelection,
            AfterSelection));
        AEditHistory.AddApplied(CompoundCommand);
      end
      else
        AEditHistory.AddApplied(TVectArtInsertRectanglesCommand.Create(
          ADocument, StartIndex, Data, BeforeSelection, AfterSelection));
  finally
    UsedNames.Free;
    NewIndices.Free;
    ArcDataList.Free;
    ArcShapeDataList.Free;
    RectangleLineDataList.Free;
    RoundedLineDataList.Free;
    EllipseDataList.Free;
    EllipseLineDataList.Free;
    RoundedDataList.Free;
    PathDataList.Free;
    ImageDataList.Free;
    TextDataList.Free;
    DataList.Free;
  end;
end;

end.
