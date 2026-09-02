// 図形レイヤーの挿入、削除、積層順変更をUndo／Redo可能にする。
unit ScreenLayoutLayerStructureCommands;

interface

uses
  ScreenLayoutDocument, ScreenLayoutEditCommands;

type
  TVectArtInsertRectangleCommand = class(TVectArtEditCommand)
  private
    FAfterSelection: TArray<Integer>;
    FBeforeSelection: TArray<Integer>;
    FData: TVectArtRectangleData;
    FDocument: TVectArtDocument;
    FIndex: Integer;
  public
    constructor Create(ADocument: TVectArtDocument; Index: Integer;
      const Data: TVectArtRectangleData; const BeforeSelection,
      AfterSelection: TArray<Integer>);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TScreenLayoutInsertRoundedRectangleCommand = class(TVectArtEditCommand)
  private
    FAfterSelection: TArray<Integer>;
    FBeforeSelection: TArray<Integer>;
    FData: TScreenLayoutRoundedRectangleData;
    FDocument: TVectArtDocument;
    FIndex: Integer;
  public
    constructor Create(ADocument: TVectArtDocument; Index: Integer;
      const Data: TScreenLayoutRoundedRectangleData; const BeforeSelection,
      AfterSelection: TArray<Integer>);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TScreenLayoutInsertEllipseCommand = class(TVectArtEditCommand)
  private
    FAfterSelection: TArray<Integer>;
    FBeforeSelection: TArray<Integer>;
    FData: TScreenLayoutEllipseData;
    FDocument: TVectArtDocument;
    FIndex: Integer;
  public
    constructor Create(ADocument: TVectArtDocument; Index: Integer;
      const Data: TScreenLayoutEllipseData; const BeforeSelection,
      AfterSelection: TArray<Integer>);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TScreenLayoutInsertArcCommand = class(TVectArtEditCommand)
  private
    FAfterSelection: TArray<Integer>;
    FBeforeSelection: TArray<Integer>;
    FData: TScreenLayoutArcData;
    FDocument: TVectArtDocument;
    FIndex: Integer;
  public
    constructor Create(ADocument: TVectArtDocument; Index: Integer;
      const Data: TScreenLayoutArcData; const BeforeSelection,
      AfterSelection: TArray<Integer>);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TScreenLayoutInsertEllipseArcShapeCommand = class(TVectArtEditCommand)
  private
    FAfterSelection: TArray<Integer>;
    FBeforeSelection: TArray<Integer>;
    FData: TScreenLayoutEllipseArcShapeData;
    FDocument: TVectArtDocument;
    FIndex: Integer;
  public
    constructor Create(ADocument: TVectArtDocument; Index: Integer;
      const Data: TScreenLayoutEllipseArcShapeData; const BeforeSelection,
      AfterSelection: TArray<Integer>);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TScreenLayoutInsertRectangleLineCommand = class(TVectArtEditCommand)
  private
    FAfterSelection: TArray<Integer>;
    FBeforeSelection: TArray<Integer>;
    FData: TScreenLayoutRectangleLineData;
    FDocument: TVectArtDocument;
    FIndex: Integer;
  public
    constructor Create(ADocument: TVectArtDocument; Index: Integer;
      const Data: TScreenLayoutRectangleLineData; const BeforeSelection,
      AfterSelection: TArray<Integer>);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TScreenLayoutInsertRoundedRectangleLineCommand = class(TVectArtEditCommand)
  private
    FAfterSelection: TArray<Integer>;
    FBeforeSelection: TArray<Integer>;
    FData: TScreenLayoutRoundedRectangleLineData;
    FDocument: TVectArtDocument;
    FIndex: Integer;
  public
    constructor Create(ADocument: TVectArtDocument; Index: Integer;
      const Data: TScreenLayoutRoundedRectangleLineData;
      const BeforeSelection, AfterSelection: TArray<Integer>);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TScreenLayoutInsertEllipseLineCommand = class(TVectArtEditCommand)
  private
    FAfterSelection: TArray<Integer>;
    FBeforeSelection: TArray<Integer>;
    FData: TScreenLayoutEllipseLineData;
    FDocument: TVectArtDocument;
    FIndex: Integer;
  public
    constructor Create(ADocument: TVectArtDocument; Index: Integer;
      const Data: TScreenLayoutEllipseLineData; const BeforeSelection,
      AfterSelection: TArray<Integer>);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TVectArtInsertPathCommand = class(TVectArtEditCommand)
  private
    FAfterSelection: TArray<Integer>;
    FBeforeSelection: TArray<Integer>;
    FData: TVectArtPathData;
    FDocument: TVectArtDocument;
    FIndex: Integer;
  public
    constructor Create(ADocument: TVectArtDocument; Index: Integer;
      const Data: TVectArtPathData; const BeforeSelection,
      AfterSelection: TArray<Integer>);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TScreenLayoutInsertShapeCommand = class(TVectArtEditCommand)
  private
    FAfterSelection: TArray<Integer>;
    FBeforeSelection: TArray<Integer>;
    FData: TScreenLayoutShapeData;
    FDocument: TVectArtDocument;
    FIndex: Integer;
  public
    // Shape挿入の前後選択状態と独立した輪郭データを保持する。
    constructor Create(ADocument: TVectArtDocument; Index: Integer;
      const Data: TScreenLayoutShapeData; const BeforeSelection,
      AfterSelection: TArray<Integer>);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TVectArtDeleteRectangleCommand = class(TVectArtEditCommand)
  private
    FAfterSelection: TArray<Integer>;
    FBeforeSelection: TArray<Integer>;
    FData: TVectArtRectangleData;
    FDocument: TVectArtDocument;
    FIndex: Integer;
  public
    constructor Create(ADocument: TVectArtDocument; Index: Integer;
      const Data: TVectArtRectangleData; const BeforeSelection,
      AfterSelection: TArray<Integer>);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TScreenLayoutDeleteRoundedRectangleCommand = class(TVectArtEditCommand)
  private
    FAfterSelection: TArray<Integer>;
    FBeforeSelection: TArray<Integer>;
    FData: TScreenLayoutRoundedRectangleData;
    FDocument: TVectArtDocument;
    FIndex: Integer;
  public
    constructor Create(ADocument: TVectArtDocument; Index: Integer;
      const Data: TScreenLayoutRoundedRectangleData; const BeforeSelection,
      AfterSelection: TArray<Integer>);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TScreenLayoutDeleteEllipseCommand = class(TVectArtEditCommand)
  private
    FAfterSelection: TArray<Integer>;
    FBeforeSelection: TArray<Integer>;
    FData: TScreenLayoutEllipseData;
    FDocument: TVectArtDocument;
    FIndex: Integer;
  public
    constructor Create(ADocument: TVectArtDocument; Index: Integer;
      const Data: TScreenLayoutEllipseData; const BeforeSelection,
      AfterSelection: TArray<Integer>);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TScreenLayoutDeleteArcCommand = class(TVectArtEditCommand)
  private
    FAfterSelection: TArray<Integer>;
    FBeforeSelection: TArray<Integer>;
    FData: TScreenLayoutArcData;
    FDocument: TVectArtDocument;
    FIndex: Integer;
  public
    constructor Create(ADocument: TVectArtDocument; Index: Integer;
      const Data: TScreenLayoutArcData; const BeforeSelection,
      AfterSelection: TArray<Integer>);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TScreenLayoutDeleteEllipseArcShapeCommand = class(TVectArtEditCommand)
  private
    FAfterSelection: TArray<Integer>;
    FBeforeSelection: TArray<Integer>;
    FData: TScreenLayoutEllipseArcShapeData;
    FDocument: TVectArtDocument;
    FIndex: Integer;
  public
    constructor Create(ADocument: TVectArtDocument; Index: Integer;
      const Data: TScreenLayoutEllipseArcShapeData; const BeforeSelection,
      AfterSelection: TArray<Integer>);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TScreenLayoutDeleteRectangleLineCommand = class(TVectArtEditCommand)
  private
    FAfterSelection: TArray<Integer>;
    FBeforeSelection: TArray<Integer>;
    FData: TScreenLayoutRectangleLineData;
    FDocument: TVectArtDocument;
    FIndex: Integer;
  public
    constructor Create(ADocument: TVectArtDocument; Index: Integer;
      const Data: TScreenLayoutRectangleLineData; const BeforeSelection,
      AfterSelection: TArray<Integer>);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TScreenLayoutDeleteRoundedRectangleLineCommand = class(TVectArtEditCommand)
  private
    FAfterSelection: TArray<Integer>;
    FBeforeSelection: TArray<Integer>;
    FData: TScreenLayoutRoundedRectangleLineData;
    FDocument: TVectArtDocument;
    FIndex: Integer;
  public
    constructor Create(ADocument: TVectArtDocument; Index: Integer;
      const Data: TScreenLayoutRoundedRectangleLineData;
      const BeforeSelection, AfterSelection: TArray<Integer>);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TScreenLayoutDeleteEllipseLineCommand = class(TVectArtEditCommand)
  private
    FAfterSelection: TArray<Integer>;
    FBeforeSelection: TArray<Integer>;
    FData: TScreenLayoutEllipseLineData;
    FDocument: TVectArtDocument;
    FIndex: Integer;
  public
    constructor Create(ADocument: TVectArtDocument; Index: Integer;
      const Data: TScreenLayoutEllipseLineData; const BeforeSelection,
      AfterSelection: TArray<Integer>);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TVectArtDeletePathCommand = class(TVectArtEditCommand)
  private
    FAfterSelection: TArray<Integer>;
    FBeforeSelection: TArray<Integer>;
    FData: TVectArtPathData;
    FDocument: TVectArtDocument;
    FIndex: Integer;
  public
    constructor Create(ADocument: TVectArtDocument; Index: Integer;
      const Data: TVectArtPathData; const BeforeSelection,
      AfterSelection: TArray<Integer>);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TScreenLayoutDeleteShapeCommand = class(TVectArtEditCommand)
  private
    FAfterSelection: TArray<Integer>;
    FBeforeSelection: TArray<Integer>;
    FData: TScreenLayoutShapeData;
    FDocument: TVectArtDocument;
    FIndex: Integer;
  public
    // Shape削除の前後選択状態と再挿入に必要な全データを保持する。
    constructor Create(ADocument: TVectArtDocument; Index: Integer;
      const Data: TScreenLayoutShapeData; const BeforeSelection,
      AfterSelection: TArray<Integer>);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TVectArtDeleteImageCommand = class(TVectArtEditCommand)
  private
    FAfterSelection: TArray<Integer>;
    FBeforeSelection: TArray<Integer>;
    FData: TVectArtImageData;
    FDocument: TVectArtDocument;
    FIndex: Integer;
  public
    constructor Create(ADocument: TVectArtDocument; Index: Integer;
      const Data: TVectArtImageData; const BeforeSelection,
      AfterSelection: TArray<Integer>);
    procedure Execute; override;
    procedure Undo; override;
  end;

  TVectArtMoveLayerCommand = class(TVectArtEditCommand)
  private
    FAfterSelection: TArray<Integer>;
    FBeforeSelection: TArray<Integer>;
    FDocument: TVectArtDocument;
    FNewIndex: Integer;
    FOldIndex: Integer;
  public
    constructor Create(ADocument: TVectArtDocument; OldIndex,
      NewIndex: Integer; const BeforeSelection,
      AfterSelection: TArray<Integer>);
    procedure Execute; override;
    procedure Undo; override;
  end;

