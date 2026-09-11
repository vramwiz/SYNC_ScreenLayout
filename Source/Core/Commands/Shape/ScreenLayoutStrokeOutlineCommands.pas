// 開いた線Pathを同じ位置の閉じたShapeへ置換し、Undoで元のPathへ戻す。
unit ScreenLayoutStrokeOutlineCommands;

interface

uses
  ScreenLayoutDocument, ScreenLayoutEditHistory, ScreenLayoutEditorState;

function ExecuteScreenLayoutStrokeOutline(Document: TVectArtDocument;
  EditorState: TVectArtEditorState; EditHistory: TVectArtEditHistory;
  PathLayer: TVectArtPathLayer): Boolean;

implementation

uses
  System.SysUtils, Vcl.Graphics, ScreenLayoutEditCommands,
  ScreenLayoutStrokeOutlineGeometry;

type
  TScreenLayoutStrokeOutlineCommand = class(TVectArtEditCommand)
  private
    FDocument: TVectArtDocument;
    FEditorState: TVectArtEditorState;
    FIndex: Integer;
    FParent: TScreenLayoutGroupLayer;
    FOriginal: TVectArtPathLayer;
    FOriginalInDocument: Boolean;
    FOutlined: TScreenLayoutShapeLayer;
    FOutlinedInDocument: Boolean;
    procedure SelectCurrent(Index: Integer);
  public
    constructor Create(ADocument: TVectArtDocument;
      AEditorState: TVectArtEditorState; AParent: TScreenLayoutGroupLayer;
      Index: Integer;
      Original: TVectArtPathLayer; Outlined: TScreenLayoutShapeLayer);
    destructor Destroy; override;
    procedure Execute; override;
    procedure Undo; override;
  end;

constructor TScreenLayoutStrokeOutlineCommand.Create(
  ADocument: TVectArtDocument; AEditorState: TVectArtEditorState;
  AParent: TScreenLayoutGroupLayer; Index: Integer;
  Original: TVectArtPathLayer;
  Outlined: TScreenLayoutShapeLayer);
begin
  inherited Create;
  FDocument := ADocument;
  FEditorState := AEditorState;
  FParent := AParent;
  FIndex := Index;
  FOriginal := Original;
  FOutlined := Outlined;
  FOriginalInDocument := True;
end;

destructor TScreenLayoutStrokeOutlineCommand.Destroy;
begin
  if not FOriginalInDocument then
    FOriginal.Free;
  if not FOutlinedInDocument then
    FOutlined.Free;
  inherited Destroy;
end;

procedure TScreenLayoutStrokeOutlineCommand.Execute;
begin
  if (FDocument = nil) or not FOriginalInDocument then
    Exit;
  FDocument.BeginUpdate;
  try
    if FParent <> nil then
      FOriginal := TVectArtPathLayer(FParent.ExtractChild(FIndex))
    else
      FOriginal := TVectArtPathLayer(FDocument.ExtractLayer(FIndex));
    FOriginalInDocument := False;
    if FParent <> nil then
      FParent.InsertChild(FIndex, FOutlined)
    else
      FDocument.InsertLayer(FIndex, FOutlined);
    FOutlinedInDocument := True;
    SelectCurrent(FIndex);
  finally
    FDocument.EndUpdate;
  end;
end;

procedure TScreenLayoutStrokeOutlineCommand.SelectCurrent(Index: Integer);
begin
  if FParent <> nil then
  begin
    FDocument.SetSelectedLayers([]);
    FEditorState.SetOpenGroupChildren([FParent[Index]]);
  end
  else
    FDocument.SetSelectedLayers([Index]);
  if FEditorState <> nil then
    FEditorState.ValidateSelectedFilter(FDocument);
end;

procedure TScreenLayoutStrokeOutlineCommand.Undo;
begin
  if (FDocument = nil) or not FOutlinedInDocument then
    Exit;
  FDocument.BeginUpdate;
  try
    if FParent <> nil then
      FOutlined := TScreenLayoutShapeLayer(FParent.ExtractChild(FIndex))
    else
      FOutlined := TScreenLayoutShapeLayer(FDocument.ExtractLayer(FIndex));
    FOutlinedInDocument := False;
    if FParent <> nil then
      FParent.InsertChild(FIndex, FOriginal)
    else
      FDocument.InsertLayer(FIndex, FOriginal);
    FOriginalInDocument := True;
    SelectCurrent(FIndex);
  finally
    FDocument.EndUpdate;
  end;
end;

function ExecuteScreenLayoutStrokeOutline(Document: TVectArtDocument;
  EditorState: TVectArtEditorState; EditHistory: TVectArtEditHistory;
  PathLayer: TVectArtPathLayer): Boolean;
var
  Command: TScreenLayoutStrokeOutlineCommand;
  Contours: TArray<TScreenLayoutContour>;
  I: Integer;
  Index: Integer;
  Parent: TScreenLayoutGroupLayer;
  Shape: TScreenLayoutShapeLayer;
begin
  Result := False;
  if (Document = nil) or (PathLayer = nil) or PathLayer.Locked or
    PathLayer.Closed then
    Exit;
  Index := -1;
  Parent := nil;
  if (EditorState <> nil) and (EditorState.OpenGroup <> nil) and
    EditorState.IsOpenGroupChildSelected(PathLayer) then
  begin
    Parent := EditorState.OpenGroup;
    for I := 0 to Parent.ChildCount - 1 do
      if Parent[I] = PathLayer then
      begin
        Index := I;
        Break;
      end;
  end
  else
    for I := 1 to Document.LayerCount - 1 do
      if Document[I] = PathLayer then
      begin
        Index := I;
        Break;
      end;
  if Index < 0 then
    Exit;
  Contours := BuildScreenLayoutStrokeOutlineContours(PathLayer);
  if Length(Contours) = 0 then
    Exit;
  Shape := TScreenLayoutShapeLayer.Create(PathLayer.Name + ' outline',
    Contours);
  Shape.FillColor := PathLayer.StrokeColor;
  Shape.FillRule := slfrEvenOdd;
  Shape.Locked := PathLayer.Locked;
  Shape.Opacity := PathLayer.Opacity;
  Shape.PaintStyle := PathLayer.PaintStyle;
  Shape.StrokeWidth := 0;
  Shape.Transform := PathLayer.Transform;
  Shape.Visible := PathLayer.Visible;
  for I := 0 to PathLayer.FilterCount - 1 do
    Shape.AddFilter(PathLayer.Filters[I].Clone);
  Command := TScreenLayoutStrokeOutlineCommand.Create(Document,
    EditorState, Parent, Index, PathLayer, Shape);
  Command.Execute;
  if EditHistory <> nil then
    EditHistory.AddApplied(Command)
  else
    Command.Free;
  Result := True;
end;

end.