implementation

procedure CopyShapeData(const Source: TScreenLayoutShapeData;
  out Target: TScreenLayoutShapeData);
var
  I: Integer;
begin
  Target := Source;
  SetLength(Target.Contours, Length(Source.Contours));
  for I := 0 to High(Source.Contours) do
    Target.Contours[I].Vertices := Copy(Source.Contours[I].Vertices);
end;

{ TScreenLayoutInsertShapeCommand }

constructor TScreenLayoutInsertShapeCommand.Create(
  ADocument: TVectArtDocument; Index: Integer;
  const Data: TScreenLayoutShapeData; const BeforeSelection,
  AfterSelection: TArray<Integer>);
begin
  inherited Create;
  FDocument := ADocument;
  FIndex := Index;
  CopyShapeData(Data, FData);
  FBeforeSelection := Copy(BeforeSelection);
  FAfterSelection := Copy(AfterSelection);
end;

procedure TScreenLayoutInsertShapeCommand.Execute;
begin
  if FDocument = nil then
    Exit;
  FIndex := FDocument.InsertShape(FIndex, FData);
  FDocument.SetSelectedLayers(FAfterSelection);
end;

procedure TScreenLayoutInsertShapeCommand.Undo;
var
  RemovedData: TScreenLayoutShapeData;
begin
  if FDocument = nil then
    Exit;
  FDocument.RemoveShape(FIndex, RemovedData);
  FDocument.SetSelectedLayers(FBeforeSelection);
end;

{ TScreenLayoutDeleteShapeCommand }

constructor TScreenLayoutDeleteShapeCommand.Create(
  ADocument: TVectArtDocument; Index: Integer;
  const Data: TScreenLayoutShapeData; const BeforeSelection,
  AfterSelection: TArray<Integer>);
begin
  inherited Create;
  FDocument := ADocument;
  FIndex := Index;
  CopyShapeData(Data, FData);
  FBeforeSelection := Copy(BeforeSelection);
  FAfterSelection := Copy(AfterSelection);
end;

procedure TScreenLayoutDeleteShapeCommand.Execute;
var
  RemovedData: TScreenLayoutShapeData;
begin
  if FDocument = nil then
    Exit;
  FDocument.RemoveShape(FIndex, RemovedData);
  FDocument.SetSelectedLayers(FAfterSelection);
end;

procedure TScreenLayoutDeleteShapeCommand.Undo;
begin
  if FDocument = nil then
    Exit;
  FIndex := FDocument.InsertShape(FIndex, FData);
  FDocument.SetSelectedLayers(FBeforeSelection);
end;

{ TVectArtInsertPathCommand }

constructor TVectArtInsertPathCommand.Create(ADocument: TVectArtDocument;
  Index: Integer; const Data: TVectArtPathData; const BeforeSelection,
  AfterSelection: TArray<Integer>);
begin
  inherited Create;
  FDocument := ADocument;
  FIndex := Index;
  FData := Data;
  FData.Vertices := Copy(Data.Vertices);
  FBeforeSelection := Copy(BeforeSelection);
  FAfterSelection := Copy(AfterSelection);
end;

procedure TVectArtInsertPathCommand.Execute;
begin
  if FDocument = nil then
    Exit;
  FIndex := FDocument.InsertPath(FIndex, FData);
  FDocument.SetSelectedLayers(FAfterSelection);
end;

procedure TVectArtInsertPathCommand.Undo;
var
  RemovedData: TVectArtPathData;
begin
  if FDocument = nil then
    Exit;
  FDocument.RemovePath(FIndex, RemovedData);
  FDocument.SetSelectedLayers(FBeforeSelection);
end;

{ TVectArtInsertRectangleCommand }

constructor TVectArtInsertRectangleCommand.Create(
  ADocument: TVectArtDocument; Index: Integer;
  const Data: TVectArtRectangleData; const BeforeSelection,
  AfterSelection: TArray<Integer>);
begin
  inherited Create;
  FDocument := ADocument;
  FIndex := Index;
  FData := Data;
  FBeforeSelection := Copy(BeforeSelection);
  FAfterSelection := Copy(AfterSelection);
end;

procedure TVectArtInsertRectangleCommand.Execute;
begin
  if FDocument = nil then
    Exit;
  FIndex := FDocument.InsertRectangle(FIndex, FData);
  FDocument.SetSelectedLayers(FAfterSelection);
end;

procedure TVectArtInsertRectangleCommand.Undo;
var
  RemovedData: TVectArtRectangleData;
begin
  if FDocument = nil then
    Exit;
  FDocument.RemoveRectangle(FIndex, RemovedData);
  FDocument.SetSelectedLayers(FBeforeSelection);
end;

{ TScreenLayoutInsertRoundedRectangleCommand }

constructor TScreenLayoutInsertRoundedRectangleCommand.Create(
  ADocument: TVectArtDocument; Index: Integer;
  const Data: TScreenLayoutRoundedRectangleData; const BeforeSelection,
  AfterSelection: TArray<Integer>);
begin
  inherited Create;
  FDocument := ADocument;
  FIndex := Index;
  FData := Data;
  FBeforeSelection := Copy(BeforeSelection);
  FAfterSelection := Copy(AfterSelection);
end;

procedure TScreenLayoutInsertRoundedRectangleCommand.Execute;
begin
  if FDocument = nil then
    Exit;
  FIndex := FDocument.InsertRoundedRectangle(FIndex, FData);
  FDocument.SetSelectedLayers(FAfterSelection);
end;

procedure TScreenLayoutInsertRoundedRectangleCommand.Undo;
var
  RemovedData: TScreenLayoutRoundedRectangleData;
begin
  if FDocument = nil then
    Exit;
  FDocument.RemoveRoundedRectangle(FIndex, RemovedData);
  FDocument.SetSelectedLayers(FBeforeSelection);
end;

{ TScreenLayoutInsertEllipseCommand }

constructor TScreenLayoutInsertEllipseCommand.Create(
  ADocument: TVectArtDocument; Index: Integer;
  const Data: TScreenLayoutEllipseData; const BeforeSelection,
  AfterSelection: TArray<Integer>);
begin
  inherited Create;
  FDocument := ADocument;
  FIndex := Index;
  FData := Data;
  FBeforeSelection := Copy(BeforeSelection);
  FAfterSelection := Copy(AfterSelection);
end;

procedure TScreenLayoutInsertEllipseCommand.Execute;
begin
  if FDocument = nil then
    Exit;
  FIndex := FDocument.InsertEllipse(FIndex, FData);
  FDocument.SetSelectedLayers(FAfterSelection);
end;

procedure TScreenLayoutInsertEllipseCommand.Undo;
var
  RemovedData: TScreenLayoutEllipseData;
begin
  if FDocument = nil then
    Exit;
  FDocument.RemoveEllipse(FIndex, RemovedData);
  FDocument.SetSelectedLayers(FBeforeSelection);
end;

{ TScreenLayoutInsertArcCommand }

constructor TScreenLayoutInsertArcCommand.Create(ADocument: TVectArtDocument;
  Index: Integer; const Data: TScreenLayoutArcData; const BeforeSelection,
  AfterSelection: TArray<Integer>);
begin
  inherited Create;
  FDocument := ADocument;
  FIndex := Index;
  FData := Data;
  FBeforeSelection := Copy(BeforeSelection);
  FAfterSelection := Copy(AfterSelection);
end;

procedure TScreenLayoutInsertArcCommand.Execute;
begin
  if FDocument = nil then
    Exit;
  FIndex := FDocument.InsertArc(FIndex, FData);
  FDocument.SetSelectedLayers(FAfterSelection);
end;

procedure TScreenLayoutInsertArcCommand.Undo;
var
  RemovedData: TScreenLayoutArcData;
begin
  if FDocument = nil then
    Exit;
  FDocument.RemoveArc(FIndex, RemovedData);
  FDocument.SetSelectedLayers(FBeforeSelection);
end;

{ TScreenLayoutInsertEllipseArcShapeCommand }

constructor TScreenLayoutInsertEllipseArcShapeCommand.Create(
  ADocument: TVectArtDocument; Index: Integer;
  const Data: TScreenLayoutEllipseArcShapeData; const BeforeSelection,
  AfterSelection: TArray<Integer>);
begin
  inherited Create;
  FDocument := ADocument;
  FIndex := Index;
  FData := Data;
  FBeforeSelection := Copy(BeforeSelection);
  FAfterSelection := Copy(AfterSelection);
end;

procedure TScreenLayoutInsertEllipseArcShapeCommand.Execute;
begin
  if FDocument = nil then
    Exit;
  FIndex := FDocument.InsertEllipseArcShape(FIndex, FData);
  FDocument.SetSelectedLayers(FAfterSelection);
end;

procedure TScreenLayoutInsertEllipseArcShapeCommand.Undo;
var
  RemovedData: TScreenLayoutEllipseArcShapeData;
begin
  if FDocument = nil then
    Exit;
  FDocument.RemoveEllipseArcShape(FIndex, RemovedData);
  FDocument.SetSelectedLayers(FBeforeSelection);
end;

{ TScreenLayoutInsertRectangleLineCommand }

constructor TScreenLayoutInsertRectangleLineCommand.Create(
  ADocument: TVectArtDocument; Index: Integer;
  const Data: TScreenLayoutRectangleLineData; const BeforeSelection,
  AfterSelection: TArray<Integer>);
begin
  inherited Create;
  FDocument := ADocument;
  FIndex := Index;
  FData := Data;
  FBeforeSelection := Copy(BeforeSelection);
  FAfterSelection := Copy(AfterSelection);
end;

procedure TScreenLayoutInsertRectangleLineCommand.Execute;
begin
  if FDocument = nil then
    Exit;
  FIndex := FDocument.InsertRectangleLine(FIndex, FData);
  FDocument.SetSelectedLayers(FAfterSelection);
end;

procedure TScreenLayoutInsertRectangleLineCommand.Undo;
var
  RemovedData: TScreenLayoutRectangleLineData;
begin
  if FDocument = nil then
    Exit;
  FDocument.RemoveRectangleLine(FIndex, RemovedData);
  FDocument.SetSelectedLayers(FBeforeSelection);
end;

{ TScreenLayoutInsertRoundedRectangleLineCommand }

constructor TScreenLayoutInsertRoundedRectangleLineCommand.Create(
  ADocument: TVectArtDocument; Index: Integer;
  const Data: TScreenLayoutRoundedRectangleLineData;
  const BeforeSelection, AfterSelection: TArray<Integer>);
begin
  inherited Create;
  FDocument := ADocument;
  FIndex := Index;
  FData := Data;
  FBeforeSelection := Copy(BeforeSelection);
  FAfterSelection := Copy(AfterSelection);
end;

procedure TScreenLayoutInsertRoundedRectangleLineCommand.Execute;
begin
  if FDocument = nil then
    Exit;
  FIndex := FDocument.InsertRoundedRectangleLine(FIndex, FData);
  FDocument.SetSelectedLayers(FAfterSelection);
end;

procedure TScreenLayoutInsertRoundedRectangleLineCommand.Undo;
var
  RemovedData: TScreenLayoutRoundedRectangleLineData;
begin
  if FDocument = nil then
    Exit;
  FDocument.RemoveRoundedRectangleLine(FIndex, RemovedData);
  FDocument.SetSelectedLayers(FBeforeSelection);
end;

{ TScreenLayoutInsertEllipseLineCommand }

constructor TScreenLayoutInsertEllipseLineCommand.Create(
  ADocument: TVectArtDocument; Index: Integer;
  const Data: TScreenLayoutEllipseLineData; const BeforeSelection,
  AfterSelection: TArray<Integer>);
begin
  inherited Create;
  FDocument := ADocument;
  FIndex := Index;
  FData := Data;
  FBeforeSelection := Copy(BeforeSelection);
  FAfterSelection := Copy(AfterSelection);
end;

procedure TScreenLayoutInsertEllipseLineCommand.Execute;
begin
  if FDocument = nil then
    Exit;
  FIndex := FDocument.InsertEllipseLine(FIndex, FData);
  FDocument.SetSelectedLayers(FAfterSelection);
end;

procedure TScreenLayoutInsertEllipseLineCommand.Undo;
var
  RemovedData: TScreenLayoutEllipseLineData;
begin
  if FDocument = nil then
    Exit;
  FDocument.RemoveEllipseLine(FIndex, RemovedData);
  FDocument.SetSelectedLayers(FBeforeSelection);
end;

{ TVectArtDeleteRectangleCommand }

constructor TVectArtDeletePathCommand.Create(ADocument: TVectArtDocument;
  Index: Integer; const Data: TVectArtPathData; const BeforeSelection,
  AfterSelection: TArray<Integer>);
begin
  inherited Create;
  FDocument := ADocument;
  FIndex := Index;
  FData := Data;
  FData.Vertices := Copy(Data.Vertices);
  FBeforeSelection := Copy(BeforeSelection);
  FAfterSelection := Copy(AfterSelection);
end;

procedure TVectArtDeletePathCommand.Execute;
var
  RemovedData: TVectArtPathData;
begin
  if FDocument = nil then
    Exit;
  FDocument.RemovePath(FIndex, RemovedData);
  FDocument.SetSelectedLayers(FAfterSelection);
end;

procedure TVectArtDeletePathCommand.Undo;
begin
  if FDocument = nil then
    Exit;
  FIndex := FDocument.InsertPath(FIndex, FData);
  FDocument.SetSelectedLayers(FBeforeSelection);
end;

constructor TVectArtDeleteImageCommand.Create(ADocument: TVectArtDocument;
  Index: Integer; const Data: TVectArtImageData; const BeforeSelection,
  AfterSelection: TArray<Integer>);
begin
  inherited Create;
  FDocument := ADocument;
  FIndex := Index;
  FData := Data;
  FData.PngData := Copy(Data.PngData);
  FBeforeSelection := Copy(BeforeSelection);
  FAfterSelection := Copy(AfterSelection);
end;

procedure TVectArtDeleteImageCommand.Execute;
var
  RemovedData: TVectArtImageData;
begin
  if FDocument = nil then
    Exit;
  FDocument.RemoveImage(FIndex, RemovedData);
  FDocument.SetSelectedLayers(FAfterSelection);
end;

procedure TVectArtDeleteImageCommand.Undo;
begin
  if FDocument = nil then
    Exit;
  FIndex := FDocument.InsertImage(FIndex, FData);
  FDocument.SetSelectedLayers(FBeforeSelection);
end;

{ TVectArtDeleteRectangleCommand }

constructor TVectArtDeleteRectangleCommand.Create(
  ADocument: TVectArtDocument; Index: Integer;
  const Data: TVectArtRectangleData; const BeforeSelection,
  AfterSelection: TArray<Integer>);
begin
  inherited Create;
  FDocument := ADocument;
  FIndex := Index;
  FData := Data;
  FBeforeSelection := Copy(BeforeSelection);
  FAfterSelection := Copy(AfterSelection);
end;

procedure TVectArtDeleteRectangleCommand.Execute;
var
  RemovedData: TVectArtRectangleData;
begin
  if FDocument = nil then
    Exit;
  FDocument.RemoveRectangle(FIndex, RemovedData);
  FDocument.SetSelectedLayers(FAfterSelection);
end;

procedure TVectArtDeleteRectangleCommand.Undo;
begin
  if FDocument = nil then
    Exit;
  FIndex := FDocument.InsertRectangle(FIndex, FData);
  FDocument.SetSelectedLayers(FBeforeSelection);
end;

{ TScreenLayoutDeleteRoundedRectangleCommand }

constructor TScreenLayoutDeleteRoundedRectangleCommand.Create(
  ADocument: TVectArtDocument; Index: Integer;
  const Data: TScreenLayoutRoundedRectangleData; const BeforeSelection,
  AfterSelection: TArray<Integer>);
begin
  inherited Create;
  FDocument := ADocument;
  FIndex := Index;
  FData := Data;
  FBeforeSelection := Copy(BeforeSelection);
  FAfterSelection := Copy(AfterSelection);
end;

procedure TScreenLayoutDeleteRoundedRectangleCommand.Execute;
var
  RemovedData: TScreenLayoutRoundedRectangleData;
begin
  if FDocument = nil then
    Exit;
  FDocument.RemoveRoundedRectangle(FIndex, RemovedData);
  FDocument.SetSelectedLayers(FAfterSelection);
end;

procedure TScreenLayoutDeleteRoundedRectangleCommand.Undo;
begin
  if FDocument = nil then
    Exit;
  FIndex := FDocument.InsertRoundedRectangle(FIndex, FData);
  FDocument.SetSelectedLayers(FBeforeSelection);
end;

{ TScreenLayoutDeleteEllipseCommand }

constructor TScreenLayoutDeleteEllipseCommand.Create(
  ADocument: TVectArtDocument; Index: Integer;
  const Data: TScreenLayoutEllipseData; const BeforeSelection,
  AfterSelection: TArray<Integer>);
begin
  inherited Create;
  FDocument := ADocument;
  FIndex := Index;
  FData := Data;
  FBeforeSelection := Copy(BeforeSelection);
  FAfterSelection := Copy(AfterSelection);
end;

procedure TScreenLayoutDeleteEllipseCommand.Execute;
var
  RemovedData: TScreenLayoutEllipseData;
begin
  if FDocument = nil then
    Exit;
  FDocument.RemoveEllipse(FIndex, RemovedData);
  FDocument.SetSelectedLayers(FAfterSelection);
end;

procedure TScreenLayoutDeleteEllipseCommand.Undo;
begin
  if FDocument = nil then
    Exit;
  FIndex := FDocument.InsertEllipse(FIndex, FData);
  FDocument.SetSelectedLayers(FBeforeSelection);
end;

{ TScreenLayoutDeleteArcCommand }

constructor TScreenLayoutDeleteArcCommand.Create(ADocument: TVectArtDocument;
  Index: Integer; const Data: TScreenLayoutArcData; const BeforeSelection,
  AfterSelection: TArray<Integer>);
begin
  inherited Create;
  FDocument := ADocument;
  FIndex := Index;
  FData := Data;
  FBeforeSelection := Copy(BeforeSelection);
  FAfterSelection := Copy(AfterSelection);
end;

procedure TScreenLayoutDeleteArcCommand.Execute;
var
  RemovedData: TScreenLayoutArcData;
begin
  if FDocument = nil then
    Exit;
  FDocument.RemoveArc(FIndex, RemovedData);
  FDocument.SetSelectedLayers(FAfterSelection);
end;

procedure TScreenLayoutDeleteArcCommand.Undo;
begin
  if FDocument = nil then
    Exit;
  FIndex := FDocument.InsertArc(FIndex, FData);
  FDocument.SetSelectedLayers(FBeforeSelection);
end;

{ TScreenLayoutDeleteEllipseArcShapeCommand }

constructor TScreenLayoutDeleteEllipseArcShapeCommand.Create(
  ADocument: TVectArtDocument; Index: Integer;
  const Data: TScreenLayoutEllipseArcShapeData; const BeforeSelection,
  AfterSelection: TArray<Integer>);
begin
  inherited Create;
  FDocument := ADocument;
  FIndex := Index;
  FData := Data;
  FBeforeSelection := Copy(BeforeSelection);
  FAfterSelection := Copy(AfterSelection);
end;

procedure TScreenLayoutDeleteEllipseArcShapeCommand.Execute;
var
  RemovedData: TScreenLayoutEllipseArcShapeData;
begin
  if FDocument = nil then
    Exit;
  FDocument.RemoveEllipseArcShape(FIndex, RemovedData);
  FDocument.SetSelectedLayers(FAfterSelection);
end;

procedure TScreenLayoutDeleteEllipseArcShapeCommand.Undo;
begin
  if FDocument = nil then
    Exit;
  FIndex := FDocument.InsertEllipseArcShape(FIndex, FData);
  FDocument.SetSelectedLayers(FBeforeSelection);
end;

{ TScreenLayoutDeleteRectangleLineCommand }

constructor TScreenLayoutDeleteRectangleLineCommand.Create(
  ADocument: TVectArtDocument; Index: Integer;
  const Data: TScreenLayoutRectangleLineData; const BeforeSelection,
  AfterSelection: TArray<Integer>);
begin
  inherited Create;
  FDocument := ADocument;
  FIndex := Index;
  FData := Data;
  FBeforeSelection := Copy(BeforeSelection);
  FAfterSelection := Copy(AfterSelection);
end;

procedure TScreenLayoutDeleteRectangleLineCommand.Execute;
var
  RemovedData: TScreenLayoutRectangleLineData;
begin
  if FDocument = nil then
    Exit;
  FDocument.RemoveRectangleLine(FIndex, RemovedData);
  FDocument.SetSelectedLayers(FAfterSelection);
end;

procedure TScreenLayoutDeleteRectangleLineCommand.Undo;
begin
  if FDocument = nil then
    Exit;
  FIndex := FDocument.InsertRectangleLine(FIndex, FData);
  FDocument.SetSelectedLayers(FBeforeSelection);
end;

{ TScreenLayoutDeleteRoundedRectangleLineCommand }

constructor TScreenLayoutDeleteRoundedRectangleLineCommand.Create(
  ADocument: TVectArtDocument; Index: Integer;
  const Data: TScreenLayoutRoundedRectangleLineData;
  const BeforeSelection, AfterSelection: TArray<Integer>);
begin
  inherited Create;
  FDocument := ADocument;
  FIndex := Index;
  FData := Data;
  FBeforeSelection := Copy(BeforeSelection);
  FAfterSelection := Copy(AfterSelection);
end;

procedure TScreenLayoutDeleteRoundedRectangleLineCommand.Execute;
var
  RemovedData: TScreenLayoutRoundedRectangleLineData;
begin
  if FDocument = nil then
    Exit;
  FDocument.RemoveRoundedRectangleLine(FIndex, RemovedData);
  FDocument.SetSelectedLayers(FAfterSelection);
end;

procedure TScreenLayoutDeleteRoundedRectangleLineCommand.Undo;
begin
  if FDocument = nil then
    Exit;
  FIndex := FDocument.InsertRoundedRectangleLine(FIndex, FData);
  FDocument.SetSelectedLayers(FBeforeSelection);
end;

{ TScreenLayoutDeleteEllipseLineCommand }

constructor TScreenLayoutDeleteEllipseLineCommand.Create(
  ADocument: TVectArtDocument; Index: Integer;
  const Data: TScreenLayoutEllipseLineData; const BeforeSelection,
  AfterSelection: TArray<Integer>);
begin
  inherited Create;
  FDocument := ADocument;
  FIndex := Index;
  FData := Data;
  FBeforeSelection := Copy(BeforeSelection);
  FAfterSelection := Copy(AfterSelection);
end;

procedure TScreenLayoutDeleteEllipseLineCommand.Execute;
var
  RemovedData: TScreenLayoutEllipseLineData;
begin
  if FDocument = nil then
    Exit;
  FDocument.RemoveEllipseLine(FIndex, RemovedData);
  FDocument.SetSelectedLayers(FAfterSelection);
end;

procedure TScreenLayoutDeleteEllipseLineCommand.Undo;
begin
  if FDocument = nil then
    Exit;
  FIndex := FDocument.InsertEllipseLine(FIndex, FData);
  FDocument.SetSelectedLayers(FBeforeSelection);
end;

{ TVectArtMoveLayerCommand }

constructor TVectArtMoveLayerCommand.Create(ADocument: TVectArtDocument;
  OldIndex, NewIndex: Integer; const BeforeSelection,
  AfterSelection: TArray<Integer>);
begin
  inherited Create;
  FDocument := ADocument;
  FOldIndex := OldIndex;
  FNewIndex := NewIndex;
  FBeforeSelection := Copy(BeforeSelection);
  FAfterSelection := Copy(AfterSelection);
end;

procedure TVectArtMoveLayerCommand.Execute;
begin
  if FDocument = nil then
    Exit;
  FDocument.MoveLayer(FOldIndex, FNewIndex);
  FDocument.SetSelectedLayers(FAfterSelection);
end;

procedure TVectArtMoveLayerCommand.Undo;
begin
  if FDocument = nil then
    Exit;
  FDocument.MoveLayer(FNewIndex, FOldIndex);
  FDocument.SetSelectedLayers(FBeforeSelection);
end;

end.
